import AppKit
import SwiftUI

@MainActor
final class ShareViewController: NSViewController {
    private let flow = ShareFlow()
    override func loadView() {
        Fonts.register()
        view = NSHostingView(rootView: SavedSheetView(flow: flow).frame(width: 440, height: 360))
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        Task { await flow.start(context: extensionContext) }
    }
}
