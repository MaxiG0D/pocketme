import Foundation
import Testing
@testable import PocketMe

struct URLNormalizerTests {
    @Test(arguments: [
        ("HTTPS://WWW.Example.COM/story/?utm_source=mail&z=2&a=1#part", "https://example.com/story?a=1&z=2"),
        ("http://www.example.com/", "http://example.com"),
        ("https://example.com/Path/?a=2&a=1&fbclid=x&gclid=y&mc_cid=z&mc_eid=q&ref=q&ref_src=q", "https://example.com/Path?a=1&a=2"),
        ("https://example.com/?UTM_Medium=x&a&b=", "https://example.com?a&b="),
        ("https://example.com/a%2Fb/?q=hello%20world&x=%26", "https://example.com/a%2Fb?q=hello%20world&x=%26"),
        ("https://example.com/?literal=%2B&space=+", "https://example.com?literal=%2B&space=+"),
        ("  https://example.com/a?useful=1  ", "https://example.com/a?useful=1")
    ])
    func canonicalLinks(input: String, expected: String) throws {
        #expect(try URLNormalizer.normalize(input) == expected)
        #expect(try URLNormalizer.normalize(expected) == expected)
    }

    @Test(arguments: ["", "a sentence", "file:///tmp/file", "ftp://example.com", "https:///", "https://user:password@example.com"])
    func rejectsUnsupportedLinks(_ input: String) {
        #expect(throws: URLNormalizer.InvalidURL.self) { try URLNormalizer.normalize(input) }
    }

    @Test func keepsMeaningfulDifferences() throws {
        #expect(try URLNormalizer.normalize("http://example.com/Path") != URLNormalizer.normalize("https://example.com/Path"))
        #expect(try URLNormalizer.normalize("https://example.com/Path") != URLNormalizer.normalize("https://example.com/path"))
    }
}
