import SwiftData
import SwiftUI

/// Latest scroll position. Deliberately not observable: the page draws its own bar, so a scroll never redraws the reader.
@MainActor final class ReadingProgress {
    var value: Double = 0
}

struct ReaderView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ReaderPreferences.self) private var preferences
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    let article: Article
    var backTitle = "Unread"
    /// Set when the reader sits beside the Mac library list, whose own toggle stands in for a back button.
    var besideList = false
    var clearsTrafficLights = false
    var close: (() -> Void)?
    @State private var progress = ReadingProgress()
    /// Where the page should open; the live position is not part of the page configuration.
    @State private var startProgress: Double = 0
    @State private var saveTask: Task<Void, Never>?
    @State private var settings = false
    @State private var videoPlaying = false
    private var video: VideoLink? { VideoLink(article.url) }
    private var theater: Bool { store.theater && video != nil }
    private var next: Article? { articles.first { $0.id != article.id && $0.archivedAt == nil } }
    private var fileURL: URL? {
        guard store.processor?.offlineReady.contains(article.id) == true else { return nil }
        return store.processor?.assets.index(article.id)
    }
    private var config: String {
        let config = Configuration(theme: preferences.theme.rawValue, font: preferences.sans ? "sans" : "serif", size: preferences.size,
                                   progress: startProgress, favorite: article.isFavorite, archived: article.archivedAt != nil, mac: isMac)
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
            // In theater mode the header steps aside, so the video centers in the whole window.
            if !theater { header.transition(.opacity) }
            #endif
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
                if article.status == .failed && video == nil {
                    HStack(spacing: 12) {
                        Text("The clean article isn’t available yet.").font(Typo.meta).foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Open original") { if let url = URL(string: article.url) { openURL(url) } }.font(Typo.button).buttonStyle(.plain)
                        Button("Retry") { store.retry(article) }.font(Typo.button).buttonStyle(.plain)
                    }.padding(14).background(Theme.chip)
                }
                if let video { videoPage(video) } else {
                    ReaderWebView(article: article, fileURL: fileURL, configurationJSON: config, next: next, onMessage: message,
                                  openLink: { openURL($0) }, saveLink: { _ = store.saveLink($0.absoluteString) }, reduceMotion: reduceMotion)
                }
            }
        }
        .foregroundStyle(preferences.theme.ink).background(preferences.theme.paper)
        .preferredColorScheme(preferences.theme == .dark ? .dark : preferences.theme == .light ? .light : nil)
        .sheet(isPresented: $settings) { ReaderSettingsSheet() }
        .onAppear { open(article) }
        // The reader stays put when another article is picked beside it, so the page can fade across.
        .onChange(of: article) { old, new in saveProgress(old, force: true); open(new) }
        .onDisappear { saveProgress(force: true); store.setTheater(false) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { saveProgress(force: true) } }
        #if os(macOS)
        // The window has a hidden title bar; the header shares its row with the traffic lights.
        .ignoresSafeArea(.container, edges: .top)
        #endif
        #if os(iOS)
        // The system bar keeps Back first and moves to the side on the iPhone Duo outer display.
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(preferences.theme.paper, for: .navigationBar)
        // Softened so the bar glyphs sit gently on every reader paper.
        .tint(preferences.theme.ink.opacity(0.6))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if video == nil { Button("Reader settings", systemImage: "textformat.size") { settings = true } }
                else { Button("Theater mode", systemImage: "popcorn", action: enterTheater) }
                if let url = URL(string: article.url) {
                    Button("Open in Browser", systemImage: "safari") { openURL(url) }.keyboardShortcut("o", modifiers: [])
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .toolbar(theater && sizeClass != .regular ? .hidden : .automatic, for: .navigationBar)
        .toolbar(theater && sizeClass != .regular ? .hidden : .automatic, for: .tabBar)
        // On a wide screen these leave the bars a little low when the lights return, and the status bar stays there anyway.
        .statusBarHidden(theater && sizeClass != .regular)
        .persistentSystemOverlays(theater && sizeClass != .regular ? .hidden : .automatic)
        .sensoryFeedback(.impact(weight: .light), trigger: theater)
        #endif
    }

    private var header: some View {
        HStack(spacing: 0) {
            backButton
            Spacer()
            if isMac { Text(article.title).font(Typo.sans(13).weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(1); Spacer() }
            if video == nil { Button { settings = true } label: { Text("Aa").font(Typo.serif(17)) }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Reader settings") }
            else { Button(action: enterTheater) { Image(systemName: "popcorn") }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Theater mode").help("Theater mode (T)").keyboardShortcut("t", modifiers: []) }
            if isMac { Button { store.favorite(article) } label: { Image(systemName: article.isFavorite ? "bookmark.fill" : "bookmark") }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Toggle favorite") }
            if let url = URL(string: article.url) {
                Button { openURL(url) } label: { Image(systemName: "safari") }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Open in Browser").keyboardShortcut("o", modifiers: [])
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Share article")
            }
        // On the Mac the row is as tall as the compact title bar, so its icons share the window buttons' center line.
        }.padding(.horizontal, 12).padding(.leading, !isMac ? 0 : !besideList ? 72 : clearsTrafficLights ? 118 : 0).frame(height: isMac ? 40 : 44).background(preferences.theme.paper)
    }
    @ViewBuilder private var backButton: some View {
        if besideList { EmptyView() } else if isMac {
            Button(action: goBack) { Label(backTitle, systemImage: "chevron.left") }
                .buttonStyle(.plain).font(Typo.sans(13).weight(.medium)).frame(minHeight: 44)
                .accessibilityLabel("Back to library")
        } else {
            Button(action: goBack) { Image(systemName: "chevron.left") }
                .buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Back to library")
        }
    }
    /// Videos get only the player and their title, centered; there is nothing to read or scroll.
    /// Playing one dims the lights: the title fades and the player grows into the middle of the dark.
    private func videoPage(_ video: VideoLink) -> some View {
        GeometryReader { stage in
            // The reader sits flush right, so the window's center is half its left inset away; the player centers there.
            let inset = stage.frame(in: .global).minX
            let screen = CGSize(width: stage.size.width + inset, height: stage.size.height)
            VStack(spacing: 20) {
                VideoPlayerView(article: article, video: video, playing: $videoPlaying, play: { if preferences.theaterOnPlay { store.setTheater(true, reduceMotion: reduceMotion) } })
                    .frame(width: theater ? Theater.videoWidth(in: screen, mac: isMac) : nil)
                    .id(article.id)
                if !theater {
                    Text(article.title).font(isMac ? Typo.serif(26) : Typo.cardTitleSerif).multilineTextAlignment(.center)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: theater ? .infinity : (isMac ? 860 : 640)).padding(.horizontal, theater ? 0 : (isMac ? 40 : 16))
            .frame(width: stage.size.width, height: stage.size.height)
            .offset(x: theater ? -inset / 2 : 0)
        }
        // On a phone the bars are gone, so the player centers on the whole screen, not the space between the insets.
        .ignoresSafeArea(.container, edges: theater ? .all : [])
        .background {
            Theater.shade.opacity(theater ? 1 : 0).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture { store.setTheater(false, reduceMotion: reduceMotion) }
                .allowsHitTesting(theater).accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if theater {
                Button { store.setTheater(false, reduceMotion: reduceMotion) } label: {
                    Image(systemName: "popcorn.fill").font(.system(size: isMac ? 13 : 15, weight: .medium)).foregroundStyle(Theater.ink.opacity(0.75))
                        .frame(width: isMac ? 30 : 36, height: isMac ? 30 : 36).background(Theater.ink.opacity(0.08), in: Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Leave theater mode").keyboardShortcut(.cancelAction)
                .padding(.top, isMac ? 0 : 8).padding(.trailing, 12).transition(.opacity)
            }
        }
    }
    private func enterTheater() {
        videoPlaying = true
        store.setTheater(true, reduceMotion: reduceMotion)
    }
    private var originalButton: some View {
        Button("Open original") { if let url = URL(string: article.url) { openURL(url) } }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 300)
    }
    private func goBack() {
        saveProgress(force: true)
        if let close { close() } else if !besideList { dismiss() }
    }
    private func open(_ article: Article) {
        videoPlaying = false
        store.setTheater(false, reduceMotion: reduceMotion)
        saveTask?.cancel()
        startProgress = min(max(article.readingProgress, 0), 1)
        progress.value = startProgress
        article.lastOpenedAt = .now; store.persist()
        if article.status == .pending { store.processor?.start() }
    }
    private func saveProgress(_ target: Article? = nil, force: Bool = false) {
        let target = target ?? article
        guard target.modelContext != nil else { return }
        saveTask?.cancel()
        target.readingProgress = min(max(progress.value, 0), 1)
        store.persist()
    }
    /// Saves a moment after scrolling stops rather than writing to the store mid-scroll.
    private func saveSoon() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveProgress(force: true)
        }
    }
    private func message(_ action: String, _ value: Double?) {
        switch action {
        case "progress": if let value, value.isFinite { progress.value = min(max(value, 0), 1); saveSoon() }
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
