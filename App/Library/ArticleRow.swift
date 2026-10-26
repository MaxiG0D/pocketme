import SwiftUI

struct ArticleRow: View {
    let article: Article
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(article.title).font(Typo.rowTitle).foregroundStyle(Theme.ink)
                    .lineLimit(3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                ArticleMetaView(article: article)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ArticleThumb(article: article, width: Theme.rowThumb, height: Theme.rowThumb)
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { ArticleRow(article: a).padding(20).frame(width: 390) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { ArticleRow(article: a).padding(20).frame(width: 390) } }.preferredColorScheme(.dark) }
#endif
