import Foundation

/// Video saves come from oEmbed (title, channel, thumbnail) plus the watch page's description and length.
enum VideoMetadata {
    private struct OEmbed: Decodable {
        let title: String
        let author_name: String?
        let thumbnail_url: String?
        let description: String?
        let duration: Int?
    }

    static func fetch(_ video: VideoLink) async throws -> ExtractedArticle {
        let (data, _) = try await NetworkData.fetch(video.oEmbedURL, limit: 256 * 1_024)
        let embed = try JSONDecoder().decode(OEmbed.self, from: data)
        var description = embed.description ?? ""
        var seconds = embed.duration
        if video.provider == .youtube, let page = await watchPage(video) {
            description = jsonString(after: "\"shortDescription\":", in: page) ?? description
            seconds = jsonString(after: "\"lengthSeconds\":", in: page).flatMap(Int.init) ?? seconds
        }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(200)) }
        return ExtractedArticle(title: embed.title, siteName: embed.author_name ?? (video.provider == .youtube ? "YouTube" : "Vimeo"),
                                excerpt: excerpt, leadImageURL: video.thumbnailCandidates.first ?? embed.thumbnail_url,
                                imageCandidates: video.thumbnailCandidates + [embed.thumbnail_url].compactMap { $0 },
                                content: html(text), wordCount: text.split(whereSeparator: \.isWhitespace).count,
                                minutes: seconds.map { max(1, Int((Double($0) / 60).rounded())) })
    }

    /// Plain-text description as paragraphs, with bare links made tappable.
    static func html(_ text: String) -> String {
        text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { paragraph in
            let escaped = ReaderDocument.escape(paragraph)
            let linked = HTMLAssets.replacing(#"https?://[^\s<>"]+[^\s<>".,;:!?)\]']"#, in: escaped, with: #"<a href="$0">$0</a>"#)
            return "<p>" + linked.replacingOccurrences(of: "\n", with: "<br>") + "</p>"
        }.joined()
    }

    private static func watchPage(_ video: VideoLink) async -> String? {
        var request = URLRequest(url: video.watchURL, timeoutInterval: 15)
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        // Skips the EU consent interstitial, which has no video data.
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Reads the JSON string literal that follows `key` in the page's embedded player data.
    static func jsonString(after key: String, in page: String) -> String? {
        guard let start = page.range(of: key)?.upperBound, page[start...].first == "\"" else { return nil }
        var index = page.index(after: start), escaped = false
        while index < page.endIndex {
            let character = page[index]
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" { break }
            index = page.index(after: index)
        }
        guard index < page.endIndex else { return nil }
        let literal = Data(page[start...index].utf8)
        return try? JSONSerialization.jsonObject(with: literal, options: .fragmentsAllowed) as? String
    }
}
