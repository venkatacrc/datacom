import SwiftUI

struct CardsDetail: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var navigator: Navigator
    @ObservedObject var session: StudySession
    let restart: () -> Void

    private var testing: Bool { navigator.cardMode == .test }

    var body: some View {
        VStack(spacing: 16) {
            if let focus = navigator.focus {
                HStack {
                    Text("Cards from \(focus.title)").font(.headline)
                    Spacer()
                    Button("All selected tracks") { navigator.focus = nil }
                }
            }
            if testing && session.finished {
                summary
            } else if let card = session.current {
                header
                cardView(card)
                    .onTapGesture { if testing { session.revealed = true } }
                controls(card)
            } else {
                ContentUnavailableView("No cards to practise", systemImage: "rectangle.stack", description: Text(emptyHint))
            }
        }
        .padding(22)
    }

    private var emptyHint: String {
        switch navigator.filter {
        case .review: return "No cards here are marked for review. Press R on a card to mark it."
        case .unknown: return "Every card here is marked known."
        case .all: return "Tick at least one track in the sidebar."
        }
    }

    private var header: some View {
        HStack {
            Text("Card \(session.position + 1) of \(session.deck.count)").font(.headline)
            Spacer()
            if testing {
                let answered = session.answers.count
                Text("Score \(session.got) of \(answered) · \(session.deck.count - answered) to go").font(.callout.weight(.medium))
            } else {
                let known = session.deck.filter { progress.mark($0.id) == "known" }.count
                let review = session.deck.filter { progress.mark($0.id) == "review" }.count
                Text("Known \(known) · Review \(review)").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func cardView(_ card: Card) -> some View {
        let show = !testing || session.revealed
        let lesson = store.lessonByID[card.lesson]
        var html = card.front
        if show {
            html += "<div class=\"answer\">\(card.back)</div>"
            if let lesson { html += "<p class=\"fine\"><a href=\"#lesson/\(HTMLPage.esc(lesson.id))\">📖 \(HTMLPage.esc(lesson.title))</a></p>" }
        } else {
            html += "<p class=\"fine\" style=\"margin-top:28px;text-align:center\">Recall the answer, then press Space or click the card.</p>"
        }
        let mark = progress.mark(card.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(store.trackTitle(card.track))\(card.label.isEmpty ? "" : " · " + card.label)".uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: store.trackByID[card.track]?.color ?? ""))
                    .lineLimit(1)
                Spacer()
                if let mark {
                    Text(mark == "known" ? "Known" : "Review")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .foregroundStyle(mark == "known" ? Color.green : Color.orange)
                        .background(Capsule().fill((mark == "known" ? Color.green : Color.orange).opacity(0.16)))
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 18)
            HTMLView(html: html, key: "\(card.id)#\(show)", onLink: { link in
                if link.hasPrefix("lesson/") { navigator.open(lesson: String(link.dropFirst(7))) }
            })
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(Color(hex: store.trackByID[card.track]?.color ?? "")).frame(height: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
        .contentShape(Rectangle())
    }

    private func controls(_ card: Card) -> some View {
        HStack(spacing: 12) {
            Button { session.move(-1, testing: testing) } label: { Label("Previous", systemImage: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            if testing {
                if session.revealed {
                    Button { session.answer(false, progress: progress) } label: { Label("Missed it (M)", systemImage: "xmark.circle") }
                        .keyboardShortcut("m", modifiers: [])
                        .tint(.orange)
                    Button { session.answer(true, progress: progress) } label: { Label("Got it (G)", systemImage: "checkmark.circle") }
                        .keyboardShortcut("g", modifiers: [])
                        .tint(.green)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { session.revealed = true } label: { Label("Show answer", systemImage: "eye") }
                        .keyboardShortcut(.space, modifiers: [])
                        .buttonStyle(.borderedProminent)
                }
            }
            Button { session.move(1, testing: testing) } label: { Label(testing ? "Skip" : "Next", systemImage: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Spacer()
            if !testing {
                let mark = progress.mark(card.id)
                Button { progress.toggle(card.id, "known") } label: {
                    Label("Known (K)", systemImage: mark == "known" ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .keyboardShortcut("k", modifiers: [])
                Button { progress.toggle(card.id, "review") } label: {
                    Label("Review (R)", systemImage: mark == "review" ? "flag.fill" : "flag")
                }
                .keyboardShortcut("r", modifiers: [])
            }
        }
        .controlSize(.large)
    }

    private var summary: some View {
        let missed = session.missed
        let total = session.deck.count
        let percent = total == 0 ? 0 : Int((Double(session.got) / Double(total) * 100).rounded())
        return VStack(spacing: 16) {
            Image(systemName: missed.isEmpty ? "star.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(missed.isEmpty ? .yellow : .green)
            Text("Test complete").font(.largeTitle.weight(.semibold))
            Text("\(session.got) of \(total) correct (\(percent)%)").font(.title2)
            Text(missed.isEmpty ? "Every card you answered is now marked known."
                 : "Cards you got are marked known; the \(missed.count) you missed are marked for review.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if !missed.isEmpty {
                    Button("Retest the \(missed.count) missed") { session.retestMissed() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Button("Start a new test", action: restart)
                Button("Switch to Learn") { navigator.cardMode = .learn }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
