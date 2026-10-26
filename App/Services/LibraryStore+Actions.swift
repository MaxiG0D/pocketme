import Foundation
import SwiftData

extension LibraryStore {
    @discardableResult
    func saveLink(_ raw: String, title: String? = nil) -> Article? {
        guard let persistence else { return nil }
        do {
            let article = try ArticleRepository(context: persistence.container.mainContext).save(url: raw, title: title)
            errorMessage = nil
            savedToken += 1
            processor?.start()
            return article
        } catch { errorMessage = (error as? URLNormalizer.InvalidURL)?.errorDescription ?? "This link couldn’t be saved. Please try again."; return nil }
    }

    func drainInbox() async {
        guard let persistence, !draining else { return }
        draining = true
        defer { draining = false }
        do {
            let root = persistence.container.configurations.first?.url.deletingLastPathComponent()
            let queue = try SaveQueue(directory: AppIdentity.groupURL ?? root)
            while true {
              let entries = try await queue.entries()
              if entries.isEmpty { break }
              for entry in entries {
                try ArticleRepository(context: persistence.container.mainContext).save(url: entry.url, title: entry.title, at: entry.savedAt)
                try await queue.acknowledge([entry.id])
                savedToken += 1
              }
            }
            processor?.start()
        } catch { errorMessage = "Some shared links couldn’t be saved yet. They’ll stay in your inbox to try again." }
    }

    func openLink(_ url: URL) async {
        guard url.scheme == "pocketme", url.host == "open",
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value else { return }
        await drainInbox()
        if let normalized = try? URLNormalizer.normalize(raw), let context = persistence?.container.mainContext,
           let article = try? context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.normalizedURL == normalized })).first {
            requestedArticleID = article.id
        }
    }

    func archive(_ article: Article) {
        article.archivedAt = article.archivedAt == nil ? .now : nil
        persist()
        actionToken += 1
    }

    func favorite(_ article: Article) { article.isFavorite.toggle(); persist(); actionToken += 1 }
    func retry(_ article: Article) {
        article.status = .pending; article.failureReason = nil; article.extractionAttempts = 0
        persist(); processor?.start()
    }
    func delete(_ article: Article) {
        let id = article.id
        persistence?.container.mainContext.delete(article)
        persist()
        Task { try? await processor?.assets.delete(id) }
    }
    func persist() {
        do { try persistence?.container.mainContext.save() }
        catch { errorMessage = "Your changes couldn’t be saved. Please try again." }
    }
}
