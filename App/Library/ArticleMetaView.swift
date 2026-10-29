import SwiftUI

struct ArticleMetaView: View {
    @Environment(LibraryStore.self) private var store
    let article: Article
    /// Promotes the site to a title when the article has no title of its own.
    var emphasizeSite = false
    var body: some View {
        // This article's own flags: another article starting or finishing a download does not redraw this row.
        let offline = store.processor?.state(for: article.id)
        VStack(alignment: .leading, spacing: 5) {
            Text(article.readingMinutes > 0 ? "\(article.siteName) · \(article.readingMinutes) min" : article.siteName)
                .font(emphasizeSite ? Typo.sans(15).weight(.semibold) : Typo.meta).foregroundStyle(emphasizeSite ? Theme.ink : Theme.muted)
            if article.status == .failed {
                HStack(spacing: 0) {
                    Text("Couldn’t load · ").foregroundStyle(Theme.muted)
                    Button("Retry") { store.retry(article) }.buttonStyle(.plain).underline().foregroundStyle(Theme.ink)
                        .padding(.vertical, 12).contentShape(Rectangle()).padding(.vertical, -12)
                }.font(Typo.meta)
            } else if article.status == .pending || offline?.downloading == true || offline?.missing == true {
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
