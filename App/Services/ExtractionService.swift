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
    var readingMinutes: Int { max(1, Int((Double(wordCount) / 230).rounded())) }
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
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15"
    }

    func extract(url: URL) async throws -> ExtractedArticle {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let id = UUID(); requestID = id
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled, self?.requestID == id else { return }
                    self?.finish(.failure(ExtractionError.timedOut))
                }
                if url.isFileURL { webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
                else { webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let id = requestID
        Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard let self, self.requestID == id, self.continuation != nil else { return }
                for name in ["Readability", "extract"] {
                    guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { throw ExtractionError.resourceMissing }
                    let source = try String(contentsOf: url, encoding: .utf8)
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
