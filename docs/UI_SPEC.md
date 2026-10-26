# PocketMe: UI Spec (read this before writing any view)

This is the companion to `docs/IMPLEMENTATION_PLAN.md`. It turns the approved mockups into exact numbers and SwiftUI patterns. **When this file and your instinct disagree, this file wins.** When it is silent, copy the nearest thing that it does specify.

The design goal in one sentence: **clean but warm, like a well-made paper magazine, not like a settings screen.**

---

## 1. The ten rules (violating any of these = redo the view)

1. **Never use `List` or `Form` with default styling for content screens.** No inset grouped backgrounds, no grey section headers, no chevrons. Use `ScrollView` + `LazyVStack` (iPhone) or `LazyVGrid` (Mac) with our own rows. (`List` is allowed only on the iPhone Settings tab and in the Mac sidebar.)
2. **Never use system colors** (`.blue`, `.gray`, `Color(.systemBackground)`, `.secondary`, `.accentColor` defaults). Every color comes from `Theme`. Set `.tint(Theme.accent)` once on the root.
3. **The background is never pure white** in light mode. It is `paper #FAFAF8`. Pure white (`surface`) is only for cards and sheets that sit on top of paper.
4. **Two fonts only:** Newsreader for titles and article text, Inter for everything else. Never SF Pro for visible text (SF Symbols for icons are fine).
5. **No shadows** except on floating sheets (`0 20 50 rgba(0,0,0,0.25)` on the Saved sheet and `0 -10 40 rgba(0,0,0,0.12)` on the reader settings sheet). No gradients. No blur materials except the tab bar.
6. **Dividers are 1pt `hairline` lines**, full width of the text column, never inset with a leading gap like the system list separators.
7. **Thumbnails are always on the right** in iPhone rows, always 76×76, radius 12, and `.clipped()` with `.aspectRatio(contentMode: .fill)`.
8. **One accent, used sparingly:** the `+` button, the progress bars, the selected ring in reader settings, the primary "Read now"/"Save" buttons. Nothing else is coral. Text links are `ink`, not coral.
9. **Nothing floats over article text.** No floating buttons in the reader.
10. **Generous whitespace.** If in doubt, add space, not lines or boxes.

---

## 2. Tokens (`Shared/Design/Theme.swift`)

```swift
import SwiftUI

enum Theme {
    // Colors (light / dark), defined in the asset catalog as Color Sets with Any/Dark appearances
    static let paper    = Color("Paper")    // #FAFAF8 / #141414
    static let surface  = Color("Surface")  // #FFFFFF / #1E1E1C
    static let sidebar  = Color("Sidebar")  // #F1F1EC / #1A1A18
    static let ink      = Color("Ink")      // #1A1A1A / #EDEDE8
    static let body     = Color("Body")     // #262624 / #D6D6D0
    static let muted    = Color("Muted")    // #6B6B66 / #9C9C95
    static let hairline = Color("Hairline") // #ECECE7 / white 8%
    static let chip     = Color("Chip")     // #EEEEEA / #2A2A28
    static let accent   = Color("Accent")   // #E2562B both
    static let success  = Color("Success")  // #3D7A4F / #5C9A6E
    static let pending  = Color("Pending")  // dot #C79A2E, label #8A6A1F / #D9B25A

    // Spacing
    static let gutter: CGFloat = 20        // iPhone screen side padding
    static let rowThumb: CGFloat = 76
    static let radiusThumb: CGFloat = 12
    static let radiusHero: CGFloat = 16
    static let radiusSheet: CGFloat = 28
}

enum Typo {
    // Newsreader
    static let largeTitle = Font.custom("Newsreader", size: 34).weight(.semibold)   // tracking -0.5
    static let heroTitle  = Font.custom("Newsreader", size: 23).weight(.semibold)   // line spacing 1.2
    static let readerH1   = Font.custom("Newsreader", size: 31).weight(.semibold)
    static let sheetTitle = Font.custom("Newsreader", size: 26).weight(.semibold)
    static let cardTitleSerif = Font.custom("Newsreader", size: 18).weight(.semibold)
    // Inter
    static let rowTitle   = Font.custom("Inter", size: 15.5).weight(.semibold)      // line height 1.3
    static let meta       = Font.custom("Inter", size: 13)                          // muted
    static let kicker     = Font.custom("Inter", size: 12).weight(.semibold)        // UPPERCASE, tracking 0.4, muted
    static let pill       = Font.custom("Inter", size: 14).weight(.medium)
    static let button     = Font.custom("Inter", size: 15).weight(.semibold)
    static let tab        = Font.custom("Inter", size: 11).weight(.semibold)
}
```

Use `relativeTo:` on the custom fonts (`Font.custom("Inter", size: 13, relativeTo: .footnote)`) so Dynamic Type works.

Reusable modifiers you **must** create and use instead of re-styling ad hoc:

```swift
extension View {
    func kicker() -> some View {            // "SLOWMAG · 11 MIN"
        self.font(Typo.kicker).textCase(.uppercase).tracking(0.4).foregroundStyle(Theme.muted)
    }
}

struct PillButtonStyle: ButtonStyle {     // filter pills "Unread · 12" / "Archive"
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.pill)
            .padding(.horizontal, 14).frame(height: 34)
            .background(selected ? Theme.ink : Theme.chip, in: Capsule())
            .foregroundStyle(selected ? Theme.paper : Color("PillInactiveText")) // #4A4A4A / #BDBDB6
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {  // full-width 50pt capsule: "Paste link from clipboard", "Archive"
    var fill: Color = Theme.ink
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.button)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(fill, in: Capsule())
            .foregroundStyle(Theme.paper)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle { /* same shape, background Theme.chip, text Theme.ink */ }

struct CircleIconButtonStyle: ButtonStyle { /* 44×44 circle; .plain = transparent; .accent = Theme.accent fill + white icon */ }
```

Icons: SF Symbols at `.font(.system(size: 20, weight: .regular))`. Mapping: search `magnifyingglass`, add `plus` (weight .semibold), back `chevron.left`, share `square.and.arrow.up`, archive `archivebox`, favorite `bookmark` / `bookmark.fill`, settings `gearshape`, library `book`, downloading = a 6pt `Theme.pending` circle (not a symbol).

---

## 3. iPhone screens (frame: 390×844 reference)

### 3.1 Library (Unread)

```
┌──────────────────────────────────────┐
│ (safe area)                          │
│ Reading                    (🔍) (+)  │  ← largeTitle, 44pt buttons, + is accent circle
│ [Unread · 12] [Archive]              │  ← pills, gap 6, 16pt below title row
│                                      │  ← 20pt
│ ┌──────────────────────────────────┐ │
│ │      hero image 196pt tall       │ │  ← radius 16
│ │ [Continue · 6 min left]          │ │  ← white 92% chip, 12pt semibold, 12pt inset bottom-left
│ └──────────────────────────────────┘ │
│ SLOWMAG · 11 MIN                     │  ← kicker, 12pt below image
│ The quiet return of reading things   │  ← heroTitle (Newsreader 23)
│ all the way through                  │
│ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░░░░░░░░░░░░░░░░  │  ← 4pt progress bar, accent on #E6E6E1, radius 2
│                                      │  ← 22pt
│ ──────────────────────────────────── │  ← hairline
│ Title, semibold Inter 15.5,   ┌────┐ │
│ up to 3 lines                 │76² │ │  ← row: 12pt vertical padding, 14pt gap
│ Site · 9 min                  └────┘ │  ← meta, muted
│ ──────────────────────────────────── │
│ …                                    │
├──────────────────────────────────────┤
│  Library     Favorites     Settings  │  ← tab bar
└──────────────────────────────────────┘
```

Structure:

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 0) {
        LibraryHeader(...)                    // title row + pills
            .padding(.bottom, 20)
        if let current = continueReading {
            ContinueReadingCard(article: current)
                .padding(.bottom, 22)
        }
        LazyVStack(spacing: 0) {
            ForEach(articles) { a in
                ArticleRow(article: a)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }
    }
    .padding(.horizontal, Theme.gutter)
}
.background(Theme.paper)
.scrollIndicators(.hidden)
```

- Hide the navigation bar (`.toolbar(.hidden, for: .navigationBar)`) and draw our own title row; it must **not** collapse into an inline title.
- Title row: top padding = 8pt below the safe area. `HStack { Text("Reading").font(Typo.largeTitle).tracking(-0.5); Spacer(); search; add }`, the buttons with a gap of 4.
- Swipe actions: since we do not use `List`, implement a custom `SwipeableRow` (drag gesture, reveal width 96, snap threshold 60, full swipe > 70% width triggers). Trailing reveals **Archive** (background `Theme.success`, white `archivebox` icon above the label "Archive", Inter 12 semibold). Leading reveals **Favorite** (background `Theme.ink`). Also add a `.contextMenu` with Favorite, Archive, Copy link and Delete (destructive).
- Row title: max 3 lines, `.multilineTextAlignment(.leading)`, and `.fixedSize(horizontal: false, vertical: true)`.
- Pending row: meta line shows `Site · 9 min` + 6pt amber dot + "Downloading" in `Theme.pending`, Inter 13.
- Failed row: meta shows "Couldn't load · " plus a "Retry" text button in `ink` underline.
- Tapping a row pushes the reader (`NavigationStack` path). Tapping the hero card opens the reader at the saved position.

### 3.2 Thumbnails

```swift
struct ArticleThumb: View {
    let article: Article; let size: CGSize; let radius: CGFloat
    var body: some View {
        Group {
            if let data = article.thumbnailData, let img = PlatformImage(data: data) {
                Image(platformImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                GeneratedCoverView(siteName: article.siteName)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
```

`GeneratedCoverView`: `ZStack(alignment: .topLeading)` with the background color from the palette; an initial in Newsreader semibold at **45% of the height** (34pt at 76); a site name in Inter 9pt bold uppercase tracking 0.5 at the bottom-left; padding = 12% of the width. The text color is the palette's paired foreground. Always use `.continuous` corner style.

### 3.3 Reader

- `NavigationStack` push, with the system nav bar **hidden**; custom top bar: `HStack { back(44) ; Spacer(); "Aa" button (Newsreader 17 semibold, 44×44); share(44) }`, padded 12 horizontally. Under it, a 2pt bar: track `ink.opacity(0.06)`, fill `accent`, width = progress.
- The web content handles all the article layout (section 5). The top bar stays visible (it does not hide on scroll in v1).
- Swipe from the left edge to go back must keep working (do not break the interactive pop gesture when hiding the nav bar: use `.navigationBarBackButtonHidden()` plus a custom back button, and keep the gesture via a small UIKit helper if needed).

### 3.4 Reader settings sheet

`.sheet` with `.presentationDetents([.height(330), .large])`, `.presentationCornerRadius(26)`, `.presentationBackground(Theme.surface)`, and a visible drag indicator. Content padding 20, vertical spacing 22:
1. Size row: `A` button (44 circle, chip background, Inter 14 semibold), a 4pt track with an ink fill showing the position, and an `A` button (Inter 21 semibold).
2. "THEME" kicker, then a 4-column grid with gap 10: each tile is 64pt tall, radius 14, filled with that theme's paper color, with "Aa" (Newsreader 18) above the label (Inter 13 semibold) in that theme's ink. The selected tile gets a 2pt accent stroke; others a 1pt `#E0E0DA` stroke.
3. "FONT" kicker, then a segmented control drawn by us: a chip-colored container with radius 14 and padding 4; segments 42pt tall with radius 10, the selected one on `segmentSelected` (`#FFFFFF`, dark `#3A3A37`, always lighter than the container). "Serif" is set in Newsreader 16, "Sans" in Inter 15.

The article behind the sheet updates live.

### 3.5 Saved sheet (Share extension)

The extension view itself (not a system sheet), bottom-aligned card: horizontal margin 10, bottom margin 34, radius 28, `paper` background, padding 22, vertical spacing 18, with the shadow from rule 5.
- Header: a 28pt `success` circle with a white checkmark (`checkmark`, bold, 16pt), then "Saved to PocketMe" in Inter 17 semibold, gap 10.
- Card: `surface`, radius 16, 1pt hairline border, padding 12. An 84×84 thumbnail, then a VStack (gap 5) with the title (Newsreader 18 semibold, 3 lines max), `Site · N min` (or just the site, until it is known) and "Will download for offline" in `success`, Inter 12.5 medium.
- Buttons: a 2-column grid with gap 10: **Read now** (accent fill, white text) and **Done** (chip, ink text), each 50pt tall capsules.

### 3.6 Empty state

Centered column, horizontal padding 32, spacing 26:
- Illustration: three 120×120 rounded rectangles (radius 16) stacked with rotations of -8° (`#E6DEEA`), +6° (`#DCE3EC`) and 0° (`surface` with a hairline border, holding a 40pt tinted block and two 8pt grey bars). Build it in SwiftUI, not as an image.
- "Nothing saved yet": sheetTitle (Newsreader 26).
- Body: Inter 15, line spacing 1.5, color `#5E5E59` (dark: `#A8A8A1`). Text: "Save anything you want to read later. It downloads for offline and shows up on your Mac too."
- Two step cards (`surface`, radius 14, hairline border, padding 14): a numbered 28pt chip circle, then the text with **bold** keywords.
- Step text: "In Safari or any app, tap **Share**, then **PocketMe**" and "Or copy a link and tap **+** up top" (Mac: "click", and "Or paste a link in the field up top").
- While the library is empty, the header shows only the title and `+` (no search button, no Unread/Archive pills).
- Primary button "Paste link from clipboard" (`PrimaryButtonStyle`, ink fill).

### 3.7 Tab bar

The system `TabView` (on iOS 26 this is the native floating glass bar, which is the approved look), tinted: `.tint(Theme.ink)` for the selected item and `Theme.muted` for unselected (set via `UITabBarAppearance` in the app init: background `paper` at 96% opacity, a hairline shadow color, and Inter 11 for the item titles). Icons: `book`, `bookmark`, `gearshape`.

---

## 4. Mac screens

### 4.1 Library window

Always list + reader side by side. There is no sidebar, no card grid and no preview pane.

```
┌ ● ● ●  ─────────────────┬─ reader ──────────────────────────────┐
│ (+) [Unread 16][Fav][Arch]│ ▣     article title        Aa ☆ ⎙     │
│ ▢ title · meta           │                                       │
│ ▢ title · meta           │ article…                              │
└──────────────────────────┴───────────────────────────────────────┘
```

- **List column**: 360 wide, `paper` background, a hairline between it and the reader. Below the traffic lights (44 top padding) is one row: the **+** button, then the section tabs.
- **+ button**: an accent 28pt circle with a white plus. If the clipboard holds a link it saves it; otherwise it opens the Add link sheet. ⌘N does the same and ⌘V saves a pasted link. There is no paste field.
- **Tabs**: capsules 28 tall (Inter 13), selected = `#E4E4DE` / dark `#2A2A28`, with the unread count in `muted`.
- **Rows**: 56pt thumbnail (radius 10), title Inter 14 semibold (2 lines), then the meta. 8pt padding, radius 12. The selected row uses `cardSelection`; hover is the same at 50%. Single click reads the article in place; ↑/↓ move between rows.
- **Selection**: on launch and when switching sections, the most recently opened article in the section is selected (else the first). When a section is empty the reader area shows the empty state.
- **Hide list**: the `sidebar.left` button at the left of the reader header collapses the list for focused reading (animated, 0.25s). When hidden, the header leaves 76pt for the traffic lights.
- Remove the default toolbar background so the window feels like one sheet of paper: `.toolbarBackground(.hidden, for: .windowToolbar)` and a unified compact title bar.

### 4.2 Mac reader

- Fills the pane to the right of the list. The header bar is 52 tall: the hide-list toggle at the left (no back button, since there is nothing to go back to), the centered article title (Inter 13 semibold, muted, one line truncated), then the `Aa`, favorite and share buttons (34×30, radius 8). Under it, the 2pt progress bar.
- The article column is max 680 wide and centered, with 56 top padding. H1 is Newsreader 46 semibold with tracking -0.6; the body is Newsreader 21 with line height 1.65. All of this is in CSS (section 5), and the Mac CSS just uses larger values via a `.mac` class on `<html>`.

---

## 5. Reader HTML/CSS (where most of the "feel" lives)

`reader.css` core (variables are set from Swift):

```css
:root {
  --paper:#FAFAF8; --ink:#1A1A1A; --body:#262624; --muted:#6B6B66; --hair:rgba(0,0,0,.06); --accent:#E2562B;
  --font-body:"Newsreader", Georgia, serif; --font-ui:"Inter", -apple-system, sans-serif;
  --size:19px; --measure:34rem;
}
html.sepia { --paper:#F4ECDC; --ink:#2B2418; --body:#3A3022; --muted:#6E6150; }
html.dark  { --paper:#141414; --ink:#EDEDE8; --body:#D6D6D0; --muted:#9C9C95; --hair:rgba(255,255,255,.08); }
html.sans  { --font-body:"Inter", -apple-system, sans-serif; }
html.mac   { --measure:40rem; }

body { margin:0; background:var(--paper); color:var(--body); font:400 var(--size)/1.6 var(--font-body);
       -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility; }
main { max-width:var(--measure); margin:0 auto; padding:22px 26px 48px; }
.kicker { font:600 12px/1 var(--font-ui); letter-spacing:.4px; text-transform:uppercase; color:var(--muted); margin-bottom:16px; }
h1 { font:600 31px/1.15 "Newsreader", Georgia, serif; letter-spacing:-.3px; color:var(--ink); margin:0 0 16px; }
html.mac h1 { font-size:46px; line-height:1.1; letter-spacing:-.6px; }
.lead { width:100%; aspect-ratio:16/9; object-fit:cover; border-radius:14px; margin:0 0 20px; }
p { margin:0 0 1em; }
h2, h3 { font-family:"Newsreader", Georgia, serif; color:var(--ink); line-height:1.25; margin:1.6em 0 .5em; }
img { max-width:100%; height:auto; border-radius:10px; }
figure { margin:1.4em 0; } figcaption { font:13px/1.4 var(--font-ui); color:var(--muted); margin-top:8px; }
blockquote { margin:1.4em 0; padding-left:1em; border-left:2px solid var(--hair); font-style:italic; color:var(--ink); }
a { color:var(--ink); text-decoration-thickness:1px; text-underline-offset:3px; }
pre, code { font-family:ui-monospace, Menlo, monospace; font-size:.85em; }
pre { overflow-x:auto; background:var(--hair); padding:12px 14px; border-radius:10px; }
hr { border:0; border-top:1px solid var(--hair); margin:2em 0; }
.end { margin-top:40px; padding-top:26px; border-top:1px solid var(--hair); text-align:center; font-family:var(--font-ui); }
.end .done { font-size:13px; color:var(--muted); margin-bottom:14px; }
.btn { display:flex; align-items:center; justify-content:center; gap:8px; height:50px; border-radius:25px;
       font:600 15px var(--font-ui); border:0; width:100%; }
.btn.primary { background:var(--ink); color:var(--paper); }
.btn.outline { height:46px; background:transparent; color:var(--ink); border:1px solid var(--hair); }
.row2 { display:grid; grid-template-columns:1fr 1fr; gap:10px; margin-top:10px; }
.upnext { text-align:left; margin-top:28px; }
```

The Readability output often contains junk: strip empty `<p>`, inline `style` and `width`/`height` attributes on images, `<script>`, `<iframe>` (replace YouTube iframes with a link card), and `font`/`center` tags before saving `contentHTML`.

---

## 6. Motion and feel

- Use `.animation(.snappy(duration: 0.25), value:)` for pill selection, swipe snaps and favorite toggles. No bouncy springs.
- Archiving a row: the row slides out and the list closes the gap with `.transition(.move(edge: .trailing).combined(with: .opacity))`.
- Haptics (iOS): `.sensoryFeedback(.success, trigger:)` on save, archive and favorite.
- Images fade in over 0.2s when the thumbnail data arrives. Never show a grey spinner in a thumbnail slot; show the generated cover until the image is ready.
- No skeleton shimmer, no confetti.

---

## 7. Dark mode

Every token has a dark value (section 2). Check each screen in dark mode before opening the PR. Thumbnails and covers keep their colors in dark mode. The selected pill becomes `ink` (light text color) with `paper` text, which is correct and intended.

---

## 8. Visual QA checklist (put this in every UI PR description and tick it)

- [ ] Compared side-by-side with the matching mockup artboard at the same size (iPhone 16 / 390pt wide; Mac 1440×900).
- [ ] No system blue anywhere (tint, selection, links, toggles).
- [ ] No default `List` insets or separators on content screens.
- [ ] All text is Newsreader or Inter; there are no SF Pro labels.
- [ ] The background is `paper`, not white, in light mode.
- [ ] Row thumbnails are 76×76 on the right with radius 12, continuous corners.
- [ ] Spacing matches: 20 gutter, 16 under the title, 20 above the hero, 22 below it, and 12 row padding.
- [ ] Works at the largest Dynamic Type size without clipping (rows grow; thumbnails stay 76).
- [ ] Dark mode checked.
- [ ] Screenshots of light and dark attached to the PR.

---

## 9. Previews and sample data

Create `SampleData.swift` with 8 articles: a mix of with-thumbnail, without (generated cover), pending, failed, long title (3 lines), and short title. The site names to use are Slowmag, Build Weekly, Kitchen Notes, Wayfarer, Green Room. Every view has `#Preview("Light")` and `#Preview("Dark")` using an in-memory `ModelContainer` seeded with this data. Use previews to verify against the mockups before running the app.
