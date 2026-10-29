import SwiftUI
import WebKit

/// The video's poster with a play button; tapping swaps in the provider's privacy-enhanced player.
struct VideoPlayerView: View {
    let article: Article
    let video: VideoLink
    @Binding var playing: Bool
    let pip: VideoPiP
    var play: () -> Void = {}
    @Environment(\.openURL) private var openURL

    var body: some View {
        Color.black
            .overlay {
                if playing {
                    VideoEmbedView(video: video, pip: pip, openLink: { openURL($0) })
                } else {
                    Button { playing = true; play() } label: { poster }.buttonStyle(.plain).accessibilityLabel("Play video")
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var poster: some View {
        ArticleThumb(article: article, radius: 0)
            .overlay {
                AsyncImage(url: article.leadImageURL.flatMap(URL.init(string:))) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.clear }
            }
            .clipped()
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .offset(x: 2)
                    .frame(width: 64, height: 64)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            }
            .contentShape(Rectangle())
    }
}

private struct VideoEmbedView {
    let video: VideoLink
    let pip: VideoPiP
    let openLink: @MainActor (URL) -> Void

    @MainActor func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        pip.attach(to: configuration)
        if video.provider == .youtube { configuration.userContentController.addUserScript(VideoQuality.script) }
        let web = WKWebView(frame: .zero, configuration: configuration)
        pip.web = web
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        #if os(iOS)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        #else
        // Black from the first frame, so the player never flashes white while it grows into theater mode.
        web.setValue(false, forKey: "drawsBackground")
        web.wantsLayer = true
        web.layer?.backgroundColor = NSColor.black.cgColor
        #endif
        web.underPageBackgroundColor = .black
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{display:block;border:0;width:100%;height:100%}</style></head>
        <body><iframe src="\(ReaderDocument.escape(video.embedURL.absoluteString))" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        // YouTube refuses embeds without a referrer, so the page gets an https origin named after the app.
        web.loadHTMLString(html, baseURL: URL(string: "https://" + (Bundle.main.bundleIdentifier ?? "pocketme").lowercased()))
        return web
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(openLink: openLink) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let openLink: @MainActor (URL) -> Void
        init(openLink: @escaping @MainActor (URL) -> Void) { self.openLink = openLink }

        // Links out of the player (channel, "Watch on YouTube") open in the browser, not in the frame.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else { return .allow }
            openLink(url)
            return .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { openLink(url) }
            return nil
        }
    }
}

#if os(iOS)
extension VideoEmbedView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else
extension VideoEmbedView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
