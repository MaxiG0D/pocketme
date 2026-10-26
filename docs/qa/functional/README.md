# Functional app QA — 2026-10-26

The owner explicitly requested continuing through to a usable save-and-read app. The data, saving, extraction/offline, library and reader milestones were implemented together locally. No commits, pull requests, uploads or releases were created by this work.

## Verified

- Swift Testing: 16 tests passed, zero failures, including parameterized URL cases.
- Persistent SwiftData records survive reopening; duplicate URLs merge favorites, reading progress and usable content.
- Private CloudKit: a dev article created on Maxime’s iPad arrived on the iPhone Duo. Both diagnostics reported `cloud`; the receiving device found exactly one record.
- The signed Mac dev app imported the same CloudKit article.
- Concurrent shared-inbox writers retain all entries; acknowledgments preserve newer saves.
- Readability extracts a fixture DOM with the expected title, author, site and 242 words, stripping scripts, handlers, inline style and unsafe links.
- Real Mac and iPhone saves extracted “How to Do Great Work” and “Is High Quality Software Worth the Cost?”. The latter’s inline images rendered from a local `index.html` with remote image loading disabled by CSP.
- Offline HTML and bundled fonts remain on disk; cached images survive a template refresh without network access. Deletion removes cached files.
- Mac footer Favorite updates immediately; Archive removes the article from Unread and returns to the library.
- iPhone reader controls changed theme, text size and Serif/Sans live. Settings persisted after restarting the test app.
- The iPhone library restored a Continue Reading card after restarting; largest Dynamic Type remained scrollable without clipping.
- The signed simulator’s actual PocketMe share extension completed and auto-dismissed. The unsigned simulator correctly surfaced failure because it lacked App Group access; signed builds are required for this check.
- The Mac share extension is registered with the OS.
- Signed dev builds installed on Maxime’s iPad and iPhone Duo. Other paired but unavailable devices were skipped.
- Final local Mac and iOS Release archives completed successfully; nothing was uploaded. The final signed Mac dev build also passed.

## Visual checks

- [x] No system blue in app-drawn content; Newsreader/Inter; warm paper background.
- [x] iPhone thumbnails on the right at 76×76, radius 12; rows use custom separators and swipe actions.
- [x] Header spacing and the generated-cover/reader typography checked against the transcribed UI specification.
- [x] Light/dark iPhone library/reader and Mac Sepia reader checked.
- [x] Largest Dynamic Type checked on the populated iPhone library.
- [ ] Pixel comparison against private canvas artboards: those artboards were not available.
- [ ] Every screen at every accessibility size and a 500-article UI performance run remain part of release polish.

Screenshots are in this folder: iPhone library, reader light/dark, settings, system share row, large text, and Mac reader Sepia. Screenshots depict local dev/test data.

## Release boundary

CloudKit production schema deployment, App Store/TestFlight listing/export setup, notarized Mac distribution, and remote CI execution remain release tasks. The applet retains Carnet’s original layout and intentionally blocks uploads/publishing until distribution is configured. Local build/test/archive actions work.

App Transport Security stays enabled. Failed extraction offers Retry and Open original; pages that cannot load securely can be read in the system browser.

Scripted builds generate their project outside Documents and request any evicted checkout files from iCloud Drive before compiling. Generated app bundles, archives, local signing settings and credentials are ignored.

## Thumbnail follow-up

- Preview extraction now checks alternate Open Graph/Twitter metadata, `image_src`, lazy-image attributes, and responsive image candidates. Empty/unsafe URLs are rejected.
- Thumbnail downloads try multiple candidates before Apple LinkPresentation's page image. Existing records without thumbnails are enriched automatically without re-extracting or replacing their article text. Successful thumbnails sync through the existing CloudKit field.
- Missing-image attempts are limited to once per day per device; pages without usable artwork retain their generated covers. Images smaller than 120×80 are rejected to avoid tracking pixels and tiny icons.
- Regression suite: 20 tests passed (31 runs including parameterized cases), zero failures. New coverage checks alternate metadata, lazy/responsive image extraction, 600px downsampling and tracking-pixel rejection.
