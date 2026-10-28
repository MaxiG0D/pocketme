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
    @State private var openSwipe: SwipeOpen?
    @State private var showAdd = false
    @State private var search = ""
    @State private var searching = false
    @State private var heroSquish: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @FocusState private var gridFocused: Bool
    @AppStorage(LibraryLayout.storageKey) private var layout: LibraryLayout = .list
    /// In the grid the reader covers the whole window instead of sitting beside a list.
    @State private var gridReader = false
    @State private var zoomAnchor = UnitPoint.center
    @State private var revealID: UUID?
    @State private var windowSize = CGSize.zero
    @State private var frames = CardFrames()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var filtered: [Article] {
        articles.filter { section.includes($0) && (search.isEmpty || ($0.title + " " + $0.siteName).localizedCaseInsensitiveContains(search)) }
            .sorted { section == .archive ? ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) : $0.savedAt > $1.savedAt }
    }
    /// The most recently opened unread article (even if scrolled back to the top), shown as a card above the rest of the list.
    private var inProgress: Article? {
        guard section == .unread, search.isEmpty else { return nil }
        return filtered.filter { $0.lastOpenedAt != nil && $0.readingProgress < 0.95 }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }
    private var openArticle: Article? { readerID.flatMap { id in articles.first { $0.id == id } } }
    private var unread: Int { articles.filter { $0.archivedAt == nil }.count }

    var body: some View {
        ZStack {
            if layout == .grid { gridMode.transition(.libraryLayout(reduceMotion: reduceMotion)) }
            else { split.transition(.libraryLayout(reduceMotion: reduceMotion)) }
        }
        .coordinateSpace(.named(CardFrames.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .libraryLayout, value: layout)
        #if os(macOS)
        .toolbarBackground(.hidden, for: .windowToolbar)
        // An empty toolbar item makes the title bar a 52pt unified one, which centers the window buttons on the reader header's line.
        .toolbar { windowToolbar }
        .frame(minWidth: 900, minHeight: 600)
        #endif
        .background(Theme.paper)
        .overlay(alignment: .bottom) { ToastView(store: store) }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.toast?.id)
        .onAppear(perform: ensureSelection)
        .onChange(of: readerID) { _, _ in openSwipe = nil }
        .onChange(of: section) { _, _ in ensureSelection() }
        .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
        .onChange(of: store.focusPasteToken) { _, _ in addLink() }
        .onChange(of: store.findToken) { _, _ in listVisible = true; searching = true; searchFocused = true }
        .onChange(of: store.toggleListToken) { _, _ in if layout == .list { listVisible.toggle() } }
        .onChange(of: store.requestedLayout) { _, new in if let new { switchLayout(to: new); store.requestedLayout = nil } }
        .onChange(of: store.requestedArticleID) { _, id in
            guard let id else { return }
            section = .unread; readerID = id; store.requestedArticleID = nil
            if layout == .grid && !gridReader { open(id) }
        }
        .confirmationDialog("Delete this article?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete article", role: .destructive) { if let article = toDelete { store.delete(article) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        }
        .sheet(isPresented: $showAdd) { AddLinkSheet().frame(width: 420) }
    }

    private var split: some View {
        HStack(spacing: 0) {
            if listVisible {
                list.frame(width: 360).overlay { TheaterShade() }.transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .leading).combined(with: .opacity))
            }
            reader.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .leading) { if listVisible && !store.theater { Rectangle().fill(Theme.hairline).frame(width: 1) } }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: listVisible)
    }

    // MARK: Grid

    /// The grid fills the window; opening a card grows the reader out of it, and closing shrinks it back in.
    private var gridMode: some View {
        ZStack {
            grid
                .scaleEffect(showingGridReader && !reduceMotion ? 0.97 : 1)
                .opacity(showingGridReader ? 0 : 1)
                .allowsHitTesting(!showingGridReader)
                .accessibilityHidden(showingGridReader)
            if showingGridReader, let article = openArticle {
                ReaderView(article: article, backTitle: section.title, close: closeGrid)
                    .background { Button("Back to library", action: closeGrid).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true) }
                    .transition(zoomTransition)
                    .zIndex(1)
            }
        }
    }
    private var showingGridReader: Bool {
        gridReader && openArticle != nil
    }
    private var gridColumns: Int { min(5, max(2, Int(windowSize.width / 300))) }
    /// At its smallest the reader is one card wide, so it starts and ends right over the card.
    private var zoomTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let scale = 1 / CGFloat(gridColumns)
        return .asymmetric(
            insertion: .scale(scale: scale, anchor: zoomAnchor).combined(with: .opacity.animation(.easeOut(duration: 0.14))),
            removal: .scale(scale: scale, anchor: zoomAnchor).combined(with: .opacity.animation(.easeIn(duration: 0.3))))
    }
    private var zoomAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.38) }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The same header, at the list column's width, so no control moves when the layout switches.
            header.frame(width: 360, alignment: .leading)
            ScrollViewReader { proxy in
                ScrollView {
                    if filtered.isEmpty {
                        emptyContent.frame(maxWidth: .infinity).padding(.top, 120)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: gridColumns), alignment: .leading, spacing: 16) {
                        ForEach(filtered) { article in
                            MacGridItem(article: article, selected: readerID == article.id, frames: frames, open: { open(article.id) },
                                        favorite: { store.favorite(article) }, archive: { store.archive(article) })
                                .contextMenu { menu(article) }
                                .id(article.id)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 32)
                }.scrollIndicators(.hidden)
                .onChange(of: revealID) { _, id in if let id { proxy.scrollTo(id, anchor: .center); revealID = nil } }
                .onChange(of: readerID) { _, id in if let id, !gridReader { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } } }
            }
        }.background(Theme.paper)
            .focusable().focusEffectDisabled().focused($gridFocused)
            .onKeyPress(.leftArrow) { gridStep(-1) }
            .onKeyPress(.rightArrow) { gridStep(1) }
            .onKeyPress(.upArrow) { gridStep(-gridColumns) }
            .onKeyPress(.downArrow) { gridStep(gridColumns) }
            .onKeyPress(.return) { guard !searchFocused, let readerID else { return .ignored }; open(readerID); return .handled }
            .onKeyPress("e") { act { store.archive($0) } }
            .onKeyPress("f") { act { store.favorite($0) } }
            .onKeyPress(.delete) { act { toDelete = $0 } }
            .onKeyPress(.deleteForward) { act { toDelete = $0 } }
            .onAppear { gridFocused = true }
    }

    private func switchLayout(to new: LibraryLayout) {
        guard new != layout else { return }
        gridReader = false
        layout = new
    }
    private func open(_ id: UUID) {
        readerID = id
        zoomAnchor = anchor(for: id)
        withAnimation(zoomAnimation) { gridReader = true }
    }
    /// The card may have moved since the reader opened (Next article, a resized window), so the anchor is
    /// measured again and applied a frame before the reader leaves.
    private func closeGrid() {
        guard gridReader else { return }
        if let readerID {
            zoomAnchor = anchor(for: readerID)
            if zoomAnchor == .center { revealID = readerID }
        }
        Task { @MainActor in
            withAnimation(zoomAnimation) { gridReader = false }
            gridFocused = true
            ensureSelection()
        }
    }
    /// The point the reader scales around so that, shrunk to one card's width, it sits centered on the card.
    private func anchor(for id: UUID) -> UnitPoint {
        let size = windowSize
        guard size.width > 0, size.height > 0, let card = frames[id],
              CGRect(origin: .zero, size: size).contains(CGPoint(x: card.midX, y: card.midY)) else { return .center }
        let scale = 1 / CGFloat(gridColumns)
        let x = (card.midX - scale * size.width / 2) / (1 - scale)
        let y = (card.midY - scale * size.height / 2) / (1 - scale)
        return UnitPoint(x: x / size.width, y: y / size.height)
    }
    private func gridStep(_ delta: Int) -> KeyPress.Result {
        guard !gridReader, !searchFocused else { return .ignored }
        return step(delta)
    }

    // MARK: List

    @ViewBuilder private var reader: some View {
        if let article = openArticle, filtered.contains(where: { $0.id == article.id }) {
            ReaderView(article: article, besideList: true, clearsTrafficLights: !listVisible)
        } else {
            emptyContent.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    @ViewBuilder private var emptyContent: some View {
        if articles.isEmpty {
            EmptyStateView { pasteFromClipboard() }
        } else {
            Text(search.isEmpty ? "No articles here yet" : "No matching articles").font(Typo.meta).foregroundStyle(Theme.muted)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let current = inProgress {
                        ContinueReadingCard(article: current, squish: reduceMotion ? 0 : heroSquish) { readerID = current.id }
                            .padding(.bottom, 4)
                    }
                    ForEach(filtered.filter { $0.id != inProgress?.id }) { article in
                        // A real button takes the click itself; stacked tap gestures on the card were swallowing it.
                        Button { readerID = article.id } label: {
                            CompactRow(article: article, selected: readerID == article.id)
                        }.buttonStyle(CardButtonStyle()).frame(maxWidth: .infinity)
                            .swipeReveal(id: article.id, open: $openSwipe, actions: swipeActions(for: article), cornerRadius: 16)
                            .contextMenu { menu(article) }
                            .accessibilityAddTraits(readerID == article.id ? [.isButton, .isSelected] : .isButton)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 24)
            }.scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                min(max((geometry.contentOffset.y + geometry.contentInsets.top) / 320, 0), 1)
            } action: { _, new in heroSquish = new }
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
    /// The title and controls, shared by the list column and the grid.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The layout toggle rides on the title line, so the tabs below keep their full width.
            HStack {
                Text("Pocket Me").font(Typo.largeTitle).tracking(-0.5).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                layoutButton
            }.padding(.leading, 16).padding(.trailing, 6).padding(.top, 8).padding(.bottom, 10)
            HStack(spacing: 8) { addButton; Divider().frame(height: 16).padding(.horizontal, 4); tabs; Spacer(minLength: 0); searchButton }
                .padding(.horizontal, 12).padding(.bottom, searching ? 6 : 10)
            if searching { searchField }
            if let message = store.errorMessage { Text(message).font(Typo.meta).foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.bottom, 8) }
        }
    }
    private var layoutButton: some View {
        HoverIconButton(symbol: layout.toggleSymbol, glyph: 17, size: 40, label: layout.toggleLabel,
                        help: layout == .list ? "Show as Grid (⌘2)" : "Show as List (⌘1)") { switchLayout(to: layout.other) }
    }
    /// The list toggle, like Mail and Notes: one spot beside the window buttons. In the grid and in theater mode the item stays,
    /// empty, so the bar keeps its height. The glass behind it is hidden so nothing draws around it.
    private var listToggle: some View {
        Group {
            if layout == .list && !store.theater {
                HoverIconButton(symbol: "sidebar.left", glyph: 15, size: 30, label: listVisible ? "Hide list" : "Show list", help: "Show or Hide List (⌃⌘S)") { listVisible.toggle() }
            } else {
                Color.clear.frame(width: 30, height: 30).accessibilityHidden(true)
            }
        }
    }
    @ToolbarContentBuilder private var windowToolbar: some ToolbarContent {
        // `sharedBackgroundVisibility` only exists in the Swift 6.2 (Xcode 26) SDKs; CI's pinned Xcode 16.4 must not see it.
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { listToggle }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { listToggle }
        }
        #else
        ToolbarItem(placement: .navigation) { listToggle }
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
                    }.fixedSize().foregroundStyle(section == choice ? Theme.ink : Theme.muted)
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
        // An article archived from the full-window reader stays on screen while the reader shrinks back.
        if gridReader && layout == .grid && openArticle != nil { return }
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
        guard !searchFocused, !(layout == .grid && gridReader), let article = openArticle else { return .ignored }
        action(article)
        return .handled
    }
    private func swipeActions(for article: Article) -> [SwipeAction] {[
        SwipeAction(side: .leading, symbol: "bookmark", color: Theme.swipeFavorite, label: article.isFavorite ? "Remove favorite" : "Favorite") { store.favorite(article) },
        SwipeAction(side: .trailing, symbol: "archivebox", color: Theme.swipeArchive, label: article.archivedAt == nil ? "Archive" : "Unarchive") { store.archive(article) },
    ]}
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

/// Where each grid card sits, kept out of SwiftUI state so scrolling the grid redraws nothing.
@MainActor final class CardFrames {
    nonisolated static let space = "library"
    private var frames: [UUID: CGRect] = [:]
    subscript(id: UUID) -> CGRect? {
        get { frames[id] }
        set { frames[id] = newValue }
    }
}

/// One grid card. The card is a single Button; the hover actions sit beside it in an overlay, never inside it,
/// so a click lands on exactly one control.
private struct MacGridItem: View {
    let article: Article
    let selected: Bool
    let frames: CardFrames
    let open: () -> Void
    let favorite: () -> Void
    let archive: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: open) { ArticleGridCard(article: article, selected: selected, hovered: hover, showsFavorite: !hover) }
            .buttonStyle(GridCardButtonStyle())
            .overlay(alignment: .topTrailing) {
                if hover {
                    HStack(spacing: 6) {
                        quick(article.isFavorite ? "bookmark.fill" : "bookmark", label: article.isFavorite ? "Remove favorite" : "Favorite",
                              tint: article.isFavorite ? Theme.swipeFavorite : Theme.icon, action: favorite)
                        quick("archivebox", label: article.archivedAt == nil ? "Archive" : "Unarchive", tint: Theme.icon, action: archive)
                    }.padding(16).transition(.opacity)
                }
            }
            .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hover = inside } }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CardFrames.space)) } action: { frames[article.id] = $0 }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    private func quick(_ symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 28, height: 28).background(Theme.paper.opacity(0.94), in: Circle())
                .shadow(color: Theme.ink.opacity(0.12), radius: 4, y: 1)
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}

/// A bare glyph with a soft disc on hover, so it reads as a target without drawing a button.
private struct HoverIconButton: View {
    let symbol: String
    let glyph: CGFloat
    let size: CGFloat
    let label: String
    let help: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: glyph, weight: .medium)).foregroundStyle(hover ? Theme.iconSelected : Theme.icon)
                .frame(width: size, height: size)
                .background(Theme.chip.opacity(hover ? 1 : 0), in: Circle())
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }.buttonStyle(.plain)
            .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hover = inside } }
            .accessibilityLabel(label).help(help)
    }
}

/// Passes the card through untouched, so the button keeps the card's full width and look.
private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
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
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            .background(selected ? Theme.cardSelection : hover ? Theme.cardSelection.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // A faint ink ring makes the open article read at a glance without shouting.
            .overlay { if selected { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ink.opacity(0.14), lineWidth: 1) } }
            .contentShape(Rectangle()).onHover { hover = $0 }
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in MacLibraryView().frame(width: 1440, height: 900) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in MacLibraryView().frame(width: 1440, height: 900) }.preferredColorScheme(.dark) }
#endif
#endif
