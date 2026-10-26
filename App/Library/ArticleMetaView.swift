import SwiftUI

struct ArticleMetaView: View {
    @Environment(LibraryStore.self) private var store
    let article: Article
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(article.readingMinutes > 0 ? "\(article.siteName) · \(article.readingMinutes) min" : article.siteName)
                .font(Typo.meta).foregroundStyle(Theme.muted)
            if article.status == .failed {
                HStack(spacing: 0) {
                    Text("Couldn’t load · ").foregroundStyle(Theme.muted)
                    Button("Retry") { store.retry(article) }.buttonStyle(.plain).underline().foregroundStyle(Theme.ink)
                }.font(Typo.meta)
            } else if article.status == .pending || store.processor?.downloading.contains(article.id) == true ||
                        (article.contentHTML != nil && store.processor != nil && store.processor?.offlineReady.contains(article.id) != true) {
                HStack(spacing: 5) {
                    Circle().fill(Theme.pendingDot).frame(width: 6, height: 6)
                    Text("Downloading").font(Typo.meta).foregroundStyle(Theme.pending)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { ArticleMetaView(article: a) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { ArticleMetaView(article: a) } }.preferredColorScheme(.dark) }
#endif
