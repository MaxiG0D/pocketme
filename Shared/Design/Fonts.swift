import CoreText
import Foundation
import SwiftUI

/// Explicit registration also supports macOS, extensions and Xcode previews.
enum Fonts {
    static let resourceNames = ["Newsreader", "Inter"]

    static func register() {
        for name in resourceNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font: \(name)")
                continue
            }
            // Already-registered fonts are harmless (iOS also reads UIAppFonts).
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum Typo {
    static let largeTitle = serif(34, relativeTo: .largeTitle)
    static let heroTitle = serif(23, relativeTo: .title2)
    static let readerH1 = serif(31, relativeTo: .title)
    static let sheetTitle = serif(26, relativeTo: .title2)
    static let cardTitleSerif = serif(18, relativeTo: .headline)
    static let rowTitle = sans(15.5, relativeTo: .headline).weight(.semibold)
    static let meta = sans(13, relativeTo: .footnote)
    static let kicker = sans(12, relativeTo: .caption).weight(.semibold)
    static let pill = sans(14, relativeTo: .subheadline).weight(.medium)
    static let button = sans(15, relativeTo: .body).weight(.semibold)
    static let tab = sans(11, relativeTo: .caption2).weight(.semibold)

    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom("Newsreader16pt-Regular", size: size, relativeTo: style).weight(.semibold)
    }

    static func sans(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom("Inter-Regular", size: size, relativeTo: style)
    }
}
