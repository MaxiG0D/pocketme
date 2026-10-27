import SwiftData
import SwiftUI

struct ReaderView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ReaderPreferences.self) private var preferences
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    let article: Article
    var backTitle = "Unread"
    /// Set when the reader sits beside the Mac library list: the back button becomes a list toggle.
    var toggleList: (() -> Void)?
    var clearsTrafficLights = false
    var close: (() -> Void)?
    @State private var progress: Double = 0
    @State private var lastSaved = Date.distantPast
    @State private var settings = false
    private var video: VideoLink? { VideoLink(article.url) }
    private var next: Article? { articles.first { $0.id != article.id && $0.archivedAt == nil } }
    private var fileURL: URL? {
        guard store.processor?.offlineReady.contains(article.id) == true else { return nil }
        return store.processor?.assets.index(article.id)
    }
    private var config: String {
        let config = Configuration(theme: preferences.theme.rawValue, font: preferences.sans ? "sans" : "serif", size: preferences.size,
                                   progress: progress, favorite: article.isFavorite, archived: article.archivedAt != nil, mac: isMac)
        return (try? JSONEncoder().encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            header
            #endif
            GeometryReader { geometry in
                Rectangle().fill(preferences.theme.ink.opacity(0.06))
                Rectangle().fill(Theme.accent).frame(width: geometry.size.width * progress)
            }.frame(height: 2)
            if article.status == .pending {
                VStack(spacing: 20) {
                    Text(article.title).font(Typo.sheetTitle)
                    ProgressView().accessibilityLabel("Getting your article ready")
                    originalButton
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if article.status == .ready && article.contentHTML == nil {
                VStack(spacing: 20) {
                    Text(article.title).font(Typo.sheetTitle)
                    Text("This link opens in your browser.").font(Typo.meta).foregroundStyle(Theme.muted)
                    originalButton
                    Button(article.archivedAt == nil ? "Archive" : "Unarchive") { store.archive(article); goBack() }.buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 300)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if article.status == .failed {
                    HStack(spacing: 12) {
                        Text("The clean article isn’t available yet.").font(Typo.meta).foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Open original") { if let url = URL(string: article.url) { openURL(url) } }.font(Typo.button).buttonStyle(.plain)
                        Button("Retry") { store.retry(article) }.font(Typo.button).buttonStyle(.plain)
                    }.padding(14).background(Theme.chip)
                }
                if let video {
                    VideoPlayerView(article: article, video: video).id(article.id)
                        .frame(maxWidth: isMac ? 760 : 600).padding(.horizontal, isMac ? 26 : 16).padding(.top, isMac ? 8 : 12)
                }
                if video == nil || article.contentHTML != nil {
                    ReaderWebView(article: article, fileURL: fileURL, configurationJSON: config, next: next, onMessage: message,
                                  openLink: { openURL($0) }, saveLink: { _ = store.saveLink($0.absoluteString) }, reduceMotion: reduceMotion)
                } else { Spacer() }
            }
        }
        .foregroundStyle(preferences.theme.ink).background(preferences.theme.paper)
        .preferredColorScheme(preferences.theme == .dark ? .dark : preferences.theme == .light ? .light : nil)
        .sheet(isPresented: $settings) { ReaderSettingsSheet() }
        .onAppear { open(article) }
        // The reader stays put when another article is picked beside it, so the page can fade across.
        .onChange(of: article) { old, new in saveProgress(old, force: true); open(new) }
        .onDisappear { saveProgress(force: true) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { saveProgress(force: true) } }
        #if os(macOS)
        // The window has a hidden title bar; the header shares its row with the traffic lights.
        .ignoresSafeArea(.container, edges: .top)
        #endif
        #if os(iOS)
        // The system bar keeps Back first and moves to the side on the iPhone Duo outer display.
        .toolbar(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(preferences.theme.paper, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarColorScheme(barScheme, for: .navigationBar)
        .tint(preferences.theme.ink)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Reader settings", systemImage: "textformat.size") { settings = true }
                if let url = URL(string: article.url) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private var barScheme: ColorScheme? {
        switch preferences.theme { case .dark: .dark; case .light, .sepia: .light; case .auto: nil }
    }
    #endif

    private var header: some View {
        HStack(spacing: 0) {
            backButton
            Spacer()
            if isMac { Text(article.title).font(Typo.sans(13).weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(1); Spacer() }
            Button { settings = true } label: { Text("Aa").font(Typo.serif(17)) }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Reader settings")
            if isMac { Button { store.favorite(article) } label: { Image(systemName: article.isFavorite ? "bookmark.fill" : "bookmark") }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Toggle favorite") }
            if let url = URL(string: article.url) {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Share article")
            }
        }.padding(.horizontal, 12).padding(.leading, isMac && (toggleList == nil || clearsTrafficLights) ? 76 : 0).frame(height: isMac ? 52 : 44).background(preferences.theme.paper)
    }
    @ViewBuilder private var backButton: some View {
        if let toggleList {
            Button(action: toggleList) { Image(systemName: "sidebar.left") }
                .buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Toggle article list")
        } else if isMac {
            Button(action: goBack) { Label(backTitle, systemImage: "chevron.left") }
                .buttonStyle(.plain).font(Typo.sans(13).weight(.medium)).frame(minHeight: 44)
                .accessibilityLabel("Back to library")
        } else {
            Button(action: goBack) { Image(systemName: "chevron.left") }
                .buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Back to library")
        }
    }
    private var originalButton: some View {
        Button("Open original") { if let url = URL(string: article.url) { openURL(url) } }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 300)
    }
    private func goBack() {
        saveProgress(force: true)
        if let close { close() } else if toggleList == nil { dismiss() }
    }
    private func open(_ article: Article) {
        progress = min(max(article.readingProgress, 0), 1)
        article.lastOpenedAt = .now; store.persist()
        if article.status == .pending { store.processor?.start() }
    }
    private func saveProgress(_ target: Article? = nil, force: Bool = false) {
        let target = target ?? article
        guard target.modelContext != nil else { return }
        guard force || Date.now.timeIntervalSince(lastSaved) >= 2 else { return }
        target.readingProgress = min(max(progress, 0), 1)
        lastSaved = .now; store.persist()
    }
    private func message(_ action: String, _ value: Double?) {
        switch action {
        case "progress": if let value, value.isFinite { progress = min(max(value, 0), 1); saveProgress() }
        case "archive": store.archive(article); goBack()
        case "favorite": store.favorite(article)
        case "share": if let url = URL(string: article.url) { SharePresenter.share(url) }
        case "next": if let next { saveProgress(force: true); store.requestedArticleID = next.id }
        case "back": goBack()
        case "smaller": preferences.resize(-1)
        case "larger": preferences.resize(1)
        default: break
        }
    }
    private struct Configuration: Codable {
        let theme: String; let font: String; let size: Double; let progress: Double
        let favorite: Bool; let archived: Bool; let mac: Bool
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { ReaderView(article: a).frame(width: 390, height: 844) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { ReaderView(article: a).frame(width: 390, height: 844) } }.preferredColorScheme(.dark) }
#endif
