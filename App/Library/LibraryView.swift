#if os(iOS)
import SwiftData
import SwiftUI

/// One adaptive split view for iPhone, iPad and iPhone Duo: a stack when compact, list and reader side by side when regular.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    var favoritesOnly = false
    @State private var archive = false
    @State private var heroSquish: CGFloat = 0
    @State private var search = ""
    @State private var showSearch = false
    @State private var addLink = false
    @State private var selection: UUID?
    @State private var columns = NavigationSplitViewVisibility.doubleColumn
    @State private var toDelete: Article?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    private var filtered: [Article] {
        let section: LibrarySection = favoritesOnly ? .favorites : archive ? .archive : .unread
        return articles.filter { section.includes($0) && (search.isEmpty || ($0.title + " " + $0.siteName).localizedCaseInsensitiveContains(search)) }
            .sorted { archive && !favoritesOnly ? ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) : $0.savedAt > $1.savedAt }
    }
    /// Side by side, the article being read is already open next to the list; promoting it to a hero card
    /// would make its row jump in and out as reading progress changes.
    private var current: Article? { sizeClass == .regular ? nil : inProgress }
    private var inProgress: Article? {
        guard !favoritesOnly, !archive, search.isEmpty else { return nil }
        return filtered.filter { $0.lastOpenedAt != nil && $0.readingProgress > 0.02 && $0.readingProgress < 0.95 }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }
    private var rows: [Article] { filtered.filter { $0.id != current?.id } }
    private let rowInsets = EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter)
    @State private var openSwipe: SwipeOpen?
    private func swipeActions(for article: Article) -> [SwipeAction] {[
        SwipeAction(side: .leading, symbol: "bookmark", color: Theme.swipeFavorite, label: article.isFavorite ? "Remove favorite" : "Favorite") { store.favorite(article) },
        SwipeAction(side: .trailing, symbol: "archivebox", color: Theme.swipeArchive, label: article.archivedAt == nil ? "Archive" : "Unarchive") { store.archive(article) },
    ]}

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            list
                .navigationTitle(favoritesOnly ? "Favorites" : "Pocket Me")
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        } detail: {
            detail
        }
        .tint(Theme.icon)
        .sheet(isPresented: $addLink) { AddLinkSheet() }
        .confirmationDialog("Delete this article?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete article", role: .destructive) { if let article = toDelete { store.delete(article) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        }
        .onChange(of: articles.map(\.id)) { _, ids in if let selection, !ids.contains(selection) { self.selection = nil } }
        .onAppear(perform: ensureSelection)
        .onChange(of: selection) { _, _ in openSwipe = nil }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
        .onChange(of: sizeClass) { _, _ in ensureSelection() }
        .onChange(of: store.requestedArticleID) { _, id in if let id { selection = id; store.requestedArticleID = nil } }
        .sensoryFeedback(.success, trigger: store.savedToken).sensoryFeedback(.success, trigger: store.actionToken)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: archive)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: filtered.map(\.id))
    }

    private var list: some View {
        List(selection: $selection) {
            filters.listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Theme.paper)
            if let error = store.errorMessage {
                Text(error).font(Typo.meta).foregroundStyle(Theme.muted)
                    .listRowInsets(rowInsets).listRowSeparator(.hidden).listRowBackground(Theme.paper)
            }
            if filtered.isEmpty {
                Group {
                    if articles.isEmpty { EmptyStateView(paste: pasteOrAdd).frame(maxWidth: .infinity).padding(.top, 30) }
                    else { Text(search.isEmpty ? "No articles here yet" : "No matching articles").font(Typo.meta).foregroundStyle(Theme.muted).padding(.top, 40) }
                }.listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Theme.paper)
            } else {
                if let current {
                    ContinueReadingCard(article: current, squish: reduceMotion ? 0 : heroSquish) { selection = current.id }
                        .listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 22, trailing: Theme.gutter))
                        .listRowSeparator(.hidden).listRowBackground(Theme.paper)
                }
                ForEach(rows, id: \.id) { article in
                    ArticleRow(article: article)
                        .padding(.horizontal, Theme.gutter)
                        // Behind the swipe, so the row slides over one still surface instead of dragging a slab along.
                        .swipeReveal(id: article.id, open: $openSwipe, actions: swipeActions(for: article), inset: Theme.gutter, gap: 12, cornerRadius: Theme.radiusThumb, maxHeight: Theme.rowThumb, edge: 12)
                        .background(selection == article.id ? Theme.cardSelection : Theme.paper)
                        .listRowInsets(EdgeInsets()).listRowBackground(Theme.paper)
                        .listRowSeparatorTint(Theme.hairline)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in Theme.gutter }
                        .alignmentGuide(.listRowSeparatorTrailing) { $0.width - Theme.gutter }
                        .contextMenu { articleMenu(article) }
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.paper).scrollIndicators(.hidden)
        // Follows the finger only while the card is leaving; past it the value stops changing, so reading down sends no updates.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            return min(max(offset / 200, 0), 1)
        } action: { _, new in heroSquish = new }
        .modifier(LibrarySearch(enabled: !articles.isEmpty, text: $search, isPresented: $showSearch))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { addLink = true } label: { Image(systemName: "plus").fontWeight(.bold) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(Theme.accent)
                    .accessibilityLabel("Save a link")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !articles.isEmpty { Button("Search", systemImage: "magnifyingglass") { showSearch = true } }
            }
        }
        .refreshable { store.refresh(); await store.drainInbox() }
        .overlay(alignment: .bottom) { ToastView(store: store) }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.toast?.id)
    }

    @ViewBuilder private var filters: some View {
        if !favoritesOnly && !articles.isEmpty {
            HStack(spacing: 6) {
                Button("Unread · \(articles.filter { $0.archivedAt == nil }.count)") { archive = false }.buttonStyle(PillButtonStyle(selected: !archive))
                Button("Archive") { archive = true }.buttonStyle(PillButtonStyle(selected: archive))
                Spacer(minLength: 0)
            }.padding(.horizontal, Theme.gutter).padding(.vertical, 10).background(Theme.paper)
        }
    }

    @ViewBuilder private var detail: some View {
        if let selection, let article = articles.first(where: { $0.id == selection }) {
            ReaderView(article: article, close: { self.selection = nil })
        } else {
            Theme.paper.ignoresSafeArea()
        }
    }

    /// Side by side, the reader pane never opens blank: it shows the article being read, else the newest.
    private func ensureSelection() {
        guard sizeClass == .regular else { return }
        if let selection, filtered.contains(where: { $0.id == selection }) { return }
        selection = (inProgress ?? filtered.first)?.id
    }
    private func pasteOrAdd() { if let link = Clipboard.link { _ = store.saveLink(link) } else { addLink = true } }
    @ViewBuilder private func articleMenu(_ article: Article) -> some View {
        Button(article.isFavorite ? "Remove favorite" : "Favorite", systemImage: "bookmark") { store.favorite(article) }
        Button(article.archivedAt == nil ? "Archive" : "Unarchive", systemImage: "archivebox") { store.archive(article) }
        Button("Copy link", systemImage: "link") { Clipboard.copy(article.url) }
        Button("Delete", systemImage: "trash", role: .destructive) { toDelete = article }
    }
}

/// An empty library has nothing to search, so the field only appears once there is something to find.
private struct LibrarySearch: ViewModifier {
    let enabled: Bool
    @Binding var text: String
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        if enabled { content.searchable(text: $text, isPresented: $isPresented, prompt: "Title or site") }
        else { content }
    }
}
#endif

#if DEBUG && os(iOS)
#Preview("Light") { PreviewHost { store, articles in LibraryView() }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in LibraryView() }.preferredColorScheme(.dark) }
#endif
