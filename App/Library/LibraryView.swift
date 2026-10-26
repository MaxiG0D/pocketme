#if os(iOS)
import SwiftData
import SwiftUI

/// One adaptive split view for iPhone, iPad and iPhone Duo: a stack when compact, list and reader side by side when regular.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    var favoritesOnly = false
    @State private var archive = false
    @State private var search = ""
    @State private var showSearch = false
    @State private var addLink = false
    @State private var selection: UUID?
    @State private var columns = NavigationSplitViewVisibility.automatic
    @State private var toDelete: Article?
    @State private var saved = false
    @State private var toast: Task<Void, Never>?

    private var filtered: [Article] {
        let section: LibrarySection = favoritesOnly ? .favorites : archive ? .archive : .unread
        return articles.filter { section.includes($0) && (search.isEmpty || ($0.title + " " + $0.siteName).localizedCaseInsensitiveContains(search)) }
            .sorted { archive && !favoritesOnly ? ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) : $0.savedAt > $1.savedAt }
    }
    private var current: Article? {
        guard !favoritesOnly, !archive, search.isEmpty else { return nil }
        return filtered.filter { $0.lastOpenedAt != nil && $0.readingProgress > 0.02 && $0.readingProgress < 0.95 }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }
    private var rows: [Article] { filtered.filter { $0.id != current?.id } }
    private let rowInsets = EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter)

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            list
                .navigationTitle(favoritesOnly ? "Favorites" : "Reading")
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        } detail: {
            detail
        }
        .tint(Theme.ink)
        .sheet(isPresented: $addLink) { AddLinkSheet() }
        .confirmationDialog("Delete this article?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete article", role: .destructive) { if let article = toDelete { store.delete(article) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        }
        .onChange(of: store.savedToken) { _, _ in
            saved = true; toast?.cancel()
            toast = Task { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { saved = false } }
        }
        .onChange(of: articles.map(\.id)) { _, ids in if let selection, !ids.contains(selection) { self.selection = nil } }
        .onChange(of: store.requestedArticleID) { _, id in if let id { selection = id; store.requestedArticleID = nil } }
        .sensoryFeedback(.success, trigger: store.savedToken).sensoryFeedback(.success, trigger: store.actionToken)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: archive)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: filtered.map(\.id))
    }

    private var list: some View {
        List(selection: $selection) {
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
                    ContinueReadingCard(article: current) { selection = current.id }
                        .listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 22, trailing: Theme.gutter))
                        .listRowSeparator(.hidden).listRowBackground(Theme.paper)
                }
                ForEach(rows, id: \.id) { article in
                    ArticleRow(article: article)
                        .listRowInsets(rowInsets).listRowSeparatorTint(Theme.hairline)
                        .listRowBackground(selection == article.id ? Theme.cardSelection : Theme.paper)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button { store.favorite(article) } label: { Label(article.isFavorite ? "Remove favorite" : "Favorite", systemImage: "bookmark") }
                                .tint(Theme.ink)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button { store.archive(article) } label: { Label(article.archivedAt == nil ? "Archive" : "Unarchive", systemImage: "archivebox") }
                                .tint(Theme.success)
                        }
                        .contextMenu { articleMenu(article) }
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.paper).scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { filters }
        .modifier(LibrarySearch(enabled: !articles.isEmpty, text: $search, isPresented: $showSearch))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !articles.isEmpty { Button("Search", systemImage: "magnifyingglass") { showSearch = true } }
                Button("Save a link", systemImage: "plus") { addLink = true }.tint(Theme.accent)
            }
        }
        .refreshable { store.refresh(); await store.drainInbox() }
        .overlay(alignment: .bottom) {
            if saved { Text("Saved").font(Typo.button).padding(.horizontal, 22).padding(.vertical, 12).background(Theme.ink, in: Capsule()).foregroundStyle(Theme.paper).padding(.bottom, 20).accessibilityAddTraits(.updatesFrequently) }
        }
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
            ReaderView(article: article, close: { self.selection = nil }).id(article.id)
        } else {
            Theme.paper.ignoresSafeArea()
        }
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
