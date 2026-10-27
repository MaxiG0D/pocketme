#if os(macOS)
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
    @State private var search = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var filtered: [Article] {
        articles.filter { section.includes($0) && (search.isEmpty || ($0.title + " " + $0.siteName).localizedCaseInsensitiveContains(search)) }
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
        .overlay(alignment: .bottom) { ToastView(store: store) }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.toast?.id)
        .onAppear(perform: ensureSelection)
        .onChange(of: section) { _, _ in ensureSelection() }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
        .onChange(of: store.focusPasteToken) { _, _ in addLink() }
        .onChange(of: store.findToken) { _, _ in listVisible = true; searching = true; searchFocused = true }
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
            ReaderView(article: article, toggleList: { listVisible.toggle() }, clearsTrafficLights: !listVisible)
        } else {
            VStack(spacing: 0) {
                if !listVisible { Button { listVisible = true } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Show list")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 76).padding(.top, 8) }
                Group {
                    if articles.isEmpty {
                        EmptyStateView { pasteFromClipboard() }
                    } else {
                        Text(search.isEmpty ? "No articles here yet" : "No matching articles").font(Typo.meta).foregroundStyle(Theme.muted)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pocket Me").font(Typo.largeTitle).tracking(-0.5).foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.top, 44).padding(.bottom, 10)
            HStack(spacing: 8) { addButton; Divider().frame(height: 16).padding(.horizontal, 4); tabs; Spacer(minLength: 0); searchButton }.padding(.horizontal, 12).padding(.bottom, searching ? 6 : 10)
            if searching { searchField }
            if let message = store.errorMessage { Text(message).font(Typo.meta).foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.bottom, 8) }
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { article in
                        CompactRow(article: article, selected: readerID == article.id)
                            .swipeToArchive(archived: article.archivedAt != nil, favorite: article.isFavorite,
                                            onArchive: { store.archive(article) }, onFavorite: { store.favorite(article) })
                            .onTapGesture { Diag.log("row tap \(article.title.prefix(30))"); readerID = article.id }.contextMenu { menu(article) }
                            .accessibilityAddTraits(readerID == article.id ? [.isButton, .isSelected] : .isButton)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 24)
            }.scrollIndicators(.hidden)
            .onChange(of: readerID) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }.background(Theme.paper)
            .focusable().focusEffectDisabled()
            .onKeyPress(.downArrow) { step(1) }
            .onKeyPress(.upArrow) { step(-1) }
            .onKeyPress("e") { act { store.archive($0) } }
            .onKeyPress("f") { act { store.favorite($0) } }
            .onKeyPress(.delete) { act { toDelete = $0 } }
            .onKeyPress(.deleteForward) { act { toDelete = $0 } }
            #if os(macOS)
            .onPasteCommand(of: [.url, .plainText]) { providers in
                let item = NSExtensionItem(); item.attachments = providers
                Task { if let url = try? await ShareInput.link(from: [item]) { _ = store.saveLink(url.absoluteString) } }
            }
            #endif
    }
    private var searchButton: some View {
        Button { searching.toggle(); searchFocused = searching; if !searching { search = "" } } label: {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(searching ? Theme.ink : Theme.muted)
                .frame(width: 28, height: 28)
        }.buttonStyle(.plain).accessibilityLabel("Search").help("Search (⌘F)")
    }
    private var searchField: some View {
        HStack(spacing: 6) {
            TextField("Title or site", text: $search).textFieldStyle(.plain).font(Typo.sans(13)).focused($searchFocused)
                .onSubmit { searchFocused = false }
                .onExitCommand { search = ""; searching = false; searchFocused = false }
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted.opacity(0.7)).accessibilityLabel("Clear")
            }
        }.padding(.horizontal, 10).frame(height: 30)
            .background(Theme.chip, in: Capsule())
            .padding(.horizontal, 12).padding(.bottom, 10)
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

    /// Opens the sheet, which prefills a copied link; nothing is saved until it is confirmed.
    private func addLink() { showAdd = true }
    private func pasteFromClipboard() { if let raw = Clipboard.link { _ = store.saveLink(raw) } else { showAdd = true } }
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
    /// Runs a list shortcut on the open article; ignored while typing in the search field.
    private func act(_ action: (Article) -> Void) -> KeyPress.Result {
        guard !searchFocused, let article = openArticle else { return .ignored }
        action(article)
        return .handled
    }
    @ViewBuilder private func menu(_ article: Article) -> some View {
        Button("Open original in browser") { if let url = URL(string: article.url) { openURL(url) } }
        Button("Copy link") { Clipboard.copy(article.url) }
        if let url = URL(string: article.url) { ShareLink("Share", item: url) }
        Button(article.isFavorite ? "Remove favorite" : "Favorite") { store.favorite(article) }
        Button(article.archivedAt == nil ? "Archive" : "Unarchive") { store.archive(article) }
        if article.status == .failed { Button("Retry") { store.retry(article) } }
        Button("Delete", role: .destructive) { toDelete = article }
    }
}

/// Thumbnail-led card, matching the Mac mockup: a wide cover with the title and source underneath.
private struct CompactRow: View {
    let article: Article
    let selected: Bool
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArticleThumb(article: article, height: 148, radius: Theme.radiusThumb)
                .overlay { RoundedRectangle(cornerRadius: Theme.radiusThumb, style: .continuous).strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 0.5) }
            VStack(alignment: .leading, spacing: 5) {
                // A link without a real title is named after its site; say it once, not twice.
                if article.title != article.siteName {
                    Text(article.title).font(Typo.sans(15).weight(.semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                ArticleMetaView(article: article, emphasizeSite: article.title == article.siteName)
            }.padding(.horizontal, 2)
        }.padding(8)
            .background(selected ? Theme.cardSelection : hover ? Theme.cardSelection.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle()).onHover { hover = $0 }
    }
}

/// Two-finger trackpad swipe on a card, like the iPhone list: left opens Archive, right opens Favorite; clicking the button acts.
private struct SwipeToArchive: ViewModifier {
    let archived: Bool
    let favorite: Bool
    let onArchive: () -> Void
    let onFavorite: () -> Void
    @State private var offset: CGFloat = 0
    @State private var hover = false
    @State private var monitor: Any?
    @State private var horizontal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let reveal: CGFloat = 84

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: offset < 0 ? .trailing : .leading) { actionButton }
            .onHover { hover = $0 }
            .onAppear { monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { handle($0) } }
            .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
            .simultaneousGesture(TapGesture().onEnded { if offset != 0 { settle(0) } })
            .accessibilityAction(named: archived ? "Unarchive" : "Archive", onArchive)
    }

    @ViewBuilder private var actionButton: some View {
        if offset != 0 {
            let leftward = offset < 0
            Button {
                settle(0)
                if leftward { onArchive() } else { onFavorite() }
            } label: {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(leftward ? Theme.success : Theme.ink)
                    .overlay {
                        Image(systemName: leftward ? "archivebox" : "bookmark")
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    }
            }.buttonStyle(.plain).frame(width: min(abs(offset), reveal))
                .accessibilityLabel(leftward ? (archived ? "Unarchive" : "Archive") : (favorite ? "Remove favorite" : "Favorite"))
        }
    }

    private func settle(_ target: CGFloat) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { offset = target }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.hasPreciseScrollingDeltas else { return event }
        if event.phase == .began || event.phase == .mayBegin {
            horizontal = hover && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            if !horizontal && offset != 0 { settle(0) }
        }
        guard horizontal else {
            // Scrolling the list vertically closes an open card.
            if offset != 0, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) { settle(0) }
            return event
        }
        if event.phase == .ended || event.phase == .cancelled {
            horizontal = false
            settle(abs(offset) > reveal / 2 ? (offset < 0 ? -reveal : reveal) : 0)
            return nil
        }
        offset = min(reveal * 1.4, max(-reveal * 1.4, offset + event.scrollingDeltaX))
        return nil
    }
}

private extension View {
    func swipeToArchive(archived: Bool, favorite: Bool, onArchive: @escaping () -> Void, onFavorite: @escaping () -> Void) -> some View {
        modifier(SwipeToArchive(archived: archived, favorite: favorite, onArchive: onArchive, onFavorite: onFavorite))
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in MacLibraryView().frame(width: 1440, height: 900) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in MacLibraryView().frame(width: 1440, height: 900) }.preferredColorScheme(.dark) }
#endif
#endif
