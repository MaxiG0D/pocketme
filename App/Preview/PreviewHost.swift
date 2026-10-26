#if DEBUG
import SwiftData
import SwiftUI

@MainActor
struct PreviewHost<Content: View>: View {
    private let container: ModelContainer?
    private let content: (LibraryStore, [Article]) -> Content

    init(@ViewBuilder content: @escaping (LibraryStore, [Article]) -> Content) {
        Fonts.register()
        container = try? SampleData.container()
        self.content = content
    }
    var body: some View {
        if let container, let articles = try? container.mainContext.fetch(FetchDescriptor<Article>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)])) {
            let store = LibraryStore(persistence: AppPersistence(container: container, mode: .local))
            content(store, articles).modelContainer(container).environment(store).environment(store.readerPreferences)
                .font(Typo.meta).foregroundStyle(Theme.ink).tint(Theme.accent)
        }
    }
}
#endif
