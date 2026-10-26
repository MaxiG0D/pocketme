import SwiftUI

struct PreviewPane: View {
    @Environment(LibraryStore.self) private var store
    let article: Article?
    let open: () -> Void
    var body: some View {
        ScrollView {
            if let article {
                VStack(alignment: .leading, spacing: 18) {
                    ArticleThumb(article: article, contentMode: .fit, radius: 14).aspectRatio(1.6, contentMode: .fit)
                    Text("\(article.siteName) · \(article.readingMinutes) min").kicker()
                    Text(article.title).font(Typo.serif(28)).foregroundStyle(Theme.ink)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    if let excerpt = article.excerpt {
                        Text(excerpt).font(.custom("Newsreader16pt-Regular", size: 17, relativeTo: .body))
                            .lineSpacing(5).foregroundStyle(Theme.previewBody).lineLimit(6)
                    }
                    HStack(spacing: 10) {
                        Button("Open reader", action: open).buttonStyle(PrimaryButtonStyle())
                        Button { store.archive(article) } label: { Image(systemName: "archivebox") }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel(article.archivedAt == nil ? "Archive" : "Unarchive")
                        Button { store.favorite(article) } label: { Image(systemName: article.isFavorite ? "bookmark.fill" : "bookmark") }.buttonStyle(CircleIconButtonStyle()).accessibilityLabel("Toggle favorite")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 32).padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    Text("Room for a good read").font(Typo.sheetTitle).foregroundStyle(Theme.ink)
                    Text("Select an article to take a closer look.").font(Typo.meta).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity).padding(.horizontal, 32).padding(.top, 80)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.surface)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in PreviewPane(article: articles.first, open: {}).frame(width: 400, height: 800) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in PreviewPane(article: articles.first, open: {}).frame(width: 400, height: 800) }.preferredColorScheme(.dark) }
#endif
