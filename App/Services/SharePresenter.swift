import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Opens the system share sheet directly, for buttons that live inside the reader's web content.
enum SharePresenter {
    @MainActor static func share(_ url: URL) {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 120, width: 1, height: 1)
        }
        top.present(controller, animated: true)
        #else
        guard let view = NSApp.keyWindow?.contentView else { return }
        NSSharingServicePicker(items: [url])
            .show(relativeTo: CGRect(x: view.bounds.midX, y: view.bounds.minY + 120, width: 1, height: 1), of: view, preferredEdge: .minY)
        #endif
    }
}
