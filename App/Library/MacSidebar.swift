import SwiftUI

struct MacSidebar: View {
    @Binding var section: LibrarySection
    let unread: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("PocketMe").font(Typo.serif(22)).foregroundStyle(Theme.ink).padding(.horizontal, 12).padding(.top, 24)
            VStack(spacing: 4) {
                ForEach(LibrarySection.allCases) { choice in
                    Button { section = choice } label: {
                        HStack(spacing: 10) {
                            Image(systemName: choice.icon).font(.system(size: 17, weight: .regular)).frame(width: 20)
                            Text(choice.title).font(Typo.sans(14))
                            Spacer()
                            if choice == .unread { Text(String(unread)).font(Typo.sans(14)).foregroundStyle(Theme.muted) }
                        }.foregroundStyle(Theme.ink).padding(.horizontal, 12).frame(height: 36)
                            .background(section == choice ? Theme.sidebarSelection : Theme.sidebar.opacity(0), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityAddTraits(section == choice ? .isSelected : [])
                }
            }
            Spacer()
        }.padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
    }
}

#if DEBUG && os(macOS)
#Preview("Light") { PreviewHost { store, articles in MacSidebar(section: .constant(.unread), unread: 7).frame(width: 240, height: 800) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in MacSidebar(section: .constant(.unread), unread: 7).frame(width: 240, height: 800) }.preferredColorScheme(.dark) }
#endif
