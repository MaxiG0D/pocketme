import SwiftUI

struct MacShareView: View {
    let flow: ShareFlow

    var body: some View {
        HStack(spacing: 14) {
            thumbnail.frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(flow.title).font(Typo.cardTitleSerif).lineLimit(2)
                Text(flow.site).font(Typo.meta).foregroundStyle(Theme.muted)
                Text(status).font(Typo.sans(12.5).weight(.medium))
                    .foregroundStyle(flow.errorMessage == nil ? Theme.success : Theme.muted)
            }
            Spacer(minLength: 0)
            indicator
        }
        .foregroundStyle(Theme.ink)
        .padding(18).frame(width: 400, height: 100)
        .background(Theme.paper)
        .onExitCommand { flow.finish() }
        .animation(.snappy, value: flow.saved)
    }

    private var status: String {
        flow.errorMessage ?? (flow.saved ? "Saved to PocketMe" : "Saving…")
    }

    @ViewBuilder private var indicator: some View {
        if flow.errorMessage != nil {
            Button("Done") { flow.finish() }.buttonStyle(SecondaryButtonStyle())
        } else if flow.saved {
            Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.onAccent).frame(width: 30, height: 30)
                .background(Theme.success, in: Circle())
        } else {
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let data = flow.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else { GeneratedCoverView(siteName: flow.site) }
    }
}
