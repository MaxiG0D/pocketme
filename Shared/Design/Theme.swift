import SwiftUI

enum Theme {
    static let paper = Color("Paper")
    static let surface = Color("Surface")
    static let sidebar = Color("Sidebar")
    static let ink = Color("Ink")
    static let body = Color("Body")
    static let muted = Color("Muted")
    static let hairline = Color("Hairline")
    static let chip = Color("Chip")
    static let accent = Color("Accent")
    static let success = Color("Success")
    static let pending = Color("Pending")
    static let pendingDot = Color("PendingDot")
    static let pillInactiveText = Color("PillInactiveText")
    static let onAccent = Color("OnAccent")
    static let coverChip = Color("CoverChip")
    static let coverChipInk = Color("CoverChipInk")
    static let progressTrack = Color("ProgressTrack")
    static let emptyBody = Color("EmptyBody")
    static let sidebarSelection = Color("SidebarSelection")
    static let cardSelection = Color("CardSelection")
    static let previewBody = Color("PreviewBody")
    static let themeBorder = Color("ThemeBorder")
    static let segmentSelected = Color("SegmentSelected")
    static let sepiaPaper = Color("SepiaPaper")
    static let sepiaInk = Color("SepiaInk")
    static let readerLightPaper = Color("ReaderLightPaper")
    static let readerLightInk = Color("ReaderLightInk")
    static let readerDarkPaper = Color("ReaderDarkPaper")
    static let readerDarkInk = Color("ReaderDarkInk")
    static let gutter: CGFloat = 20
    static let rowThumb: CGFloat = 76
    static let radiusThumb: CGFloat = 12
    static let radiusHero: CGFloat = 16
    static let radiusSheet: CGFloat = 28

    struct CoverPalette {
        let background: Color
        let foreground: Color
    }

    // Paired colors stay the same in light and dark appearance.
    static let covers: [CoverPalette] = [
        .init(background: Color("Cover0"), foreground: Color("CoverLightInk")),
        .init(background: Color("Cover1"), foreground: Color("CoverDarkInk")),
        .init(background: Color("Cover2"), foreground: Color("CoverDarkInk")),
        .init(background: Color("Cover3"), foreground: Color("CoverDarkInk")),
        .init(background: Color("Cover4"), foreground: Color("CoverDarkInk")),
        .init(background: Color("Cover5"), foreground: Color("CoverLightInk")),
        .init(background: Color("Cover6"), foreground: Color("CoverLightInk")),
        .init(background: Color("Cover7"), foreground: Color("CoverDarkInk"))
    ]

    /// FNV-1a, unlike Swift Hasher, is stable across app launches and devices.
    static func coverIndex(for siteName: String) -> Int {
        let key = siteName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hash = key.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return Int(hash % UInt64(covers.count))
    }
}
