import Foundation

/// Runs Python with the user's own python3 (so numpy, pandas, torch and friends are whatever
/// they have installed), streaming stdout and stderr as they arrive. Each run gets a fresh
/// temp folder holding main.py and the dc.py helpers.
@MainActor
final class PythonRunner: ObservableObject {
    struct Chunk {
        let text: String
        let isError: Bool
    }

    struct TestResult: Decodable, Equatable {
        let passed: Int
        let total: Int
    }

    enum Status: Equatable {
        case idle
        case running(Date)
        case finished(ok: Bool, seconds: Double, result: TestResult?)
        case stopped(seconds: Double)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var chunks: [Chunk] = []
    /// Bumped on every append or clear; the console view redraws from it.
    @Published private(set) var revision = 0
    /// Which problem id or playground key the console belongs to.
    @Published private(set) var key: String?
    @Published private(set) var interpreter = ""
    @Published private(set) var interpreterInfo = "Finding python3…"

    private static let marker = "__DC_RESULT__ "
    private static let maxChars = 200_000
    private var process: Process?
    private var started = Date()
    private var heldLine = ""
    private var result: TestResult?
    private var chars = 0
    private var folder: URL?
    private var onFinish: ((TestResult?) -> Void)?
    private var stopping = false

    var isRunning: Bool { if case .running = status { return true } else { return false } }

    init() { locatePython() }

    /// Uses the Settings override if any, otherwise the python3 an interactive login shell finds,
    /// so conda / pyenv / Homebrew setups in ~/.zshrc are respected.
    func locatePython() {
        let custom = UserDefaults.standard.string(forKey: "python")?.trimmingCharacters(in: .whitespaces) ?? ""
        Task.detached {
            var path = custom
            if path.isEmpty {
                let found = Shell.run("command -v python3", in: FileManager.default.homeDirectoryForCurrentUser,
                                      interactive: true, timeout: 15)
                path = found.output.split(separator: "\n").map(String.init).last(where: { $0.hasPrefix("/") }) ?? "/usr/bin/python3"
            }
            let probe = Shell.run("""
                \(shellQuote(path)) -c "import sys, importlib.util as u; print(sys.version.split()[0], *[m for m in ('numpy', 'pandas', 'torch') if u.find_spec(m)])"
                """, in: FileManager.default.homeDirectoryForCurrentUser, timeout: 30)
            let line = probe.output.split(separator: "\n").last.map(String.init) ?? ""
            let info: String
            if probe.status == 0 {
                let parts = line.split(separator: " ").map(String.init)
                let mods = parts.dropFirst()
                info = "Python \(parts.first ?? "?")" + (mods.isEmpty ? " · no numpy / pandas" : " · " + mods.joined(separator: ", "))
            } else {
                info = "python3 not found at \(path)"
            }
            let resolved = path
            await MainActor.run {
                self.interpreter = resolved
                self.interpreterInfo = info
            }
        }
    }

    func clear() {
        guard !isRunning else { return }
        chunks = []
        chars = 0
        status = .idle
        revision += 1
    }

    func run(_ code: String, key: String, helpers: String, stdin: String = "", onFinish: ((TestResult?) -> Void)? = nil) {
        guard !isRunning else { return }
        self.key = key
        self.onFinish = onFinish
        chunks = []
        chars = 0
        heldLine = ""
        result = nil
        stopping = false
        revision += 1

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("datacom-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try code.write(to: dir.appendingPathComponent("main.py"), atomically: true, encoding: .utf8)
            try helpers.write(to: dir.appendingPathComponent("dc.py"), atomically: true, encoding: .utf8)
        } catch {
            append("Could not prepare the run: \(error.localizedDescription)\n", isError: true)
            status = .finished(ok: false, seconds: 0, result: nil)
            return
        }
        folder = dir

        let p = Process()
        p.executableURL = URL(fileURLWithPath: interpreter.isEmpty ? "/usr/bin/python3" : interpreter)
        p.arguments = ["-u", "main.py"]
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        env["MPLBACKEND"] = "Agg"
        p.environment = env
        let out = Pipe()
        let err = Pipe()
        let input = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = input
        out.fileHandleForReading.readabilityHandler = Self.reader { [weak self] text in self?.handleStdout(text) }
        err.fileHandleForReading.readabilityHandler = Self.reader { [weak self] text in self?.append(text, isError: true) }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            // Let the pipe handlers drain before finishing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                MainActor.assumeIsolated {
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    self?.finish(exitCode: code)
                }
            }
        }
        do {
            try p.run()
        } catch {
            append("Could not start \(p.executableURL?.path ?? "python3"): \(error.localizedDescription)\nSet the interpreter in Datacom ▸ Settings.\n", isError: true)
            status = .finished(ok: false, seconds: 0, result: nil)
            return
        }
        process = p
        started = Date()
        status = .running(started)
        if !stdin.isEmpty { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? input.fileHandleForWriting.close()
    }

    func stop() {
        guard let p = process, p.isRunning else { return }
        stopping = true
        p.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }

    /// Bytes of a split multi-byte character, held until the next read. A pipe's handler is
    /// called serially, so one handler never races itself.
    private final class Carry: @unchecked Sendable { var data = Data() }

    /// Decodes UTF-8 from a pipe, carrying split multi-byte characters over to the next read.
    nonisolated private static func reader(_ deliver: @escaping @MainActor @Sendable (String) -> Void) -> @Sendable (FileHandle) -> Void {
        let carry = Carry()
        return { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            carry.data.append(data)
            let all = carry.data
            var cut = all.count
            var text: String?
            while cut > 0 && cut >= all.count - 3 {
                if let s = String(data: all.prefix(cut), encoding: .utf8) { text = s; break }
                cut -= 1
            }
            let s = text ?? String(decoding: all, as: UTF8.self)
            carry.data = text == nil ? Data() : Data(all.suffix(from: all.startIndex + cut))
            DispatchQueue.main.async { MainActor.assumeIsolated { deliver(s) } }
        }
    }

    /// Passes stdout through, except the harness's result line, which is parsed and hidden.
    private func handleStdout(_ s: String) {
        var text = heldLine + s
        heldLine = ""
        var shown = ""
        while let nl = text.firstIndex(of: "\n") {
            let line = String(text[..<nl])
            text = String(text[text.index(after: nl)...])
            if line.hasPrefix(Self.marker) { parseResult(line) } else { shown += line + "\n" }
        }
        if !text.isEmpty {
            if Self.marker.hasPrefix(text) || text.hasPrefix(Self.marker) { heldLine = text } else { shown += text }
        }
        append(shown, isError: false)
    }

    private func parseResult(_ line: String) {
        let json = line.dropFirst(Self.marker.count)
        result = try? JSONDecoder().decode(TestResult.self, from: Data(json.utf8))
    }

    private func append(_ text: String, isError: Bool) {
        guard !text.isEmpty else { return }
        if let last = chunks.last, last.isError == isError {
            chunks[chunks.count - 1] = Chunk(text: last.text + text, isError: isError)
        } else {
            chunks.append(Chunk(text: text, isError: isError))
        }
        chars += text.count
        while chars > Self.maxChars, chunks.count > 1 {
            chars -= chunks.removeFirst().text.count
        }
        if chars > Self.maxChars, let only = chunks.first {
            let keep = String(only.text.suffix(Self.maxChars / 2))
            chunks = [Chunk(text: keep, isError: only.isError)]
            chars = keep.count
        }
        revision += 1
    }

    private func finish(exitCode: Int32) {
        if !heldLine.isEmpty {
            if heldLine.hasPrefix(Self.marker) { parseResult(heldLine) } else { append(heldLine, isError: false) }
            heldLine = ""
        }
        let seconds = Date().timeIntervalSince(started)
        process = nil
        if stopping {
            status = .stopped(seconds: seconds)
        } else {
            status = .finished(ok: exitCode == 0, seconds: seconds, result: result)
        }
        if chunks.isEmpty && !stopping { append("(no output)\n", isError: false) }
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        let done = onFinish
        onFinish = nil
        done?(stopping ? nil : result)
    }
}
