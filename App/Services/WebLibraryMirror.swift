import CloudKit
import Foundation
import OSLog
import SwiftData

/// The web app can't read SwiftData's own CloudKit records, so the library is also published as simple
/// `WebArticle` records in a zone of its own. The app is the only writer; the web app only reads them and
/// sends archive and favorite changes back as `WebChange` requests (see `WebSaveInbox`).
@MainActor
final class WebLibraryMirror {
    static let zoneName = "WebLibrary"
    static let recordType = "WebArticle"
    /// CloudKit limits a record to 1 MB; longer articles open the original on the web instead.
    static let maxBody = 600_000
    private static let log = Logger(subsystem: "com.maxigariepy.pocketme", category: "WebMirror")
    private static let stateKey = "webMirror.v1"

    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var running = false
    private var rerun = false
    private var zoneReady = false

    /// What the web already has for an article: signatures of its content and details, and whether it has a thumbnail.
    private struct Sent: Codable, Equatable { var content: String; var details: String; var thumbnail: Bool }

    init?() {
        guard let identifier = AppIdentity.cloudIdentifier, AppIdentity.canUseCloudKit else { return nil }
        database = CKContainer(identifier: identifier).privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    func publish(from context: ModelContext) async {
        // A change that arrives mid-publish runs one more pass afterwards instead of racing this one.
        if running { rerun = true; return }
        running = true
        defer { running = false }
        repeat {
            rerun = false
            await pass(context)
        } while rerun
    }

    private func pass(_ context: ModelContext) async {
        if !zoneReady {
            do { _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: []); zoneReady = true }
            catch { Self.log.error("zone setup failed: \(error.localizedDescription, privacy: .public)"); return }
        }
        guard let articles = try? context.fetch(FetchDescriptor<Article>()) else { return }
        let previous = Self.load()
        var next = previous
        var records: [CKRecord] = []
        var pending: [String: Sent] = [:]
        var files: [URL] = []
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }

        for article in articles {
            let name = article.id.uuidString
            let sent = previous[name]
            let content = [article.statusRaw, article.title, article.siteName, article.author ?? "", article.excerpt ?? "",
                           article.leadImageURL ?? "", "\(article.wordCount)", "\(article.readingMinutes)"].joined(separator: "|")
            let details = "\(article.savedAt.timeIntervalSince1970)|\(article.archivedAt?.timeIntervalSince1970 ?? 0)|\(article.isFavorite)"
            let contentChanged = sent?.content != content
            // An article without a thumbnail has nothing to send; it must not count as unsent on every pass.
            let needsThumbnail = !(sent?.thumbnail ?? false) && article.thumbnailData != nil
            guard contentChanged || sent?.details != details || needsThumbnail else { continue }

            let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
            var hasThumbnail = sent?.thumbnail ?? false
            if contentChanged || sent == nil {
                record["articleID"] = name
                record["url"] = article.url
                record["title"] = article.title
                record["siteName"] = article.siteName
                record["author"] = article.author
                record["excerpt"] = article.excerpt
                record["leadImageURL"] = article.leadImageURL
                record["status"] = article.statusRaw
                record["wordCount"] = article.wordCount
                record["readingMinutes"] = article.readingMinutes
                let html = article.contentHTML.flatMap { String(data: $0, encoding: .utf8) }
                record["body"] = html.flatMap { $0.utf8.count <= Self.maxBody ? $0 : nil }
            }
            record["savedAt"] = article.savedAt
            record["archived"] = article.archivedAt == nil ? 0 : 1
            record["isFavorite"] = article.isFavorite ? 1 : 0
            if (contentChanged || needsThumbnail), let data = article.thumbnailData {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("web-\(UUID().uuidString).jpg")
                if (try? data.write(to: file)) != nil {
                    files.append(file)
                    record["thumbnail"] = CKAsset(fileURL: file)
                    hasThumbnail = true
                }
            }
            records.append(record)
            pending[name] = Sent(content: content, details: details, thumbnail: hasThumbnail)
        }

        // Articles deleted in the app disappear from the web too.
        let live = Set(articles.map { $0.id.uuidString })
        let removed = previous.keys.filter { !live.contains($0) }.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        for id in removed { next[id.recordName] = nil }
        guard !records.isEmpty || !removed.isEmpty else { return }

        // Batches stay small so one article's size can't hold the rest back.
        for start in stride(from: 0, to: records.count, by: 25) {
            let batch = Array(records[start..<min(start + 25, records.count)])
            do {
                let result = try await database.modifyRecords(saving: batch, deleting: [], savePolicy: .changedKeys)
                for (id, outcome) in result.saveResults {
                    switch outcome {
                    case .success: if let sent = pending[id.recordName] { next[id.recordName] = sent }
                    case .failure(let error): Self.log.error("mirror save failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            } catch {
                Self.log.error("mirror publish failed: \(error.localizedDescription, privacy: .public)")
                break
            }
        }
        if !removed.isEmpty { _ = try? await database.modifyRecords(saving: [], deleting: removed) }
        Self.save(next)
        Self.log.info("published \(pending.count) article(s), removed \(removed.count)")
    }

    private static func load() -> [String: Sent] {
        UserDefaults.standard.data(forKey: stateKey).flatMap { try? JSONDecoder().decode([String: Sent].self, from: $0) } ?? [:]
    }
    private static func save(_ state: [String: Sent]) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: stateKey) }
    }
}
