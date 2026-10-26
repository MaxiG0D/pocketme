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
        }.tint(Theme.ink)
        #endif
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in ReadingView() }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in ReadingView() }.preferredColorScheme(.dark) }
#endif
