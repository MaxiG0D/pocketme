#if DEBUG
import SwiftData
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum SampleData {
    static func container() throws -> ModelContainer {
        let container = try AppPersistence.inMemory()
        let sites = ["Slowmag", "Build Weekly", "Kitchen Notes", "Wayfarer", "Green Room", "Slowmag", "Wayfarer", "Build Weekly"]
        let titles = ["The quiet return of reading things all the way through", "Why small software tends to last",
                      "A slow Sunday in the kitchen", "The long way home", "Growing a little green space",
                      "A very long article title about the small everyday rituals that help us find time to read again",
                      "Somewhere new", "A better kind of weekend"]
        for index in sites.indices {
            let article = Article(url: "https://example.com/sample/\(index)", normalizedURL: "https://example.com/sample/\(index)",
                                  title: titles[index], siteName: sites[index], savedAt: .now.addingTimeInterval(Double(-index * 3600)))
            article.readingMinutes = 6 + index
            article.wordCount = article.readingMinutes * 230
            article.excerpt = "A thoughtful story about making room for the things that matter."
            article.status = index == 2 ? .pending : index == 3 ? .failed : .ready
            if index == 3 { article.failureReason = "The page could not be loaded." }
            if index == 0 { article.readingProgress = 0.4; article.lastOpenedAt = .now }
            if index == 4 { article.archivedAt = .now }
            article.isFavorite = index == 1 || index == 4
            if index == 0 || index == 1 { article.thumbnailData = thumbnail(siteName: sites[index]) }
            container.mainContext.insert(article)
        }
        // Last and oldest, so the order of the other rows (and the tests that tap them) stays put.
        let video = Article(url: "https://www.youtube.com/watch?v=aqz-KE-bpKQ", normalizedURL: "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                            title: "A short film about slow mornings", siteName: "YouTube", savedAt: .now.addingTimeInterval(-9 * 3600))
        video.status = .ready
        video.contentHTML = Data("<p></p>".utf8)
        container.mainContext.insert(video)
        try container.mainContext.save()
        return container
    }

    private static func thumbnail(siteName: String) -> Data? {
        let renderer = ImageRenderer(content: GeneratedCoverView(siteName: siteName).frame(width: 600, height: 375))
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif
