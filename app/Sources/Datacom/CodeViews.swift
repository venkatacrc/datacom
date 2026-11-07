import AppKit
import SwiftUI

/// View state for Code: which playground buffer is open, "Try" from lessons, revealed solutions.
@MainActor
final class PlaygroundModel: ObservableObject {
    /// "scratch" or a saved snippet id.
    @Published var item = "scratch"
    /// Bumped when the open buffer is replaced from outside the editor.
    @Published var epoch = 0
    /// Problems whose reference solution is shown.
    @Published var revealed: Set<String> = []
    @Published var problemEpoch = 0
    @Published var solvedBanner = false
    @Published var showStdin = false

    func code(_ progress: ProgressStore, templates: [Template]) -> String {
        if item != "scratch", let s = progress.data.snippets[item] { return s.code }
        return progress.data.scratch ?? templates.first?.code ?? ""
    }

    /// Saves scratch as a snippet before replacing it, unless it's empty or an untouched template.
    func keepScratch(_ progress: ProgressStore, templates: [Template]) {
        guard let s = progress.data.scratch, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !templates.contains(where: { $0.code == s }) else { return }
        _ = progress.addSnippet(title: "Scratch \(Date().formatted(date: .abbreviated, time: .shortened))", code: s)
    }

    func open(_ code: String, navigator: Navigator, progress: ProgressStore, templates: [Template] = []) {
        keepScratch(progress, templates: templates)
        progress.setScratch(code)
        progress.save()
        item = "scratch"
        epoch += 1
        navigator.openPlayground()
    }
}

/// Editor over console, shared by problems and the playground.
struct Workbench: View {
    @EnvironmentObject private var runner: PythonRunner
    let fileName: String
    let code: String
    let key: String
    let runKey: String
    var tools: AnyView = AnyView(EmptyView())
    let onChange: (String) -> Void
    let run: () -> Void

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(fileName).font(.system(.callout, design: .monospaced)).foregroundStyle(Color(white: 0.75))
                    Spacer()
                    Text(runner.interpreterInfo).font(.caption).foregroundStyle(Color(white: 0.6)).lineLimit(1)
                        .truncationMode(.middle)
                        .help(runner.interpreter)
                    tools
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(nsColor: Editor.background))
                CodeEditor(text: code, key: key, onChange: onChange, onRun: run)
            }
            .frame(minHeight: 180)
            VStack(spacing: 0) {
                HStack {
                    RunStatus(runner: runner, key: runKey)
                    Spacer()
                    Button("Clear") { runner.clear() }.buttonStyle(.link).disabled(runner.isRunning)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.07))
                ConsoleView(runner: runner, key: runKey)
            }
            .frame(minHeight: 110, idealHeight: 220)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

struct ProblemView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var navigator: Navigator
    @EnvironmentObject private var runner: PythonRunner
    @EnvironmentObject private var playground: PlaygroundModel
    let problem: Problem

    private var code: String { progress.code(for: problem) }

    var body: some View {
        GeometryReader { geo in
        HStack(spacing: 0) {
            HTMLView(html: promptHTML, key: "\(problem.id)#\(playground.revealed.contains(problem.id))#\(progress.isSolved(problem.id))",
                     onMessage: { type, body in
                         if type == "try", let code = body["code"] as? String {
                             playground.open(code, navigator: navigator, progress: progress, templates: store.library.playground)
                         }
                     }, onLink: { link in
                         if link.hasPrefix("lesson/") { navigator.open(lesson: String(link.dropFirst(7))) }
                     })
                .frame(width: max(260, geo.size.width * 0.4))
                .background(Color(nsColor: .textBackgroundColor))
            Divider()
            VStack(spacing: 10) {
                Workbench(fileName: "solution.py", code: code, key: "\(problem.id)#\(progress.revision)#\(playground.problemEpoch)",
                          runKey: problem.id,
                          tools: AnyView(HStack(spacing: 10) {
                              Button("Reset") { reset() }.buttonStyle(.link)
                              Button("Copy") {
                                  NSPasteboard.general.clearContents()
                                  NSPasteboard.general.setString(progress.code(for: problem), forType: .string)
                              }.buttonStyle(.link)
                          }),
                          onChange: { progress.setCode($0, for: problem.id) },
                          run: run)
                HStack(spacing: 12) {
                    Button { navigator.stepProblem(-1, in: store) } label: { Label("Previous", systemImage: "chevron.left") }
                        .help("Previous problem (⌘[)")
                    Button { navigator.stepProblem(1, in: store) } label: { Label("Next", systemImage: "chevron.right") }
                        .help("Next problem (⌘])")
                    Spacer()
                    if playground.solvedBanner {
                        Label("Solved", systemImage: "checkmark.seal.fill").foregroundStyle(.green).transition(.opacity)
                    }
                    Button { revealSolution() } label: { Label("Solution", systemImage: "lightbulb") }
                        .disabled(playground.revealed.contains(problem.id))
                    if runner.isRunning && runner.key == problem.id {
                        Button { runner.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                            .keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button(action: run) { Label("Run tests", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent)
                            .disabled(runner.isRunning)
                    }
                }
                .controlSize(.large)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runCode)) { _ in run() }
    }

    private var promptHTML: String {
        let p = problem
        var chips = "<span class=\"chip \(HTMLPage.esc(p.difficulty.lowercased()))\">\(HTMLPage.esc(p.difficulty))</span>"
        chips += p.tags.map { "<span class=\"chip\">\(HTMLPage.esc($0))</span>" }.joined()
        if !p.leetcode.isEmpty {
            chips += "<a class=\"chip\" href=\"https://leetcode.com/problemset/?search=\(p.leetcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")\">LeetCode \(HTMLPage.esc(p.leetcode))</a>"
        }
        if !p.source.isEmpty { chips += "<span class=\"chip\">\(HTMLPage.esc(p.source))</span>" }
        if !p.needs.isEmpty { chips += "<span class=\"chip\">uses \(HTMLPage.esc(p.needs.joined(separator: ", ")))</span>" }
        let solved = progress.isSolved(p.id) ? "<span style=\"color:var(--green)\">✓</span> " : ""
        var html = """
        <p class="fine" style="text-transform:uppercase;letter-spacing:.05em;font-weight:650;margin:0 0 4px">\(HTMLPage.esc(store.trackTitle(p.track))) · \(HTMLPage.esc(store.sectionTitle[p.section] ?? ""))</p>
        <h1>\(solved)\(HTMLPage.esc(p.title))</h1>
        <div class="chips">\(chips)</div>
        \(p.prompt)
        <details><summary>Tests</summary><pre><code class="language-python">\(HTMLPage.esc(p.tests))</code></pre></details>
        """
        if playground.revealed.contains(p.id) {
            html += "<details class=\"solution\" open><summary>Reference solution</summary><pre><code class=\"language-python\">\(HTMLPage.esc(p.solution))</code></pre></details>"
        }
        return html
    }

    private func run() {
        guard !runner.isRunning else { return }
        let id = problem.id
        runner.run(problem.harness(progress.code(for: problem)), key: id, helpers: store.library.helpers) { result in
            guard let result else { return }
            if progress.record(id, passed: result.passed, total: result.total) {
                withAnimation { playground.solvedBanner = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { playground.solvedBanner = false } }
            }
        }
    }

    private func reset() {
        guard confirm("Replace your code with the starter code?") else { return }
        progress.resetCode(problem.id)
        playground.problemEpoch += 1
    }

    private func revealSolution() {
        let alert = NSAlert()
        alert.messageText = "Show the reference solution?"
        alert.informativeText = "Try for a while first: struggling is where the learning happens."
        alert.addButton(withTitle: "Show")
        alert.addButton(withTitle: "Show and load into the editor")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            playground.revealed.insert(problem.id)
        case .alertSecondButtonReturn:
            playground.revealed.insert(problem.id)
            progress.setCode(problem.solution, for: problem.id)
            progress.save()
            playground.problemEpoch += 1
        default:
            break
        }
    }
}

struct PlaygroundView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var runner: PythonRunner
    @EnvironmentObject private var playground: PlaygroundModel

    private var item: String { progress.data.snippets[playground.item] == nil ? "scratch" : playground.item }
    private var runKey: String { "pg:" + item }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("Snippet", selection: Binding(get: { item }, set: { playground.item = $0 })) {
                    Text("Scratch").tag("scratch")
                    let saved = progress.data.snippets.sorted { $0.value.at > $1.value.at }
                    if !saved.isEmpty {
                        Divider()
                        ForEach(saved, id: \.key) { id, s in Text(s.title).tag(id) }
                    }
                }
                .frame(maxWidth: 320)
                Menu {
                    ForEach(store.library.playground) { t in
                        Button(t.title) {
                            playground.keepScratch(progress, templates: store.library.playground)
                            progress.setScratch(t.code)
                            progress.save()
                            playground.item = "scratch"
                            playground.epoch += 1
                        }
                    }
                } label: { Label("Templates", systemImage: "doc.on.doc") }
                .frame(maxWidth: 160)
                if item == "scratch" {
                    Button("Save as…") {
                        if let name = ask("Save this code as:", default: "") {
                            playground.item = progress.addSnippet(title: name, code: playground.code(progress, templates: store.library.playground))
                            playground.epoch += 1
                        }
                    }
                } else {
                    Button("Rename…") {
                        if let name = ask("Rename to:", default: progress.data.snippets[item]?.title ?? "") {
                            progress.renameSnippet(item, to: name)
                        }
                    }
                    Button("Delete", role: .destructive) {
                        if confirm("Delete “\(progress.data.snippets[item]?.title ?? "")”?") {
                            progress.deleteSnippet(item)
                            playground.item = "scratch"
                            playground.epoch += 1
                        }
                    }
                }
                Spacer()
                Toggle("Input", isOn: $playground.showStdin).toggleStyle(.button).help("Text for input() and sys.stdin")
                if runner.isRunning && runner.key == runKey {
                    Button { runner.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button(action: run) { Label("Run", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(runner.isRunning)
                }
            }
            .controlSize(.large)
            if playground.showStdin {
                TextEditor(text: Binding(get: { progress.data.stdin }, set: { progress.setStdin($0) }))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            }
            Workbench(fileName: item == "scratch" ? "scratch.py" : (progress.data.snippets[item]?.title ?? "snippet"),
                      code: playground.code(progress, templates: store.library.playground),
                      key: "pg:\(item)#\(playground.epoch)#\(progress.revision)", runKey: runKey,
                      onChange: { code in
                          if item == "scratch" { progress.setScratch(code) } else { progress.setSnippet(item, code: code) }
                      },
                      run: run)
            Text("Your own python3 runs this, with whatever packages you have installed. `from dc import stream, clickstream, ticks, sensor, orders, table, check` gives you data sources and test helpers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .onReceive(NotificationCenter.default.publisher(for: .runCode)) { _ in run() }
    }

    private func run() {
        guard !runner.isRunning else { return }
        runner.run(playground.code(progress, templates: store.library.playground), key: runKey,
                   helpers: store.library.helpers, stdin: progress.data.stdin)
    }
}

struct CodeHome: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        ContentUnavailableView {
            Label("Pick a problem", systemImage: "chevron.left.forwardslash.chevron.right")
        } description: {
            Text("\(progress.data.solved.keys.filter { store.problemByID[$0] != nil }.count) of \(store.library.problems.count) solved. Choose one in the sidebar, or open the playground to run any Python.")
        } actions: {
            Button("Playground") { navigator.openPlayground() }
            if let next = store.orderedProblems.first(where: { !progress.isSolved($0.id) }) {
                Button("Next unsolved: \(next.title)") { navigator.open(problem: next.id) }.buttonStyle(.borderedProminent)
            }
        }
    }
}

@MainActor
func confirm(_ message: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}

@MainActor
func ask(_ message: String, default value: String) -> String? {
    let alert = NSAlert()
    alert.messageText = message
    let field = NSTextField(string: value)
    field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
    alert.accessoryView = field
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = field.stringValue.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
}
