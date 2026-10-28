import SwiftUI

struct ReadingView: View {
    @Environment(LibraryStore.self) private var store
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
        .background(TabBarTint(theater: store.theater))
        #endif
    }
}

#if os(iOS)
/// The iOS 26 glass bar ignores tint for unselected tabs and draws them stark black or white, even through
/// `unselectedItemTintColor`. Glyphs set as original-rendering images keep their color, so the bar's items
/// get warm pre-colored images, redone whenever the appearance changes.
/// On a wide screen it also fades the tab bar and the navigation bars away for theater mode. SwiftUI's own
/// hiding leaves the bars a little low afterwards there, while an alpha fade leaves the layout alone.
private struct TabBarTint: UIViewControllerRepresentable {
    let theater: Bool
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) { controller.apply(); controller.fade(away: theater) }

    final class Probe: UIViewController {
        private let symbols = ["book", "bookmark", "gearshape"]
        private var selection: NSKeyValueObservation?
        private var itemWatchers: [NSKeyValueObservation] = []
        private var watched: [ObjectIdentifier] = []
        private var glyphs: [String: UIImage] = [:]
        private weak var bar: UITabBar?
        private var painting = false

        override func viewDidLoad() {
            super.viewDidLoad()
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (probe: Probe, _) in probe.glyphs = [:]; probe.apply() }
        }

        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }

        func apply() {
            guard let root = view.window?.rootViewController, let tabs = tabBarController(in: root) else { return }
            if selection == nil {
                selection = tabs.observe(\.selectedIndex) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.apply() }
                }
            }
            bar = tabs.tabBar
            let items = tabs.tabBar.items ?? []
            items.forEach(paint)
            // SwiftUI swaps the items' images when the selection changes. Repainting inside that setter,
            // before the frame is drawn, keeps its stark default glyph from flashing for a frame.
            let ids = items.map(ObjectIdentifier.init)
            if ids != watched {
                watched = ids
                itemWatchers = items.flatMap { item in [
                    item.observe(\.image) { [weak self] item, _ in MainActor.assumeIsolated { self?.paint(item) } },
                    item.observe(\.selectedImage) { [weak self] item, _ in MainActor.assumeIsolated { self?.paint(item) } },
                ] }
            }
        }

        func fade(away: Bool) {
            guard let tabs = view.window?.rootViewController.flatMap(tabBarController(in:)), tabs.traitCollection.horizontalSizeClass == .regular else { return }
            let alpha: CGFloat = away ? 0 : 1
            let bars = [floatingBar(in: tabs.view) ?? tabs.tabBar] + navigationBars(in: tabs.view)
            guard bars.contains(where: { $0.alpha != alpha }) else { return }
            bars.forEach { $0.isUserInteractionEnabled = !away }
            // The status bar's clock and icons follow the window's style, so they turn light over the dark.
            view.window?.overrideUserInterfaceStyle = away ? .dark : .unspecified
            UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) { bars.forEach { $0.alpha = alpha } }
        }

        /// Wide screens draw the bar floating at the top, as a view of its own rather than the controller's `tabBar`.
        private func floatingBar(in view: UIView) -> UIView? {
            if String(describing: type(of: view)).contains("FloatingTabBar") { return view }
            for child in view.subviews { if let found = floatingBar(in: child) { return found } }
            return nil
        }

        private func navigationBars(in view: UIView) -> [UIView] {
            (view is UINavigationBar ? [view] : []) + view.subviews.flatMap(navigationBars)
        }

        private func paint(_ item: UITabBarItem) {
            guard !painting, let tabs = bar, let index = tabs.items?.firstIndex(of: item), symbols.indices.contains(index) else { return }
            let image = glyph(symbols[index], color: "Icon", traits: tabs.traitCollection)
            let selected = glyph(symbols[index] + ".fill", color: "IconSelected", traits: tabs.traitCollection)
            // Our own writes re-fire the observers; the flag and identity checks keep that from looping.
            painting = true
            defer { painting = false }
            if item.image !== image { item.image = image }
            if item.selectedImage !== selected { item.selectedImage = selected }
        }

        private func glyph(_ symbol: String, color: String, traits: UITraitCollection) -> UIImage {
            if let cached = glyphs[symbol] { return cached }
            let tint = (UIColor(named: color) ?? .gray).resolvedColor(with: traits)
            let image = UIImage(systemName: symbol)?.withTintColor(tint, renderingMode: .alwaysOriginal) ?? UIImage()
            glyphs[symbol] = image
            return image
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
