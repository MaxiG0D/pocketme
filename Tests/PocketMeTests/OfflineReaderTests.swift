import Foundation
import Testing
@testable import PocketMe

@MainActor
struct OfflineReaderTests {
    @Test func offlineDocumentAndFontsRemainOnDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let article = Article(url: "https://example.com/a", title: "A <safe> title", siteName: "Slowmag")
        article.contentHTML = Data("<p>Readable without a network connection.</p>".utf8)
        article.readingMinutes = 1
        let snapshot = ArticleContent(article)
        let store = OfflineAssetStore(root: root)
        try await store.prepare(snapshot)
        #expect(await store.isReady(snapshot))
        let html = try String(contentsOf: store.index(article.id), encoding: .utf8)
        #expect(html.contains("Readable without a network connection."))
        #expect(html.contains("A &lt;safe&gt; title"))
        #expect(html.contains("data-action=\"archive\""))
        #expect(html.contains("script-src 'none'"))
        #expect(FileManager.default.fileExists(atPath: store.folder(article.id).appending(path: "Newsreader.ttf").path))
        #expect(FileManager.default.fileExists(atPath: store.folder(article.id).appending(path: "Inter.ttf").path))
        try await store.delete(article.id)
        #expect(!FileManager.default.fileExists(atPath: store.index(article.id).path))
    }

    @Test func cachedImagesSurviveAnOfflineTemplateRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let article = Article(url: "https://example.invalid/story", title: "Offline refresh", siteName: "Example")
        article.contentHTML = Data("<p>Keep the text and image.</p><img src=\"https://example.invalid/photo.png\">".utf8)
        let store = OfflineAssetStore(root: root)
        let images = store.folder(article.id).appending(path: "img")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let filename = "6376b715542b03afe3375bae23f46e82add569ad.png"
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jh1sAAAAASUVORK5CYII=")!
        try png.write(to: images.appending(path: filename))
        try await store.prepare(ArticleContent(article))
        let html = try String(contentsOf: store.index(article.id), encoding: .utf8)
        #expect(html.contains("img/" + filename))
        #expect(try Data(contentsOf: images.appending(path: filename)) == png)
        try await store.purgeOrphans(keeping: [])
        #expect(!FileManager.default.fileExists(atPath: store.folder(article.id).path))
    }

    @Test func imageRewritingKeepsTextAndDropsUncachedImages() {
        let input = "<p>Keep me</p><img src=\"https://example.com/a.jpg?q=1&amp;x=2\" srcset=\"one 1x, two 2x\"><img src='https://example.com/missing.jpg'>"
        let result = HTMLAssets.rewrite(input, paths: ["https://example.com/a.jpg?q=1&x=2": "img/a.jpg"])
        #expect(result.contains("<p>Keep me</p>"))
        #expect(result.contains("src=\"img/a.jpg\""))
        #expect(!result.contains("srcset"))
        #expect(!result.contains("missing.jpg"))
    }

    @Test func settingsSurviveRecreationAndClampSize() {
        let suite = "PocketMeTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ReaderPreferences(defaults: defaults)
        settings.theme = .sepia; settings.sans = true; settings.resize(100)
        let reopened = ReaderPreferences(defaults: defaults)
        #expect(reopened.theme == .sepia && reopened.sans)
        #expect(reopened.size == 25)
        reopened.resize(-100)
        #expect(reopened.size == 15)
    }
}
