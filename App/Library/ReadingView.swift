import SwiftUI

struct ReadingView: View {
    var body: some View {
        #if os(macOS)
        MacLibraryView()
        #else
        TabView {
            LibraryView().tabItem { Label("Library", systemImage: "book") }
            LibraryView(favoritesOnly: true).tabItem { Label("Favorites", systemImage: "bookmark") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.iconSelected)
        .background(TabBarTint())
        #endif
    }
}

#if os(iOS)
/// The iOS 26 glass bar ignores tint for unselected tabs and draws them stark black or white, even through
/// `unselectedItemTintColor`. Glyphs set as original-rendering images keep their color, so the bar's items
/// get warm pre-colored images, redone whenever the appearance changes.
private struct TabBarTint: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) { controller.apply() }

    final class Probe: UIViewController {
        private let symbols = ["book", "bookmark", "gearshape"]
        private var selection: NSKeyValueObservation?

        override func viewDidLoad() {
            super.viewDidLoad()
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (probe: Probe, _) in probe.apply() }
        }

        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }

        func apply() {
            guard let root = view.window?.rootViewController, let tabs = tabBarController(in: root) else { return }
            // SwiftUI rebuilds the items when the selection changes, so the colors go on again afterwards.
            if selection == nil {
                selection = tabs.observe(\.selectedIndex) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.apply() }
                }
            }
            let color = (UIColor(named: "Icon") ?? .gray).resolvedColor(with: tabs.traitCollection)
            for (item, symbol) in zip(tabs.tabBar.items ?? [], symbols) {
                item.image = UIImage(systemName: symbol)?.withTintColor(color, renderingMode: .alwaysOriginal)
                item.selectedImage = UIImage(systemName: symbol + ".fill")
            }
        }

        private func tabBarController(in controller: UIViewController) -> UITabBarController? {
            if let tabs = controller as? UITabBarController { return tabs }
            for child in controller.children { if let found = tabBarController(in: child) { return found } }
            return nil
        }
    }
}
#endif

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in ReadingView() }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in ReadingView() }.preferredColorScheme(.dark) }
#endif
