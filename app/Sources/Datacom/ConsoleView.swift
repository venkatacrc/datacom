import AppKit
import SwiftUI

/// Program output: stdout in the normal colour, stderr in red. Follows new output while the
/// view is scrolled to the bottom.
struct ConsoleView: NSViewRepresentable {
    @ObservedObject var runner: PythonRunner
    let key: String

    final class Coordinator {
        var revision = -1
        var key = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false
            view.isSelectable = true
            view.isRichText = false
            view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            view.textContainerInset = NSSize(width: 8, height: 8)
            view.backgroundColor = .textBackgroundColor
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        guard c.revision != runner.revision || c.key != key, let view = scroll.documentView as? NSTextView else { return }
        c.revision = runner.revision
        c.key = key
        let clip = scroll.contentView
        let atBottom = clip.bounds.maxY >= view.frame.height - 30
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let out = NSMutableAttributedString()
        if runner.key == key {
            for chunk in runner.chunks {
                out.append(NSAttributedString(string: chunk.text, attributes: [
                    .font: font, .foregroundColor: chunk.isError ? NSColor.systemRed : NSColor.textColor,
                ]))
            }
        }
        view.textStorage?.setAttributedString(out)
        if atBottom || runner.isRunning { view.scrollToEndOfDocument(nil) }
    }
}

/// "Running… 1.2 s", "✓ 5/5 tests passed", "✗ Error" and so on.
struct RunStatus: View {
    @ObservedObject var runner: PythonRunner
    let key: String

    var body: some View {
        Group {
            if runner.key != key {
                Text("Ready · ⌘R runs").foregroundStyle(.secondary)
            } else {
                switch runner.status {
                case .idle:
                    Text("Ready · ⌘R runs").foregroundStyle(.secondary)
                case .running(let start):
                    TimelineView(.periodic(from: start, by: 0.1)) { context in
                        Text("Running… \(context.date.timeIntervalSince(start), specifier: "%.1f") s · ⌘. stops")
                            .foregroundStyle(.secondary)
                    }
                case .stopped(let seconds):
                    Text("■ Stopped after \(seconds, specifier: "%.2f") s").foregroundStyle(.orange)
                case .finished(let ok, let seconds, let result):
                    if let result, result.total > 0 {
                        let all = result.passed == result.total
                        Text("\(all ? "✓" : "✗") \(result.passed)/\(result.total) tests passed · \(seconds, specifier: "%.2f") s")
                            .foregroundStyle(all ? .green : .red)
                    } else if ok {
                        Text("✓ Finished in \(seconds, specifier: "%.2f") s").foregroundStyle(.green)
                    } else {
                        Text("✗ Error after \(seconds, specifier: "%.2f") s").foregroundStyle(.red)
                    }
                }
            }
        }
        .font(.callout.weight(.medium))
        .lineLimit(1)
    }
}
