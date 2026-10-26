import Foundation

enum ReaderDocument {
    // Bump when changing the on-disk HTML/CSS template.
    static let version = "1"
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
        <button class="btn primary" data-action="archive">Archive</button><div class="row2">
        <button class="btn outline" data-action="favorite">Favorite</button><button class="btn outline" data-action="share">Share</button></div>
        <div class="upnext" hidden><div class="kicker">Up next</div><button data-action="next"></button></div></section>
        </main></body></html>
        """
    }
}
