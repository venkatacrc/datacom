import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.library.subtitle.isEmpty ? "Crack the interview" : store.library.subtitle)
                        .font(.system(size: 34, weight: .bold))
                    Text("Library built \(store.library.built) · \(store.library.lessons.count) lessons · \(store.library.cards.count) cards · \(store.library.problems.count) problems")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Stat(value: progress.data.solved.keys.filter { store.problemByID[$0] != nil }.count, total: store.library.problems.count, label: "problems solved")
                    Stat(value: progress.data.cards.values.filter { $0 == "known" }.count, total: store.library.cards.count, label: "cards known")
                    Stat(value: progress.data.read.keys.filter { store.lessonByID[$0] != nil }.count, total: store.library.lessons.count, label: "lessons read")
                }
                HStack(spacing: 12) {
                    Button { navigator.openPlayground() } label: { Label("Playground", systemImage: "terminal") }
                    if let next = store.orderedProblems.first(where: { !progress.isSolved($0.id) }) {
                        Button { navigator.open(problem: next.id) } label: { Label("Next problem: \(next.title)", systemImage: "play") }
                    }
                    Button { navigator.focus = nil; navigator.mode = .cards } label: { Label("Practise cards", systemImage: "rectangle.on.rectangle.angled") }
                }
                .controlSize(.large)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(store.tracks) { track in TrackTile(track: track) }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

struct Stat: View {
    let value: Int
    let total: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)").font(.system(size: 26, weight: .bold)).monospacedDigit()
                Text("/\(total)").foregroundStyle(.secondary).monospacedDigit()
            }
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.08)))
    }
}

struct TrackTile: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var navigator: Navigator
    let track: Track

    var body: some View {
        let lessons = store.lessons(of: track.id)
        let problems = store.problems(of: track.id)
        let cards = store.cards(of: track.id)
        let read = lessons.filter { progress.isRead($0.id) }.count
        let solved = problems.filter { progress.isSolved($0.id) }.count
        let known = cards.filter { progress.mark($0.id) == "known" }.count
        let total = lessons.count + problems.count + cards.count
        VStack(alignment: .leading, spacing: 8) {
            Text(track.title).font(.headline)
            Text(track.blurb).font(.callout).foregroundStyle(.secondary).lineLimit(3).frame(maxHeight: .infinity, alignment: .top)
            ProgressView(value: total == 0 ? 0 : Double(read + solved + known) / Double(total)).tint(Color(hex: track.color))
            HStack(spacing: 10) {
                if !lessons.isEmpty {
                    Button("\(read)/\(lessons.count) lessons") {
                        navigator.open(lesson: lessons.first { !progress.isRead($0.id) }?.id ?? lessons[0].id)
                    }
                }
                if !problems.isEmpty {
                    Button("\(solved)/\(problems.count) problems") {
                        navigator.open(problem: problems.first { !progress.isSolved($0.id) }?.id ?? problems[0].id)
                    }
                }
                if !cards.isEmpty {
                    Button("\(cards.count) cards") {
                        navigator.practise(.init(kind: .track, id: track.id, title: track.title))
                    }
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14).fill(Color(hex: track.color)).frame(height: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

struct LessonDetail: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var navigator: Navigator
    @EnvironmentObject private var playground: PlaygroundModel
    let lesson: Lesson

    var body: some View {
        let list = store.lessons(of: lesson.track)
        let index = list.firstIndex(of: lesson) ?? 0
        VStack(spacing: 14) {
            HStack {
                Text("\(store.trackTitle(lesson.track)) · \(store.sectionTitle[lesson.section] ?? "")")
                    .font(.headline)
                Spacer()
                Text("\(index + 1) of \(list.count)").font(.callout).foregroundStyle(.secondary)
            }
            HTMLView(html: HTMLPage.lesson(lesson), key: lesson.id, onMessage: { type, body in
                if type == "try", let code = body["code"] as? String { playground.open(code, navigator: navigator, progress: progress, templates: store.library.playground) }
            }, onLink: open)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            HStack(spacing: 12) {
                Button { navigator.stepLesson(-1, in: store) } label: { Label("Previous", systemImage: "chevron.left") }
                    .disabled(!navigator.canStepLesson(-1, in: store))
                    .help("Previous lesson (⌘[)")
                Button { navigator.stepLesson(1, in: store) } label: { Label("Next", systemImage: "chevron.right") }
                    .disabled(!navigator.canStepLesson(1, in: store))
                    .help("Next lesson (⌘])")
                Spacer()
                let count = store.cards(lesson: lesson.id).count
                if count > 0 {
                    Button { navigator.practise(.init(kind: .lesson, id: lesson.id, title: lesson.title)) } label: {
                        Label("Practise \(count) cards", systemImage: "rectangle.on.rectangle.angled")
                    }
                    .help("Cards from this lesson only (⌘L)")
                }
                Button { HTMLPrinter.run(HTMLPage.lesson(lesson), title: lesson.title) } label: { Label("Print", systemImage: "printer") }
                    .help("Print or save as PDF (⌘P)")
                Button {
                    let wasRead = progress.isRead(lesson.id)
                    progress.toggleRead(lesson.id)
                    if !wasRead { navigator.stepLesson(1, in: store) }
                } label: {
                    Label(progress.isRead(lesson.id) ? "Read" : "Mark read",
                          systemImage: progress.isRead(lesson.id) ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(progress.isRead(lesson.id) ? .green : .accentColor)
                .help("Mark read and go to the next lesson")
            }
            .controlSize(.large)
        }
        .padding(22)
    }

    private func open(_ link: String) {
        let parts = link.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "lesson": if store.lessonByID[parts[1]] != nil { navigator.open(lesson: parts[1]) }
        case "problem": if store.problemByID[parts[1]] != nil { navigator.open(problem: parts[1]) }
        default: break
        }
    }
}
