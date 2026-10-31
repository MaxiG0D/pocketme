import Foundation
import ImageIO
import LinkPresentation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class ShareFlow {
    private(set) var title = "Saving your link…"
    private(set) var site = ""
    private(set) var thumbnail: Data?
    private(set) var saved = false
    private(set) var errorMessage: String?
    private(set) var url: URL?
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    @ObservationIgnored private var hasHostTitle = false
    @ObservationIgnored private var hasFetchedTitle = false
    @ObservationIgnored private var provider: LPMetadataProvider?
    @ObservationIgnored private var context: NSExtensionContext?
    /// Host-specific opener. Share extensions can't use `NSExtensionContext.open`, so iOS supplies one.
    @ObservationIgnored var opener: ((URL) -> Bool)?

    func start(context: NSExtensionContext?) async {
        self.context = context
        do {
            let link = try await ShareInput.link(from: context?.inputItems as? [NSExtensionItem] ?? [])
            url = link
            site = link.host()?.replacingOccurrences(of: "www.", with: "") ?? "Website"
            title = Self.hostTitle(from: context) ?? site
            hasHostTitle = title != site
            fetchMetadata(link)
            fetchQuickPage(link)
            let queue = try SaveQueue()
            try await queue.append(url: link.absoluteString, title: hasHostTitle ? title : nil)
            saved = true
            dismissal = Task { [weak self] in
                #if os(macOS)
                try? await Task.sleep(for: .seconds(1.2))
                #else
                try? await Task.sleep(for: .seconds(4))
                #endif
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        } catch {
            errorMessage = "This link couldn’t be saved. Open PocketMe and paste it there."
            title = "Couldn’t save this link"
        }
    }

    private func fetchMetadata(_ url: URL) {
        let provider = LPMetadataProvider()
        self.provider = provider
        provider.timeout = 2
        provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
            let title = metadata?.title
            let imageProvider = metadata?.imageProvider
            if let imageProvider {
                imageProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    let small = data.flatMap { Self.downsample($0) }
                    Task { @MainActor in if self?.thumbnail == nil { self?.thumbnail = small } }
                }
            }
            Task { @MainActor in if let title, !title.isEmpty, self?.hasHostTitle == false, self?.errorMessage == nil { self?.title = title; self?.hasFetchedTitle = true } }
        }
    }

    /// A plain request for the first part of the page: the title shows long before LinkPresentation finishes, and so can the image.
    private func fetchQuickPage(_ url: URL) {
        if let video = VideoLink(url.absoluteString), video.provider == .youtube,
           let poster = URL(string: "https://i.ytimg.com/vi/\(video.id)/mqdefault.jpg") {
            fetchThumbnail(poster)
        }
        Task { [weak self] in
            var request = URLRequest(url: url, timeoutInterval: 4)
            request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 206,
                  http.mimeType == "text/html" else { return }
            let html = Self.decodeHTML(data.prefix(65536), charset: http.textEncodingName)
            guard let self, self.errorMessage == nil else { return }
            if let found = Self.pageTitle(in: html), !self.hasHostTitle, !self.hasFetchedTitle { self.title = found }
            if self.thumbnail == nil, let image = Self.pageImage(in: html, base: http.url ?? url) { self.fetchThumbnail(image) }
        }
    }

    private func fetchThumbnail(_ imageURL: URL) {
        guard imageURL.scheme == "https" || imageURL.scheme == "http" else { return }
        Task { [weak self] in
            let request = URLRequest(url: imageURL, timeoutInterval: 4)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4_000_000,
                  let small = Self.downsample(data), let self, self.thumbnail == nil else { return }
            self.thumbnail = small
        }
    }

    /// A small JPEG: the bar shows at most 84pt, and the extension has little memory.
    nonisolated static func downsample(_ data: Data, maxPixel: Int = 252) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    nonisolated static func pageImage(in html: String, base: URL) -> URL? {
        for (pattern, group) in [("<meta[^>]+(?:property|name)=([\"'])(?:og:image|twitter:image)(?::src)?\\1[^>]+content=([\"'])(.*?)\\2", 3),
                                 ("<meta[^>]+content=([\"'])(.*?)\\1[^>]+(?:property|name)=([\"'])(?:og:image|twitter:image)(?::src)?\\3", 2)] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: group), in: html) else { continue }
            let raw = decodeEntities(String(html[range])).trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty, let url = URL(string: raw, relativeTo: base)?.absoluteURL { return url }
        }
        return nil
    }

    /// Uses the page's declared charset; otherwise lossy UTF-8, so a cut in the middle of a character never turns into Latin-1 garble.
    nonisolated static func decodeHTML(_ data: Data, charset: String?) -> String {
        if let charset {
            let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cf != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if encoding != .utf8, let text = String(data: data, encoding: encoding) { return text }
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private nonisolated static let interstitialTitles = ["just a moment", "access denied", "attention required", "403 forbidden", "404", "are you a robot",
                                              "please wait", "checking your browser", "before you continue", "one more step"]

    nonisolated static func pageTitle(in html: String) -> String? {
        for (pattern, group) in [("<meta[^>]+property=([\"'])og:title\\1[^>]+content=([\"'])(.*?)\\2", 3),
                                 ("<meta[^>]+content=([\"'])(.*?)\\1[^>]+property=([\"'])og:title\\3", 2),
                                 ("<title[^>]*>([^<]+)</title>", 1)] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: group), in: html) else { continue }
            let text = decodeEntities(String(html[range]))
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || interstitialTitles.contains(where: { text.lowercased().hasPrefix($0) }) { continue }
            return text
        }
        return nil
    }

    nonisolated static func decodeEntities(_ text: String) -> String {
        var result = text
        let named = ["&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&rsquo;": "’", "&lsquo;": "‘",
                     "&rdquo;": "”", "&ldquo;": "“", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&raquo;": "»", "&laquo;": "«",
                     "&middot;": "·", "&bull;": "•", "&copy;": "©", "&trade;": "™", "&eacute;": "é", "&egrave;": "è", "&agrave;": "à",
                     "&ccedil;": "ç", "&ecirc;": "ê", "&ocirc;": "ô", "&icirc;": "î", "&ucirc;": "û", "&acirc;": "â"]
        for (entity, value) in named { result = result.replacingOccurrences(of: entity, with: value) }
        if let regex = try? NSRegularExpression(pattern: "&#([xX][0-9a-fA-F]+|[0-9]+);") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
            for match in matches {
                guard let whole = Range(match.range, in: result), let code = Range(match.range(at: 1), in: result) else { continue }
                let digits = result[code]
                let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                if let value, value >= 0x20, let scalar = Unicode.Scalar(value) { result.replaceSubrange(whole, with: String(Character(scalar))) }
            }
        }
        // Ampersand last, so "&amp;#8217;" stays literal text.
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Safari hands over the page title with the link, so the bar can show it at once instead of waiting on the web.
    private static func hostTitle(from context: NSExtensionContext?) -> String? {
        for item in context?.inputItems as? [NSExtensionItem] ?? [] {
            for candidate in [item.attributedTitle?.string, item.attributedContentText?.string] {
                let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !text.isEmpty, text.count < 300, URL(string: text)?.scheme == nil { return text }
            }
        }
        return nil
    }

    func keepOpen() { dismissal?.cancel() }

    func finish() {
        dismissal?.cancel()
        provider?.cancel()
        context?.completeRequest(returningItems: nil)
    }

    func readNow() {
        dismissal?.cancel()
        guard saved, let url else { finish(); return }
        var deepLink = URLComponents()
        deepLink.scheme = "pocketme"; deepLink.host = "open"
        deepLink.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let link = deepLink.url else { finish(); return }
        AppIdentity.openRequest?.set(Date(), forKey: AppIdentity.openRequestKey)
        if opener?(link) == true { finish(); return }
        context?.open(link) { [weak self] _ in Task { @MainActor in self?.finish() } }
    }
}
