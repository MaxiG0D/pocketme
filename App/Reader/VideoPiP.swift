import SwiftUI
import WebKit
#if os(iOS)
import AVFoundation
#endif

/// The system Picture in Picture for the embedded player. The player is a cross-origin iframe, so a script injected
/// into every frame finds its video, reports play and pause, and enters PiP when asked from the page that holds it.
@MainActor @Observable
final class VideoPiP: NSObject, WKScriptMessageHandler {
    /// A video is playing in the page and can float.
    private(set) var isPlaying = false
    /// The video is already floating.
    private(set) var isActive = false
    @ObservationIgnored weak var web: WKWebView?
    @ObservationIgnored private var frame: WKFrameInfo?

    static let handlerName = "pocketmePip"
    /// Its own world keeps the script's names out of the player's page.
    static let world = WKContentWorld.world(name: "pocketme.pip")

    static var script: WKUserScript {
        WKUserScript(source: """
        (function () {
          if (window.__pmPip) { return; }
          window.__pmPip = true;
          var hooked = new WeakSet();
          function post(v) {
            try {
              webkit.messageHandlers.\(handlerName).postMessage({
                playing: !v.paused && !v.ended,
                active: v.webkitPresentationMode === 'picture-in-picture'
              });
            } catch (e) {}
          }
          function hook(v) {
            if (hooked.has(v)) { return; }
            hooked.add(v);
            ['play', 'playing', 'pause', 'ended', 'emptied', 'webkitpresentationmodechanged'].forEach(function (name) {
              v.addEventListener(name, function () { post(v); });
            });
            post(v);
          }
          function scan() { document.querySelectorAll('video').forEach(hook); }
          new MutationObserver(scan).observe(document, { childList: true, subtree: true });
          scan();
          window.__pmEnterPip = function () {
            var v = document.querySelector('video');
            if (!v) { return false; }
            if (v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('picture-in-picture')) {
              v.webkitSetPresentationMode('picture-in-picture');
              return true;
            }
            if (v.requestPictureInPicture) { v.requestPictureInPicture(); return true; }
            return false;
          };
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world)
    }

    /// The Mac's web view rejects Picture in Picture for its videos ("does not support the Picture-in-Picture mode"),
    /// so there it stays out of the page.
    func attach(to configuration: WKWebViewConfiguration) {
        #if os(iOS)
        configuration.userContentController.addUserScript(Self.script)
        configuration.userContentController.add(self, contentWorld: Self.world, name: Self.handlerName)
        configuration.allowsPictureInPictureMediaPlayback = true
        // Playing audio is what lets the picture keep going once the app is out of the way.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let state = message.body as? [String: Any] else { return }
        let playing = state["playing"] as? Bool ?? false
        let active = state["active"] as? Bool ?? false
        if playing || active { frame = message.frameInfo }
        isPlaying = playing || active
        isActive = active
    }

    /// Floats the video if one is playing. It has to be asked from a tap or as the app steps aside.
    func enter() {
        guard isPlaying, !isActive, let web, let frame else { return }
        Task { _ = try? await web.callAsyncJavaScript("return window.__pmEnterPip ? window.__pmEnterPip() : false", in: frame, contentWorld: Self.world) }
    }

    func reset() {
        isPlaying = false
        isActive = false
        frame = nil
    }
}
