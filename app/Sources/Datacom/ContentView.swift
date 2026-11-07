import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var navigator: Navigator
    @EnvironmentObject private var runner: PythonRunner
    @StateObject private var session = StudySession()

    var body: some View {
        NavigationSplitView {
            Sidebar(search: navigator.search)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            detail
                .toolbar { toolbar }
                .navigationTitle(title)
        }
        .searchable(text: $navigator.search, placement: .sidebar, prompt: navigator.mode == .code ? "Filter problems" : "Filter lessons")
        .onAppear(perform: rebuildDeck)
        .onChange(of: navigator.mode) { if navigator.mode == .cards { rebuildDeck() } }
        .onChange(of: navigator.cardMode) { rebuildDeck() }
        .onChange(of: navigator.filter) { rebuildDeck() }
        .onChange(of: navigator.shuffle) { rebuildDeck() }
        .onChange(of: navigator.focus) { rebuildDeck() }
        .onChange(of: progress.data.selected) { rebuildDeck() }
        .onChange(of: store.library.version) { rebuildDeck() }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil || progress.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil; progress.errorMessage = nil } })
        ) {
            Button("OK") { store.errorMessage = nil; progress.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? progress.errorMessage ?? "")
        }
    }

    private func rebuildDeck() { session.rebuild(store: store, progress: progress, navigator: navigator) }

    private var title: String {
        switch navigator.mode {
        case .learn: return navigator.lessonID.flatMap { store.lessonByID[$0]?.title } ?? store.library.title
        case .code:
            if navigator.codeItem == Navigator.playground { return "Playground" }
            return navigator.codeItem.flatMap { store.problemByID[$0]?.title } ?? "Code"
        default: return navigator.mode.title
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigator.mode {
        case .learn:
            if let id = navigator.lessonID, let lesson = store.lessonByID[id] {
                LessonDetail(lesson: lesson)
            } else {
                HomeView()
            }
        case .cards:
            CardsDetail(session: session, restart: rebuildDeck)
        case .code:
            if navigator.codeItem == Navigator.playground {
                PlaygroundView()
            } else if let id = navigator.codeItem, let problem = store.problemByID[id] {
                ProblemView(problem: problem)
            } else {
                CodeHome()
            }
        case .progress:
            ProgressPage()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("View", selection: $navigator.mode) {
                ForEach(Mode.allCases) { Label($0.title, systemImage: $0.symbol).labelStyle(.titleOnly).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Learn, Cards, Code, Progress (⌘1 to ⌘4)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if store.rebuilding {
                ProgressView().controlSize(.small).help("Rebuilding the library from your repos…")
            }
            switch navigator.mode {
            case .cards:
                Picker("Mode", selection: $navigator.cardMode) {
                    ForEach(CardMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Learn: see each card in full. Test: recall it, then mark whether you got it.")
                Picker("Cards", selection: $navigator.filter) {
                    ForEach(CardFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Toggle(isOn: $navigator.shuffle) { Label("Shuffle", systemImage: "shuffle") }
                    .toggleStyle(.button)
                    .help("Shuffle the deck")
                Button(action: rebuildDeck) { Label("Restart", systemImage: "arrow.counterclockwise") }
                    .help("Start the deck again")
            case .code:
                if navigator.codeItem != nil {
                    if runner.isRunning {
                        Button { runner.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                            .help("Stop the program (⌘.)")
                    } else {
                        Button { NotificationCenter.default.post(name: .runCode, object: nil) } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .help("Run (⌘R)")
                    }
                }
            case .learn:
                if navigator.lessonID != nil {
                    Button { navigator.lessonID = nil } label: { Label("Home", systemImage: "house") }
                        .help("All tracks")
                }
            case .progress:
                EmptyView()
            }
        }
    }
}

extension Notification.Name {
    /// Sent by the toolbar and ⌘R; the open problem or playground runs its code.
    static let runCode = Notification.Name("datacom.runCode")
}

// ---- sidebar ----

struct Sidebar: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var navigator: Navigator
    let search: String
    @AppStorage("codeFilter") private var codeFilter = "all"

    private func matches(_ text: String) -> Bool {
        let terms = search.lowercased().split(separator: " ")
        let t = text.lowercased()
        return terms.allSatisfy { t.contains($0) }
    }

    private func expanded(_ id: String) -> Binding<Bool> {
        Binding(get: { !search.isEmpty || !navigator.collapsed.contains(id) },
                set: { if $0 { navigator.collapsed.remove(id) } else { navigator.collapsed.insert(id) } })
    }

    var body: some View {
        switch navigator.mode {
        case .learn: learn
        case .cards, .progress: tracks
        case .code: code
        }
    }

    private var learn: some View {
        List(selection: $navigator.lessonID) {
            ForEach(store.tracks) { track in
                let lessons = store.lessons(of: track.id).filter { matches("\($0.title) \(store.sectionTitle[$0.section] ?? "")") }
                if !lessons.isEmpty {
                    Section(isExpanded: expanded(track.id)) {
                        ForEach(track.sections) { section in
                            let rows = lessons.filter { $0.section == section.id }
                            if !rows.isEmpty {
                                Text(section.title.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                    .selectionDisabled()
                                ForEach(rows) { lesson in
                                    Label {
                                        Text(lesson.title).lineLimit(2)
                                    } icon: {
                                        Image(systemName: progress.isRead(lesson.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(progress.isRead(lesson.id) ? Color.green : Color.secondary)
                                    }
                                    .tag(Optional(lesson.id))
                                }
                            }
                        }
                    } header: {
                        TrackHeader(track: track, done: lessons.filter { progress.isRead($0.id) }.count, total: lessons.count)
                    }
                }
            }
        }
    }

    private var code: some View {
        List(selection: $navigator.codeItem) {
            Label("Playground", systemImage: "terminal").tag(Optional(Navigator.playground))
            ForEach(store.tracks) { track in
                let problems = store.problems(of: track.id).filter { p in
                    matches("\(p.title) \(p.tags.joined(separator: " ")) \(p.difficulty)")
                        && (codeFilter == "all" || (codeFilter == "solved") == progress.isSolved(p.id))
                }
                if !problems.isEmpty {
                    Section(isExpanded: expanded("code-" + track.id)) {
                        ForEach(track.sections) { section in
                            let rows = problems.filter { $0.section == section.id }
                            if !rows.isEmpty {
                                Text(section.title.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                    .selectionDisabled()
                                ForEach(rows) { p in ProblemRow(problem: p).tag(Optional(p.id)) }
                            }
                        }
                    } header: {
                        TrackHeader(track: track, done: problems.filter { progress.isSolved($0.id) }.count, total: problems.count)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("Show", selection: $codeFilter) {
                Text("All").tag("all")
                Text("To do").tag("todo")
                Text("Solved").tag("solved")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var tracks: some View {
        let selected = progress.selected(in: store.tracks)
        return List {
            Section("Tracks in Cards") {
                ForEach(store.tracks) { track in
                    Toggle(isOn: Binding(
                        get: { selected.contains(track.id) },
                        set: { on in
                            var s = selected
                            if on { s.insert(track.id) } else { s.remove(track.id) }
                            progress.setSelected(s, in: store.tracks)
                            navigator.focus = nil
                        })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                            Text("\(store.cards(of: track.id).count) cards · \(store.lessons(of: track.id).count) lessons · \(store.problems(of: track.id).count) problems")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Section {
                HStack {
                    Button("Select all") { progress.setSelected(Set(store.tracks.map(\.id)), in: store.tracks) }
                    Button("Clear") { progress.setSelected([], in: store.tracks) }
                }
                .buttonStyle(.link)
            }
        }
    }
}

struct TrackHeader: View {
    let track: Track
    let done: Int
    let total: Int

    var body: some View {
        HStack {
            Circle().fill(Color(hex: track.color)).frame(width: 8, height: 8)
            Text(track.title)
            Spacer()
            Text("\(done)/\(total)").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

struct ProblemRow: View {
    @EnvironmentObject private var progress: ProgressStore
    let problem: Problem

    var body: some View {
        HStack(spacing: 8) {
            if progress.isSolved(problem.id) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if progress.attempt(problem.id) != nil {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(.orange)
            } else {
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            Text(problem.title).lineLimit(1)
            Spacer()
            DifficultyBadge(difficulty: problem.difficulty)
        }
    }
}

struct DifficultyBadge: View {
    let difficulty: String

    var color: Color {
        switch difficulty.lowercased() {
        case "easy": return .green
        case "hard": return .red
        default: return .orange
        }
    }

    var body: some View {
        Text(difficulty)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 6 {
            self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
        } else {
            self = .accentColor
        }
    }
}
