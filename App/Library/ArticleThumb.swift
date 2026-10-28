import SwiftUI

#if os(iOS)
private typealias ThumbImage = UIImage
#else
private typealias ThumbImage = NSImage
#endif

/// Decoded thumbnails by article, so scrolling a row back into view never decodes (or reads its stored data) on the main thread.
@MainActor private enum ThumbCache {
    final class Entry { let size: Int; let image: ThumbImage; init(_ size: Int, _ image: ThumbImage) { self.size = size; self.image = image } }
    static let images = NSCache<NSString, Entry>()
    static func key(_ id: UUID) -> NSString { id.uuidString as NSString }
}

struct ArticleThumb: View {
    let article: Article
    var width: CGFloat?
    var height: CGFloat?
    var contentMode: ContentMode = .fill
    var radius: CGFloat = Theme.radiusThumb
    @State private var decoded: ThumbImage?
    private var shown: ThumbImage? { decoded ?? ThumbCache.images.object(forKey: ThumbCache.key(article.id))?.image }
    var body: some View {
        // The image is decoration inside a layout-owned rectangle. Its intrinsic
        // aspect ratio must never enlarge a grid cell or a split-view column.
        Theme.chip.overlay { image }
            .frame(width: width, height: height)
            .clipped().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            // Clipping hides a filled image's overflow but not its hit area, which would swallow clicks meant for the next row.
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .task(id: article.thumbnailData?.count) { await load() }
            .accessibilityHidden(true)
    }
    @ViewBuilder private var image: some View {
        if let shown {
            #if os(iOS)
            Image(uiImage: shown).resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
            #else
            Image(nsImage: shown).resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
            #endif
        } else { GeneratedCoverView(siteName: article.siteName) }
    }
    private func load() async {
        let id = article.id
        guard let data = article.thumbnailData else {
            ThumbCache.images.removeObject(forKey: ThumbCache.key(id)); decoded = nil; return
        }
        if let hit = ThumbCache.images.object(forKey: ThumbCache.key(id)), hit.size == data.count { decoded = hit.image; return }
        let image = await Task.detached(priority: .userInitiated) { () -> ThumbImage? in
            #if os(iOS)
            return UIImage(data: data)?.preparingForDisplay()
            #else
            return NSImage(data: data)
            #endif
        }.value
        guard let image, !Task.isCancelled else { return }
        ThumbCache.images.setObject(ThumbCache.Entry(data.count, image), forKey: ThumbCache.key(id))
        withAnimation(.easeInOut(duration: 0.2)) { decoded = image }
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { ArticleThumb(article: a, width: 76, height: 76) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { ArticleThumb(article: a, width: 76, height: 76) } }.preferredColorScheme(.dark) }
#endif
