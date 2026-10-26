import Foundation
import UniformTypeIdentifiers

enum ShareInput {
    @MainActor
    static func link(from items: [NSExtensionItem]) async throws -> URL {
        let providers = items.flatMap { $0.attachments ?? [] }
        for type in [UTType.url.identifier, UTType.plainText.identifier] {
            for provider in providers where provider.hasItemConformingToTypeIdentifier(type) {
                let string: String? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                        if let url = item as? URL { continuation.resume(returning: url.absoluteString) }
                        else if let text = item as? String { continuation.resume(returning: text) }
                        else if let data = item as? Data { continuation.resume(returning: String(data: data, encoding: .utf8)) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                guard let string else { continue }
                if (try? URLNormalizer.normalize(string)) != nil,
                   let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) { return url }
                let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                if let match = detector.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
                   let url = match.url, (try? URLNormalizer.normalize(url.absoluteString)) != nil { return url }
            }
        }
        throw URLNormalizer.InvalidURL.unsupported
    }
}
