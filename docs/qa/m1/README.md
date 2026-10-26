# Milestone 1 verification

Verified locally on 2026-10-26 with Xcode 27.1 and XcodeGen 2.46.0.

- XcodeGen creates all four targets; generated project is ignored.
- iOS Simulator app + embedded iOS share extension build successfully.
- Native macOS app + embedded Mac share extension build successfully.
- Both Swift Testing tests pass: bundled fonts resolve to Newsreader/Inter, and cover selection is stable across launches/case/whitespace.
- iPhone simulator launches the empty Reading screen in light and dark mode; largest Dynamic Type does not clip.
- Native Mac launches the empty Reading screen in light mode; the same view was rendered through NSHostingView and visually checked in dark mode.
- Unsigned local Mac and iOS archives complete through the applet backend.
- Release applet compiles with Swift 6 strict concurrency. Its actual Run Tests and Build and Open buttons succeed.
- GitHub Actions contains the platform builds, tests and applet build. Remote CI has not run; nothing has been committed or pushed.

Screenshots: [iPhone light](iphone-light.png), [iPhone dark](iphone-dark.png), [largest Dynamic Type](iphone-dynamic-type.png), [Mac light](mac-light.png), [Mac dark render](mac-dark-render.png), [release applet](release-applet.png).

## UI specification checklist

- [ ] Compared against private mockup artboards at exactly the reference sizes. Private canvas is unavailable; full library UI belongs to M5.
- [x] No system blue in the product content.
- [x] No default List insets or separators on the Reading screen.
- [x] Product text uses Newsreader/Inter (font families independently tested).
- [x] Light background is paper, not white.
- [ ] Row thumbnails are 76×76 with radius 12. Not applicable yet: rows belong to M5.
- [x] M1 iPhone header uses the 20pt gutter and 8pt top inset; no hero/row spacing to evaluate yet.
- [x] Largest Dynamic Type checked on iPhone without clipping.
- [x] iPhone dark mode checked; native Mac dark view rendered and visually checked.
- [x] Light/dark iPhone screenshots saved alongside this file. No PR has been created.

The release applet deliberately retains the Carnet template's fonts, grouped forms and layout at Max's explicit request; it is separate from the product design system. Actual uploads/publishing are unavailable until M7. Device installation needs the owner's signing team and has not been exercised on physical devices.
