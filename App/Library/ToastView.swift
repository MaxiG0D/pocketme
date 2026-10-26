import SwiftUI

/// A short confirmation pill at the bottom of the library, with Undo when the action can be reversed.
struct ToastView: View {
    let store: LibraryStore
    var body: some View {
        if let toast = store.toast {
            HStack(spacing: 14) {
                Text(toast.text).font(Typo.button)
                if let undo = toast.undo {
                    Button("Undo") { undo(); store.dismissToast() }
                        .font(Typo.button).buttonStyle(.plain).underline().frame(minHeight: 44)
                }
            }
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 22).padding(.vertical, toast.undo == nil ? 12 : 0)
            .background(Theme.ink, in: Capsule())
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
