import SwiftUI

struct SavedSheetView: View {
    let flow: ShareFlow

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: flow.saved ? "checkmark" : "link")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.onAccent).frame(width: 28, height: 28)
                        .background(Theme.success, in: Circle())
                    Text(flow.saved ? "Saved to PocketMe" : "Save to PocketMe")
                        .font(Typo.sans(17).weight(.semibold))
                }
                HStack(spacing: 12) {
                    thumbnail.frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(flow.title).font(Typo.cardTitleSerif).lineLimit(3)
                        Text(flow.site).font(Typo.meta).foregroundStyle(Theme.muted)
                        Text(flow.errorMessage ?? (flow.saved ? "Will download for offline" : "Saving…"))
                            .font(Typo.sans(12.5).weight(.medium)).foregroundStyle(flow.errorMessage == nil ? Theme.success : Theme.muted)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
                HStack(spacing: 10) {
                    Button("Read now") { flow.readNow() }.buttonStyle(PrimaryButtonStyle(fill: Theme.accent, foreground: Theme.onAccent)).disabled(!flow.saved)
                    Button("Done") { flow.finish() }.buttonStyle(SecondaryButtonStyle())
                }
            }
            .foregroundStyle(Theme.ink).padding(22)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 10).padding(.bottom, 34)
        }
        .font(Typo.meta).simultaneousGesture(TapGesture().onEnded { flow.keepOpen() })
        #if os(iOS)
        .sensoryFeedback(.success, trigger: flow.saved)
        #endif
    }

    @ViewBuilder private var thumbnail: some View {
        #if os(iOS)
        if let data = flow.thumbnail, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
        } else { GeneratedCoverView(siteName: flow.site) }
        #else
        if let data = flow.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else { GeneratedCoverView(siteName: flow.site) }
        #endif
    }
}

#Preview("Light") { Fonts.register(); return SavedSheetView(flow: ShareFlow()).frame(width: 390, height: 500).preferredColorScheme(.light) }
#Preview("Dark") { Fonts.register(); return SavedSheetView(flow: ShareFlow()).frame(width: 390, height: 500).preferredColorScheme(.dark) }
