import Foundation

/// A YouTube or Vimeo link, recognized from the saved URL so video saves skip article extraction.
struct VideoLink: Hashable, Sendable {
    enum Provider: Sendable { case youtube, vimeo }
    let provider: Provider
    let id: String

    init?(_ raw: String) {
        guard let parts = URLComponents(string: raw), let host = parts.host?.lowercased() else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = parts.path.split(separator: "/").map(String.init)
        switch bare {
        case "youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com":
            if path.first == "watch" { self.init(.youtube, parts.queryItems?.first { $0.name == "v" }?.value) }
            else if path.count >= 2, ["shorts", "live", "embed", "v"].contains(path[0]) { self.init(.youtube, path[1]) }
            else { return nil }
        case "youtu.be":
            self.init(.youtube, path.first)
        case "vimeo.com", "player.vimeo.com":
            self.init(.vimeo, path.last { $0.allSatisfy(\.isNumber) })
        default:
            return nil
        }
    }

    private init?(_ provider: Provider, _ id: String?) {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard let id, !id.isEmpty, id.count <= 32, id.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        self.provider = provider
        self.id = id
    }

    var oEmbedURL: URL {
        var parts = URLComponents(string: provider == .youtube ? "https://www.youtube.com/oembed" : "https://vimeo.com/api/oembed.json")!
        parts.queryItems = [URLQueryItem(name: "url", value: watchURL.absoluteString), URLQueryItem(name: "format", value: "json")]
        return parts.url!
    }

    var watchURL: URL {
        URL(string: provider == .youtube ? "https://www.youtube.com/watch?v=\(id)" : "https://vimeo.com/\(id)")!
    }

    /// Privacy-enhanced player, started by the reader's poster tap.
    var embedURL: URL {
        URL(string: provider == .youtube
            ? "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&playsinline=1&rel=0"
            : "https://player.vimeo.com/video/\(id)?autoplay=1&dnt=1&title=0&byline=0&portrait=0")!
    }

    /// Largest first; YouTube answers 404 when a size doesn't exist, so later ones are fallbacks.
    var thumbnailCandidates: [String] {
        guard provider == .youtube else { return [] }
        return ["maxresdefault", "sddefault", "hqdefault"].map { "https://i.ytimg.com/vi/\(id)/\($0).jpg" }
    }
}
