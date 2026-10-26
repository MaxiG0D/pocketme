import SwiftUI

struct AddLinkSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    private var valid: Bool { (try? URLNormalizer.normalize(link)) != nil }

    var body: some View {
        content
            .onAppear { if link.isEmpty, let copied = Clipboard.link { link = copied }; focused = true }
            .onChange(of: link) { _, _ in error = nil }
    }

    #if os(macOS)
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save a link").font(Typo.serif(20, relativeTo: .title3)).foregroundStyle(Theme.ink)
            field
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    .buttonStyle(CompactButtonStyle(fill: Theme.chip, foreground: Theme.ink))
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(!valid)
                    .buttonStyle(CompactButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
            }
        }
        .padding(20).background(Theme.paper)
    }
    #else
    private var content: some View {
        NavigationStack {
            field.padding(.horizontal, Theme.gutter).padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.paper)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                    ToolbarItem(placement: .principal) { Text("Save a link").font(Typo.serif(18, relativeTo: .headline)).foregroundStyle(Theme.ink) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold).tint(Theme.accent).disabled(!valid) }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.paper, for: .navigationBar)
        }
        .tint(Theme.ink)
        .presentationDetents([.height(error == nil ? 150 : 180)]).presentationCornerRadius(Theme.radiusSheet)
        .presentationBackground(Theme.paper)
    }
    #endif

    private var field: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "link").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(valid ? Theme.accent : Theme.muted).accessibilityHidden(true)
                TextField("Paste a link", text: $link).font(Typo.sans(15)).textFieldStyle(.plain)
                    .foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                    .focused($focused).onSubmit { if valid { save() } }
                    .accessibilityLabel("Link")
                    #if os(iOS)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.done)
                    #endif
                if !link.isEmpty {
                    Button { link = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.muted.opacity(0.7)).accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 14).frame(minHeight: fieldHeight)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1))
            if let error { Text(error).font(Typo.meta).foregroundStyle(Theme.accent).padding(.horizontal, 4) }
        }
    }

    #if os(macOS)
    private let fieldHeight: CGFloat = 40
    #else
    private let fieldHeight: CGFloat = 48
    #endif

    private func save() {
        if store.saveLink(link) != nil { dismiss() } else { error = store.errorMessage }
    }
}

#if os(macOS)
/// Mac sheet buttons sit compact and right-aligned, per the HIG.
private struct CompactButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Typo.sans(13).weight(.semibold))
            .padding(.horizontal, 16).frame(minWidth: 76, minHeight: 30)
            .background(fill, in: Capsule()).foregroundStyle(foreground)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}
#endif

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in AddLinkSheet().frame(width: 420) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in AddLinkSheet().frame(width: 420) }.preferredColorScheme(.dark) }
#endif
