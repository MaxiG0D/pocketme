import SwiftUI

struct ArticleCard: View {
    let article: Article
    var selected = false
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArticleThumb(article: article).aspectRatio(1.6, contentMode: .fit)
            Text(article.title).font(Typo.sans(15).weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            ArticleMetaView(article: article)
            Spacer(minLength: 0)
        }
        .padding(8).background(Theme.cardSelection.opacity(selected ? 1 : hover ? 0.5 : 0), in: RoundedRectangle(cornerRadius: 16))
        .padding(-8).contentShape(Rectangle()).onHover { hover = $0 }
        .accessibilityElement(children: .combine).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { ArticleCard(article: a).frame(width: 240) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { ArticleCard(article: a).frame(width: 240) } }.preferredColorScheme(.dark) }
#endif
