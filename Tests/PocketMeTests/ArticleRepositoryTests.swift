import Foundation
import SwiftData
import Testing
@testable import PocketMe

@MainActor
struct ArticleRepositoryTests {
    @Test func resavingMovesToTopAndUnarchivesWithoutLosingState() throws {
        let container = try AppPersistence.inMemory()
        let repo = ArticleRepository(context: container.mainContext)
        let first = try repo.save(url: "https://www.example.com/story/?utm_source=test", at: Date(timeIntervalSince1970: 10))
        first.archivedAt = Date(timeIntervalSince1970: 20)
        first.isFavorite = true
        first.readingProgress = 0.6
        let again = try repo.save(url: "https://example.com/story#fragment", at: Date(timeIntervalSince1970: 30))
        #expect(first.id == again.id)
        #expect(again.archivedAt == nil)
        #expect(again.isFavorite)
        #expect(again.readingProgress == 0.6)
        #expect(again.savedAt == Date(timeIntervalSince1970: 30))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Article>()) == 1)
    }

    @Test func mergesConcurrentSavesAndPreservesOfflineContent() throws {
        let container = try AppPersistence.inMemory()
        let context = container.mainContext
        let oldest = Article(url: "https://example.com/story", title: "Original", savedAt: Date(timeIntervalSince1970: 10))
        oldest.archivedAt = Date(timeIntervalSince1970: 11)
        oldest.readingProgress = 0.2
        let newest = Article(url: "https://www.example.com/story/?utm_campaign=test", title: "Extracted title", savedAt: Date(timeIntervalSince1970: 20))
        newest.isFavorite = true
        newest.status = .ready
        newest.contentHTML = Data("<p>A saved story</p>".utf8)
        newest.thumbnailData = Data([1, 2, 3])
        newest.readingProgress = 0.8
        newest.lastOpenedAt = Date(timeIntervalSince1970: 30)
        context.insert(oldest); context.insert(newest)
        try context.save()
        #expect(try ArticleRepository(context: context).deduplicate() == 1)
        let remaining = try #require(context.fetch(FetchDescriptor<Article>()).first)
        #expect(remaining.id == oldest.id)
        #expect(remaining.savedAt == Date(timeIntervalSince1970: 10))
        #expect(remaining.isFavorite && remaining.readingProgress == 0.8)
        #expect(remaining.archivedAt == nil)
        #expect(remaining.title == "Extracted title")
        #expect(remaining.contentHTML == newest.contentHTML)
        #expect(remaining.thumbnailData == Data([1, 2, 3]))
        #expect(remaining.status == .ready)
        #expect(try ArticleRepository(context: context).deduplicate() == 0)
    }

    @Test func deterministicTieBreakAndSeparateArticles() throws {
        let container = try AppPersistence.inMemory()
        let context = container.mainContext
        let a = Article(url: "https://example.com/a", savedAt: .distantPast)
        let b = Article(url: "https://example.com/a#part", savedAt: .distantPast)
        a.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        context.insert(b); context.insert(a)
        context.insert(Article(url: "https://example.com/b"))
        try context.save()
        #expect(try ArticleRepository(context: context).deduplicate() == 1)
        #expect(try context.fetchCount(FetchDescriptor<Article>()) == 2)
        let articles = try context.fetch(FetchDescriptor<Article>())
        #expect(articles.contains { $0.id == a.id })
    }

    @Test func diskStoreSurvivesReopening() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Library.store")
        do {
            let container = try ModelContainer(for: Article.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            try ArticleRepository(context: container.mainContext).save(url: "https://example.com/survives")
        }
        let reopened = try ModelContainer(for: Article.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<Article>()) == 1)
    }
}
