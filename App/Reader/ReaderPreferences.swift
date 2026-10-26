import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class ReaderPreferences {
    enum ThemeChoice: String, CaseIterable { case light, sepia, dark, auto
        var label: String { rawValue.capitalized }
        var paper: Color { switch self { case .light: Theme.readerLightPaper; case .sepia: Theme.sepiaPaper; case .dark: Theme.readerDarkPaper; case .auto: Theme.paper } }
        var ink: Color { switch self { case .light: Theme.readerLightInk; case .sepia: Theme.sepiaInk; case .dark: Theme.readerDarkInk; case .auto: Theme.ink } }
    }
    var size: Double { didSet { defaults.set(size, forKey: "readerSize") } }
    var theme: ThemeChoice { didSet { defaults.set(theme.rawValue, forKey: "readerTheme") } }
    var sans: Bool { didSet { defaults.set(sans, forKey: "readerSans") } }
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if os(macOS)
        let defaultSize = 21.0
        #else
        let defaultSize = 19.0
        #endif
        let stored = defaults.double(forKey: "readerSize")
        size = stored == 0 ? defaultSize : min(max(stored, 15), 25)
        theme = ThemeChoice(rawValue: defaults.string(forKey: "readerTheme") ?? "auto") ?? .auto
        sans = defaults.bool(forKey: "readerSans")
    }
    func resize(_ delta: Double) { size = min(max(size + delta, 15), 25) }
}
