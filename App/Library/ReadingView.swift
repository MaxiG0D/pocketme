import SwiftUI

struct ReadingView: View {
    #if os(iOS)
    private enum Section: Hashable { case library, favorites, settings }
    @State private var section = Section.library
    #endif

    var body: some View {
        #if os(macOS)
        MacLibraryView()
        #else
        TabView(selection: $section) {
            LibraryView().tabItem { tabLabel("Library", "book", .library) }.tag(Section.library)
            LibraryView(favoritesOnly: true).tabItem { tabLabel("Favorites", "bookmark", .favorites) }.tag(Section.favorites)
            SettingsView().tabItem { tabLabel("Settings", "gearshape", .settings) }.tag(Section.settings)
        }.tint(Theme.iconSelected)
        #endif
    }

    #if os(iOS)
    /// The iOS 26 glass bar ignores tint for unselected tabs and draws them stark black or white,
    /// so each glyph arrives already colored in the warm palette.
    private func tabLabel(_ title: String, _ symbol: String, _ tab: Section) -> some View {
        let color = UIColor(named: section == tab ? "IconSelected" : "Icon") ?? .secondaryLabel
        let image = UIImage(systemName: symbol)?.withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
        return Label { Text(title) } icon: { Image(uiImage: image) }
    }
    #endif
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in ReadingView() }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in ReadingView() }.preferredColorScheme(.dark) }
#endif
