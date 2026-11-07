import AppKit
import Foundation
import UniformTypeIdentifiers

enum AppFiles {
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Datacom", isDirectory: true)
    }
    static var progress: URL { support.appendingPathComponent("progress.json") }
    /// Written by Rebuild Library; preferred over the copy inside the app when present.
    static var rebuiltLibrary: URL { support.appendingPathComponent("library.json") }

    /// The datacom checkout the app was built from (Info.plist DatacomRepo), for Rebuild Library.
    static var repo: URL {
        if let path = Bundle.main.object(forInfoDictionaryKey: "DatacomRepo") as? String, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("code/datacom", isDirectory: true)
    }

    static func resource(_ name: String, _ ext: String?) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.module.url(forResource: name, withExtension: ext)
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var library: Library = .empty
    @Published var errorMessage: String?
    @Published private(set) var rebuilding = false
    @Published private(set) var rebuildLog = ""

    private(set) var lessonByID: [String: Lesson] = [:]
    private(set) var problemByID: [String: Problem] = [:]
    private(set) var trackByID: [String: Track] = [:]
    private(set) var sectionTitle: [String: String] = [:]
    /// Lessons and problems in track and section order, for Previous / Next.
    private(set) var orderedLessons: [Lesson] = []
    private(set) var orderedProblems: [Problem] = []

    init() { load() }

    func load() {
        let rebuilt = AppFiles.rebuiltLibrary
        let url = FileManager.default.fileExists(atPath: rebuilt.path) ? rebuilt : AppFiles.resource("library", "json")
        guard let url else {
            errorMessage = "library.json is missing from the app. Run scripts/build_app.sh again."
            return
        }
        do {
            install(try JSONDecoder().decode(Library.self, from: Data(contentsOf: url)))
        } catch {
            errorMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func install(_ lib: Library) {
        library = lib
        lessonByID = Dictionary(lib.lessons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        problemByID = Dictionary(lib.problems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        trackByID = Dictionary(lib.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        sectionTitle = Dictionary(lib.tracks.flatMap(\.sections).map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        var lessonsBySection: [String: [Lesson]] = [:]
        for l in lib.lessons { lessonsBySection[l.section, default: []].append(l) }
        var problemsBySection: [String: [Problem]] = [:]
        for p in lib.problems { problemsBySection[p.section, default: []].append(p) }
        orderedLessons = lib.tracks.flatMap { $0.sections.flatMap { lessonsBySection[$0.id] ?? [] } }
        orderedProblems = lib.tracks.flatMap { $0.sections.flatMap { problemsBySection[$0.id] ?? [] } }
    }

    var tracks: [Track] { library.tracks }
    func lessons(in section: TrackSection) -> [Lesson] { library.lessons.filter { $0.section == section.id } }
    func lessons(of track: String) -> [Lesson] { orderedLessons.filter { $0.track == track } }
    func problems(in section: TrackSection) -> [Problem] { library.problems.filter { $0.section == section.id } }
    func problems(of track: String) -> [Problem] { orderedProblems.filter { $0.track == track } }
    func cards(of track: String) -> [Card] { library.cards.filter { $0.track == track } }
    func cards(lesson: String) -> [Card] { library.cards.filter { $0.lesson == lesson } }
    func cards(section: String) -> [Card] { library.cards.filter { $0.section == section } }
    func trackTitle(_ id: String) -> String { trackByID[id]?.title ?? id }

    /// Re-reads every source repo (algos, deepmath, gpukernels, …) with tools/build_library.py.
    func rebuild() {
        guard !rebuilding else { return }
        let repo = AppFiles.repo
        let script = repo.appendingPathComponent("tools/build_library.py")
        guard FileManager.default.fileExists(atPath: script.path) else {
            errorMessage = "Can't find \(script.path). Rebuild Library needs the datacom checkout the app was built from."
            return
        }
        try? FileManager.default.createDirectory(at: AppFiles.support, withIntermediateDirectories: true)
        rebuilding = true
        rebuildLog = ""
        let out = AppFiles.rebuiltLibrary.path
        let command = "exec python3 \(shellQuote(script.path)) --app \(shellQuote(out))"
        Task.detached {
            let result = Shell.run(command, in: repo)
            await MainActor.run {
                self.rebuilding = false
                self.rebuildLog = result.output
                if result.status == 0 {
                    self.load()
                } else {
                    self.errorMessage = "Rebuild failed:\n\(result.output.suffix(1500))"
                }
            }
        }
    }

    /// Goes back to the library bundled in the app.
    func useBundledLibrary() {
        try? FileManager.default.removeItem(at: AppFiles.rebuiltLibrary)
        load()
    }
}

func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

/// Runs a command through the user's login shell, so python3 is the one their Terminal finds.
/// `interactive` also reads ~/.zshrc, where conda and pyenv usually set up PATH.
enum Shell {
    static func run(_ command: String, in directory: URL, interactive: Bool = false,
                    timeout: TimeInterval = 600) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [interactive ? "-ilc" : "-lc", command]
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

@MainActor
final class ProgressStore: ObservableObject {
    @Published private(set) var data = StudyState()
    /// Bumped when progress is replaced wholesale, so open editors reload.
    @Published private(set) var revision = 0
    @Published var errorMessage: String?
    private var pending: DispatchWorkItem?

    init() {
        if let raw = try? Data(contentsOf: AppFiles.progress),
           let file = try? JSONDecoder().decode(ProgressFile.self, from: raw) {
            data = file.state
        }
    }

    // ---- cards ----

    func mark(_ id: String) -> String? { data.cards[id] }

    func toggle(_ id: String, _ kind: String) {
        if data.cards[id] == kind { data.cards.removeValue(forKey: id) } else { data.cards[id] = kind }
        save()
    }

    func set(_ id: String, _ kind: String) {
        data.cards[id] = kind
        save()
    }

    func selected(in tracks: [Track]) -> Set<String> { Set(data.selected ?? tracks.map(\.id)) }

    func setSelected(_ ids: Set<String>, in tracks: [Track]) {
        let all = tracks.map(\.id)
        data.selected = ids.count == all.count ? nil : all.filter { ids.contains($0) }
        save()
    }

    // ---- lessons ----

    func isRead(_ id: String) -> Bool { data.read[id] != nil }

    func toggleRead(_ id: String) {
        if data.read[id] != nil { data.read.removeValue(forKey: id) } else { data.read[id] = now() }
        save()
    }

    // ---- problems and snippets ----

    func isSolved(_ id: String) -> Bool { data.solved[id] != nil }
    func attempt(_ id: String) -> Attempt? { data.attempts[id] }

    /// Records a test run; returns true when this run solved the problem for the first time.
    @discardableResult
    func record(_ id: String, passed: Int, total: Int) -> Bool {
        data.attempts[id] = Attempt(passed: passed, total: total, at: now())
        var first = false
        if total > 0, passed == total, data.solved[id] == nil {
            data.solved[id] = Solved(at: now())
            first = true
        }
        save()
        return first
    }

    func code(for problem: Problem) -> String { data.code[problem.id] ?? problem.starter }

    func setCode(_ code: String, for id: String) {
        data.code[id] = code
        saveSoon()
    }

    func resetCode(_ id: String) {
        data.code.removeValue(forKey: id)
        revision += 1
        save()
    }

    func setScratch(_ code: String) {
        data.scratch = code
        saveSoon()
    }

    func setSnippet(_ id: String, code: String) {
        data.snippets[id]?.code = code
        data.snippets[id]?.at = now()
        saveSoon()
    }

    func addSnippet(title: String, code: String) -> String {
        let id = "s" + String(Int(now()), radix: 36)
        data.snippets[id] = Snippet(title: title, code: code, at: now())
        save()
        return id
    }

    func renameSnippet(_ id: String, to title: String) {
        data.snippets[id]?.title = title
        save()
    }

    func deleteSnippet(_ id: String) {
        data.snippets.removeValue(forKey: id)
        save()
    }

    func setStdin(_ text: String) {
        data.stdin = text
        saveSoon()
    }

    // ---- files ----

    func exportProgress() {
        let panel = NSSavePanel()
        panel.title = "Export progress"
        panel.message = "The web app can import this file from its ☰ menu."
        panel.nameFieldStringValue = "datacom-progress-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = ProgressFile(exported: ISO8601DateFormatter().string(from: Date()), state: data)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(file).write(to: url)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Merges a file exported from the web app or this app; nothing done here is lost.
    func importProgress() {
        let panel = NSOpenPanel()
        panel.title = "Import progress"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try JSONDecoder().decode(ProgressFile.self, from: Data(contentsOf: url))
            guard file.app == "datacom" else {
                errorMessage = "That file is not a Datacom progress export."
                return
            }
            let s = file.state
            data.cards.merge(s.cards) { _, new in new }
            data.read.merge(s.read) { _, new in new }
            data.attempts.merge(s.attempts) { _, new in new }
            data.code.merge(s.code) { _, new in new }
            data.snippets.merge(s.snippets) { _, new in new }
            data.solved.merge(s.solved) { old, _ in old }
            revision += 1
            save()
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func reset() {
        let alert = NSAlert()
        alert.messageText = "Reset progress?"
        alert.informativeText = "This clears card marks, read lessons and solved problems. Your code and snippets are kept."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        data.cards = [:]
        data.read = [:]
        data.solved = [:]
        data.attempts = [:]
        revision += 1
        save()
    }

    private func saveSoon() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.save() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func save() {
        pending?.cancel()
        pending = nil
        do {
            try FileManager.default.createDirectory(at: AppFiles.support, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(ProgressFile(state: data)).write(to: AppFiles.progress, options: .atomic)
        } catch {
            errorMessage = "Could not save progress: \(error.localizedDescription)"
        }
    }
}

/// What the window shows. Shared by the window and the menu commands.
@MainActor
final class Navigator: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var mode: Mode = .learn { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    @Published var lessonID: String? { didSet { defaults.set(lessonID, forKey: "lesson") } }
    /// A problem id, or "playground".
    @Published var codeItem: String? { didSet { defaults.set(codeItem, forKey: "codeItem") } }
    @Published var cardMode: CardMode = .learn { didSet { defaults.set(cardMode.rawValue, forKey: "cardMode") } }
    @Published var filter: CardFilter = .all { didSet { defaults.set(filter.rawValue, forKey: "filter") } }
    @Published var shuffle = false { didSet { defaults.set(shuffle, forKey: "shuffle") } }
    /// When set, Cards practises only these cards.
    @Published var focus: Focus?
    /// Sidebar filter text and collapsed track sections.
    @Published var search = ""
    @Published var collapsed: Set<String> = []

    struct Focus: Equatable {
        enum Kind { case track, section, lesson }
        let kind: Kind
        let id: String
        let title: String
    }

    static let playground = "playground"

    init() {
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .learn
        lessonID = defaults.string(forKey: "lesson")
        codeItem = defaults.string(forKey: "codeItem")
        cardMode = CardMode(rawValue: defaults.string(forKey: "cardMode") ?? "") ?? .learn
        filter = CardFilter(rawValue: defaults.string(forKey: "filter") ?? "") ?? .all
        shuffle = defaults.bool(forKey: "shuffle")
    }

    func open(lesson id: String) {
        lessonID = id
        mode = .learn
    }

    func open(problem id: String) {
        codeItem = id
        mode = .code
    }

    func openPlayground() {
        codeItem = Self.playground
        mode = .code
    }

    func practise(_ focus: Focus) {
        self.focus = focus
        mode = .cards
    }

    func stepLesson(_ delta: Int, in store: LibraryStore) {
        guard let id = lessonID, let lesson = store.lessonByID[id] else { return }
        let list = store.lessons(of: lesson.track)
        guard let i = list.firstIndex(of: lesson), list.indices.contains(i + delta) else { return }
        lessonID = list[i + delta].id
    }

    func canStepLesson(_ delta: Int, in store: LibraryStore) -> Bool {
        guard let id = lessonID, let lesson = store.lessonByID[id] else { return false }
        let list = store.lessons(of: lesson.track)
        guard let i = list.firstIndex(of: lesson) else { return false }
        return list.indices.contains(i + delta)
    }

    func stepProblem(_ delta: Int, in store: LibraryStore) {
        guard let id = codeItem, let p = store.problemByID[id], let i = store.orderedProblems.firstIndex(of: p),
              store.orderedProblems.indices.contains(i + delta) else { return }
        codeItem = store.orderedProblems[i + delta].id
    }

    func step(_ delta: Int, in store: LibraryStore) {
        switch mode {
        case .learn: stepLesson(delta, in: store)
        case .code: stepProblem(delta, in: store)
        default: break
        }
    }
}

/// The deck being practised in Cards.
@MainActor
final class StudySession: ObservableObject {
    @Published var deck: [Card] = []
    @Published var position = 0
    @Published var revealed = false
    @Published var finished = false
    @Published var answers: [String: Bool] = [:]

    var current: Card? { deck.indices.contains(position) ? deck[position] : nil }
    var got: Int { answers.values.filter { $0 }.count }
    var missed: [String] { deck.map(\.id).filter { answers[$0] == false } }

    func rebuild(store: LibraryStore, progress: ProgressStore, navigator: Navigator) {
        var pool: [Card]
        if let f = navigator.focus {
            switch f.kind {
            case .track: pool = store.cards(of: f.id)
            case .section: pool = store.cards(section: f.id)
            case .lesson: pool = store.cards(lesson: f.id)
            }
        } else {
            let selected = progress.selected(in: store.tracks)
            pool = store.library.cards.filter { selected.contains($0.track) }
        }
        pool = pool.filter { card in
            let mark = progress.mark(card.id)
            switch navigator.filter {
            case .all: return true
            case .unknown: return mark != "known"
            case .review: return mark == "review"
            }
        }
        if navigator.shuffle { pool.shuffle() }
        start(pool)
    }

    func start(_ cards: [Card]) {
        deck = cards
        position = 0
        revealed = false
        finished = false
        answers = [:]
    }

    func retestMissed() {
        let ids = Set(missed)
        start(deck.filter { ids.contains($0.id) })
    }

    func move(_ delta: Int, testing: Bool) {
        guard !deck.isEmpty, !finished else { return }
        let next = position + delta
        guard next >= 0 else { return }
        if next >= deck.count {
            if testing { finished = true }
            return
        }
        position = next
        revealed = false
    }

    func answer(_ got: Bool, progress: ProgressStore) {
        guard revealed, !finished, let card = current else { return }
        answers[card.id] = got
        progress.set(card.id, got ? "known" : "review")
        if position + 1 >= deck.count { finished = true } else { position += 1 }
        revealed = false
    }
}
