import SwiftUI

@main
struct PocketMeApp: App {
    @State private var store: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @State private var updater = AppUpdater()
    #endif
    init() {
        Fonts.register()
        let store = LibraryStore()
        _store = State(initialValue: store)
        BackgroundRefresh.register(store: store)
        #if os(iOS)
        // iOS 26 and later draw the system glass bar, which ignores per-item glyph colors; only the selected tint applies there.
        if #unavailable(iOS 26) { configureTabBar() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            LibraryHostView(store: store)
                .environment(store)
                .environment(store.readerPreferences)
                .font(Typo.meta)
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .task { await store.open() }
                .onOpenURL { url in Task { await store.openLink(url) } }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refresh()
                        Task { await store.drainInbox() }
                    } else if phase == .background { store.persist(); BackgroundRefresh.schedule() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.check() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Save a link") { store.focusPasteToken += 1 }.keyboardShortcut("n")
                Button("Search") { store.findToken += 1 }.keyboardShortcut("f")
            }
            CommandGroup(after: .toolbar) {
                Button("as List") { store.requestedLayout = .list }.keyboardShortcut("1")
                Button("as Grid") { store.requestedLayout = .grid }.keyboardShortcut("2")
                Button("Show or Hide List") { store.toggleListToken += 1 }.keyboardShortcut("s", modifiers: [.command, .control])
                Divider()
                Button("Bigger Text") { store.readerPreferences.resize(1) }.keyboardShortcut("+")
                Button("Smaller Text") { store.readerPreferences.resize(-1) }.keyboardShortcut("-")
            }
        }
        #endif
        #if os(macOS)
        Settings {
            SettingsView().environment(store).environment(store.readerPreferences).frame(width: 560, height: 720)
        }
        #endif
    }
    #if os(iOS)
    private func configureTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "Paper")?.withAlphaComponent(0.96)
        appearance.shadowColor = UIColor(named: "Hairline")
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = UIColor(named: "Icon")
            layout.selected.iconColor = UIColor(named: "IconSelected")
            var normal: [NSAttributedString.Key: Any] = [:]
            var selected: [NSAttributedString.Key: Any] = [:]
            if let font = UIFont(name: "Inter-Regular_SemiBold", size: 11) { normal[.font] = font; selected[.font] = font }
            normal[.foregroundColor] = UIColor(named: "Icon"); selected[.foregroundColor] = UIColor(named: "IconSelected")
            layout.normal.titleTextAttributes = normal; layout.selected.titleTextAttributes = selected
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    #endif
}
