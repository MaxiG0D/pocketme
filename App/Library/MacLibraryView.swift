import SwiftData
import SwiftUI

struct MacLibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    @State private var section: LibrarySection = .unread
    @State private var selectedID: UUID?
    @State private var readerID: UUID?
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

    private var readerOpen: Bool { openArticle != nil }
    private var openArticle: Article? { readerID.flatMap { id in articles.first { $0.id == id } } }
    private var topInset: CGFloat {
        #if os(macOS)
        84 // room for the traffic lights, which share the header row
        #else
        0
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            library
                .frame(maxWidth: readerOpen ? 360 : .infinity)
            if let article = openArticle {
                // The reader opens beside the list, so moving between articles never leaves the library.
                ReaderView(article: article, backTitle: section.title, embedded: true) { readerID = nil }
                    .id(article.id)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: readerID)
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 600)
        .onExitCommand { readerID = nil }
        #endif
        .background(Theme.paper)
        .onChange(of: section) { _, _ in selectedID = nil }
        .onChange(of: store.focusPasteToken) { _, _ in pasteFocused = true }
        .onChange(of: articles.map(\.id)) { _, ids in
            if let readerID, !ids.contains(readerID) { self.readerID = nil }
        }
        .onChange(of: store.requestedArticleID) { _, id in if let id { readerID = id; selectedID = id; store.requestedArticleID = nil } }
        .confirmationDialog("Delete this article?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete article", role: .destructive) { if let article = toDelete { if selectedID == article.id { selectedID = nil }; store.delete(article) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        }
        .sheet(isPresented: $showAdd) { AddLinkSheet().frame(width: 420) }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: readerOpen ? 14 : 28) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { tabs; Spacer(minLength: 12); if !readerOpen { pasteField } }
                    VStack(alignment: .leading, spacing: 18) { tabs; if !readerOpen { pasteField } }
                }
                if let message = store.errorMessage { Text(message).font(Typo.meta).foregroundStyle(Theme.muted) }
                if articles.isEmpty {
                    EmptyStateView {
                        if let raw = Clipboard.link { _ = store.saveLink(raw) } else { showAdd = true }
                    }.frame(maxWidth: .infinity).padding(.top, 30)
                } else if filtered.isEmpty {
                    Text("No articles here yet").font(Typo.meta).foregroundStyle(Theme.muted).padding(.top, 40)
                } else if readerOpen {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { article in
                            CompactRow(article: article, selected: readerID == article.id)
                                .onTapGesture { open(article) }.contextMenu { menu(article) }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 22)], alignment: .leading, spacing: 22) {
                        ForEach(filtered) { article in
                            ArticleCard(article: article, selected: selectedID == article.id)
                                .onTapGesture { open(article) }
                                .contextMenu { menu(article) }
                        }
                    }
                }
            }.padding(.horizontal, readerOpen ? 12 : 32).padding(.top, 14).padding(.bottom, 32)
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
    /// The three sections live in the header as quiet tabs instead of a sidebar.
    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(LibrarySection.allCases) { choice in
                Button { section = choice } label: {
                    HStack(spacing: 6) {
                        Text(choice.title).font(Typo.sans(readerOpen ? 13 : 14).weight(section == choice ? .semibold : .medium))
                        if choice == .unread { Text(String(unread)).font(Typo.sans(12).weight(.medium)).foregroundStyle(Theme.muted) }
                    }.foregroundStyle(section == choice ? Theme.ink : Theme.muted)
                        .padding(.horizontal, readerOpen ? 10 : 14).frame(height: 32)
                        .background(section == choice ? Theme.sidebarSelection : .clear, in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(section == choice ? .isSelected : [])
            }
        }.padding(.leading, topInset).padding(.top, 4)
    }
    private var unread: Int { articles.filter { $0.archivedAt == nil }.count }
    private var pasteField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(Theme.muted)
                TextField("Paste a link to save", text: $link).textFieldStyle(.plain).font(Typo.sans(14)).focused($pasteFocused).onSubmit(save)
            }.padding(.horizontal, 12).frame(minWidth: 150, idealWidth: 260, maxWidth: 260).frame(height: 38)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
            Button("Save", action: save).buttonStyle(.plain).font(Typo.sans(14).weight(.semibold))
                .foregroundStyle(Theme.onAccent).padding(.horizontal, 16).frame(height: 38)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10)).disabled(link.isEmpty)
        }
    }
    private func save() { if let article = store.saveLink(link) { selectedID = article.id; link = "" } }
    private func open(_ article: Article) { selectedID = article.id; readerID = article.id }
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

private struct CompactRow: View {
    let article: Article
    let selected: Bool
    @State private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            ArticleThumb(article: article, width: 56, height: 56, radius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title).font(Typo.sans(14).weight(.semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                ArticleMetaView(article: article)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(8)
            .background(selected ? Theme.cardSelection : hover ? Theme.cardSelection.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle()).onHover { hover = $0 }
    }
}

#if DEBUG && os(macOS)
#Preview("Light") { PreviewHost { store, articles in MacLibraryView().frame(width: 1440, height: 900) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in MacLibraryView().frame(width: 1440, height: 900) }.preferredColorScheme(.dark) }
#endif
