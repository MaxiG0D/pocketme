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
