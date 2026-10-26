import SwiftUI
import SwiftData

struct LibraryHostView: View {
    let store: LibraryStore

    var body: some View {
        Group {
            if let persistence = store.persistence {
                ReadingView().modelContainer(persistence.container)
            } else if let message = store.errorMessage {
                VStack(spacing: 20) {
                    Text("Reading").font(Typo.largeTitle).foregroundStyle(Theme.ink)
                    Text(message).font(Typo.meta).foregroundStyle(Theme.muted)
                    Button("Try again") { Task { await store.open() } }
                        .buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 260)
                }.padding(Theme.gutter)
            } else {
                Text("Opening your library…").font(Typo.meta).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper).environment(store).environment(store.readerPreferences)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, _ in LibraryHostView(store: store) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, _ in LibraryHostView(store: store) }.preferredColorScheme(.dark) }
#endif
