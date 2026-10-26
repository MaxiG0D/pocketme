# PocketMe development

A calm, warm, minimal read-it-later app for iPhone and Mac, synced with iCloud.

- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [UI specification](docs/UI_SPEC.md)

## Development

Requires Xcode 16 or later with Swift 6, macOS 15 or later, and XcodeGen 2.42 or later. Deployment targets are iOS 18 and native macOS 15 (no Catalyst). There are no Swift package dependencies.

```sh
brew install xcodegen
xcodegen generate
open PocketMe.xcodeproj
```

The generated project is ignored. Edit `project.yml` and regenerate after changing targets or files. The `PocketMe` scheme builds the app and the share extension for the selected platform. Select an iPhone/iPad simulator or My Mac, then Run.

## Signing and iCloud

Before installing on a device, the owner must:

1. Set `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX` in `Config/Shared.xcconfig`. App Group and iCloud identifiers derive from that prefix. For machine-specific overrides, create ignored `Config/Local.xcconfig`.
2. Use an Apple Developer account and let Xcode register the App Group and iCloud container (or register them in the developer portal). All app/extension targets must use the same team and App Group.
3. After milestone 2, verify private CloudKit sync on two signed devices, then deploy the development schema to production before TestFlight.

Platform-specific entitlements configure CloudKit, push notifications and the shared App Group for the apps. Extensions have only the App Group (plus sandbox/network access on Mac); they will never write directly to CloudKit.

## Build and test

```sh
xcodegen generate
xcodebuild build -project PocketMe.xcodeproj -scheme PocketMe -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project PocketMe.xcodeproj -scheme PocketMe -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project PocketMe.xcodeproj -scheme PocketMe -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

GitHub Actions runs those commands on `macos-15`. Unsigned builds need no developer account. Unsigned builds and simulators use a local SwiftData store. Signed device and Mac builds use private CloudKit when the account is available, with a persistent local fallback.

## Using the app

- On iPhone, tap **+** to save the clipboard link or enter a URL. In Safari and other apps, choose **PocketMe** from the Share Sheet.
- On Mac and regular-width iPad, paste into **Paste a link to save** and choose **Save**. Mac supports ⌘N to focus the field, ⌘V over the grid, and Return/double-click to read.
- Saved pages are extracted automatically. Text, lead thumbnails and inline images are stored for offline reading. Extraction failures offer Retry and Open original.
- Read in Light, Sepia, Dark or Auto, choose Serif/Sans and adjust font size. Reading position, favorites and archive state persist and sync.
- Archive at the end of an article, swipe an iPhone row, or use its context menu. Deleting requires confirmation.
- Settings shows the current iCloud mode, local storage usage, image cleanup and bundled licenses.

Inline images download separately on each device, capped at 40 images/15 MB per article. Sites that block extraction, require a login/paywall, or cannot load under transport security can still be opened in the browser. No transport-security exceptions are enabled.

Signed simulator builds are required to exercise the share extension’s App Group. An unsigned simulator build can verify the app itself but its extension cannot open the shared inbox.

Shared saves are coordinated JSON lines in the App Group. Entries are acknowledged only after SwiftData saves, so concurrent extension saves remain queued. Remote CloudKit imports trigger URL deduplication and per-device offline processing.

Cross-device sync was verified on the owner’s iPad and iPhone Duo. See [functional QA](docs/qa/functional/README.md) for test evidence and remaining release checks. Debug-only `-PocketMeSyncProbe URL [-PocketMeSyncCreate|-PocketMeSyncCleanup]` writes a local diagnostic JSON for development sync verification.

## Fonts and licenses

Bundled variable fonts are from the [Google Fonts repository](https://github.com/google/fonts): [Newsreader](https://github.com/google/fonts/tree/main/ofl/newsreader) and [Inter](https://github.com/google/fonts/tree/main/ofl/inter). Their SIL Open Font Licenses are included beside the `.ttf` files in `Shared/Resources/Fonts`. iOS declares `UIAppFonts`; explicit Core Text registration supports macOS and previews as well.

Readability 0.6.0 is vendored from Mozilla under Apache 2.0; both Mozilla’s notice and the full license are bundled in `App/Reader/Resources`. It has no runtime npm dependency.

## Release applet

Run `Release/build_release_app.sh`, then open **PocketMe Release.app** at the project root. This reuses the existing Carnet de Recettes release applet layout, with Build, TestFlight and Publish tabs, and uses PocketMe's approved taupe pocket icon. Its source and provenance are in `Release/PocketMeRelease` and `Release/TEMPLATE.md`.

- **Build:** build the Mac app and install it in `/Applications` (replacing the old copy), then open it, run tests, or install on paired iPhones/iPads after setting your signing team. There is one PocketMe: builds use the same bundle ID, App Group and iCloud library as the installed app.
- **TestFlight:** with Upload unchecked, create an unsigned local iOS archive.
- **Publish:** with Publish unchecked, run tests and create unsigned local Mac and iOS archives.

Uploads and publishing are unavailable until M7 configures PocketMe’s own distribution. Local archives are for inspection, cannot be installed as distribution builds, and leave the source version/build counter unchanged. No Carnet credentials or release destinations are copied. The applet never commits or tags.

Commands: `Release/dev.sh build` (build without opening), `Release/dev.sh open`, `Release/dev.sh test`, `Release/dev.sh devices`, `Release/release.sh --no-publish --ios`, `Release/testflight.sh --no-upload`. Scripted project generation and build products stay under `~/Library/Caches/PocketMe` to avoid iCloud Drive placeholders and duplicate generated projects in Documents; archives appear in ignored `Release Archive/`.
