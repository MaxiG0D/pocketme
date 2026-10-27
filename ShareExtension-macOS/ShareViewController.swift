import AppKit
import SwiftUI

@MainActor
final class ShareViewController: NSViewController {
    private let flow = ShareFlow()
    override func loadView() {
        Fonts.register()
        view = NSHostingView(rootView: MacShareView(flow: flow))
        preferredContentSize = NSSize(width: 400, height: 100)
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        Task { await flow.start(context: extensionContext) }
    }
}
