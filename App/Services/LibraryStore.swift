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
    var findToken = 0
    var processor: ProcessingCoordinator?
    var requestedArticleID: UUID?
    /// Set from the View menu; the library applies it with its own animation.
    var requestedLayout: LibraryLayout?
    var savedToken = 0
    var actionToken = 0
    /// A video is playing in theater mode; everything around it dims.
    var theater = false
    var draining = false
    private(set) var toast: Toast?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var inboxObserver: InboxObserver?
    #if os(macOS)
    @ObservationIgnored private let localSaveServer = LocalSaveServer()
    #endif
    private var opening = false
    @ObservationIgnored private var remoteChanges: Task<Void, Never>?
    @ObservationIgnored var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var maintenance: Task<Void, Never>?
    /// True while a library list or grid is being scrolled; background bookkeeping waits for it to settle.
    @ObservationIgnored var listScrolling = false

    init(persistence: AppPersistence? = nil) { self.persistence = persistence }

    func open() async {
        guard persistence == nil, !opening else { return }
        opening = true
        defer { opening = false }
        do {
            #if DEBUG
            // UI tests run against the sample library so they never touch the real one.
            if ProcessInfo.processInfo.arguments.contains("-PocketMeUITest") {
                persistence = AppPersistence(container: try SampleData.container(), mode: .local)
                return
            }
            #endif
            let opened = try await AppPersistence.open()
            #if DEBUG && os(macOS)
            try DeveloperImport.runIfRequested(persistence: opened)
            #endif
            persistence = opened
            if let root = opened.container.configurations.first?.url.deletingLastPathComponent() {
                processor = ProcessingCoordinator(context: opened.container.mainContext, root: root)
            }
            errorMessage = nil
            #if os(macOS)
            localSaveServer.start()
            #endif
            inboxObserver = InboxObserver { [weak self] in Task { await self?.drainInbox() } }
            await drainInbox()
            // De-duplication and the background pass both walk every article on the main actor; they wait for the first screen.
            scheduleMaintenance()
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

    func show(_ text: String, undo: (@MainActor () -> Void)? = nil) {
        let toast = Toast(text: text, undo: undo)
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 2 : 4))
            if !Task.isCancelled, self?.toast?.id == toast.id { self?.toast = nil }
        }
    }
    func dismissToast() { toastTask?.cancel(); toast = nil }

    /// Merges duplicates and restarts background processing a little later, once. Called at launch, whenever the app
    /// becomes active and on every sync notification, so doing it inline put a full pass over the library into the
    /// first seconds of scrolling; repeated calls now coalesce.
    func scheduleMaintenance(after delay: Duration = .seconds(2.5)) {
        maintenance?.cancel()
        maintenance = Task { [weak self] in
            try? await Task.sleep(for: delay)
            // Never in the middle of a scroll: wait for the finger and the deceleration to finish, up to half a minute.
            var waited = 0
            while let self, self.listScrolling, waited < 60, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(500)); waited += 1 }
            guard !Task.isCancelled, let self, let persistence = self.persistence else { return }
            do {
                try ArticleRepository(context: persistence.container.mainContext).deduplicate()
                self.errorMessage = nil
                self.processor?.start()
            } catch { self.errorMessage = "Some articles couldn’t be updated. Please try again." }
        }
    }

    func refresh() { scheduleMaintenance(after: .seconds(1.5)) }
}

struct Toast: Identifiable {
    let id = UUID()
    let text: String
    var undo: (@MainActor () -> Void)?
}
