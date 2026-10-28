import SwiftUI

/// Theater mode: a playing video glides to the middle of the window while the rest of the app dims around it.
enum Theater {
    /// A warm near-black, so the dimmed app reads as lights down rather than a cold void.
    static let shade = Color(red: 0.067, green: 0.059, blue: 0.051)
    static let ink = Color(red: 0.96, green: 0.93, blue: 0.88)
    /// Glides in and settles with a little life, like the app's other springs.
    static let spring = Animation.spring(duration: 0.6, bounce: 0.16)
    static let fade = Animation.easeInOut(duration: 0.25)

    /// The largest 16:9 width that fits `stage` with room left around it.
    static func videoWidth(in stage: CGSize, mac: Bool) -> CGFloat {
        let side: CGFloat = mac ? 48 : 12
        // Tall screens leave room for the lights-on button above the picture; a phone on its side has none to spare.
        let top: CGFloat = mac ? 64 : (stage.height > 700 ? 100 : 56)
        return max(0, min(stage.width - side * 2, (stage.height - top * 2) * 16 / 9))
    }
}

extension LibraryStore {
    func setTheater(_ on: Bool, reduceMotion: Bool = false) {
        guard theater != on else { return }
        withAnimation(reduceMotion ? Theater.fade : Theater.spring) { theater = on }
    }
}

/// Dims a part of the app that sits beside the reader; a click on it brings the lights back.
struct TheaterShade: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Theater.shade.opacity(store.theater ? 0.92 : 0).ignoresSafeArea()
            .contentShape(Rectangle()).onTapGesture { store.setTheater(false, reduceMotion: reduceMotion) }
            .allowsHitTesting(store.theater).accessibilityHidden(true)
    }
}
