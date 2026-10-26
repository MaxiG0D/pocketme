import SwiftUI

struct ReaderSettingsControls: View {
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(ReaderPreferences.self) private var preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                Button { preferences.resize(-1) } label: { Text("A").font(Typo.sans(14).weight(.semibold)).frame(width: 44, height: 44).background(Theme.chip, in: Circle()) }
                    .accessibilityLabel("Decrease font size").disabled(preferences.size <= 15)
                GeometryReader { geometry in
                    Capsule().fill(Theme.chip)
                    Capsule().fill(Theme.ink).frame(width: geometry.size.width * (preferences.size - 15) / 10)
                }.frame(height: 4).accessibilityLabel("Font size \(Int(preferences.size))")
                Button { preferences.resize(1) } label: { Text("A").font(Typo.sans(21).weight(.semibold)).frame(width: 44, height: 44).background(Theme.chip, in: Circle()) }
                    .accessibilityLabel("Increase font size").disabled(preferences.size >= 25)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 10) {
                Text("Theme").kicker()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicType.isAccessibilitySize ? 2 : 4), spacing: 10) {
                    ForEach(ReaderPreferences.ThemeChoice.allCases, id: \.self) { theme in
                        Button { preferences.theme = theme } label: {
                            VStack(spacing: 4) {
                                Text("Aa").font(Typo.cardTitleSerif)
                                Text(theme.label).font(Typo.sans(13).weight(.semibold))
                            }.frame(maxWidth: .infinity).frame(minHeight: 64)
                                .foregroundStyle(theme.ink).background(theme.paper, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(preferences.theme == theme ? Theme.accent : Theme.themeBorder, lineWidth: preferences.theme == theme ? 2 : 1))
                        }.buttonStyle(.plain).accessibilityAddTraits(preferences.theme == theme ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Font").kicker()
                HStack(spacing: 0) {
                    Button { preferences.sans = false } label: { Text("Serif").font(Typo.serif(16)).frame(maxWidth: .infinity).frame(minHeight: 42).background(preferences.sans ? Theme.chip : Theme.segmentSelected, in: RoundedRectangle(cornerRadius: 10)) }.accessibilityAddTraits(preferences.sans ? [] : .isSelected)
                    Button { preferences.sans = true } label: { Text("Sans").font(Typo.sans(15)).frame(maxWidth: .infinity).frame(minHeight: 42).background(preferences.sans ? Theme.segmentSelected : Theme.chip, in: RoundedRectangle(cornerRadius: 10)) }.accessibilityAddTraits(preferences.sans ? .isSelected : [])
                }.buttonStyle(.plain).padding(4).background(Theme.chip, in: RoundedRectangle(cornerRadius: 14))
            }
        }.foregroundStyle(Theme.ink).padding(20).background(Theme.surface)

    }
}


#if DEBUG
#Preview("Light") { PreviewHost { _, _ in ReaderSettingsControls().frame(width: 390) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { _, _ in ReaderSettingsControls().frame(width: 390) }.preferredColorScheme(.dark) }
#endif
