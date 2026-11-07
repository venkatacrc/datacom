import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DatacomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore()
    @StateObject private var progress = ProgressStore()
    @StateObject private var navigator = Navigator()
    @StateObject private var runner = PythonRunner()
    @StateObject private var playground = PlaygroundModel()

    var body: some Scene {
        WindowGroup("Datacom") {
            ContentView()
                .environmentObject(store)
                .environmentObject(progress)
                .environmentObject(navigator)
                .environmentObject(runner)
                .environmentObject(playground)
                .frame(minWidth: 1000, minHeight: 640)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    runner.stop()
                    progress.save()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .printItem) {
                Button("Print / Save as PDF…") { printCurrent() }
                    .keyboardShortcut("p")
            }
            CommandGroup(after: .newItem) {
                Button("Rebuild Library from Repos") { store.rebuild() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(store.rebuilding)
                Button("Use the Library Bundled in the App") { store.useBundledLibrary() }
                Divider()
                Button("Export Progress…") { progress.exportProgress() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Import Progress…") { progress.importProgress() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Reset Progress…") { progress.reset() }
            }
            CommandMenu("Go") {
                ForEach(Array(Mode.allCases.enumerated()), id: \.element) { index, mode in
                    Button(mode.title) { navigator.mode = mode }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
                Divider()
                Button("Previous") { navigator.step(-1, in: store) }
                    .keyboardShortcut("[")
                Button("Next") { navigator.step(1, in: store) }
                    .keyboardShortcut("]")
                Button("Playground") { navigator.openPlayground() }
                    .keyboardShortcut("y")
                Button("Practise This Lesson's Cards") {
                    if let id = navigator.lessonID, let lesson = store.lessonByID[id] {
                        navigator.practise(.init(kind: .lesson, id: id, title: lesson.title))
                    }
                }
                .keyboardShortcut("l")
            }
            CommandMenu("Run") {
                Button("Run") { NotificationCenter.default.post(name: .runCode, object: nil) }
                    .keyboardShortcut("r")
                    .disabled(navigator.mode != .code || runner.isRunning)
                Button("Stop") { runner.stop() }
                    .keyboardShortcut(".")
                    .disabled(!runner.isRunning)
                Divider()
                Button("Find python3 Again") { runner.locatePython() }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(runner)
                .environmentObject(store)
        }
    }

    @MainActor
    private func printCurrent() {
        switch navigator.mode {
        case .learn:
            if let id = navigator.lessonID, let lesson = store.lessonByID[id] {
                HTMLPrinter.run(HTMLPage.lesson(lesson), title: lesson.title)
            }
        case .code:
            if let id = navigator.codeItem, let p = store.problemByID[id] {
                let body = "<h1>\(HTMLPage.esc(p.title))</h1>\(p.prompt)<h3>My code</h3><pre><code class=\"language-python\">\(HTMLPage.esc(progress.code(for: p)))</code></pre>"
                HTMLPrinter.run(body, title: p.title)
            }
        default:
            NSSound.beep()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var runner: PythonRunner
    @EnvironmentObject private var store: LibraryStore
    @AppStorage("python") private var python = ""

    var body: some View {
        Form {
            Section("Python") {
                TextField("Interpreter", text: $python, prompt: Text("python3 from your shell"))
                    .onSubmit { runner.locatePython() }
                HStack {
                    Text(runner.interpreter.isEmpty ? "…" : runner.interpreter).font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text(runner.interpreterInfo).font(.caption).foregroundStyle(.secondary)
                }
                Text("Leave empty to use the python3 your Terminal finds. Point it at a venv or conda python (…/bin/python) to use that environment's packages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply") { runner.locatePython() }
            }
            Section("Library") {
                LabeledContent("Repo", value: AppFiles.repo.path)
                LabeledContent("Built", value: store.library.built)
                LabeledContent("Version", value: store.library.version)
                Text("File ▸ Rebuild Library from Repos re-reads ~/code/algos, deepmath, gpukernels and the other sources listed in sources.json, and also refreshes web/library.json for the phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding()
    }
}
