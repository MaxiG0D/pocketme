import Foundation

enum URLNormalizer {
    enum InvalidURL: Error, LocalizedError {
        case unsupported
        var errorDescription: String? { "Enter a complete http or https link." }
    }

    static func normalize(_ raw: String) throws -> String {
        guard var parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil else { throw InvalidURL.unsupported }
        parts.scheme = scheme
        parts.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        parts.fragment = nil
        if parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath.removeLast() }
        let tracking: Set<String> = ["fbclid", "gclid", "mc_cid", "mc_eid", "ref", "ref_src"]
        let items = zip(parts.queryItems ?? [], parts.percentEncodedQueryItems ?? []).map { (decoded: $0, encoded: $1) }
            .filter { !tracking.contains($0.decoded.name.lowercased()) && !$0.decoded.name.lowercased().hasPrefix("utm_") }
            .sorted {
                if $0.decoded.name != $1.decoded.name { return $0.decoded.name < $1.decoded.name }
                if $0.decoded.value == nil { return $1.decoded.value != nil }
                if $0.decoded.value != $1.decoded.value { return ($0.decoded.value ?? "") < ($1.decoded.value ?? "") }
                return ($0.encoded.value ?? "") < ($1.encoded.value ?? "")
            }
        // Preserve escaping: converting %2B to a bare + changes many servers' query semantics.
        parts.percentEncodedQueryItems = items.isEmpty ? nil : items.map(\.encoded)
        guard let result = parts.url?.absoluteString else { throw InvalidURL.unsupported }
        return result
    }
}
