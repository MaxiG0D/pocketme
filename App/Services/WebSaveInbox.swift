import CloudKit
import Foundation

/// Links saved from the web (Windows, Chrome) arrive as small `SaveRequest` records in a dedicated zone of the
/// private database. They never touch the library's own mirrored records: each one is moved into the local
/// `SaveQueue`, so it follows the same path as a share-extension save, and is then deleted from iCloud.
struct WebSaveInbox: Sendable {
    static let zoneName = "WebSaves"
    static let recordType = "SaveRequest"
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID

    init?() {
        guard let identifier = AppIdentity.cloudIdentifier, AppIdentity.canUseCloudKit else { return nil }
        database = CKContainer(identifier: identifier).privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Creates the zone on first use so the web page has somewhere to write.
    func prepare() async {
        _ = try? await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
    }

    /// Moves every pending request into `queue`. A record is deleted only after its link is safely queued.
    func drain(into queue: SaveQueue) async throws -> Int {
        await prepare()
        let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: nil)
        var handled: [CKRecord.ID] = []
        for (id, result) in changes.modificationResultsByID {
            guard let record = try? result.get().record, record.recordType == Self.recordType else { continue }
            if let url = record["url"] as? String {
                try await queue.append(url: url, title: record["title"] as? String, at: record["savedAt"] as? Date ?? .now)
            }
            handled.append(id)
        }
        guard !handled.isEmpty else { return 0 }
        _ = try await database.modifyRecords(saving: [], deleting: handled)
        return handled.count
    }
}
