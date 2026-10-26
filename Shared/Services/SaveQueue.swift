import Foundation
import CoreFoundation

actor SaveQueue {
    struct Entry: Codable, Sendable, Identifiable {
        var id = UUID()
        let url: String
        let title: String?
        let savedAt: Date
    }
    enum QueueError: Error { case groupUnavailable, invalidInbox }
    static let notification = "com.pocketme.save-inbox-changed"
    private let url: URL

    init(directory: URL? = AppIdentity.groupURL) throws {
        guard let directory else { throw QueueError.groupUnavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "SaveInbox.jsonl")
    }

    func append(url raw: String, title: String? = nil, at date: Date = .now) throws {
        _ = try URLNormalizer.normalize(raw)
        try coordinate { location in
            var data = FileManager.default.fileExists(atPath: location.path) ? try Data(contentsOf: location) : Data()
            data.append(try JSONEncoder().encode(Entry(url: raw, title: title, savedAt: date)))
            data.append(0x0A)
            try data.write(to: location, options: .atomic)
        }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.notification as CFString), nil, nil, true)
    }

    func entries() throws -> [Entry] {
        try coordinate { try Self.read($0) }
    }

    /// Acknowledge only after the SwiftData save succeeds. Concurrent extension saves stay queued.
    func acknowledge(_ ids: Set<UUID>) throws {
        try coordinate { location in
            let remaining = try Self.read(location).filter { !ids.contains($0.id) }
            var data = Data()
            for entry in remaining { data.append(try JSONEncoder().encode(entry)); data.append(0x0A) }
            try data.write(to: location, options: .atomic)
        }
    }

    private static func read(_ location: URL) throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: location.path) else { return [] }
        // A malformed line must not wedge the whole inbox; skip it (acknowledge rewrites the file without it).
        return try Data(contentsOf: location).split(separator: 0x0A).compactMap {
            try? JSONDecoder().decode(Entry.self, from: Data($0))
        }
    }

    private func coordinate<T>(_ operation: (URL) throws -> T) throws -> T {
        var error: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error) { location in
            result = Result { try operation(location) }
        }
        if let error { throw error }
        guard let result else { throw QueueError.invalidInbox }
        return try result.get()
    }
}
