import CloudKit
import Foundation
import OSLog

/// An archive or favorite change made in the web app, waiting for the app to apply it.
struct WebChange: Sendable {
    let articleID: UUID
    let action: String
    let at: Date
}

/// Links saved from the web (Windows, Chrome) arrive as small `SaveRequest` records in a dedicated zone of the
/// private database. They never touch the library's own mirrored records: each one is moved into the local
/// `SaveQueue`, so it follows the same path as a share-extension save, and is then deleted from iCloud.
struct WebSaveInbox: Sendable {
    static let zoneName = "WebSaves"
    static let recordType = "SaveRequest"
    static let changeType = "WebChange"
    private static let log = Logger(subsystem: "com.maxigariepy.pocketme", category: "WebSave")
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID

    init?() {
        guard let identifier = AppIdentity.cloudIdentifier, AppIdentity.canUseCloudKit else { return nil }
        database = CKContainer(identifier: identifier).privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Creates the zone on first use so the web page has somewhere to write.
    func prepare() async {
        do { _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: []) }
        catch { Self.log.error("zone setup failed: \(error.localizedDescription, privacy: .public)") }
    }

    /// Moves every pending request into `queue` and hands the web app's changes to `apply`. A record is deleted
    /// only after its link is safely queued or its change applied.
    func drain(into queue: SaveQueue, apply: @MainActor ([WebChange]) -> Void) async throws -> Int {
        do {
            await prepare()
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: nil)
            if let user = try? await CKContainer(identifier: AppIdentity.cloudIdentifier ?? "").userRecordID() {
                Self.log.info("signed in as …\(String(user.recordName.suffix(6)), privacy: .public)")
            }
            Self.log.info("fetched \(changes.modificationResultsByID.count) web save request(s)")
            var handled: [CKRecord.ID] = []
            var saved = 0
            var edits: [WebChange] = []
            for (id, result) in changes.modificationResultsByID {
                guard let record = try? result.get().record else { continue }
                if record.recordType == Self.recordType {
                    if let url = record["url"] as? String {
                        try await queue.append(url: url, title: record["title"] as? String, at: record["savedAt"] as? Date ?? .now)
                        saved += 1
                    }
                    handled.append(id)
                } else if record.recordType == Self.changeType {
                    if let raw = record["articleID"] as? String, let article = UUID(uuidString: raw), let action = record["action"] as? String {
                        edits.append(WebChange(articleID: article, action: action, at: record["at"] as? Date ?? record.creationDate ?? .now))
                    }
                    handled.append(id)
                }
            }
            guard !handled.isEmpty else { return 0 }
            if !edits.isEmpty { await apply(edits.sorted { $0.at < $1.at }) }
            _ = try await database.modifyRecords(saving: [], deleting: handled)
            return saved
        } catch {
            Self.log.error("web save import failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
