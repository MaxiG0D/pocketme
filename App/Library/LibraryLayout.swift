import SwiftUI

/// List or grid. Each device keeps its own choice, so the phone can stay a list while the Mac shows a grid.
enum LibraryLayout: String {
    case list, grid
    static let storageKey = "libraryLayout"
    var other: LibraryLayout { self == .list ? .grid : .list }
    /// The toggle shows where it goes, not where you are.
    var toggleSymbol: String { self == .list ? "square.grid.2x2" : "list.bullet" }
    var toggleLabel: String { self == .list ? "Show as grid" : "Show as list" }
}

/// Cards slide apart and settle while the two layouts crossfade; Reduce Motion keeps only the fade.
extension AnyTransition {
    static func libraryLayout(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985))
    }
}

extension Animation {
    static let libraryLayout = Animation.smooth(duration: 0.32)
}
