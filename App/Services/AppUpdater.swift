#if os(macOS)
import Sparkle

/// Mac-only automatic updates. Sparkle reads the feed and public key from Info.plist and checks in the background.
@MainActor
final class AppUpdater {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func check() { controller.checkForUpdates(nil) }
}
#endif
