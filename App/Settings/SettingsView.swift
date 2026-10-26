import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @State private var bytes: Int64 = 0
    @State private var clear = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings").font(Typo.largeTitle).tracking(-0.5).foregroundStyle(Theme.ink)
                section("iCloud") {
                    Label(store.persistence?.mode == .cloud ? "iCloud sync is on" : "Saved on this device", systemImage: store.persistence?.mode == .cloud ? "icloud" : "internaldrive")
                        .font(Typo.button).foregroundStyle(Theme.ink)
                    if store.persistence?.mode != .cloud {
                        Text("iCloud is unavailable. Your articles are saved on this device.").font(Typo.meta).foregroundStyle(Theme.muted)
                    }
                }
                section("Offline reading") {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " stored on this device")
                        .font(Typo.meta).foregroundStyle(Theme.muted)
                    Button("Clear downloaded images") { clear = true }.buttonStyle(SecondaryButtonStyle())
                }
                section("Reader defaults") { ReaderSettingsControls() }
                section("About") {
                    Text("PocketMe").font(Typo.cardTitleSerif).foregroundStyle(Theme.ink)
                    Text("Newsreader and Inter · SIL Open Font License\nReadability 0.6.0 · Apache License 2.0").font(Typo.meta).foregroundStyle(Theme.muted)
                    ForEach(["Newsreader-OFL", "Inter-OFL", "Readability-Apache-2.0"], id: \.self) { name in
                        if let text = license(name) {
                            DisclosureGroup(name.replacingOccurrences(of: "-OFL", with: "").replacingOccurrences(of: "-Apache-2.0", with: "")) {
                                Text(text).font(Typo.sans(11)).foregroundStyle(Theme.muted).textSelection(.enabled)
                            }.font(Typo.meta).tint(Theme.ink)
                        }
                    }
                }
            }.padding(Theme.gutter).frame(maxWidth: 620)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(Theme.paper).tint(Theme.ink)
            .task { bytes = await store.processor?.assets.storageBytes() ?? 0 }
            .confirmationDialog("Clear downloaded images?", isPresented: $clear, titleVisibility: .visible) {
                Button("Clear images", role: .destructive) {
                    Task {
                        do { try await store.processor?.assets.clearImages(); bytes = await store.processor?.assets.storageBytes() ?? 0 }
                        catch { store.errorMessage = "Downloaded images couldn’t be cleared. Please try again." }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).kicker()
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func license(_ name: String) -> String? {
        let ext = name == "Readability-LICENSE" ? "md" : "txt"
        return Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

#if DEBUG
#Preview("Light") { PreviewHost { store, articles in SettingsView().frame(width: 390, height: 844) }.preferredColorScheme(.light) }
#Preview("Dark") { PreviewHost { store, articles in SettingsView().frame(width: 390, height: 844) }.preferredColorScheme(.dark) }
#endif
