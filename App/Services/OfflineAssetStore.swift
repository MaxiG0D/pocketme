import CryptoKit
import Foundation

actor OfflineAssetStore {
    let root: URL
    init(root: URL) { self.root = root.appending(path: "Articles", directoryHint: .isDirectory) }
    nonisolated func folder(_ id: UUID) -> URL { root.appending(path: id.uuidString, directoryHint: .isDirectory) }
    nonisolated func index(_ id: UUID) -> URL { folder(id).appending(path: "index.html") }

    func prepare(_ article: ArticleContent) async throws {
        let folder = folder(article.id)
        let imageFolder = folder.appending(path: "img", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
        var urls = HTMLAssets.images(in: article.html)
        if let lead = article.leadImageURL { urls.insert(lead, at: 0) }
        let cached = (try? FileManager.default.contentsOfDirectory(at: imageFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var seen = Set<String>(), paths: [String: String] = [:], downloaded = 0
        let budget = 15 * 1_024 * 1_024
        var wanted: [(raw: String, url: URL, hash: String)] = []
        for raw in urls where wanted.count < 40 {
            guard seen.insert(raw).inserted, let url = URL(string: raw) else { continue }
            wanted.append((raw, url, Insecure.SHA1.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()))
        }
        // Images load in parallel; the size budget is applied in document order afterwards.
        var fetched: [String: (data: Data, ext: String)] = [:]
        try await withThrowingTaskGroup(of: (String, Data, String)?.self) { group in
            var iterator = wanted.makeIterator(), active = 0
            func next(_ group: inout ThrowingTaskGroup<(String, Data, String)?, Error>) {
                while active < 12, let item = iterator.next() {
                    if cached.contains(where: { $0.deletingPathExtension().lastPathComponent == item.hash }) { continue }
                    active += 1
                    group.addTask {
                        do {
                            let (data, mime) = try await NetworkData.fetch(item.url, limit: 8 * 1_024 * 1_024)
                            guard mime?.hasPrefix("image/") == true else { return nil }
                            let ext = ["image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp", "image/avif": "avif", "image/svg+xml": "svg"][mime ?? ""] ?? "img"
                            return (item.raw, data, ext)
                        } catch is CancellationError { throw CancellationError() }
                        catch { return nil }
                    }
                }
            }
            next(&group)
            while let result = try await group.next() {
                active -= 1
                if let (raw, data, ext) = result { fetched[raw] = (data, ext) }
                next(&group)
            }
        }
        for item in wanted {
            let remaining = budget - downloaded
            guard remaining > 0 else { break }
            if let existing = cached.first(where: { $0.deletingPathExtension().lastPathComponent == item.hash }),
               let size = try? existing.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= remaining {
                paths[item.raw] = "img/" + existing.lastPathComponent; downloaded += size
            } else if let (data, ext) = fetched[item.raw], data.count <= remaining {
                let filename = "\(item.hash).\(ext)"
                try data.write(to: imageFolder.appending(path: filename), options: .atomic)
                paths[item.raw] = "img/\(filename)"; downloaded += data.count
            }
        }
        let kept = Set(paths.values.map { URL(fileURLWithPath: $0).lastPathComponent })
        for old in cached where !kept.contains(old.lastPathComponent) { try? FileManager.default.removeItem(at: old) }
        let content = HTMLAssets.rewrite(article.html, paths: paths)
        try copyFonts(to: folder)
        let document = try ReaderDocument.html(article: article, content: content, leadImage: article.leadImageURL.flatMap { ReaderDocument.leadRepeats(in: article.html, lead: $0) ? nil : paths[$0] }, offline: true)
        try document.write(to: index(article.id), atomically: true, encoding: .utf8)
        try signature(article).write(to: folder.appending(path: "source.txt"), atomically: true, encoding: .utf8)
    }

    func isReady(_ article: ArticleContent) -> Bool {
        FileManager.default.fileExists(atPath: index(article.id).path) &&
        (try? String(contentsOf: folder(article.id).appending(path: "source.txt"), encoding: .utf8)) == signature(article)
    }

    func delete(_ id: UUID) throws {
        let path = folder(id)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }

    func recordFailure(_ id: UUID) throws {
        let folder = folder(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(Date.now).write(to: folder.appending(path: "retry.json"), options: .atomic)
    }

    func retryDate(_ id: UUID, attempts: Int, fallback: Date) -> Date {
        let date = (try? Data(contentsOf: folder(id).appending(path: "retry.json"))).flatMap { try? JSONDecoder().decode(Date.self, from: $0) } ?? fallback
        let delay = [60.0, 600.0, 3600.0][min(max(attempts - 1, 0), 2)]
        return date.addingTimeInterval(delay)
    }

    func storageBytes() -> Int64 {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }

    func clearImages() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let images = folder.appending(path: "img")
            if FileManager.default.fileExists(atPath: images.path) { try FileManager.default.removeItem(at: images) }
            let index = folder.appending(path: "index.html")
            if let html = try? String(contentsOf: index, encoding: .utf8) {
                let withoutImages = HTMLAssets.replacing(#"<img\b[^>]*>"#, in: html, with: "")
                try withoutImages.write(to: index, atomically: true, encoding: .utf8)
            }
        }
    }

    func purgeOrphans(keeping ids: Set<UUID>) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            if let id = UUID(uuidString: folder.lastPathComponent), !ids.contains(id) { try FileManager.default.removeItem(at: folder) }
        }
    }

    private func signature(_ article: ArticleContent) -> String {
        SHA256.hash(data: Data((ReaderDocument.version + article.title + article.site + String(article.minutes) + (article.leadImageURL ?? "") + article.html).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func copyFonts(to folder: URL) throws {
        for name in Fonts.resourceNames {
            guard let source = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            let target = folder.appending(path: "\(name).ttf")
            if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
        }
    }
}
