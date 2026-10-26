import CoreText
import Foundation
import Testing
@testable import PocketMe

struct FoundationTests {
    @Test func bundledFontsResolveToTheirRealFamilies() throws {
        Fonts.register()
        for (postScriptName, family) in [("Newsreader16pt-Regular", "Newsreader"), ("Inter-Regular", "Inter")] {
            let font = CTFontCreateWithName(postScriptName as CFString, 16, nil)
            #expect(CTFontCopyFamilyName(font) as String == family)
        }
    }

    @Test func coverPaletteIsStableAndCaseInsensitive() {
        #expect(Theme.coverIndex(for: "slowmag") == 7)
        #expect(Theme.coverIndex(for: " Slowmag ") == Theme.coverIndex(for: "slowmag"))
    }
}
