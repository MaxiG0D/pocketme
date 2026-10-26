# PocketMe: Implementation Plan

A calm, warm, minimal read-it-later app (Pocket/Instapaper alternative) for a small group of people (the owner, friends and family). v1 targets **iPhone and Mac**. iPad comes almost for free from the same code; a **web** client comes later.

Approved mockups: private design canvas owned by the project owner. `docs/UI_SPEC.md` transcribes them exactly, so treat it as the source of truth for look and feel.

Repo: `github.com/MaxiG0D/pocketme` (currently empty).

---

## 0. How to use this plan (for the coding agent)

- **Read `docs/UI_SPEC.md` before writing any SwiftUI view.** It holds the exact sizes, fonts, colors, layouts, reusable styles and a visual QA checklist. UI quality is the main point of this app, and "looks like a default SwiftUI List" is a failed milestone.
- Work **milestone by milestone** (section 9). One milestone ≈ one pull request. Do not start the next milestone until the current one builds and its acceptance criteria pass.
- Keep it simple. If a choice is not specified here, pick the most boring, native Apple option.
- **Do not add features that are not listed.** In particular: no highlights, tags, notes, text-to-speech, social features, recommendations, accounts or analytics.
- Every PR must build for both iOS and macOS in CI (section 8) and keep tests green.
- Prefer SwiftUI everywhere. Use AppKit/UIKit only where SwiftUI cannot do the job (for example `WKWebView` wrappers).

---

## 1. Product scope

### v1 must have
1. **Save a link**:
   - from the iOS Share Sheet (Share extension), and from the macOS Share menu (Share extension);
   - by pasting a link inside the app (`+` button on iPhone, "Paste a link to save" field on Mac);
   - "Paste link from clipboard" on the empty state.
2. **Automatic extraction**: title, site name, author (if any), estimated reading time, lead image and clean article HTML.
3. **Offline by default**: every saved article (text and inline images) is downloaded automatically. There is no "make available offline" toggle.
4. **Clean reader**: serif typography, three themes (Light, Sepia, Dark, plus Auto following the system), font size, Serif/Sans choice. Reading position is remembered and synced.
5. **Library**: Unread and Archive lists, plus Favorites. Thumbnail-led list (iPhone) or grid (Mac). A "Continue reading" hero card for the most recently opened unfinished article.
6. **Archive**: swipe to archive in lists, and an Archive button at the **end** of the article. Nothing floats over the text while reading.
7. **Favorites**: toggle from the reader end card, swipe action and Mac preview pane.
8. **iCloud sync** between the user's own devices (private CloudKit database). No custom backend, no sign-up.
9. **Delete** an article (swipe or context menu, with confirmation).

### Explicitly out of scope for v1
Highlights, tags, folders, search across full text (title search only is fine), TTS, sharing lists between users, import from Pocket/Instapaper, push notifications, widgets, iPad-specific layouts beyond what SwiftUI gives for free, web client.

---

### Owner-authorized one-off migration (2026-10-26)

Max requested an Instapaper migration performed here, with no in-app import flow. A macOS Debug-only developer launch argument may import prepared link metadata through the signed app’s normal SwiftData container. For this migration, import only the 14 unread links; exclude all archived links. Keep the personal export and payload out of the repository. This does not add an Instapaper account integration to v1.

---

## 2. Tech stack and decisions

| Area | Decision | Why |
|---|---|---|
| Language | Swift 6, strict concurrency on | Current standard |
| UI | SwiftUI, multiplatform | One codebase for iPhone, iPad and Mac |
| Min OS | iOS 18, macOS 15 | Mature SwiftData + CloudKit, modern SwiftUI APIs |
| Persistence | SwiftData | Native, works with CloudKit |
| Sync | SwiftData's built-in CloudKit mirroring (private DB) | Zero backend; users sign in with their Apple ID already |
| Project generation | **XcodeGen** (`project.yml` committed, `.xcodeproj` git-ignored) | Readable diffs; agents can edit YAML safely |
| Article extraction | Mozilla **Readability.js** (`@mozilla/readability` 0.6.0, Apache-2.0) run inside an off-screen `WKWebView` | Best-in-class extraction; handles JS-rendered pages |
| Link metadata in the Share extension | `LinkPresentation` (`LPMetadataProvider`) | Fast title and image for the "Saved" sheet |
| Reader rendering | `WKWebView` loading a local HTML template + CSS | Proper typography; offline images via local file URLs |
| Fonts | Bundle **Newsreader** (serif) and **Inter** (sans), both SIL OFL from Google Fonts | Matches the approved mockups. Include the OFL license files. |
| Dependencies | None via SPM in v1 (Readability.js is a vendored JS file) | Keep it small |
| Tests | Swift Testing (`import Testing`) | Modern default |

---

## 3. Design system (from the mockups)

The look is **"clean but warm"**: off-white paper, warm greys, bookish serif, one coral accent. Avoid pure white backgrounds, cool blue greys, gradients and heavy shadows.

Put these in `Shared/Design/Theme.swift` as a single source of truth.

**Colors**

| Token | Light | Dark |
|---|---|---|
| `paper` (app background) | `#FAFAF8` | `#141414` |
| `surface` (cards, sheets) | `#FFFFFF` | `#1E1E1C` |
| `sidebar` (Mac) | `#F1F1EC` | `#1A1A18` |
| `ink` (primary text) | `#1A1A1A` | `#EDEDE8` |
| `body` (article text) | `#262624` | `#D6D6D0` |
| `muted` (secondary text) | `#6B6B66` | `#9C9C95` |
| `hairline` (dividers) | `#ECECE7` | `rgba(255,255,255,0.08)` |
| `chip` (inactive pill) | `#EEEEEA` | `#2A2A28` |
| `accent` (coral) | `#E2562B` | `#E2562B` |
| `success` (archive green) | `#3D7A4F` | `#5C9A6E` |

Sepia reader theme: paper `#F4ECDC`, ink `#2B2418`, body `#3A3022`, muted `#6E6150`.

**Type**
- Large titles, article titles, reader body: Newsreader (600 for titles, 400 for body).
- UI labels, metadata, buttons: Inter (400/500/600).
- Metadata line style: 12pt, semibold, uppercase, +0.4 tracking, `muted`. Example: `SLOWMAG · 11 MIN`.
- Reader body default 19pt, line height 1.6, range 15–25pt.

**Shape and spacing**
- Corner radii: thumbnails 12, hero card 16, sheets 26–28, pill buttons fully rounded.
- Screen side padding 20 (iPhone). Row thumbnail 76×76. Touch targets ≥ 44pt.
- Icons: SF Symbols, regular weight.

**Generated cover** (used when an article has no lead image):
- Background color picked deterministically from the site's host name (hash → index into a fixed palette of 8 warm/deep tones, e.g. `#1F3A5F`, `#EDE4CF`, `#E9D6BF`, `#D6E4E1`, `#E6DEEA`, `#3B4A3F`, `#5A3A2E`, `#DCE3EC`) with a matching foreground (light text on dark tones, dark text on light tones).
- Large Newsreader initial (first letter of the site name), site name in tiny uppercase Inter at the bottom.
- Implement it as a SwiftUI view, `GeneratedCoverView(siteName:)`, so it scales to any size.

---

## 4. Project structure

```
pocketme/
├─ project.yml                  # XcodeGen
├─ AGENTS.md                    # conventions for coding agents (copy section 0 + 10)
├─ README.md                    # setup steps (section 11)
├─ Config/
│  ├─ Shared.xcconfig           # DEVELOPMENT_TEAM, bundle id prefix, iCloud/App Group ids
│  └─ *.entitlements
├─ Shared/                      # compiled into app and extensions
│  ├─ Model/Article.swift
│  ├─ Model/ModelContainer+App.swift
│  ├─ Design/Theme.swift, Fonts.swift, GeneratedCoverView.swift
│  ├─ Services/SaveQueue.swift  # App Group inbox used by extensions
│  └─ Util/URLNormalizer.swift, ReadingTime.swift
├─ App/                         # multiplatform app target
│  ├─ PocketMeApp.swift
│  ├─ Services/
│  │  ├─ ArticleIngestor.swift       # drains SaveQueue, creates Articles, dedupes
│  │  ├─ ExtractionService.swift     # WKWebView + Readability.js
│  │  ├─ OfflineAssetStore.swift     # downloads images, rewrites HTML, file layout
│  │  ├─ ThumbnailService.swift      # downloads/downsizes lead image
│  │  └─ ProcessingCoordinator.swift # runs pending work, retries
│  ├─ Reader/
│  │  ├─ ReaderView.swift, ReaderWebView.swift (UIView/NSViewRepresentable)
│  │  ├─ ReaderSettings.swift (@AppStorage), ReaderSettingsSheet.swift
│  │  └─ Resources/reader.html, reader.css, reader.js, Readability.js
│  ├─ Library/
│  │  ├─ LibraryView.swift (iOS), ArticleRow.swift, ContinueReadingCard.swift
│  │  ├─ MacLibraryView.swift
│  │  └─ EmptyStateView.swift
│  └─ Settings/SettingsView.swift
├─ ShareExtension-iOS/
├─ ShareExtension-macOS/
├─ Tests/PocketMeTests/
│  ├─ Fixtures/*.html
│  └─ *.swift
└─ .github/workflows/build.yml
```

Targets in `project.yml`:
- `PocketMe`: multiplatform app (iOS + macOS), supported destinations iPhone, iPad, Mac (native macOS, **not** Catalyst).
- `ShareExtension-iOS`, `ShareExtension-macOS`: embedded in the app for their platform.
- `PocketMeTests`: unit tests (run on macOS in CI for speed).

Identifiers (placeholders, set once in `Config/Shared.xcconfig`):
- Bundle id prefix: `com.<owner>.pocketme`
- App Group: `group.com.<owner>.pocketme`
- iCloud container: `iCloud.com.<owner>.pocketme`

---

## 5. Data model (SwiftData + CloudKit)

CloudKit mirroring rules that **must** be respected: every stored property has a default value or is optional; no `@Attribute(.unique)`; relationships optional; no ordered relationships. Because uniqueness cannot be enforced, **dedupe in code** by `normalizedURL`.

```swift
@Model
final class Article {
    var id: UUID = UUID()
    var url: String = ""                 // as saved
    var normalizedURL: String = ""       // for dedupe (see URLNormalizer)
    var title: String = ""
    var siteName: String = ""
    var author: String?
    var excerpt: String?                 // first ~200 chars, used for the Mac preview pane
    var leadImageURL: String?
    @Attribute(.externalStorage) var thumbnailData: Data?   // downsized JPEG, ≤ 600px wide
    @Attribute(.externalStorage) var contentHTML: Data?     // cleaned Readability HTML (remote image URLs kept)
    var wordCount: Int = 0
    var readingMinutes: Int = 0

    var savedAt: Date = Date.now
    var lastOpenedAt: Date?
    var archivedAt: Date?                // nil = unread
    var isFavorite: Bool = false
    var readingProgress: Double = 0      // 0...1, scroll fraction

    var statusRaw: String = ArticleStatus.pending.rawValue  // pending | ready | failed
    var failureReason: String?
    var extractionAttempts: Int = 0
}

enum ArticleStatus: String { case pending, ready, failed }
```

Notes:
- `contentHTML` and `thumbnailData` sync through CloudKit (as assets) so a second device has text and thumbnail without re-extracting.
- **Inline article images are NOT synced.** Each device downloads them locally after the article arrives (section 6.4). This keeps CloudKit usage small.
- Per-device local state (downloaded image status) lives on disk, not in the model.
- Reading progress: write at most every 2 seconds while scrolling, and on disappear.

Queries the UI needs:
- Unread: `archivedAt == nil`, sorted by `savedAt` desc.
- Archive: `archivedAt != nil`, sorted by `archivedAt` desc.
- Favorites: `isFavorite == true`.
- Continue reading: unread, `lastOpenedAt != nil`, `0.02 < readingProgress < 0.95`, most recent `lastOpenedAt`.

Dedupe: when a URL is saved that already exists (same `normalizedURL`), do not create a duplicate. Instead move it to the top (`savedAt = now`) and unarchive it. Also run a dedupe pass after CloudKit imports (`NSPersistentStoreRemoteChange` notification) that merges duplicates created on two devices (keep the oldest `savedAt`'s record, OR-merge `isFavorite`, keep max `readingProgress`).

`URLNormalizer`: lowercase the scheme and host, strip `www.`, drop fragments, drop tracking params (`utm_*`, `fbclid`, `gclid`, `mc_cid`, `mc_eid`, `ref`, `ref_src`), drop a trailing slash, and sort the remaining query items.

---

## 6. Core flows

### 6.1 Saving from a Share extension
Extensions must stay small and fast (memory limit), so they **do not** extract articles and **do not** touch CloudKit.

1. Get the URL from the extension context (`public.url`, or `public.plain-text` containing a URL).
2. Append `{url, title?, savedAt}` as a JSON line to `SaveQueue` (a file in the App Group container, written with a file coordinator/atomic append).
3. Show the "Saved to PocketMe" sheet (mockup "iPhone · Save from Share sheet"): a ✓ header, a card with thumbnail and title from `LPMetadataProvider` (generated cover if no image, with a ~2s timeout), the site name and the line "Will download for offline", plus two buttons: **Done** (dismiss) and **Read now** (opens `pocketme://open?url=…`; on iOS use the responder-chain `openURL` workaround or just dismiss if not possible).
4. Auto-dismiss after 4 seconds if untouched.

### 6.2 Ingesting in the app
`ArticleIngestor.drain()` runs on launch, on `scenePhase == .active`, and on a Darwin notification posted by the extension. For each queued URL it dedupes, creates an `Article(status: .pending)`, then clears the queue.

Pasting a link in the app calls the same ingest path directly.

### 6.3 Extraction (`ExtractionService`)
- A single off-screen `WKWebView` (on the main actor) with a non-persistent data store and a desktop Safari user agent. Process the queue serially (one article at a time).
- Load the URL, wait for `didFinish` plus 500 ms (for JS-heavy pages), with a 20 s timeout.
- Inject `Readability.js` and run `new Readability(document.cloneNode(true)).parse()`. Also read `og:image`, `og:site_name`, `twitter:image` and `<link rel=icon>`.
- Results map to: `title`, `siteName` (falling back to the host without `www.`, capitalized), `byline`, `excerpt`, `content` (HTML), `length`.
- `readingMinutes = max(1, round(wordCount / 230))`.
- Lead image: `og:image`, else the first `<img>` in the content with width ≥ 300.
- On failure: set `failed`, keep the URL and title, and show the row with a small "Couldn't load · Retry" marker. Opening a failed article shows the original page in a web view instead. Retry automatically up to 3 times with backoff (1 min, 10 min, 1 h) and on app foreground.
- Non-HTML URLs (PDF, images, video): mark them `ready` with no content, and open them in the system viewer or browser.

### 6.4 Offline assets (`OfflineAssetStore`)
- Layout: `AppGroup/Articles/<article-id>/index.html` and `AppGroup/Articles/<article-id>/img/<sha1>.<ext>`.
- After extraction, or when a synced article arrives without local assets: parse `contentHTML`, download each `<img src>`/`srcset` best candidate (cap at 40 images and 15 MB per article; skip images that fail), rewrite the `src` attributes to relative `img/…` paths, drop `srcset`, and write `index.html`.
- An article counts as **offline-ready** when `index.html` exists. The library shows the "Downloading" marker (mockup: small amber dot plus label) only while an article is pending or its assets are not yet local.
- Use a background `URLSession` for image downloads where practical. Register a `BGAppRefreshTask` (iOS) to process pending items.
- Delete the folder when the article is deleted.

### 6.5 Thumbnails (`ThumbnailService`)
Download `leadImageURL`, downsample with ImageIO to max 600 px wide, encode as JPEG q 0.8, and store it in `thumbnailData`. If there is no image or the download fails, the UI uses `GeneratedCoverView`.

### 6.6 Reader
- `ReaderWebView` loads `index.html` via `loadFileURL(_:allowingReadAccessTo:)` (the article folder). If it is not offline-ready yet, render `contentHTML` with remote images.
- `reader.html` template: injects title, site, minutes, lead image and content, then `reader.css` with CSS variables for theme, font family and size. Settings changes call a JS function to update the variables live (no reload).
- `reader.css`: max line length ~68ch, centered; images max-width 100% with radius 14; nicely styled blockquotes and figure captions; links in `ink` with underline; respects `prefers-color-scheme` when the theme is Auto.
- `reader.js`: reports scroll progress to Swift (`WKScriptMessageHandler`, throttled), and restores the saved position on load.
- Bottom of the article (part of the HTML, not a floating overlay): a divider, then "You finished this article", a full-width **Archive** button, **Favorite** and **Share** buttons, then "Up next" (the next unread article). Buttons post messages to Swift.
- Top bar: Back, **Aa** (reader settings sheet), Share. A 2pt progress line under the bar in `accent`.
- Opening an article sets `lastOpenedAt`. Archiving from the end card returns to the library with a short haptic (iOS).
- Links inside articles open in Safari / the default browser. Long-press a link (iOS) to "Save to PocketMe".
- Mac keyboard: Space/Shift-Space to page, ↑/↓ to scroll, `E` to archive, `F` to favorite, `⌘+`/`⌘-` for font size, Esc to go back.

### 6.7 Reader settings (sheet; mockup "Reader settings")
- Font size: A− / A+ buttons with a progress bar between them (15–25pt).
- Theme: Light, Sepia, Dark, Auto (the selected one gets a 2pt accent ring).
- Font: Serif / Sans segmented control.
- Stored in `@AppStorage` (per device, not synced). Changes preview live behind the sheet.

---

## 7. Screens

### iPhone (TabView: Library, Favorites, Settings)
1. **Library** (mockup "iPhone · Library"): large title "Reading" (Newsreader 34), Search and `+` (accent circle) buttons, and pills "Unread · N" / "Archive". Continue Reading hero card (image or cover, "Continue · X min left" chip, progress bar), then the list of `ArticleRow`s (title, `Site · N min`, Downloading marker if needed, 76pt thumbnail on the right). Swipe left to **Archive** (green, `success`) or **Delete**; swipe right to **Favorite**. Pull to refresh triggers ingest and sync processing.
2. **Search**: filters by title and site name within the current list (a simple `.searchable`).
3. **Add link** (`+`): if the clipboard has a URL, save immediately with a toast "Saved"; otherwise show a small sheet with a URL field.
4. **Empty state** (mockup "First launch"): stacked-cards illustration, "Nothing saved yet", a two-step how-to, and a "Paste link from clipboard" button.
5. **Reader** and **Reader settings** as above.
6. **Favorites**: the same list UI, filtered.
7. **Settings**: iCloud sync status (account available / not signed in), storage used by offline files with "Clear downloaded images", default reader settings, About/licenses.

### Mac (mockups "Mac · Library with preview" and "Mac · Reader")
- A list + reader layout (see UI_SPEC §4.1): section tabs and a + button above a compact list of rows on the left, the reader beside it, and a toggle that hides the list.
- Toolbar: "Paste a link to save" field + Save button; ⌘N focuses the field; ⌘V on the grid saves a URL from the clipboard.
- Double-click a card or press Return to open the **reader**, which replaces the content+detail area with a centered 680pt column (keep the sidebar collapsible). The window title shows the article title.
- Right-click context menu: Open, Open original in browser, Copy link, Favorite, Archive, Delete.
- Window minimum size 900×600. Light and dark appearance supported.

---

## 8. CI

`.github/workflows/build.yml` on a `macos-15` runner:
1. `brew install xcodegen && xcodegen generate`
2. `xcodebuild build -scheme PocketMe -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
3. `xcodebuild build -scheme PocketMe -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
4. `xcodebuild test -scheme PocketMe -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

CloudKit entitlements require signing, so CI builds without signing. Make sure the app still launches unsigned in tests (guard CloudKit setup: if the iCloud container is unavailable, fall back to a local-only `ModelConfiguration`).

---

## 9. Milestones (one PR each)

**M1: Project skeleton**
- XcodeGen `project.yml` with all targets, xcconfig, entitlements (iCloud/CloudKit, App Groups), fonts bundled and registered, `Theme.swift`, `GeneratedCoverView`, CI workflow, README, AGENTS.md.
- *Done when:* CI builds iOS + macOS; the app launches to an empty "Reading" screen on both platforms in the right fonts and colors.

**M2: Data model and sync**
- `Article` model, `ModelContainer` in the App Group with CloudKit (local-only fallback), `URLNormalizer` + tests, dedupe logic + tests, seed sample data in DEBUG previews.
- *Done when:* an article created on one device appears on another signed into the same iCloud account (manual test), and unit tests pass.

**M3: Saving**
- `SaveQueue`, both Share extensions with the "Saved" sheet, `ArticleIngestor`, the `+`/paste flows, the Mac paste field, the empty state.
- *Done when:* sharing a link from Safari on iPhone and Mac adds a pending article to the library within 2 seconds of opening the app.

**M4: Extraction, thumbnails and offline**
- `ExtractionService` with Readability.js, `ThumbnailService`, `OfflineAssetStore`, `ProcessingCoordinator` with retries, background refresh.
- Tests: fixture HTML pages → expected title, site and word count (load fixtures from the file URL in the web view).
- *Done when:* saved articles turn ready with a thumbnail, and an article saved while online can be opened in Airplane Mode with its images.

**M5: Library UI**
- The iPhone library (hero card, rows, swipe actions, pills, search, tabs) and the Mac split view (sidebar, grid, preview pane, toolbar, context menus), matching the mockups.
- *Done when:* side-by-side with the mockups it looks the same in spacing, type and colors, in light and dark.

**M6: Reader**
- `ReaderWebView`, template/CSS/JS, progress sync, end-of-article card, Up next, reader settings sheet, Mac keyboard shortcuts.
- *Done when:* reading position survives an app restart and syncs to the other device; theme/size/font changes are live; Archive at the end returns to the library.

**M7: Polish and TestFlight readiness**
- App icon placeholder, launch screen, haptics, empty/failed states, Settings screen, accessibility (Dynamic Type for UI, VoiceOver labels on icon buttons, contrast ≥ 4.5:1), performance check with 500 articles.
- *Done when:* there are no layout breaks at the largest Dynamic Type size, and the archive builds sign successfully locally.

---

## 10. Conventions for the coding agent
- Keep files small (under ~300 lines). One view per file.
- No force unwraps outside tests. Errors surface to the user as a short, friendly message.
- All colors and fonts come from `Theme`. No hard-coded hex values in views.
- Every view gets a `#Preview` with sample data, in light and dark.
- Swift Concurrency only (no Combine or GCD in new code). Services are `actor`s or `@MainActor` where they touch WebKit/UI.
- Do not commit the generated `.xcodeproj`, user data or secrets.
- Write a short PR description that lists what changed and how it was tested.

---

## 11. One-time setup the owner must do (not the agent)
1. An Apple Developer account (needed for iCloud and TestFlight). Put the Team ID in `Config/Shared.xcconfig` as `DEVELOPMENT_TEAM`.
2. Choose the bundle id prefix (for example `com.yourname.pocketme`) and set it in the same file.
3. In Xcode → Signing & Capabilities, let Xcode register the iCloud container and the App Group once (or create them in the developer portal).
4. After M2, in the CloudKit Console, deploy the development schema to production before any TestFlight build.
5. Install XcodeGen: `brew install xcodegen`, then `xcodegen generate` and open `PocketMe.xcodeproj`.

---

## 12. Later: web client (not v1, keep in mind)
- Use Apple's **CloudKit JS** with "Sign in with Apple ID" to read and write the same private database from a browser. SwiftData mirrors to record type `CD_Article` with fields prefixed `CD_` (for example `CD_title`), and the web app reads those.
- Inline images will not be in CloudKit (by design), so the web reader loads them from their original URLs.
- iPad: verify that the Mac-style split view is used on regular width (`horizontalSizeClass == .regular`).
