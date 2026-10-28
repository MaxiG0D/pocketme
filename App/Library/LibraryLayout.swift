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

/// The two layouts crossfade.
extension AnyTransition {
    static func libraryLayout(reduceMotion: Bool) -> AnyTransition {
        // Pure opacity: the identical headers crossfade without wobbling.
        .opacity
    }
}

extension Animation {
    static let libraryLayout = Animation.smooth(duration: 0.32)
}
