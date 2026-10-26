import SwiftData
import SwiftUI

struct ReaderView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ReaderPreferences.self) private var preferences
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Article.savedAt, order: .reverse) private var articles: [Article]
    let article: Article
    var close: (() -> Void)?
    @State private var progress: Double = 0
    @State private var lastSaved = Date.distantPast
    @State private var settings = false
    @State private var share = false
    private var next: Article? { articles.first { $0.id != article.id && $0.archivedAt == nil } }
    private var fileURL: URL? {
        guard store.processor?.offlineReady.contains(article.id) == true else { return nil }
        return store.processor?.assets.index(article.id)
    }
    private var config: String {
        let config = Configuration(theme: preferences.theme.rawValue, font: preferences.sans ? "sans" : "serif", size: preferences.size,
                                   progress: progress, favorite: article.isFavorite, archived: article.archivedAt != nil, nextTitle: next?.title,
                                   mac: isMac)
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
            header
            GeometryReader { geometry in
                Rectangle().fill(preferences.theme.ink.opacity(0.06))
                Rectangle().fill(Theme.accent).frame(width: geometry.size.width * progress)
            }.frame(height: 2)
            if article.status == .pending {
                VStack(spacing: 20) {
                    Text(article.title).font(Typo.sheetTitle)
                    Text("Getting your article ready…").font(Typo.meta).foregroundStyle(Theme.muted)
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
                ReaderWebView(article: article, fileURL: fileURL, configurationJSON: config, onMessage: message,
                              openLink: { openURL($0) }, saveLink: { _ = store.saveLink($0.absoluteString) })
            }
        }
        .foregroundStyle(preferences.theme.ink).background(preferences.theme.paper)
        .preferredColorScheme(preferences.theme == .dark ? .dark : preferences.theme == .light ? .light : nil)
        .sheet(isPresented: $settings) { ReaderSettingsSheet() }
        .sheet(isPresented: $share) {
            VStack(spacing: 20) {
                Text("Share article").font(Typo.sheetTitle)
                if let url = URL(string: article.url) { ShareLink(item: url).font(Typo.button).tint(Theme.ink) }
                Button("Done") { share = false }.buttonStyle(SecondaryButtonStyle())
            }.padding(24).background(Theme.surface).presentationDetents([.height(220)])
        }
        .onAppear {
            progress = min(max(article.readingProgress, 0), 1)
            article.lastOpenedAt = .now; store.persist()
            if article.status == .pending { store.processor?.start() }
        }
        .onDisappear { saveProgress(force: true) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { saveProgress(force: true) } }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .background(NavigationPopEnabler())
        #endif
    }

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
        }.padding(.horizontal, 12).frame(height: isMac ? 52 : 44).background(preferences.theme.paper)
    }
    @ViewBuilder private var backButton: some View {
        if isMac {
            Button(action: goBack) { Label("Unread", systemImage: "chevron.left") }
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
    private func goBack() { saveProgress(force: true); if let close { close() } else { dismiss() } }
    private func saveProgress(force: Bool = false) {
        guard article.modelContext != nil else { return }
        guard force || Date.now.timeIntervalSince(lastSaved) >= 2 else { return }
        article.readingProgress = min(max(progress, 0), 1)
        lastSaved = .now; store.persist()
    }
    private func message(_ action: String, _ value: Double?) {
        switch action {
        case "progress": if let value, value.isFinite { progress = min(max(value, 0), 1); saveProgress() }
        case "archive": store.archive(article); goBack()
        case "favorite": store.favorite(article)
        case "share": share = true
        case "next": if let next { saveProgress(force: true); store.requestedArticleID = next.id }
        case "back": goBack()
        case "smaller": preferences.resize(-1)
        case "larger": preferences.resize(1)
        default: break
        }
    }
    private struct Configuration: Codable {
        let theme: String; let font: String; let size: Double; let progress: Double
        let favorite: Bool; let archived: Bool; let nextTitle: String?; let mac: Bool
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { ReaderView(article: a).frame(width: 390, height: 844) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { ReaderView(article: a).frame(width: 390, height: 844) } }.preferredColorScheme(.dark) }
#endif
