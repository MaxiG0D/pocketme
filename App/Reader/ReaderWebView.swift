import SwiftUI
import WebKit

struct ReaderWebView {
    let article: Article
    let fileURL: URL?
    let configurationJSON: String
    let onMessage: @MainActor (String, Double?) -> Void
    let openLink: @MainActor (URL) -> Void
    let saveLink: @MainActor (URL) -> Void

    @MainActor func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = configuration.userContentController
        controller.add(context.coordinator, name: "reader")
        if let url = Bundle.main.url(forResource: "reader", withExtension: "js"), let source = try? String(contentsOf: url, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        #if os(iOS)
        web.isOpaque = false
        web.backgroundColor = UIColor(named: "Paper")
        #endif
        return web
    }

    @MainActor func update(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.parent = self
        let key = article.id.uuidString + ":\(article.contentHTML?.count ?? 0):\(article.wordCount):\(fileURL?.path ?? ""):\(article.statusRaw)"
        if coordinator.loadedKey != key {
            coordinator.loadedKey = key
            if let fileURL {
                web.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
            } else if article.contentHTML != nil,
                      let html = try? ReaderDocument.html(article: ArticleContent(article), content: ArticleContent(article).html, leadImage: article.leadImageURL, offline: false) {
                web.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
            } else if let url = URL(string: article.url) { web.load(URLRequest(url: url)) }
        } else { coordinator.configure(web) }
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        var parent: ReaderWebView
        var loadedKey = ""
        init(_ parent: ReaderWebView) { self.parent = parent }
        func configure(_ web: WKWebView) {
            web.evaluateJavaScript("window.pocketmeConfigure && window.pocketmeConfigure(\(parent.configurationJSON))", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            configure(webView)
            #if os(macOS)
            webView.window?.makeFirstResponder(webView)
            #endif
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
            if action == "ready", let web = message.webView { configure(web) }
            else { parent.onMessage(action, body["value"] as? Double) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if ["http", "https"].contains(url.scheme ?? "") { parent.openLink(url) }
                return .cancel
            } else { return .allow }
        }
        #if os(iOS)
        func webView(_ webView: WKWebView, contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
            guard let url = elementInfo.linkURL, ["http", "https"].contains(url.scheme ?? "") else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                UIMenu(children: [UIAction(title: "Save to PocketMe", image: UIImage(systemName: "book")) { _ in self?.parent.saveLink(url) },
                                  UIAction(title: "Open in browser", image: UIImage(systemName: "safari")) { _ in self?.parent.openLink(url) }])
            }
        }
        #endif
    }
}

#if os(iOS)
extension ReaderWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ uiView: WKWebView, context: Context) { update(uiView, coordinator: context.coordinator) }
}
#else
extension ReaderWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ nsView: WKWebView, context: Context) { update(nsView, coordinator: context.coordinator) }
}
#endif
