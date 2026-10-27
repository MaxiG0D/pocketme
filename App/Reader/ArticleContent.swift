import Foundation

struct ArticleContent: Sendable {
    let id: UUID
    let title: String
    let site: String
    let minutes: Int
    let leadImageURL: String?
    let html: String
    let isVideo: Bool

    @MainActor init(_ article: Article) {
        id = article.id; title = article.title; site = article.siteName
        minutes = article.readingMinutes; leadImageURL = article.leadImageURL
        html = article.contentHTML.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        isVideo = VideoLink(article.url) != nil
    }
}
