import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum Clipboard {
    @MainActor static var link: String? {
        #if os(iOS)
        let text = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string
        #else
        let text = NSPasteboard.general.string(forType: .URL) ?? NSPasteboard.general.string(forType: .string)
        #endif
        guard let text, (try? URLNormalizer.normalize(text)) != nil else { return nil }
        return text
    }
    @MainActor static func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
