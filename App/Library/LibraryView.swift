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
    /// What the columns showed before theater mode folded them away, so they return as they were.
    @State private var columnsBeforeTheater: NavigationSplitViewVisibility?
    @State private var toDelete: Article?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @AppStorage(LibraryLayout.storageKey) private var layout: LibraryLayout = .list
    /// The article pushed from the grid; the grid always reads full screen, folded or not.
    @State private var gridOpen: UUID?
    @State private var gridWidth: CGFloat = 0
    /// The article open beside the list while the grid covers it, reopened on the way back.
    @State private var parkedSelection: UUID?
    /// The layout in front. It trails `layout` by half a switch: the old articles fade out, the layers swap
    /// in that empty moment, then the new articles fade in, so the two never show through each other.
    @State private var front: LibraryLayout
    @State private var articlesHidden = false
    @State private var listHeights = RowHeights()

    init(favoritesOnly: Bool = false) {
        self.favoritesOnly = favoritesOnly
        _front = State(initialValue: UserDefaults.standard.string(forKey: LibraryLayout.storageKey).flatMap(LibraryLayout.init) ?? .list)
    }
    @Namespace private var zoom

    private var filtered: [Article] {
        let section: LibrarySection = favoritesOnly ? .favorites : archive ? .archive : .unread
        let matches = articles.filter { section.includes($0) && (search.isEmpty || ($0.title + " " + $0.siteName).localizedCaseInsensitiveContains(search)) }
        // The query already arrives newest first; only the archive reorders, so the common case sorts nothing.
        guard archive && !favoritesOnly else { return matches }
        return matches.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }
    /// Side by side, the article being read is already open next to the list; promoting it to a hero card
    /// would make its row jump in and out as reading progress changes.
    private var current: Article? { sizeClass == .regular ? nil : inProgress }
    private var inProgress: Article? { inProgress(in: filtered) }
    private func inProgress(in filtered: [Article]) -> Article? {
        guard !favoritesOnly, !archive, search.isEmpty else { return nil }
        return filtered.filter { $0.lastOpenedAt != nil && $0.readingProgress < 0.95 }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }
    private let rowInsets = EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter)
    @State private var openSwipe: SwipeOpen?
    private func swipeActions(for article: Article) -> [SwipeAction] {[
        SwipeAction(side: .leading, symbol: "bookmark", color: Theme.swipeFavorite, label: article.isFavorite ? "Remove favorite" : "Favorite") { store.favorite(article) },
        SwipeAction(side: .trailing, symbol: "archivebox", color: Theme.swipeArchive, label: article.archivedAt == nil ? "Archive" : "Unarchive") { store.archive(article) },
    ]}

    private var gridBuilt: Bool { layout == .grid || front == .grid }
    private var gridFront: Bool { front == .grid }

    var body: some View {
        // Two stages: one long modifier chain overran the type checker's time limit on Xcode 26.6.
        layers
            .onAppear(perform: ensureSelection)
            .onChange(of: selection) { _, new in selectionChanged(to: new) }
            .onChange(of: compactColumn) { _, column in compactColumnChanged(to: column) }
            .onChange(of: filtered.map(\.id)) { _, _ in ensureSelection() }
            .onChange(of: sizeClass) { _, _ in ensureSelection() }
            .onChange(of: store.requestedArticleID) { _, id in openRequested(id) }
            .sensoryFeedback(.success, trigger: store.savedToken)
            .sensoryFeedback(.success, trigger: store.actionToken)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: archive)
            // A short ease, no overshoot: rows below close the gap and settle, they do not spring past it.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: filtered.map(\.id))
    }

    private func selectionChanged(to new: UUID?) {
        openSwipe = nil
        // Folded, the split view only moves to the reader when told; the list no longer does it through its selection.
        if sizeClass != .regular {
            let target: NavigationSplitViewColumn = new == nil ? .sidebar : .detail
            compactColumn = target
        }
    }

    private func compactColumnChanged(to column: NavigationSplitViewColumn) {
        if column == .sidebar && sizeClass != .regular { selection = nil }
    }

    private func openRequested(_ id: UUID?) {
        guard let id else { return }
        if layout == .grid { gridOpen = id } else { selection = id }
        store.requestedArticleID = nil
    }

    private var layers: some View {
        // The list stays built underneath, so it keeps its scroll spot and hidden search field for the way back.
        // The bars and pills match in both, so only the articles change; every step is a plain fade, which also suits Reduce Motion.
        ZStack {
            split.layoutLayer(shown: layout == .list)
            if gridBuilt {
                // Never faded as a whole: UIKit fades each piece on its own, so the matching bars and pills would dip grey.
                gridStack.layoutLayer(shown: layout == .grid).opacity(gridFront ? 1.0 : 0.0)
            }
        }
        .sensoryFeedback(.selection, trigger: layout)
        // Side by side, theater mode hands the whole screen to the reader so the video can center on it.
        .onChange(of: store.theater) { _, on in
            guard sizeClass == .regular else { return }
            withAnimation(reduceMotion ? Theater.fade : Theater.spring) {
                if on { columnsBeforeTheater = columns; columns = .detailOnly }
                else if let before = columnsBeforeTheater { columns = before; columnsBeforeTheater = nil }
            }
        }
        .onChange(of: layout) { _, new in
            withAnimation(.easeIn(duration: 0.12)) { articlesHidden = true } completion: {
                front = layout
                withAnimation(.easeOut(duration: 0.22)) { articlesHidden = false }
            }
            gridOpen = nil
            // Side by side, the hidden list must not keep a reader (or a playing video) open behind the grid.
            if sizeClass == .regular {
                if new == .grid { parkedSelection = selection; selection = nil } else { selection = parkedSelection }
            }
            ensureSelection()
        }
        .tint(Theme.icon)
        .sheet(isPresented: $addLink) { AddLinkSheet() }
        .confirmationDialog("Delete this article?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete article", role: .destructive) { if let article = toDelete { store.delete(article) }; toDelete = nil }
            Button("Cancel", role: .cancel) { toDelete = nil }
        }
        .onChange(of: articles.map(\.id)) { _, ids in if let selection, !ids.contains(selection) { self.selection = nil } }
    }

    private var split: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            list
                .navigationTitle(favoritesOnly ? "Favorites" : "Pocket Me")
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        } detail: {
            detail
        }
    }

    /// Two columns folded, more as the screen widens. A card is one Button, with no swipe or extra gestures;
    /// favorite and archive live in its long-press menu and at the end of the article.
    private var gridStack: some View {
        NavigationStack {
            ScrollView {
                filters
                if let error = store.errorMessage {
                    Text(error).font(Typo.meta).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.gutter)
                }
                Group {
                    if filtered.isEmpty {
                        if articles.isEmpty { EmptyStateView(paste: pasteOrAdd).frame(maxWidth: .infinity).padding(.top, 30) }
                        else { Text(search.isEmpty ? "No articles here yet" : "No matching articles").font(Typo.meta).foregroundStyle(Theme.muted).padding(.top, 40) }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: gridColumns), spacing: 10) {
                        ForEach(filtered, id: \.id) { article in
                            Button { gridOpen = article.id } label: { ArticleGridCard(article: article) }
                                .buttonStyle(GridCardButtonStyle())
                                .matchedTransitionSource(id: article.id, in: zoom)
                                .contextMenu { articleMenu(article) }
                        }
                    }.padding(.horizontal, Theme.gutter - 8).padding(.bottom, 24)
                }.opacity(articlesShown(.grid) ? 1 : 0)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .scrollIndicators(.hidden).background(Theme.paper)
            .onScrollPhaseChange { _, phase in store.listScrolling = phase != .idle }
            .navigationTitle(favoritesOnly ? "Favorites" : "Pocket Me")
            .modifier(LibrarySearch(enabled: !articles.isEmpty, text: $search, isPresented: searchPresented(in: .grid)))
            .toolbar { libraryToolbar(.grid) }
            .refreshable { store.refresh(); await store.drainInbox() }
            .overlay(alignment: .bottom) { ToastView(store: store) }
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.toast?.id)
            .navigationDestination(item: $gridOpen) { id in
                if let article = articles.first(where: { $0.id == id }) {
                    ReaderView(article: article).modifier(ZoomFromCard(id: id, namespace: zoom, enabled: !reduceMotion))
                }
            }
        }
    }
    private var gridColumns: Int { gridWidth < 600 ? 2 : gridWidth < 900 ? 3 : 4 }

    /// A lazy stack, not a `List`: a List guesses 44 pt for every row it has not built yet, so its scroll extent
    /// grew by hundreds of points as the last rows appeared and the end of the list popped. A lazy stack averages
    /// the rows it has measured, so the extent stays close to the truth from the first screen.
    private var list: some View {
        // One pass over the library for everything this list needs; each `filtered` is a walk of every article.
        let all = filtered
        let hero = sizeClass == .regular ? nil : inProgress(in: all)
        let items = hero == nil ? all : all.filter { $0.id != hero?.id }
        return ScrollView {
            VStack(spacing: 0) {
                filters.standIn(away: front != .list, id: "filters", heights: listHeights)
                if let error = store.errorMessage {
                    Text(error).font(Typo.meta).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.gutter)
                }
                if all.isEmpty {
                    Group {
                        if articles.isEmpty { EmptyStateView(paste: pasteOrAdd).frame(maxWidth: .infinity).padding(.top, 30) }
                        else { Text(search.isEmpty ? "No articles here yet" : "No matching articles").font(Typo.meta).foregroundStyle(Theme.muted).padding(.top, 40) }
                    }.opacity(articlesShown(.list) ? 1 : 0)
                } else {
                    if let hero {
                        ContinueReadingCard(article: hero, squish: reduceMotion ? 0 : heroSquish) { selection = hero.id }
                            .opacity(articlesShown(.list) ? 1 : 0)
                            .standIn(away: front != .list, id: "hero", heights: listHeights)
                            .padding(.horizontal, Theme.gutter).padding(.bottom, 22)
                    }
                    // Only the rows are lazy: with the filters and the hero card in the same stack their very different
                    // heights skewed the stack's estimate of the rows it had not built.
                    LazyVStack(spacing: 0) { ForEach(items, id: \.id) { article in
                        Button { selection = article.id } label: { ArticleRow(article: article).padding(.horizontal, Theme.gutter) }
                            .buttonStyle(RowPressStyle())
                            // Behind the swipe, so the row slides over one still surface instead of dragging a slab along.
                            .swipeReveal(id: article.id, open: $openSwipe, actions: swipeActions(for: article), inset: Theme.gutter, gap: 12, cornerRadius: Theme.radiusThumb, maxHeight: Theme.rowThumb, edge: 12)
                            .background(selection == article.id ? Theme.cardSelection : Theme.paper)
                            .opacity(articlesShown(.list) ? 1 : 0)
                            .contextMenu { articleMenu(article) }
                            .standIn(away: front != .list, id: article.id, heights: listHeights)
                            .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1).padding(.horizontal, Theme.gutter) }
                            .accessibilityAddTraits(selection == article.id ? [.isButton, .isSelected] : .isButton)
                            // The swipe has already played its closing spring, so the row is simply gone and the rows below ease up
                            // into the gap; a fade left it under them, overlapping, while they slid.
                            .transition(.identity)
                    } }
                }
            }
        }
        .background(Theme.paper).scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in store.listScrolling = phase != .idle }
        // Follows the finger only while the card is leaving; past it the value stops changing, so reading down sends no updates.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            return min(max(offset / 320, 0), 1)
        } action: { _, new in heroSquish = new }
        .modifier(LibrarySearch(enabled: !articles.isEmpty, text: $search, isPresented: searchPresented(in: .list)))
        .toolbar { libraryToolbar(.list) }
        // Side by side with a video in theater mode, the list dims as it slides away.
        .overlay { TheaterShade() }
        .refreshable { store.refresh(); await store.drainInbox() }
        .overlay(alignment: .bottom) { ToastView(store: store) }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: store.toast?.id)
    }

    /// The glass bar morphs its items between screens; the + draws its own coral disc with the shared glass hidden,
    /// so the system doesn't wrap a second circle around it as the bar re-forms on the way back from the reader.
    @ToolbarContentBuilder private func libraryToolbar(_ layer: LibraryLayout) -> some ToolbarContent {
        // `sharedBackgroundVisibility` only exists in the Swift 6.2 (Xcode 26) SDKs; CI's pinned Xcode 16.4 must not see it.
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            ToolbarItem(placement: .topBarLeading) { addButton(reachable(layer)) }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { addButton(reachable(layer)) }
        }
        if #available(iOS 26, macOS 26, *) {
            ToolbarItem(placement: .topBarTrailing) { trailingButtons(reachable(layer)) }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { trailingButtons(reachable(layer)) }
        }
        #else
        ToolbarItem(placement: .topBarLeading) { addButton(reachable(layer)) }
        ToolbarItem(placement: .topBarTrailing) { trailingButtons(reachable(layer)) }
        #endif
    }

    private func trailingButtons(_ reachable: Bool) -> some View { HStack(spacing: 8) { layoutButton(reachable); searchButton(reachable) } }
    @ViewBuilder private func layoutButton(_ reachable: Bool) -> some View {
        if !articles.isEmpty {
            Button { layout = layout.other } label: {
                // Both symbols stay put and crossfade; swapping one symbol made the toolbar re-form around it.
                ZStack {
                    ForEach([LibraryLayout.list, .grid], id: \.self) { mode in
                        Image(systemName: mode.toggleSymbol).opacity(layout == mode ? 1 : 0)
                    }
                }
                .font(.system(size: 18)).animation(.easeInOut(duration: 0.16), value: layout)
                .foregroundStyle(Theme.icon).frame(width: 44, height: 44)
                .background(Theme.paper, in: Circle()).overlay(Circle().strokeBorder(Theme.hairline))
            }
            .buttonStyle(.plain).barLabel(layout.toggleLabel, reachable: reachable)
        }
    }
    @ViewBuilder private func searchButton(_ reachable: Bool) -> some View {
        if !articles.isEmpty {
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 20))
                    .foregroundStyle(Theme.icon).frame(width: 44, height: 44)
                    .background(Theme.paper, in: Circle()).overlay(Circle().strokeBorder(Theme.hairline))
            }
            .buttonStyle(.plain).barLabel("Search", reachable: reachable)
        }
    }

    private func addButton(_ reachable: Bool) -> some View {
        Button { addLink = true } label: {
            Image(systemName: "plus").fontWeight(.bold).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(Theme.accent, in: Circle())
        }
        .buttonStyle(.plain).barLabel("Save a link", reachable: reachable)
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
        guard sizeClass == .regular, layout == .list else { return }
        if let selection, filtered.contains(where: { $0.id == selection }) { return }
        selection = (inProgress ?? filtered.first)?.id
    }
    /// The list's bar behind the grid keeps its buttons drawn, since removing them re-forms the glass bar on the way back,
    /// but they go unlabeled and hidden so VoiceOver finds one of each. The grid is only built while it is (nearly) in front.
    private func reachable(_ layer: LibraryLayout) -> Bool { layer == .grid || front == .list }
    private func articlesShown(_ layer: LibraryLayout) -> Bool { front == layer && !articlesHidden }
    /// Only the layout on screen shows the search field; the hidden one would steal its focus.
    private func searchPresented(in shown: LibraryLayout) -> Binding<Bool> {
        layout == shown ? $showSearch : .constant(false)
    }
    private func pasteOrAdd() { if let link = Clipboard.link { _ = store.saveLink(link) } else { addLink = true } }
    @ViewBuilder private func articleMenu(_ article: Article) -> some View {
        Button(article.isFavorite ? "Remove favorite" : "Favorite", systemImage: "bookmark") { store.favorite(article) }
        Button(article.archivedAt == nil ? "Archive" : "Unarchive", systemImage: "archivebox") { store.archive(article) }
        Button("Copy link", systemImage: "link") { Clipboard.copy(article.url) }
        Button("Delete", systemImage: "trash", role: .destructive) { toDelete = article }
    }
}

private extension View {
    /// The hidden layout stays built but takes no taps and says nothing to VoiceOver or UI tests.
    func layoutLayer(shown: Bool) -> some View {
        allowsHitTesting(shown).accessibilityHidden(!shown)
    }
    /// List cells live in their own UIKit hosts, out of the layer's reach, and still speak to VoiceOver when hidden.
    /// Behind the grid each row becomes an empty spacer of its own height, so the list keeps its scroll spot.
    func barLabel(_ label: String, reachable: Bool) -> some View {
        accessibilityLabel(reachable ? label : "").accessibilityHidden(!reachable)
    }
    func standIn(away: Bool, id: AnyHashable, heights: RowHeights) -> some View {
        modifier(StandIn(away: away, id: id, heights: heights))
    }
}

/// Plain storage, not state: rows note their heights as they lay out without redrawing the library.
private final class RowHeights {
    var values: [AnyHashable: CGFloat] = [:]
}

private struct StandIn: ViewModifier {
    let away: Bool
    let id: AnyHashable
    let heights: RowHeights
    func body(content: Content) -> some View {
        if away {
            Color.clear.frame(height: heights.values[id] ?? Theme.rowThumb)
        } else {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights.values[id] = $0 }
        }
    }
}

/// The reader grows out of the card it was opened from and shrinks back into it.
private struct ZoomFromCard: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.navigationTransition(.zoom(sourceID: id, in: namespace)) } else { content }
    }
}

/// An empty library has nothing to search, so the field only appears once there is something to find.
/// A row is a plain button; pressing it tints it the way a list row would.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Theme.cardSelection : Color.clear)
    }
}

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
