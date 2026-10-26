import Foundation
#if os(macOS)
import Security
#endif

enum AppIdentity {
    static var groupIdentifier: String? { value("PocketMeAppGroup") }
    static var cloudIdentifier: String? { value("PocketMeCloudContainer") }

    private static func value(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    static var canUseCloudKit: Bool {
        guard let identifier = cloudIdentifier else { return false }
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String]
        else { return false }
        return containers.contains(identifier)
        #elseif targetEnvironment(simulator)
        return false
        #else
        // A physical iOS build is code signed and carries the app's CloudKit entitlement.
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier ?? "") != nil
        #endif
    }

    static var groupURL: URL? {
        guard let identifier = groupIdentifier else { return nil }
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
              groups.contains(identifier) else { return nil }
        #endif
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
