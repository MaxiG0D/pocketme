import Foundation
import WebKit

struct ExtractedArticle: Codable, Sendable {
    var title: String
    var siteName: String
    var author: String?
    var excerpt: String?
    var leadImageURL: String?
    var imageCandidates: [String]?
    var content: String?
    var wordCount: Int
    var isExternal: Bool? = false
    /// A video's length; articles estimate from their word count.
    var minutes: Int?
    var readingMinutes: Int { minutes ?? max(1, Int((Double(wordCount) / 230).rounded())) }
}

@MainActor
final class ExtractionService: NSObject, WKNavigationDelegate {
    enum ExtractionError: Error { case timedOut, noArticle, resourceMissing }
    private let webView: WKWebView
    private var continuation: CheckedContinuation<ExtractedArticle, Error>?
    private var timeout: Task<Void, Never>?
    private var requestID = UUID()

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = Self.userAgent
    }

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15"
    private var quickMode = false

    func extract(url: URL) async throws -> ExtractedArticle {
        // Most articles are plain server-rendered HTML: fetch it directly and parse it without loading any subresources.
        if !url.isFileURL, let (html, base) = await fetchHTML(url) {
            try Task.checkCancellation()
            quickMode = true
            let quick = try? await run { $0.loadHTMLString(html, baseURL: base) }
            if let quick, quick.isExternal != true, quick.wordCount >= 120 { return quick }
        }
        try Task.checkCancellation()
        quickMode = false
        return try await run { webView in
            if url.isFileURL { webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
            else { webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)) }
        }
    }

    private func fetchHTML(_ url: URL) async -> (String, URL)? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              ["text/html", "application/xhtml+xml"].contains(http.mimeType ?? ""), data.count < 5_000_000 else { return nil }
        var encoding = String.Encoding.utf8
        if let name = http.textEncodingName {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId { encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)) }
        }
        guard let html = String(data: data, encoding: encoding) else { return nil }
        return (html, http.url ?? url)
    }

    private func run(_ start: @escaping (WKWebView) -> Void) async throws -> ExtractedArticle {
        await installRules()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let id = UUID(); requestID = id
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(self?.quickMode == true ? 8 : 20))
                    guard !Task.isCancelled, self?.requestID == id else { return }
                    self?.finish(.failure(ExtractionError.timedOut))
                }
                start(webView)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        preferences.allowsContentJavaScript = !quickMode
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let id = requestID
        Task { [weak self] in
            do {
                if self?.quickMode != true { try await Task.sleep(for: .milliseconds(150)) }
                guard let self, self.requestID == id, self.continuation != nil else { return }
                for name in ["Readability", "extract"] {
                    let source = try Self.script(name)
                    if name == "Readability" { _ = try await self.evaluate(source) }
                    else {
                        guard let json = try await self.evaluate(source), let data = json.data(using: .utf8) else { throw ExtractionError.noArticle }
                        let article = try JSONDecoder().decode(ExtractedArticle.self, from: data)
                        self.finish(.success(article))
                    }
                }
            } catch { self?.finish(.failure(error)) }
        }
    }

    private static var scripts: [String: String] = [:]
    private static func script(_ name: String) throws -> String {
        if let cached = scripts[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { throw ExtractionError.resourceMissing }
        let source = try String(contentsOf: url, encoding: .utf8)
        scripts[name] = source
        return source
    }

    /// Extraction only needs the markup. The quick pass loads nothing but the document; the full pass still skips images, media and fonts.
    private static var fullRules: WKContentRuleList?
    private static var quickRules: WKContentRuleList?
    private var installedMode: Bool?
    private func installRules() async {
        let store = WKContentRuleListStore.default()
        if Self.fullRules == nil {
            Self.fullRules = try? await store.compileContentRuleList(forIdentifier: "PocketMeExtraction", encodedContentRuleList: #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}}]"#)
        }
        if Self.quickRules == nil {
            Self.quickRules = try? await store.compileContentRuleList(forIdentifier: "PocketMeQuickExtraction", encodedContentRuleList: #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font","script","style-sheet","raw","svg-document"]},"action":{"type":"block"}}]"#)
        }
        guard installedMode != quickMode else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if let list = quickMode ? Self.quickRules : Self.fullRules { controller.add(list) }
        installedMode = quickMode
    }

    private func evaluate(_ script: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result as? String) }
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let mime = navigationResponse.response.mimeType ?? "text/html"
        if !["text/html", "application/xhtml+xml"].contains(mime), navigationResponse.isForMainFrame {
            let url = navigationResponse.response.url
            finish(.success(ExtractedArticle(title: url?.lastPathComponent ?? "Saved link", siteName: url?.host() ?? "", wordCount: 0, isExternal: true)))
            return .cancel
        } else { return .allow }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(ExtractionError.noArticle)) }

    private func finish(_ result: Result<ExtractedArticle, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        webView.stopLoading()
        continuation.resume(with: result)
    }
}
