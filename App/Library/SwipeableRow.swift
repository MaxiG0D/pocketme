import SwiftUI

struct SwipeableRow<Content: View>: View {
    let open: () -> Void
    let archive: () -> Void
    let favorite: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var offset: CGFloat = 0
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        content().hidden().overlay {
          GeometryReader { geometry in
            ZStack {
                HStack(spacing: 0) {
                    action("Favorite", symbol: "bookmark", color: Theme.ink, perform: favorite)
                    Spacer(minLength: 0)
                    action("Archive", symbol: "archivebox", color: Theme.success, perform: archive)
                }
                content().offset(x: offset + drag).onTapGesture {
                    if offset == 0 { open() } else { offset = 0 }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 20)
                    .updating($drag) { value, state, _ in
                        if abs(value.translation.width) > abs(value.translation.height) { state = value.translation.width }
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        let amount = offset + value.translation.width
                        if abs(amount) > geometry.size.width * 0.7 {
                            if amount < 0 { archive() } else { favorite() }
                            offset = 0
                        } else { offset = amount < -60 ? -96 : amount > 60 ? 96 : 0 }
                    })
            }.clipped()
        }
        }
        .clipped()
        .animation(.snappy(duration: 0.25), value: offset)
        .accessibilityAction(named: "Archive", archive)
        .accessibilityAction(named: "Favorite", favorite)
    }
    private func action(_ label: String, symbol: String, color: Color, perform: @escaping () -> Void) -> some View {
        Button { offset = 0; perform() } label: {
            VStack(spacing: 6) { Image(systemName: symbol).font(.system(size: 20)); Text(label).font(Typo.sans(12).weight(.semibold)) }
                .frame(width: 96).frame(maxHeight: .infinity).foregroundStyle(Theme.onAccent).background(color)
        }.buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in if let a = articles.first { SwipeableRow(open: {}, archive: {}, favorite: {}) { ArticleRow(article: a) }.frame(width: 390) } }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in if let a = articles.first { SwipeableRow(open: {}, archive: {}, favorite: {}) { ArticleRow(article: a) }.frame(width: 390) } }.preferredColorScheme(.dark) }
#endif
