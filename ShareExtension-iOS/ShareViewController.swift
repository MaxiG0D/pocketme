import UIKit
import SwiftUI

@MainActor
final class ShareViewController: UIViewController {
    private let flow = ShareFlow()
    override func viewDidLoad() {
        super.viewDidLoad()
        Fonts.register()
        view.backgroundColor = .clear
        flow.opener = { [weak self] url in self?.openInHostApp(url) ?? false }
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        clearContainers()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        clearContainers()
    }

    /// The system draws its own panel behind the extension; clear every container layer so only the bar shows.
    private func clearContainers() {
        var container: UIView? = view.superview
        while let current = container { current.backgroundColor = .clear; container = current.superview }
    }

    /// Share extensions can't call `extensionContext.open`; the responder chain reaches the host's UIApplication.
    private func openInHostApp(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return true
            }
            responder = current.next
        }
        return false
    }
}
