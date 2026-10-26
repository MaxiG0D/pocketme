import SwiftUI

struct ReaderSettingsSheet: View {
    var body: some View {
        ScrollView { ReaderSettingsControls() }
            .background(Theme.surface)
            .presentationDetents([.height(330), .large]).presentationCornerRadius(26)
            .presentationBackground(Theme.surface).presentationDragIndicator(.visible)
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in ReaderSettingsSheet().frame(width: 390) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in ReaderSettingsSheet().frame(width: 390) }.preferredColorScheme(.dark) }
#endif
