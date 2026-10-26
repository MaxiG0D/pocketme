#if os(iOS)
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    var favoritesOnly = false
    @State private var archive = false
    @State private var search = ""
    @State private var showSearch = false
    @State private var addLink = false
    @State private var path: [UUID] = []
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

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.bottom, 20)
                    if let error = store.errorMessage {
                        Text(error).font(Typo.meta).foregroundStyle(Theme.muted).padding(.vertical, 12)
                    }
                    if filtered.isEmpty {
                        if articles.isEmpty { EmptyStateView(paste: pasteOrAdd).padding(.horizontal, -Theme.gutter).frame(maxWidth: .infinity).padding(.top, 50) }
                        else { Text(search.isEmpty ? "No articles here yet" : "No matching articles").font(Typo.meta).foregroundStyle(Theme.muted).padding(.top, 40) }
                    } else {
                        if let current { ContinueReadingCard(article: current) { path.append(current.id) }.padding(.bottom, 22) }
                        LazyVStack(spacing: 0) {
                            ForEach(filtered.filter { $0.id != current?.id }) { article in
                                SwipeableRow(open: { path.append(article.id) }, archive: { store.archive(article) }, favorite: { store.favorite(article) }) {
                                    ArticleRow(article: article)
                                }
                                .contextMenu { articleMenu(article) }
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                }.padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.paper).scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { store.refresh(); await store.drainInbox() }
            .navigationDestination(for: UUID.self) { id in
                if let article = articles.first(where: { $0.id == id }) { ReaderView(article: article) }
            }
            .sheet(isPresented: $addLink) { AddLinkSheet() }
            .confirmationDialog("Delete this article?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("Delete article", role: .destructive) { if let article = toDelete { store.delete(article) }; toDelete = nil }
                Button("Cancel", role: .cancel) { toDelete = nil }
            }
            .overlay(alignment: .bottom) {
                if saved { Text("Saved").font(Typo.button).padding(.horizontal, 22).padding(.vertical, 12).background(Theme.ink, in: Capsule()).foregroundStyle(Theme.paper).padding(.bottom, 20).accessibilityAddTraits(.updatesFrequently) }
            }
            .onChange(of: store.savedToken) { _, _ in
                saved = true; toast?.cancel()
                toast = Task { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { saved = false } }
            }
            .onChange(of: articles.map(\.id)) { _, ids in path.removeAll { !ids.contains($0) } }
            .onChange(of: store.requestedArticleID) { _, id in if let id { path = [id]; store.requestedArticleID = nil } }
            .sensoryFeedback(.success, trigger: store.savedToken).sensoryFeedback(.success, trigger: store.actionToken)
            .animation(.snappy(duration: 0.25), value: archive)
            .animation(.snappy(duration: 0.25), value: filtered.map(\.id))
        }.tint(Theme.ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 4) {
                Text(favoritesOnly ? "Favorites" : "Reading").font(Typo.largeTitle).tracking(-0.5).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Search articles")
                Button(action: pasteOrAdd) { Image(systemName: "plus").fontWeight(.semibold) }.buttonStyle(CircleIconButtonStyle(kind: .accent)).accessibilityLabel("Save a link")
            }
            if !favoritesOnly {
                HStack(spacing: 6) {
                    Button("Unread · \(articles.filter { $0.archivedAt == nil }.count)") { archive = false }.buttonStyle(PillButtonStyle(selected: !archive))
                    Button("Archive") { archive = true }.buttonStyle(PillButtonStyle(selected: archive))
                }
            }
            if showSearch {
                TextField("Search title or site", text: $search).font(Typo.meta).padding(14)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12)).autocorrectionDisabled()
            }
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
#endif

#if DEBUG && os(iOS)
#Preview("Light") { PreviewHost { store, articles in LibraryView().frame(width: 390, height: 844) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in LibraryView().frame(width: 390, height: 844) }.preferredColorScheme(.dark) }
#endif
