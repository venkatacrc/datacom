import AppKit
import SwiftUI
import WebKit

/// Serves the bundled web assets (render.js, content.css, KaTeX) at dc://app/…, so lesson HTML
/// renders exactly as in the web app.
final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "dc"
    static let base = URL(string: "dc://app/")!
    private let root = AppFiles.resource("web", nil)?.standardizedFileURL

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let root else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let file = root.appendingPathComponent(String(url.path.drop(while: { $0 == "/" }))).standardizedFileURL
        guard file.path.hasPrefix(root.path), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let types = ["js": "text/javascript", "css": "text/css", "woff2": "font/woff2", "woff": "font/woff",
                     "ttf": "font/ttf", "html": "text/html", "json": "application/json", "svg": "image/svg+xml",
                     "png": "image/png"]
        let headers = ["Content-Type": types[file.pathExtension] ?? "application/octet-stream",
                       "Access-Control-Allow-Origin": "*"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(ResourceSchemeHandler(), forURLScheme: scheme)
        return config
    }
}

enum HTMLPage {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func document(_ body: String, title: String = "", print: Bool = false) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(esc(title))</title>
        <link rel="stylesheet" href="content.css">
        <style>
          body { margin: 0; padding: \(print ? "0" : "26px 34px 40px"); font: 16px/1.6 var(--ui);
                 color: var(--text); background: transparent; -webkit-font-smoothing: antialiased; }
          main { max-width: 860px; margin: 0 auto; }
          .answer { margin-top: 18px; padding-top: 16px; border-top: 1px dashed var(--line); }
          .source-link { margin-top: 28px; }
          details { margin: 14px 0; border: 1px solid var(--line); border-radius: 12px; padding: 4px 14px; }
          details > summary { cursor: pointer; font-weight: 600; color: var(--muted); padding: 6px 0; }
          details.solution { border-color: color-mix(in srgb, var(--orange) 50%, var(--line)); }
        </style></head>
        <body><main class="content">\(body)</main>
        <script src="render.js"></script>
        <script>
          const post = (m) => window.webkit && webkit.messageHandlers.dc && webkit.messageHandlers.dc.postMessage(m);
          DCRender.renderAll(document.body, {
            onTry: (code) => post({ type: 'try', code }),
            onCopy: (text, btn) => { post({ type: 'copy', text }); const t = btn.textContent; btn.textContent = 'Copied'; setTimeout(() => { btn.textContent = t; }, 1200); },
          });
          document.querySelectorAll('a[href^="http"]').forEach((a) => a.setAttribute('target', '_blank'));
        </script>
        </body></html>
        """
    }

    static func lesson(_ l: Lesson) -> String {
        l.html + (l.url.isEmpty ? "" : "<p class=\"fine source-link\"><a href=\"\(esc(l.url))\">↗ Open the original</a></p>")
    }
}

/// A web view showing one HTML body. Links to #lesson/… and #problem/… navigate the app, Try
/// opens code in the playground, and outside links open in the browser.
struct HTMLView: NSViewRepresentable {
    let html: String
    /// Reloads only when this changes, so SwiftUI updates don't reset the scroll position.
    let key: String
    var onMessage: (String, [String: Any]) -> Void = { _, _ in }
    var onLink: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = ResourceSchemeHandler.configuration()
        config.userContentController.add(context.coordinator, name: "dc")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = true
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        context.coordinator.onLink = onLink
        guard context.coordinator.loaded != key else { return }
        context.coordinator.loaded = key
        view.loadHTMLString(HTMLPage.document(html), baseURL: ResourceSchemeHandler.base)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "dc")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var loaded = ""
        var onMessage: (String, [String: Any]) -> Void = { _, _ in }
        var onLink: (String) -> Void = { _ in }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "copy" {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
                return
            }
            onMessage(type, body)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            if url.scheme == ResourceSchemeHandler.scheme {
                let fragment = url.fragment ?? ""
                if fragment.hasPrefix("lesson/") || fragment.hasPrefix("problem/") || fragment.hasPrefix("track/") {
                    onLink(fragment)
                    return .cancel
                }
                return .allow
            }
            NSWorkspace.shared.open(url)
            return .cancel
        }

        // target=_blank links
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { NSWorkspace.shared.open(url) }
            return nil
        }
    }
}

/// Prints HTML from an off-screen web view (File ▸ Print, or Save as PDF from the print panel).
@MainActor
final class HTMLPrinter: NSObject, WKNavigationDelegate {
    private static var current: HTMLPrinter?
    private let window: NSWindow
    private let webView: WKWebView
    private let title: String

    static func run(_ body: String, title: String) {
        let printer = HTMLPrinter(title: title)
        current = printer
        printer.webView.loadHTMLString(HTMLPage.document(body, title: title, print: true), baseURL: ResourceSchemeHandler.base)
    }

    private init(title: String) {
        self.title = title
        let frame = NSRect(x: 0, y: 0, width: 780, height: 1000)
        webView = WKWebView(frame: frame, configuration: ResourceSchemeHandler.configuration())
        window = NSWindow(contentRect: frame.offsetBy(dx: -20000, dy: -20000), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        super.init()
        window.contentView = webView
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give KaTeX a moment to typeset before paginating.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.printNow() }
    }

    private func printNow() {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 40
        info.bottomMargin = 40
        info.leftMargin = 40
        info.rightMargin = 40
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        let op = webView.printOperation(with: info)
        op.jobTitle = title
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.view?.frame = webView.bounds
        if let host = NSApp.keyWindow ?? NSApp.mainWindow {
            op.runModal(for: host, delegate: self,
                        didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        } else {
            op.run()
            finish()
        }
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                            contextInfo: UnsafeMutableRawPointer?) {
        finish()
    }

    private func finish() {
        window.close()
        HTMLPrinter.current = nil
    }
}
