import Foundation
import SwiftData

@MainActor
struct ArticleRepository {
    let context: ModelContext

    @discardableResult
    func save(url: String, title: String? = nil, at date: Date = .now) throws -> Article {
        let normalized = try URLNormalizer.normalize(url)
        let predicate = #Predicate<Article> { $0.normalizedURL == normalized }
        let matches = try context.fetch(FetchDescriptor(predicate: predicate))
        let article: Article
        if let existing = matches.sorted(by: Self.older).first {
            article = existing
            article.savedAt = date
            article.archivedAt = nil
        } else {
            let host = URL(string: normalized)?.host() ?? ""
            article = Article(url: url.trimmingCharacters(in: .whitespacesAndNewlines), normalizedURL: normalized,
                              title: title ?? host, siteName: host)
            article.savedAt = date
            context.insert(article)
        }
        // Consolidate even if a CloudKit import landed just before the save.
        for duplicate in matches where duplicate !== article {
            Self.merge(duplicate, into: article)
            context.delete(duplicate)
        }
        article.savedAt = date
        article.archivedAt = nil
        try context.save()
        return article
    }

    @discardableResult
    func deduplicate() throws -> Int {
        let articles = try context.fetch(FetchDescriptor<Article>())
        var groups: [String: [Article]] = [:]
        for article in articles {
            guard let normalized = try? URLNormalizer.normalize(article.url) else { continue }
            if article.normalizedURL != normalized { article.normalizedURL = normalized }
            groups[normalized, default: []].append(article)
        }
        var removed = 0
        for group in groups.values where group.count > 1 {
            let ordered = group.sorted(by: Self.older)
            guard let keeper = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                Self.merge(duplicate, into: keeper)
                context.delete(duplicate)
                removed += 1
            }
        }
        if context.hasChanges { try context.save() }
        return removed
    }

    private static func older(_ lhs: Article, _ rhs: Article) -> Bool {
        if lhs.savedAt != rhs.savedAt { return lhs.savedAt < rhs.savedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func merge(_ other: Article, into keeper: Article) {
        keeper.isFavorite = keeper.isFavorite || other.isFavorite
        keeper.readingProgress = max(keeper.readingProgress, other.readingProgress)
        keeper.lastOpenedAt = [keeper.lastOpenedAt, other.lastOpenedAt].compactMap { $0 }.max()
        // An unread copy must stay discoverable. Otherwise retain the latest archive date.
        if keeper.archivedAt == nil || other.archivedAt == nil { keeper.archivedAt = nil }
        else { keeper.archivedAt = [keeper.archivedAt, other.archivedAt].compactMap { $0 }.max() }
        let betterContent = (other.contentHTML?.count ?? 0) > (keeper.contentHTML?.count ?? 0)
        if betterContent {
            keeper.contentHTML = other.contentHTML
            keeper.wordCount = other.wordCount
            keeper.readingMinutes = other.readingMinutes
            keeper.title = other.title.isEmpty ? keeper.title : other.title
            keeper.siteName = other.siteName.isEmpty ? keeper.siteName : other.siteName
            keeper.author = other.author ?? keeper.author
            keeper.excerpt = other.excerpt ?? keeper.excerpt
            keeper.leadImageURL = other.leadImageURL ?? keeper.leadImageURL
        }
        if keeper.title.isEmpty { keeper.title = other.title }
        if keeper.siteName.isEmpty { keeper.siteName = other.siteName }
        keeper.author = keeper.author ?? other.author
        keeper.excerpt = keeper.excerpt ?? other.excerpt
        keeper.thumbnailData = keeper.thumbnailData ?? other.thumbnailData
        keeper.leadImageURL = keeper.leadImageURL ?? other.leadImageURL
        if other.status == .ready || keeper.status == .ready {
            keeper.status = .ready
            keeper.failureReason = nil
        } else if other.status == .pending || keeper.status == .pending {
            keeper.status = .pending
            keeper.failureReason = nil
        } else { keeper.failureReason = keeper.failureReason ?? other.failureReason }
        keeper.extractionAttempts = max(keeper.extractionAttempts, other.extractionAttempts)
    }
}
