import Foundation
import Testing
@testable import PocketMe

private final class FixtureBundle: NSObject {}

@MainActor
struct ExtractionTests {
    @Test func extractsAndSanitizesARealDOM() async throws {
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "article", withExtension: "html"))
        let result = try await ExtractionService().extract(url: url)
        #expect(result.title == "A quiet afternoon")
        #expect(result.siteName == "Slowmag")
        #expect(result.author == "Alex Reader")
        #expect(result.wordCount == 242)
        let content = try #require(result.content)
        #expect(!content.contains("<script"))
        #expect(!content.contains("<iframe"))
        #expect(!content.contains("onclick"))
        #expect(!content.contains("onerror"))
        #expect(!content.contains("javascript:"))
        #expect(!content.contains("style="))
        #expect(result.readingMinutes == 1)
    }
    @Test func findsAlternateMetadataAndLazyResponsiveImages() async throws {
        let fixture = try #require(Bundle(for: FixtureBundle.self).url(forResource: "article", withExtension: "html"))
        let html = try String(contentsOf: fixture, encoding: .utf8)
            .replacingOccurrences(of: "<head>", with: "<head><base href='https://example.com/story/'><meta property='og:image' content='javascript:bad'><meta property='twitter:image' content='/preview.jpg'>")
            .replacingOccurrences(of: "<img src=\"missing.png\" width=\"400\" height=\"400\" onerror=\"window.bad=true\">", with: "<img src='data:image/gif;base64,AA' data-src='/lazy.jpg'><img src='/small.jpg' srcset='/medium.jpg 400w, /large.jpg 1200w'>")
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "article.html")
        try html.write(to: url, atomically: true, encoding: .utf8)
        let result = try await ExtractionService().extract(url: url)
        #expect(result.leadImageURL == "https://example.com/preview.jpg")
        #expect(result.imageCandidates?.contains("https://example.com/lazy.jpg") == true)
        #expect(result.imageCandidates?.contains("https://example.com/large.jpg") == true)
        #expect(result.content?.contains("https://example.com/lazy.jpg") == true)
        #expect(result.content?.contains("https://example.com/large.jpg") == true)
        #expect(result.content?.contains("srcset=") == false)
    }

}

struct LeadImageDuplicateTests {
    @Test func recognizesTheLeadPhotoAtAnotherCrop() {
        let body = "<figure><img src=\"https://images.lpcdn.ca/924x615/202610/27/5001234-carney.jpg\"><figcaption>Caption</figcaption></figure><p>Text</p>"
        #expect(ReaderDocument.leadRepeats(in: body, lead: "https://images.lpcdn.ca/1200x630/202610/27/5001234-carney.jpg?v=2"))
        let sized = "<p><img src='https://example.com/a/photo-1020x680.jpg'></p>"
        #expect(ReaderDocument.leadRepeats(in: sized, lead: "https://example.com/a/photo.jpg"))
    }
    @Test func keepsADifferentPhoto() {
        let body = "<p><img src=\"https://example.com/a/other.jpg\"></p>"
        #expect(!ReaderDocument.leadRepeats(in: body, lead: "https://example.com/a/photo.jpg"))
        #expect(!ReaderDocument.leadRepeats(in: "<p>No images</p>", lead: "https://example.com/a/photo.jpg"))
    }
}
