import Foundation
import CoreFoundation

@MainActor
final class InboxObserver {
    private let action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), { _, pointer, _, _, _ in
                guard let pointer else { return }
                let observer = Unmanaged<InboxObserver>.fromOpaque(pointer).takeUnretainedValue()
                Task { @MainActor in observer.action() }
            }, SaveQueue.notification as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), nil, nil)
    }
}
