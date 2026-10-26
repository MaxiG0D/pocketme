#if DEBUG
import Foundation
import SwiftData

/// Opt-in, local developer diagnostic for the M2 cross-device acceptance test.
@MainActor
enum SyncProbe {
    static func runIfRequested(persistence: AppPersistence) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PocketMeSyncProbe"), arguments.indices.contains(index + 1) else { return }
        let url = arguments[index + 1]
        let shouldCreate = arguments.contains("-PocketMeSyncCreate")
        do {
            if arguments.contains("-PocketMeSyncCleanup") {
                let normalized = try URLNormalizer.normalize(url)
                let context = persistence.container.mainContext
                for article in try context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.normalizedURL == normalized })) { context.delete(article) }
                try context.save()
                return
            }
            if shouldCreate {
                let article = try ArticleRepository(context: persistence.container.mainContext).save(url: url, title: "PocketMe sync check")
                article.isFavorite = true
                article.readingProgress = 0.42
                try persistence.container.mainContext.save()
            }
            for attempt in 0..<90 {
                let context = ModelContext(persistence.container)
                let normalized = try URLNormalizer.normalize(url)
                let count = try context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { $0.normalizedURL == normalized }))
                let result = Result(mode: persistence.mode.rawValue, found: count > 0, count: count, created: shouldCreate, attempt: attempt)
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                try JSONEncoder().encode(result).write(to: documents.appending(path: "PocketMeSyncProbe.json"), options: .atomic)
                if count > 0 && !shouldCreate { return }
                try await Task.sleep(for: .seconds(2))
            }
        } catch { print("PocketMe sync probe: \(error.localizedDescription)") }
    }

    private struct Result: Codable {
        let mode: String
        let found: Bool
        let count: Int
        let created: Bool
        let attempt: Int
    }
}
#endif
