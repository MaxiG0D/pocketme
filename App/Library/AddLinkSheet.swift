import SwiftUI

struct AddLinkSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Save a link").font(Typo.sheetTitle).foregroundStyle(Theme.ink)
            TextField("https://", text: $link).font(Typo.sans(16)).textFieldStyle(.plain)
                .padding(14).background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                .focused($focused).onSubmit(save)
                #if os(iOS)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                #endif
            if let message = store.errorMessage { Text(message).font(Typo.meta).foregroundStyle(Theme.muted) }
            Button("Save", action: save).buttonStyle(PrimaryButtonStyle(fill: Theme.accent, foreground: Theme.onAccent)).disabled(link.isEmpty)
            Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
        }.padding(22).background(Theme.surface).onAppear { if link.isEmpty, let copied = Clipboard.link { link = copied }; focused = true }
        .presentationDetents([.height(320), .large]).presentationDragIndicator(.visible).presentationCornerRadius(26).presentationBackground(Theme.surface)
    }
    private func save() { if store.saveLink(link) != nil { dismiss() } }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in AddLinkSheet().frame(width: 390) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in AddLinkSheet().frame(width: 390) }.preferredColorScheme(.dark) }
#endif
