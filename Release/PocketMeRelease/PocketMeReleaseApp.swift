// PocketMe Release: a small front end for Release/release.sh (Publish tab),
// Release/testflight.sh (TestFlight tab) and Release/dev.sh (Dev tab).
// Built by Release/build_release_app.sh into "PocketMe Release.app" at the project root.

import AppKit
import SwiftUI

@main
struct PocketMeReleaseApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = ReleaseModel()

    var body: some Scene {
        Window("PocketMe Release", id: "main") {
            ReleaseView()
                .environment(model)
                .task { model.startDryRunIfRequested() }
                .frame(minWidth: 560, minHeight: 640)
        }
        .defaultSize(width: 620, height: 780)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

