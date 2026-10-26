import SwiftData
import SwiftUI

struct MacLibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    @State private var section: LibrarySection = .unread
    @State private var selectedID: UUID?
    @State private var readerID: UUID?
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var link = ""
    @State private var search = ""
    @State private var toDelete: Article?
    @State private var showAdd = false
    @FocusState private var pasteFocused: Bool
    private var selected: Article? { articles.first { $0.id == selectedID } }
    private var filtered: [Article] {
        articles.filter { section.includes($0) && (search.isEmpty || ($0.title + " " + $0.siteName).localizedCaseInsensitiveContains(search)) }
            .sorted { section == .archive ? ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) : $0.savedAt > $1.savedAt }
    }

    var body: some View {
        Group {
            if let readerID, let article = articles.first(where: { $0.id == readerID }) {
                NavigationSplitView(columnVisibility: $columns) {
                    MacSidebar(section: $section, unread: articles.filter { $0.archivedAt == nil }.count)
                } detail: {
                    ReaderView(article: article) { self.readerID = nil; columns = .all }
                }
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    MacSidebar(section: $section, unread: articles.filter { $0.archivedAt == nil }.count)
                } content: {
                    grid.navigationSplitViewColumnWidth(min: 300, ideal: 620)
                } detail: {
                    PreviewPane(article: selected) { if let selected { open(selected) } }
                        .navigationSplitViewColumnWidth(min: 360, ideal: 400, max: 440)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 600)
        #endif
        .background(Theme.paper)
        .onChange(of: section) { _, _ in readerID = nil; selectedID = nil; columns = .all }
        .onChange(of: store.focusPasteToken) { _, _ in pasteFocused = true }
        .onChange(of: articles.map(\.id)) { _, ids in
            if let readerID, !ids.contains(readerID) { self.readerID = nil; columns = .all }
        }
        .onChange(of: store.requestedArticleID) { _, id in if let id { readerID = id; selectedID = id; columns = .all; store.requestedArticleID = nil } }
        .confirmationDialog("Delete this article?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete article", role: .destructive) { if let article = toDelete { if selectedID == article.id { selectedID = nil }; store.delete(article) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        }
        .sheet(isPresented: $showAdd) { AddLinkSheet().frame(width: 420) }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { title; Spacer(minLength: 12); pasteField }
                    VStack(alignment: .leading, spacing: 18) { title; pasteField }
                }
                if let message = store.errorMessage { Text(message).font(Typo.meta).foregroundStyle(Theme.muted) }
                if articles.isEmpty {
                    EmptyStateView {
                        if let raw = Clipboard.link { _ = store.saveLink(raw) } else { showAdd = true }
                    }.frame(maxWidth: .infinity).padding(.top, 30)
                } else if filtered.isEmpty {
                    Text("No articles here yet").font(Typo.meta).foregroundStyle(Theme.muted).padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 22)], alignment: .leading, spacing: 22) {
                        ForEach(filtered) { article in
                            ArticleCard(article: article, selected: selectedID == article.id)
                                .onTapGesture(count: 2) { open(article) }.onTapGesture { selectedID = article.id }
                                .contextMenu { menu(article) }
                        }
                    }
                }
            }.padding(.horizontal, 32).padding(.top, 40).padding(.bottom, 32)
        }.background(Theme.paper).scrollIndicators(.hidden)
            .focusable().focusEffectDisabled()
            .onKeyPress(.return) { guard !pasteFocused else { return .ignored }; if let selected { open(selected); return .handled }; return .ignored }
            #if os(macOS)
            .onPasteCommand(of: [.url, .plainText]) { providers in
                let item = NSExtensionItem(); item.attachments = providers
                Task { if let url = try? await ShareInput.link(from: [item]) { _ = store.saveLink(url.absoluteString) } }
            }
            #endif
    }
    private var title: some View { Text(section.title).font(Typo.serif(30)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
    private var pasteField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(Theme.muted)
                TextField("Paste a link to save", text: $link).textFieldStyle(.plain).font(Typo.sans(14)).focused($pasteFocused).onSubmit(save)
            }.padding(.horizontal, 12).frame(minWidth: 150, idealWidth: 280, maxWidth: 280).frame(height: 38)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
            Button("Save", action: save).buttonStyle(.plain).font(Typo.sans(14).weight(.semibold))
                .foregroundStyle(Theme.onAccent).padding(.horizontal, 16).frame(height: 38)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10)).disabled(link.isEmpty)
        }
    }
    private func save() { if let article = store.saveLink(link) { selectedID = article.id; link = "" } }
    private func open(_ article: Article) { selectedID = article.id; readerID = article.id; columns = .all }
    @ViewBuilder private func menu(_ article: Article) -> some View {
        Button("Open") { open(article) }
        Button("Open original in browser") { if let url = URL(string: article.url) { openURL(url) } }
        Button("Copy link") { Clipboard.copy(article.url) }
        Button(article.isFavorite ? "Remove favorite" : "Favorite") { store.favorite(article) }
        Button(article.archivedAt == nil ? "Archive" : "Unarchive") { store.archive(article) }
        if article.status == .failed { Button("Retry") { store.retry(article) } }
        Button("Delete", role: .destructive) { toDelete = article }
    }
}

#if DEBUG && os(macOS)
#Preview("Light") { PreviewHost { store, articles in MacLibraryView().frame(width: 1440, height: 900) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in MacLibraryView().frame(width: 1440, height: 900) }.preferredColorScheme(.dark) }
#endif
