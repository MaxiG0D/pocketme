import Foundation
#if os(iOS)
import BackgroundTasks
#endif

enum BackgroundRefresh {
    @MainActor static func register(store: LibraryStore) {
        #if os(iOS)
        guard let id = Bundle.main.bundleIdentifier else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id + ".refresh", using: nil) { task in
            let work = Task { @MainActor in
                await store.open()
                await store.drainInbox()
                await store.processor?.finishPendingWork()
                task.setTaskCompleted(success: !Task.isCancelled)
                schedule()
            }
            task.expirationHandler = { work.cancel(); Task { @MainActor in store.processor?.cancel() } }
        }
        #endif
    }

    @MainActor static func schedule() {
        #if os(iOS)
        guard let id = Bundle.main.bundleIdentifier else { return }
        let request = BGAppRefreshTaskRequest(identifier: id + ".refresh")
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
}
