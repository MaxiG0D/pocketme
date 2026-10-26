import SwiftUI

struct ArticleThumb: View {
    let article: Article
    var width: CGFloat?
    var height: CGFloat?
    var contentMode: ContentMode = .fill
    var radius: CGFloat = Theme.radiusThumb
    var body: some View {
        // The image is decoration inside a layout-owned rectangle. Its intrinsic
        // aspect ratio must never enlarge a grid cell or a split-view column.
        Theme.chip.overlay { image }
            .frame(width: width, height: height)
            .clipped().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .animation(.easeInOut(duration: 0.2), value: article.thumbnailData)
            .accessibilityHidden(true)
    }
    @ViewBuilder private var image: some View {
        #if os(iOS)
        if let data = article.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else { GeneratedCoverView(siteName: article.siteName) }
        #else
        if let data = article.thumbnailData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else { GeneratedCoverView(siteName: article.siteName) }
        #endif
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { ArticleThumb(article: a, width: 76, height: 76) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { ArticleThumb(article: a, width: 76, height: 76) } }.preferredColorScheme(.dark) }
#endif
