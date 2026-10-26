#if DEBUG && os(macOS)
import Foundation
import SwiftData
import Testing
@testable import PocketMe

@MainActor
struct DeveloperImportTests {
    @Test func preservesDatesArchiveAndExistingReadingState() throws {
        let container = try AppPersistence.inMemory()
        let context = container.mainContext
        let existing = try ArticleRepository(context: context).save(url: "https://example.com/existing")
        existing.isFavorite = true
        existing.readingProgress = 0.5
        existing.archivedAt = Date(timeIntervalSince1970: 200)
        let entries = [
            DeveloperImport.Entry(url: "https://www.example.com/unread?utm_source=export", title: "Unread", savedAt: 100, archived: false),
            DeveloperImport.Entry(url: "https://example.com/archive", title: "Archive", savedAt: 50, archived: true),
            DeveloperImport.Entry(url: "https://example.com/existing", title: "Replacement", savedAt: 10, archived: false)
        ]
        #expect(try DeveloperImport.apply(entries, context: context) == 2)
        #expect(try DeveloperImport.apply(entries, context: context) == 0)
        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(articles.count == 3)
        let unread = try #require(articles.first { $0.title == "Unread" })
        #expect(unread.savedAt == Date(timeIntervalSince1970: 100))
        #expect(unread.archivedAt == nil)
        #expect(unread.normalizedURL == "https://example.com/unread")
        let archive = try #require(articles.first { $0.title == "Archive" })
        #expect(archive.archivedAt == Date(timeIntervalSince1970: 50))
        #expect(archive.status == .pending)
        #expect(existing.title != "Replacement")
        #expect(existing.isFavorite && existing.readingProgress == 0.5)
        #expect(existing.archivedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func invalidInputDoesNotPartiallyImport() throws {
        let container = try AppPersistence.inMemory()
        let context = container.mainContext
        let entries = [
            DeveloperImport.Entry(url: "https://example.com/valid", title: "Valid", savedAt: 100, archived: false),
            DeveloperImport.Entry(url: "instapaper-private://email/123", title: "Private", savedAt: 100, archived: false)
        ]
        #expect(throws: URLNormalizer.InvalidURL.self) { try DeveloperImport.apply(entries, context: context) }
        #expect(try context.fetchCount(FetchDescriptor<Article>()) == 0)
    }
}
#endif
