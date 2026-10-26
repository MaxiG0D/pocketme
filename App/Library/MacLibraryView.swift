import SwiftData
import SwiftUI

struct MacLibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    @State private var section: LibrarySection = .unread
    @State private var readerID: UUID?
    @State private var listVisible = true
    @State private var toDelete: Article?
    @State private var showAdd = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var filtered: [Article] {
        articles.filter { section.includes($0) }
            .sorted { section == .archive ? ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) : $0.savedAt > $1.savedAt }
    }
    private var openArticle: Article? { readerID.flatMap { id in articles.first { $0.id == id } } }
    private var unread: Int { articles.filter { $0.archivedAt == nil }.count }

    var body: some View {
        HStack(spacing: 0) {
            if listVisible {
                list.frame(width: 360).transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .leading).combined(with: .opacity))
            }
            reader.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .leading) { if listVisible { Rectangle().fill(Theme.hairline).frame(width: 1) } }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: listVisible)
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 600)
        #endif
        .background(Theme.paper)
        .onAppear(perform: ensureSelection)
        .onChange(of: section) { _, _ in ensureSelection() }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
        .onChange(of: store.focusPasteToken) { _, _ in addLink() }
        .onChange(of: store.toggleListToken) { _, _ in listVisible.toggle() }
        .onChange(of: store.requestedArticleID) { _, id in
            if let id { section = .unread; readerID = id; store.requestedArticleID = nil }
        }
        .confirmationDialog("Delete this article?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete article", role: .destructive) { if let article = toDelete { store.delete(article) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        }
        .sheet(isPresented: $showAdd) { AddLinkSheet().frame(width: 420) }
    }

    @ViewBuilder private var reader: some View {
        if let article = openArticle, filtered.contains(where: { $0.id == article.id }) {
            ReaderView(article: article, toggleList: { listVisible.toggle() }, clearsTrafficLights: !listVisible).id(article.id)
        } else {
            VStack(spacing: 0) {
                if !listVisible { Button { listVisible = true } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Show list")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 76).padding(.top, 8) }
                Group {
                    if articles.isEmpty {
                        EmptyStateView { addLink() }
                    } else {
                        Text("No articles here yet").font(Typo.meta).foregroundStyle(Theme.muted)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) { addButton; tabs }.padding(.horizontal, 12).padding(.top, listTopInset).padding(.bottom, 10)
            if let message = store.errorMessage { Text(message).font(Typo.meta).foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.bottom, 8) }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { article in
                        CompactRow(article: article, selected: readerID == article.id)
                            .onTapGesture { readerID = article.id }.contextMenu { menu(article) }
                            .accessibilityAddTraits(readerID == article.id ? [.isButton, .isSelected] : .isButton)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 24)
            }.scrollIndicators(.hidden)
        }.background(Theme.paper)
            .focusable().focusEffectDisabled()
            .onKeyPress(.downArrow) { step(1) }
            .onKeyPress(.upArrow) { step(-1) }
            #if os(macOS)
            .onPasteCommand(of: [.url, .plainText]) { providers in
                let item = NSExtensionItem(); item.attachments = providers
                Task { if let url = try? await ShareInput.link(from: [item]) { _ = store.saveLink(url.absoluteString) } }
            }
            #endif
    }
    /// On the Mac the hidden title bar leaves room for the traffic lights; elsewhere the safe area already does.
    private var listTopInset: CGFloat {
        #if os(macOS)
        44
        #else
        8
        #endif
    }
    private var addButton: some View {
        Button(action: addLink) {
            Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28).background(Theme.accent, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel("Add a link").help("Save a link (⌘N)")
    }
    /// The three sections are quiet tabs above the list.
    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(LibrarySection.allCases) { choice in
                Button { section = choice } label: {
                    HStack(spacing: 5) {
                        Text(choice.title).font(Typo.sans(13).weight(section == choice ? .semibold : .medium))
                        if choice == .unread { Text(String(unread)).font(Typo.sans(12).weight(.medium)).foregroundStyle(Theme.muted) }
                    }.foregroundStyle(section == choice ? Theme.ink : Theme.muted)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(section == choice ? Theme.sidebarSelection : .clear, in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(section == choice ? .isSelected : [])
            }
        }
    }

    private func addLink() { if let raw = Clipboard.link { _ = store.saveLink(raw) } else { showAdd = true } }
    /// Keeps the reader on a valid article: the one just read if there is one, else the newest.
    private func ensureSelection() {
        if let readerID, filtered.contains(where: { $0.id == readerID }) { return }
        let recent = filtered.filter { $0.lastOpenedAt != nil }.max { $0.lastOpenedAt! < $1.lastOpenedAt! }
        readerID = (recent ?? filtered.first)?.id
    }
    private func step(_ delta: Int) -> KeyPress.Result {
        guard let index = filtered.firstIndex(where: { $0.id == readerID }), filtered.indices.contains(index + delta) else { return .ignored }
        readerID = filtered[index + delta].id
        return .handled
    }
    @ViewBuilder private func menu(_ article: Article) -> some View {
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
