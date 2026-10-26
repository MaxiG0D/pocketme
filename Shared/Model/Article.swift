import Foundation
import SwiftData

@Model
final class Article {
    var id: UUID = UUID()
    var url: String = ""
    var normalizedURL: String = ""
    var title: String = ""
    var siteName: String = ""
    var author: String?
    var excerpt: String?
    var leadImageURL: String?
    @Attribute(.externalStorage) var thumbnailData: Data?
    @Attribute(.externalStorage) var contentHTML: Data?
    var wordCount: Int = 0
    var readingMinutes: Int = 0
    var savedAt: Date = Date.now
    var lastOpenedAt: Date?
    var archivedAt: Date?
    var isFavorite: Bool = false
    var readingProgress: Double = 0
    var statusRaw: String = ArticleStatus.pending.rawValue
    var failureReason: String?
    var extractionAttempts: Int = 0

    var status: ArticleStatus {
        get { ArticleStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(url: String = "", normalizedURL: String = "", title: String = "", siteName: String = "", savedAt: Date = .now) {
        self.url = url
        self.normalizedURL = normalizedURL
        self.title = title
        self.siteName = siteName
        self.savedAt = savedAt
    }
}

enum ArticleStatus: String, Codable, Sendable { case pending, ready, failed }
