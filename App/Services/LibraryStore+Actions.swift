import Foundation
import SwiftData

extension LibraryStore {
    @discardableResult
    func saveLink(_ raw: String, title: String? = nil) -> Article? {
        guard let persistence else { return nil }
        do {
            let context = persistence.container.mainContext
            let normalized = try URLNormalizer.normalize(raw)
            let known = try context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { $0.normalizedURL == normalized })) > 0
            let article = try ArticleRepository(context: context).save(url: raw, title: title)
            errorMessage = nil
            savedToken += 1
            show(known ? "Already saved" : "Saved")
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
            let queue = try SaveQueue(directory: AppIdentity.inboxURL ?? root)
            if persistence.mode == .cloud, let webInbox = WebSaveInbox() {
                // Links saved from the web; offline or signed-out iCloud just tries again next time.
                _ = try? await webInbox.drain(into: queue)
            }
            var imported = 0
            while true {
              let entries = try await queue.entries()
              if entries.isEmpty { break }
              for entry in entries {
                try ArticleRepository(context: persistence.container.mainContext).save(url: entry.url, title: entry.title, at: entry.savedAt)
                try await queue.acknowledge([entry.id])
                savedToken += 1
                imported += 1
                show("Saved")
              }
            }
            // Nothing new means nothing to start; the launch pass is scheduled separately.
            if imported > 0 { processor?.start() }
        } catch { errorMessage = "Some shared links couldn’t be saved yet. They’ll stay in your inbox to try again." }
    }

    /// The share sheet leaves a timestamp just before opening the app; cover the library before the link arrives.
    func coverIfOpeningShared() {
        guard let defaults = AppIdentity.openRequest,
              let at = defaults.object(forKey: AppIdentity.openRequestKey) as? Date, -at.timeIntervalSinceNow < 10 else { return }
        openingLink = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if let self, !self.linkInFlight { self.openingLink = false }
        }
    }

    func openLink(_ url: URL) async {
        guard url.scheme == "pocketme", url.host == "open" || url.host == "save",
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value else { return }
        if url.host == "save", let queue = try? SaveQueue(directory: AppIdentity.inboxURL) {
            try? await queue.append(url: raw)
        }
        openingLink = true
        linkInFlight = true
        AppIdentity.openRequest?.removeObject(forKey: AppIdentity.openRequestKey)
        await drainInbox()
        if let normalized = try? URLNormalizer.normalize(raw), let context = persistence?.container.mainContext,
           let article = try? context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.normalizedURL == normalized })).first {
            requestedArticleID = article.id
            // The reader finishes opening under the veil, then the veil lifts straight onto it.
            try? await Task.sleep(for: .milliseconds(450))
        }
        linkInFlight = false
        openingLink = false
    }

    func archive(_ article: Article) {
        let archiving = article.archivedAt == nil
        article.archivedAt = archiving ? .now : nil
        persist()
        actionToken += 1
        show(archiving ? "Archived" : "Moved to Reading") { [weak self, weak article] in
            guard let article, article.modelContext != nil else { return }
            article.archivedAt = archiving ? nil : .now
            self?.persist()
        }
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
        pendingSave?.cancel()
        do { try persistence?.container.mainContext.save() }
        catch { errorMessage = "Your changes couldn’t be saved. Please try again." }
    }
    /// Writes a moment later, off the transition or scroll that asked for it. A later `persist()` makes it redundant.
    func persistSoon(after delay: Duration = .seconds(1)) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            // A save rebuilds every query in the library, so it waits for the list to stop moving.
            var waited = 0
            while let self, self.listScrolling, waited < 60, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(500)); waited += 1 }
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }
}
