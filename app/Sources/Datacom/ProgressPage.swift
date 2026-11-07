import SwiftUI

struct ProgressPage: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Progress").font(.largeTitle.weight(.bold))
                HStack(spacing: 12) {
                    Stat(value: progress.data.solved.keys.filter { store.problemByID[$0] != nil }.count, total: store.library.problems.count, label: "problems solved")
                    Stat(value: progress.data.cards.values.filter { $0 == "known" }.count, total: store.library.cards.count, label: "cards known")
                    Stat(value: progress.data.cards.values.filter { $0 == "review" }.count, total: store.library.cards.count, label: "cards to review")
                    Stat(value: progress.data.read.keys.filter { store.lessonByID[$0] != nil }.count, total: store.library.lessons.count, label: "lessons read")
                }
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        Text("Track").font(.headline)
                        Text("Lessons read").font(.headline)
                        Text("Cards known").font(.headline)
                        Text("Problems solved").font(.headline)
                    }
                    Divider().gridCellColumns(4)
                    ForEach(store.tracks) { track in
                        let lessons = store.lessons(of: track.id)
                        let cards = store.cards(of: track.id)
                        let problems = store.problems(of: track.id)
                        GridRow {
                            HStack {
                                Circle().fill(Color(hex: track.color)).frame(width: 9, height: 9)
                                Text(track.title)
                            }
                            Meter(done: lessons.filter { progress.isRead($0.id) }.count, total: lessons.count, color: Color(hex: track.color))
                            Meter(done: cards.filter { progress.mark($0.id) == "known" }.count, total: cards.count, color: Color(hex: track.color))
                            Meter(done: problems.filter { progress.isSolved($0.id) }.count, total: problems.count, color: Color(hex: track.color))
                        }
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor)))

                let recent = progress.data.solved.filter { store.problemByID[$0.key] != nil }.sorted { $0.value.at > $1.value.at }.prefix(10)
                if !recent.isEmpty {
                    Text("Recently solved").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(recent), id: \.key) { id, s in
                            Button {
                                navigator.open(problem: id)
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    Text(store.problemByID[id]?.title ?? id)
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: s.at / 1000).formatted(date: .abbreviated, time: .shortened))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 12) {
                    Button { progress.exportProgress() } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                    Button { progress.importProgress() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                    Spacer()
                    Button("Reset progress…", role: .destructive) { progress.reset() }
                }
                .controlSize(.large)
                Text("Progress, your code and snippets are saved in ~/Library/Application Support/Datacom. Export moves them to the web app on your phone (☰ ▸ Import progress) and back; imports merge, so nothing is lost.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }
}

struct Meter: View {
    let done: Int
    let total: Int
    let color: Color

    var body: some View {
        if total == 0 {
            Text("—").foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 8) {
                ProgressView(value: Double(done) / Double(total)).tint(color).frame(width: 110)
                Text("\(done)/\(total)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
