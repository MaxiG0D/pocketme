import WebKit

/// YouTube's embedded player settles at 720p and stays there, however big its frame gets. It reads the quality it should
/// use from a preference in its own page storage, so a script in the player's frame saves one before the player starts.
enum VideoQuality {
    /// Full HD: what a phone or tablet screen can show, without asking for the 4K streams it would then have to fetch.
    static let height = 1080

    static var script: WKUserScript {
        WKUserScript(source: #"""
        (function () {
          if (!/(^|\.)youtube(-nocookie)?\.com$/.test(location.hostname)) { return; }
          try {
            var now = Date.now();
            localStorage.setItem('yt-player-quality', JSON.stringify({
              data: JSON.stringify({ quality: \#(height), previousQuality: \#(height) }),
              expiration: now + 2592000000,
              creation: now
            }));
          } catch (e) {}
        })();
        """#, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
    }
}
