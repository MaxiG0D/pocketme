import SwiftUI
import WebKit

struct ReaderWebView {
    let article: Article
    let fileURL: URL?
    let configurationJSON: String
    let next: Article?
    let onMessage: @MainActor (String, Double?) -> Void
    let openLink: @MainActor (URL) -> Void
    let saveLink: @MainActor (URL) -> Void

    let reduceMotion: Bool

    @MainActor func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let controller = configuration.userContentController
        controller.add(coordinator, name: "reader")
        if let url = Bundle.main.url(forResource: "reader", withExtension: "js"), let source = try? String(contentsOf: url, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = coordinator
        web.uiDelegate = coordinator
        #if os(iOS)
        web.isOpaque = false
        web.backgroundColor = UIColor(named: "Paper")
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #else
        web.autoresizingMask = [.width, .height]
        #endif
        return web
    }

    @MainActor func update(_ container: PlatformView, coordinator: Coordinator) {
        coordinator.parent = self
        let key = article.id.uuidString + ":\(article.contentHTML?.count ?? 0):\(article.wordCount):\(fileURL?.path ?? ""):\(article.statusRaw)"
        if coordinator.loadedKey != key {
            coordinator.loadedKey = key
            coordinator.load(into: container)
        } else if let web = coordinator.active { coordinator.configure(web) }
    }

    @MainActor func load(_ web: WKWebView) {
        if let fileURL {
            web.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        } else if article.contentHTML != nil,
                  let html = try? ReaderDocument.html(article: ArticleContent(article), content: ArticleContent(article).html, leadImage: article.leadImageURL, leadSource: article.leadImageURL, offline: false) {
            web.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        } else if let url = URL(string: article.url) { web.load(URLRequest(url: url)) }
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        var parent: ReaderWebView
        var loadedKey = ""
        var sentNextKey: String?
        /// The page on screen, and the next page loading invisibly above it until it has laid out.
        private var current: WKWebView?
        private var incoming: WKWebView?
        var active: WKWebView? { incoming ?? current }
        init(_ parent: ReaderWebView) { self.parent = parent }

        /// Switching articles keeps the old page in place and fades the new one in once it is styled and scrolled,
        /// so the reader never flashes blank or shows the page restyling itself.
        func load(into container: PlatformView) {
            if let incoming { discard(incoming) }
            let web = parent.makeWebView(coordinator: self)
            web.frame = container.bounds
            setAlpha(web, 0)
            container.addSubview(web)
            incoming = web
            sentNextKey = nil
            parent.load(web)
            // A page that never reports itself laid out (an original site, a failed load) still appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak web] in
                if let web { self?.reveal(web) }
            }
        }
        private func reveal(_ web: WKWebView) {
            guard web === incoming else { return }
            incoming = nil
            let old = current
            current = web
            #if os(macOS)
            web.window?.makeFirstResponder(web)
            #endif
            let finish = { [weak self] in if let old, old !== self?.current { self?.discard(old) } }
            if parent.reduceMotion {
                setAlpha(web, 1); finish()
            } else {
                #if os(iOS)
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: { web.alpha = 1 }, completion: { _ in finish() })
                #else
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    web.animator().alphaValue = 1
                }, completionHandler: finish)
                #endif
            }
        }
        private func discard(_ web: WKWebView) {
            web.stopLoading()
            web.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
            web.removeFromSuperview()
        }
        private func setAlpha(_ web: WKWebView, _ alpha: CGFloat) {
            #if os(iOS)
            web.alpha = alpha
            #else
            web.alphaValue = alpha
            #endif
        }
        func configure(_ web: WKWebView) {
            web.evaluateJavaScript("window.pocketmeConfigure && window.pocketmeConfigure(\(parent.configurationJSON))", completionHandler: nil)
            // The next article's thumbnail is large, so it is sent only when the next article changes.
            let nextKey = parent.next.map { "\($0.id):\($0.title):\($0.thumbnailData?.count ?? 0)" } ?? ""
            guard nextKey != sentNextKey else { return }
            sentNextKey = nextKey
            web.evaluateJavaScript("window.pocketmeNext && window.pocketmeNext(\(ReaderDocument.nextJSON(parent.next)))", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === active else { return }
            sentNextKey = nil
            configure(webView)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Only the newest page speaks; the page being replaced is already somebody else's article.
            guard message.frameInfo.isMainFrame, let web = message.webView, web === active,
                  let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
            switch action {
            case "ready": sentNextKey = nil; configure(web)
            case "shown": reveal(web)
            default: if web === current { parent.onMessage(action, body["value"] as? Double) }
            }
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
typealias PlatformView = UIView
extension ReaderWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) { update(uiView, coordinator: context.coordinator) }
}
#else
typealias PlatformView = NSView
extension ReaderWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) { update(nsView, coordinator: context.coordinator) }
}
#endif
