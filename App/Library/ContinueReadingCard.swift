import SwiftUI

struct ContinueReadingCard: View {
    let article: Article
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                ArticleThumb(article: article, height: 196, radius: Theme.radiusHero)
                    .overlay { RoundedRectangle(cornerRadius: Theme.radiusHero, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1) }
                    .shadow(color: Theme.ink.opacity(0.12), radius: 14, y: 6)
                    .overlay(alignment: .bottomLeading) {
                        Text("Continue · \(max(1, Int((Double(article.readingMinutes) * (1 - article.readingProgress)).rounded(.up)))) min left")
                            .font(Typo.kicker).foregroundStyle(Theme.coverChipInk)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Theme.coverChip.opacity(0.92), in: Capsule()).padding(12)
                    }
                Text("\(article.siteName) · \(article.readingMinutes) min").kicker()
                Text(article.title).font(Typo.heroTitle).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                GeometryReader { geometry in
                    Capsule().fill(Theme.progressTrack)
                    Capsule().fill(Theme.accent).frame(width: geometry.size.width * min(max(article.readingProgress, 0), 1))
                }.frame(height: 4)
            }
        }.buttonStyle(.plain)
            .scrollTransition(axis: .vertical) { content, phase in
                let leaving = reduceMotion ? 0 : min(phase.value, 0)
                return content
                    .scaleEffect(x: 1 + 0.08 * leaving, y: 1 + 0.35 * leaving, anchor: .bottom)
                    .opacity(1 + 0.9 * leaving)
            }
            .accessibilityLabel("Continue reading \(article.title)")
            .accessibilityValue("\(Int((min(max(article.readingProgress, 0), 1) * 100).rounded())) percent read")
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { ContinueReadingCard(article: a, open: {}).padding(20).frame(width: 390) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { ContinueReadingCard(article: a, open: {}).padding(20).frame(width: 390) } }.preferredColorScheme(.dark) }
#endif
