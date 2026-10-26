# iPhone Duo redesign notes
Journey: Library (list, search, add) → Reader → Reader settings → Settings, plus Mac and iPad regular layout
Stack: SwiftUI, iOS 18 / macOS 15 targets, XcodeGen; audited from code only (no Xcode or simulator in this environment)
Stage: 5  Next: run the Duo simulator checks (fold, Split View, overflow) and eyeball the list, reader bar and coral on a device

## Findings
- Tab bar: opaque UITabBarAppearance overrode the system glass bar Max chose. Change — system glass on iOS 26+ [tab-bars, materials]
- Library header (title, search, +) was a hand-built row in the scroll view. Change — large title, searchable and toolbar items [checklist §2]
- Reader header was a hand-built 44pt bar. Change — system bar with Back, Reader settings and Share on iOS and iPadOS; Mac keeps its own [checklist §2, §3]
- Regular width used a custom HStack with a fixed 360pt list. Change — one NavigationSplitView at every width [checklist §5, §6]
- Row swipe was a hand-built DragGesture. Change — List with swipeActions [gestures]
- Mac list had 44pt of traffic-light inset on iOS and iPad too. Change — fixed [layout]
- Mac list rows were tap gestures with no button or selected trait. Change — fixed [accessibility]
- Reader font-size slider was not adjustable by VoiceOver. Change — fixed [accessibility]
- Reduce Motion ignored for row and list transitions. Change — fixed [accessibility]
- Add-link sheet: fixed 320pt detent, no grabber. Change — fixed [sheets]
- Mac menu bar lacked list toggle and text size commands. Change — fixed [toolbars: macOS]
- White on coral was 3.75:1, white on dark-mode green 3.33:1. Change — light coral #C7461C, dark-mode text on accent #1A1A1A [accessibility]
- Ready: Dynamic Type via relativeTo, 44pt controls, size classes (no UIScreen or idiom checks), multiple scenes, all orientations, sheet drag-to-dismiss

## Decisions
- Library and Reader bars: managed toolbar (user, 2026-10-26)
- Regular-width layout: NavigationSplitView (user, 2026-10-26)
- Row swipe: List with swipeActions (user, 2026-10-26)
- Coral: darken for text contrast (user, 2026-10-26)

## Done / verified
- Fixes above — CI build and tests on push; Duo simulator not run
