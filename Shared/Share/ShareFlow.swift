import Foundation
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
            fetchQuickTitle(link)
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
                    Task { @MainActor in self?.thumbnail = data }
                }
            }
            Task { @MainActor in if let title, !title.isEmpty, self?.hasHostTitle == false, self?.errorMessage == nil { self?.title = title } }
        }
    }

    /// A plain request for the first part of the page, which shows the title long before LinkPresentation finishes.
    private func fetchQuickTitle(_ url: URL) {
        guard !hasHostTitle else { return }
        Task { [weak self] in
            var request = URLRequest(url: url, timeoutInterval: 4)
            request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let html = String(data: data.prefix(65536), encoding: .utf8) ?? String(data: data.prefix(65536), encoding: .isoLatin1),
                  let found = Self.pageTitle(in: html), let self, !self.hasHostTitle, self.errorMessage == nil else { return }
            self.title = found
        }
    }

    nonisolated static func pageTitle(in html: String) -> String? {
        for pattern in ["<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']",
                        "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']",
                        "<title[^>]*>([^<]+)</title>"] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let text = String(html[range])
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&#x27;", with: "'")
                .replacingOccurrences(of: "&rsquo;", with: "’").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
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
