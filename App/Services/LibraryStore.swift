import CoreData
import Foundation
import SwiftData
import Observation

@MainActor @Observable
final class LibraryStore {
    private(set) var persistence: AppPersistence?
    var errorMessage: String?
    var readerPreferences = ReaderPreferences()
    var focusPasteToken = 0
    var toggleListToken = 0
    var processor: ProcessingCoordinator?
    var requestedArticleID: UUID?
    var savedToken = 0
    var actionToken = 0
    var draining = false
    @ObservationIgnored private var inboxObserver: InboxObserver?
    private var opening = false
    @ObservationIgnored private var remoteChanges: Task<Void, Never>?

    init(persistence: AppPersistence? = nil) { self.persistence = persistence }

    func open() async {
        guard persistence == nil, !opening else { return }
        opening = true
        defer { opening = false }
        do {
            let opened = try await AppPersistence.open()
            try ArticleRepository(context: opened.container.mainContext).deduplicate()
            #if DEBUG && os(macOS)
            try DeveloperImport.runIfRequested(persistence: opened)
            #endif
            persistence = opened
            if let root = opened.container.configurations.first?.url.deletingLastPathComponent() {
                processor = ProcessingCoordinator(context: opened.container.mainContext, root: root)
            }
            errorMessage = nil
            inboxObserver = InboxObserver { [weak self] in Task { await self?.drainInbox() } }
            await drainInbox()
            remoteChanges = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange).map({ _ in () }) {
                    guard !Task.isCancelled else { return }
                    self?.refresh()
                }
            }
            #if DEBUG
            await SyncProbe.runIfRequested(persistence: opened)
            #endif
        } catch {
            errorMessage = "Your reading library couldn’t be opened. Please try again."
        }
    }

    func refresh() {
        guard let persistence else { return }
        do {
            try ArticleRepository(context: persistence.container.mainContext).deduplicate()
            errorMessage = nil
            processor?.start()
        } catch { errorMessage = "Some articles couldn’t be updated. Please try again." }
    }
}
