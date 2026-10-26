import SwiftUI

struct EmptyStateView: View {
    let paste: () -> Void
    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Theme.covers[4].background).rotationEffect(.degrees(-8))
                RoundedRectangle(cornerRadius: 16).fill(Theme.covers[7].background).rotationEffect(.degrees(6))
                RoundedRectangle(cornerRadius: 16).fill(Theme.surface).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
                VStack(alignment: .leading, spacing: 9) {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.covers[3].background).frame(height: 40)
                    Capsule().fill(Theme.chip).frame(height: 8)
                    Capsule().fill(Theme.chip).frame(width: 55, height: 8)
                }.padding(17)
            }.frame(width: 120, height: 120).accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("Nothing saved yet").font(Typo.sheetTitle).foregroundStyle(Theme.ink)
                Text("Save anything you want to read later. It downloads for offline and shows up on your Mac too.")
                    .font(Typo.sans(15)).foregroundStyle(Theme.emptyBody).multilineTextAlignment(.center).lineSpacing(1.5)
            }
            VStack(spacing: 10) {
                #if os(macOS)
                step(1, text: "In Safari or any app, click **Share**, then **PocketMe**")
                step(2, text: "Or paste a link in the field up top")
                #else
                step(1, text: "In Safari or any app, tap **Share**, then **PocketMe**")
                step(2, text: "Or copy a link and tap **+** up top")
                #endif
            }
            Button("Paste link from clipboard", action: paste).buttonStyle(PrimaryButtonStyle())
        }.frame(maxWidth: 420).padding(.horizontal, 32).padding(.vertical, 32)
    }
    private func step(_ number: Int, text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(String(number)).font(Typo.pill).frame(width: 28, height: 28).background(Theme.chip, in: Circle())
            Text(text).font(Typo.sans(14)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.foregroundStyle(Theme.ink).padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in EmptyStateView(paste: {}).frame(width: 390) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in EmptyStateView(paste: {}).frame(width: 390) }.preferredColorScheme(.dark) }
#endif
