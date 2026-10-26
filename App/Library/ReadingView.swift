import SwiftUI

struct ReadingView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    var body: some View {
        #if os(macOS)
        MacLibraryView()
        #else
        TabView {
            Group {
                if sizeClass == .regular { MacLibraryView() } else { LibraryView() }
            }.tabItem { Label("Library", systemImage: "book") }
            LibraryView(favoritesOnly: true).tabItem { Label("Favorites", systemImage: "bookmark") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }.tint(Theme.ink)
        #endif
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in ReadingView() }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in ReadingView() }.preferredColorScheme(.dark) }
#endif
