import UIKit
import SwiftUI

@MainActor
final class ShareViewController: UIViewController {
    private let flow = ShareFlow()
    override func viewDidLoad() {
        super.viewDidLoad()
        Fonts.register()
        let host = UIHostingController(rootView: SavedSheetView(flow: flow))
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        Task { await flow.start(context: extensionContext) }
    }
}
