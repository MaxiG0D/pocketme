# iPhone Duo redesign notes
Journey: Library (list, search, add) → Reader → Reader settings → Settings, plus Mac and iPad regular layout
Stack: SwiftUI, iOS 18 / macOS 15 targets, XcodeGen; audited from code only (no Xcode or simulator in this environment)
Stage: 3  Next: Max picks the pending decisions below; then build and run the Duo simulator checks

## Findings
- Tab bar: opaque UITabBarAppearance overrode the system glass bar Max chose. Change — system glass on iOS 26+ [tab-bars, materials]
- Library header (title, search, +) is a hand-built row in the scroll view, nav bar hidden. Decision [checklist §2]
- Reader header is a hand-built 44pt bar, nav and tab bars hidden. It will not go vertical on the Duo outer display. Decision [checklist §2, §3]
- Regular width (iPad, Duo inner) uses a custom HStack with a fixed 360pt list. No fold handling. Decision [checklist §5, §6]
- Row swipe is a hand-built DragGesture, not List swipeActions. Decision [gestures: supplement standard gestures]
- Mac list had 44pt of traffic-light inset on iOS and iPad too. Change — fixed [layout]
- Mac list rows were tap gestures with no button or selected trait. Change — fixed [accessibility]
- Reader font-size slider was not adjustable by VoiceOver. Change — fixed [accessibility]
- Reduce Motion ignored for row and list transitions. Change — fixed [accessibility]
- Add-link sheet: fixed 320pt detent, no grabber. Change — fixed [sheets]
- Mac menu bar lacked list toggle and text size commands. Change — fixed [toolbars: macOS]
- White on coral is 3.75:1, white on dark-mode green is 3.33:1. Passes only as bold text (3:1). Decision [accessibility]
- Ready: Dynamic Type via relativeTo, 44pt controls, size classes (no UIScreen or idiom checks), multiple scenes, all orientations, sheet drag-to-dismiss

## Decisions
- Library and Reader bars: recommended managed toolbar; chosen pending
- Regular-width layout: recommended NavigationSplitView; chosen pending
- Row swipe: recommended List with swipeActions; chosen pending

## Done / verified
- Fixes above — CI build and tests on push; Duo simulator not run
