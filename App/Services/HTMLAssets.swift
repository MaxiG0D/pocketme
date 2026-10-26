import Foundation

/// Extraction serializes sanitized DOM to quoted attributes, so the offline pass never parses arbitrary source pages.
enum HTMLAssets {
    static func images(in html: String) -> [String] {
        matches(#"<img\b[^>]*\bsrc\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#, in: html).compactMap {
            guard let range = Range($0.range(at: 1), in: html) else { return nil }
            return unescape(String(html[range]))
        }
    }

    static func rewrite(_ html: String, paths: [String: String]) -> String {
        var output = html
        for match in matches(#"<img\b[^>]*\bsrc\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#, in: html).reversed() {
            guard let range = Range(match.range, in: output), let srcRange = Range(match.range(at: 1), in: output) else { continue }
            let original = unescape(String(output[srcRange]))
            if let path = paths[original] { output.replaceSubrange(srcRange, with: path) }
            else { output.removeSubrange(range) }
        }
        return replacing(#"\s+srcset\s*=\s*([\"']).*?\1"#, in: output, with: "")
    }

    static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]).matches(in: text, range: NSRange(text.startIndex..., in: text))) ?? []
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&#x27;", with: "'")
    }
}
