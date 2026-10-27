import Foundation
import Testing
@testable import PocketMe

struct VideoLinkTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
        "https://youtube.com/watch?feature=share&v=dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"
    ])
    func recognizesYouTube(_ url: String) {
        #expect(VideoLink(url) == VideoLink("https://youtu.be/dQw4w9WgXcQ"))
        #expect(VideoLink(url)?.provider == .youtube)
    }

    @Test func recognizesVimeo() {
        #expect(VideoLink("https://vimeo.com/76979871")?.id == "76979871")
        #expect(VideoLink("https://vimeo.com/channels/staffpicks/76979871")?.id == "76979871")
        #expect(VideoLink("https://player.vimeo.com/video/76979871")?.provider == .vimeo)
    }

    @Test(arguments: ["https://www.youtube.com/", "https://www.youtube.com/@SkillUp", "https://www.youtube.com/watch",
                      "https://vimeo.com/about", "https://example.com/watch?v=dQw4w9WgXcQ", "https://youtu.be/<script>"])
    func ignoresOtherLinks(_ url: String) {
        #expect(VideoLink(url) == nil)
    }

    @Test func embedUsesPrivacyEnhancedPlayer() {
        #expect(VideoLink("https://youtu.be/dQw4w9WgXcQ")?.embedURL.host() == "www.youtube-nocookie.com")
    }

    @Test func readsDescriptionFromPlayerData() {
        let page = #"..."lengthSeconds":"1707","shortDescription":"Line one\nSee https://example.com/a?b=1&c=2.\n\n\"Quoted\" & more","isCrawlable":true"#
        let description = VideoMetadata.jsonString(after: "\"shortDescription\":", in: page)
        #expect(description == "Line one\nSee https://example.com/a?b=1&c=2.\n\n\"Quoted\" & more")
        #expect(VideoMetadata.jsonString(after: "\"lengthSeconds\":", in: page) == "1707")
        #expect(VideoMetadata.html(description ?? "") ==
                #"<p>Line one<br>See <a href="https://example.com/a?b=1&amp;c=2">https://example.com/a?b=1&amp;c=2</a>.</p><p>&quot;Quoted&quot; &amp; more</p>"#)
    }
}
