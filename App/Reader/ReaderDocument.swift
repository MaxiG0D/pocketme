import Foundation

enum ReaderDocument {
    // Bump when changing the on-disk HTML/CSS template.
    static let version = "2"
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func html(article: ArticleContent, content: String, leadImage: String?, offline: Bool) throws -> String {
        guard let cssURL = Bundle.main.url(forResource: "reader", withExtension: "css") else { throw CocoaError(.fileReadNoSuchFile) }
        let css = try String(contentsOf: cssURL, encoding: .utf8)
        let images = offline ? "'self' data:" : "'self' data: https: http:"
        let lead = leadImage.map { "<img class=\"lead\" alt=\"\" src=\"\(escape($0))\">" } ?? ""
        return """
        <!doctype html><html class="auto"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src \(images); font-src 'self'; base-uri 'none'; form-action 'none'">
        <title>\(escape(article.title))</title><style>\(css)</style></head><body><main>
        <div class="kicker">\(escape(article.site)) · \(article.minutes) min</div><h1>\(escape(article.title))</h1>\(lead)
        <article>\(content)</article>
        <section class="end"><div class="done">You finished this article</div>
        <button class="btn primary" data-action="archive">\(icon(archive))<span>Archive</span></button><div class="row2">
        <button class="btn outline" data-action="favorite">\(icon(bookmark))<span>Favorite</span></button><button class="btn outline" data-action="share">\(icon(share))<span>Share</span></button></div>
        <div class="upnext" hidden><div class="kicker">Up next</div><button data-action="next"><span class="thumb"></span><span class="info"><span class="title"></span><span class="meta"></span></span></button></div></section>
        </main></body></html>
        """
    }

    private static let archive = #"<rect x="3" y="4" width="18" height="5" rx="1"/><path d="M5 9v10h14V9M10 13h4"/>"#
    private static let bookmark = #"<path d="M7 4h10v16l-5-4-5 4z"/>"#
    private static let share = #"<path d="M12 3v12M7 8l5-5 5 5M5 13v7h14v-7"/>"#
    private static func icon(_ paths: String) -> String { #"<svg aria-hidden="true" viewBox="0 0 24 24">"# + paths + "</svg>" }

    /// The "Up next" card: title, meta, and either the real thumbnail or the generated cover's initial and palette.
    static func nextJSON(_ next: Article?) -> String {
        guard let next else { return "null" }
        struct Next: Encodable { let title: String; let meta: String; let initial: String; let cover: Int; let image: String? }
        let site = next.siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = site.isEmpty ? "PocketMe" : site
        let payload = Next(title: next.title, meta: next.readingMinutes > 0 ? "\(name) · \(next.readingMinutes) min" : name,
                           initial: String(name.prefix(1)).uppercased(), cover: Theme.coverIndex(for: name),
                           image: next.thumbnailData.map { "data:image/jpeg;base64," + $0.base64EncodedString() })
        return (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }
}
