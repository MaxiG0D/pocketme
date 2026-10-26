import Foundation
import Testing
@testable import PocketMe

struct SaveQueueTests {
    @Test func acknowledgmentsPreserveNewExtensionSaves() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let extensionQueue = try SaveQueue(directory: folder)
        let appQueue = try SaveQueue(directory: folder)
        try await extensionQueue.append(url: "https://example.com/one")
        let first = try #require(await appQueue.entries().first)
        try await extensionQueue.append(url: "https://example.com/two")
        try await appQueue.acknowledge([first.id])
        let remaining = try await appQueue.entries()
        #expect(remaining.count == 1)
        #expect(remaining.first?.url == "https://example.com/two")
    }

    @Test func multipleWritersDoNotLoseEntries() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try SaveQueue(directory: folder), b = try SaveQueue(directory: folder)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 { group.addTask { try await (i.isMultiple(of: 2) ? a : b).append(url: "https://example.com/\(i)") } }
            try await group.waitForAll()
        }
        let entries = try await a.entries()
        #expect(entries.count == 20)
        #expect(Set(entries.map(\.url)).count == 20)
    }
}
