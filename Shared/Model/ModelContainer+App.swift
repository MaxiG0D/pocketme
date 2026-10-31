import CloudKit
import Foundation
import SwiftData

struct AppPersistence {
    enum Mode: String, Sendable { case cloud, local }
    let container: ModelContainer
    let mode: Mode

    @MainActor
    static func open() async throws -> AppPersistence {
        let root = try AppIdentity.groupURL ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: Bundle.main.bundleIdentifier ?? "PocketMe", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storeURL = root.appending(path: "Library.store")
        let schema = Schema([Article.self])
        // The identity token is a local check; awaiting CKContainer.accountStatus() cost a network round trip on every launch.
        if AppIdentity.canUseCloudKit, let cloudID = AppIdentity.cloudIdentifier,
           FileManager.default.ubiquityIdentityToken != nil {
            let configuration = ModelConfiguration("Library", schema: schema, url: storeURL, cloudKitDatabase: .private(cloudID))
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
                return AppPersistence(container: container, mode: .cloud)
            }
        }
        // Keep the same on-disk store; no articles are erased if iCloud is unavailable.
        let configuration = ModelConfiguration("Library", schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try AppPersistence(container: ModelContainer(for: schema, configurations: [configuration]), mode: .local)
    }

    @MainActor
    static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: Article.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
}
