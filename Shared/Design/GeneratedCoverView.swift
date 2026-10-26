import SwiftUI

struct GeneratedCoverView: View {
    let siteName: String

    private var name: String {
        let trimmed = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "PocketMe" : trimmed
    }

    var body: some View {
        GeometryReader { geometry in
            let palette = Theme.covers[Theme.coverIndex(for: name)]
            let inset = geometry.size.width * 0.12
            ZStack(alignment: .topLeading) {
                palette.background
                Text(String(name.prefix(1)).uppercased())
                    // Covers are artwork: their lettering keeps its size whatever the Dynamic Type setting.
                    .font(Font.custom("Newsreader16pt-Regular", fixedSize: geometry.size.height * 0.45).weight(.semibold))
                    .padding(inset)
                VStack {
                    Spacer(minLength: 0)
                    Text(name.uppercased())
                        .font(Font.custom("Inter-Regular", fixedSize: 9).weight(.bold))
                        .tracking(0.5)
                        .lineLimit(1)
                        .padding(inset)
                }
            }
            .foregroundStyle(palette.foreground)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cover for \(name)")
    }
}

#Preview("Light") {
    Fonts.register()
    return GeneratedCoverView(siteName: "Slowmag")
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusThumb, style: .continuous))
        .padding().background(Theme.paper).preferredColorScheme(.light)
}

#Preview("Dark") {
    Fonts.register()
    return GeneratedCoverView(siteName: "Build Weekly")
        .frame(width: 240, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusThumb, style: .continuous))
        .padding().background(Theme.paper).preferredColorScheme(.dark)
}
