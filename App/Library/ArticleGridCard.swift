import SwiftUI

/// A grid cell: the cover on top, the serif title and source under it. Purely visual; the grid wraps it in one
/// Button so a click or tap has exactly one place to go.
struct ArticleGridCard: View {
    let article: Article
    var selected = false
    var hovered = false
    var showsFavorite = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.aspectRatio(16 / 10, contentMode: .fit)
                .overlay { ArticleThumb(article: article, radius: Theme.radiusThumb) }
                .overlay { RoundedRectangle(cornerRadius: Theme.radiusThumb, style: .continuous).strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 0.5) }
                .overlay(alignment: .topTrailing) {
                    if showsFavorite && article.isFavorite {
                        Image(systemName: "bookmark.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(Theme.swipeFavorite, in: Circle())
                            .padding(8).transition(.opacity)
                    }
                }
                .overlay(alignment: .bottom) { progress }
                .shadow(color: Theme.ink.opacity(hovered ? 0.14 : 0), radius: 10, y: 4)
                .scaleEffect(hovered ? 1.015 : 1)
            VStack(alignment: .leading, spacing: 5) {
                if article.title != article.siteName {
                    Text(article.title).font(Typo.cardTitleSerif).foregroundStyle(Theme.ink)
                        .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
                }
                ArticleMetaView(article: article, emphasizeSite: article.title == article.siteName)
            }.padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(8)
        .background(selected ? Theme.cardSelection : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { if selected { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.ink.opacity(0.14), lineWidth: 1) } }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: hovered)
        .animation(.easeOut(duration: 0.18), value: article.isFavorite)
    }
    /// An article left part-way shows how far along it is, in place of the list's continue card.
    @ViewBuilder private var progress: some View {
        if article.archivedAt == nil, article.readingProgress > 0.02, article.readingProgress < 0.95 {
            GeometryReader { geometry in
                Capsule().fill(Theme.paper.opacity(0.85))
                Capsule().fill(Theme.accent).frame(width: geometry.size.width * article.readingProgress)
            }.frame(height: 4).padding(10)
        }
    }
}

/// Pressing sinks the card a touch; the card draws everything else itself.
struct GridCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { ArticleGridCard(article: a).padding(20).frame(width: 300) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { ArticleGridCard(article: a, selected: true).padding(20).frame(width: 300) } }.preferredColorScheme(.dark) }
#endif
