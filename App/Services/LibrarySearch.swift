import Foundation
import Observation

/// Matching for the library search field: title, site and domain at once, article text once it has been indexed.
/// The article text is read out of the stored HTML a few at a time off the main thread and kept in memory, so typing
/// only scans cached, already folded strings; no HTML is parsed per keystroke.
@MainActor @Observable
final class LibrarySearchIndex {
    static let shared = LibrarySearchIndex()

    /// Bumped when more article text arrives, so a visible result list refreshes itself.
    private(set) var version = 0
    @ObservationIgnored private var heads: [UUID: (key: String, text: String)] = [:]
    @ObservationIgnored private var bodies: [UUID: (key: String, text: String)] = [:]
    @ObservationIgnored private var working = false
    @ObservationIgnored private var again = false

    /// Folded query words; every word has to appear somewhere in the article.
    static func terms(_ query: String) -> [String] {
        Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    func matches(_ article: Article, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let head = headText(article), body = bodies[article.id]?.text
        return terms.allSatisfy { head.contains($0) || (body?.contains($0) ?? false) }
    }

    private func headText(_ article: Article) -> String {
        let key = article.title + "\u{1}" + article.siteName + "\u{1}" + article.url
        if let cached = heads[article.id], cached.key == key { return cached.text }
        let host = URL(string: article.url)?.host ?? ""
        let text = Self.fold([article.title, article.siteName, host, article.author ?? ""].joined(separator: " "))
        heads[article.id] = (key, text)
        return text
    }

    private func bodyKey(_ article: Article) -> String { "\(article.statusRaw)-\(article.wordCount)" }

    /// Reads the text of every article that has none yet (or whose content changed), in small batches.
    func prepare(_ articles: [Article]) {
        if working { again = true; return }
        working = true
        Task {
            repeat {
                again = false
                let live = Set(articles.map(\.id))
                bodies = bodies.filter { live.contains($0.key) }
                let stale = articles.filter { $0.status == .ready && bodies[$0.id]?.key != bodyKey($0) }
                for start in stride(from: 0, to: stale.count, by: 12) {
                    let batch = stale[start..<min(start + 12, stale.count)].map { (id: $0.id, key: bodyKey($0), html: $0.contentHTML) }
                    let done = await Task.detached(priority: .utility) {
                        batch.map { (id: $0.id, key: $0.key, text: Self.plainText($0.html)) }
                    }.value
                    for item in done { bodies[item.id] = (item.key, item.text) }
                    version &+= 1
                }
            } while again
            working = false
        }
    }

    /// Visible text of an article's HTML, folded and capped so a very long page cannot fill memory.
    nonisolated static func plainText(_ data: Data?) -> String {
        guard let data, var html = String(data: data, encoding: .utf8) else { return "" }
        for tag in ["script", "style"] {
            html = html.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        html = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…")] {
            html = html.replacingOccurrences(of: entity, with: char)
        }
        return fold(String(html.prefix(400_000)))
    }
}
