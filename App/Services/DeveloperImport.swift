#if DEBUG && os(macOS)
import Foundation
import SwiftData

/// One-off migrations run inside the signed app so its normal store and iCloud are used.
/// No account integration or import UI is included in the product.
@MainActor
enum DeveloperImport {
    struct Entry: Codable {
        let url: String
        let title: String
        let savedAt: Double
        let archived: Bool
    }

    static func apply(_ entries: [Entry], context: ModelContext) throws -> Int {
        // Validate the entire input before inserting anything.
        let normalized = try entries.map { try URLNormalizer.normalize($0.url) }
        var known = Set(try context.fetch(FetchDescriptor<Article>()).map(\.normalizedURL))
        var inserted = 0
        for (entry, key) in zip(entries, normalized) {
            guard known.insert(key).inserted else { continue }
            let host = URL(string: key)?.host() ?? ""
            let date = Date(timeIntervalSince1970: entry.savedAt)
            let article = Article(url: entry.url, normalizedURL: key,
                                  title: entry.title.isEmpty ? host : entry.title,
                                  siteName: host, savedAt: date)
            // The export has a save timestamp, but no archive timestamp.
            article.archivedAt = entry.archived ? date : nil
            context.insert(article)
            inserted += 1
        }
        try context.save()
        return inserted
    }

    static func runIfRequested(persistence: AppPersistence) throws {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-PocketMeDeveloperImport"), args.indices.contains(index + 1) else { return }
        guard let data = Data(base64Encoded: args[index + 1]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        let context = persistence.container.mainContext
        let inserted = try apply(entries, context: context)
        let articles = try context.fetch(FetchDescriptor<Article>())
        let keys = Set(try entries.map { try URLNormalizer.normalize($0.url) })
        let imported = articles.filter { keys.contains($0.normalizedURL) }
        let report = "Imported: \(inserted); already present: \(entries.count - inserted); verified: \(imported.count); unread: \(imported.filter { $0.archivedAt == nil }.count); archived: \(imported.filter { $0.archivedAt != nil }.count); persistence: \(persistence.mode.rawValue)"
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try report.write(to: documents.appending(path: "PocketMeImportReport.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
