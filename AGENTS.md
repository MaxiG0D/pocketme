# Instructions for coding agents

PocketMe is a warm, minimal read-it-later app for iPhone and Mac (SwiftUI, SwiftData + CloudKit).

Before doing anything, read:
1. `docs/IMPLEMENTATION_PLAN.md`: scope, architecture, data model and milestones. Work one milestone per PR.
2. `docs/UI_SPEC.md`: exact UI rules. Read it in full before writing or changing any view, and tick its visual QA checklist in every UI PR.

Hard rules:
- Do not add features that are not in the plan (no highlights, tags, TTS, accounts, analytics).
- No default-styled `List`/`Form` on content screens, no system colors, only the Newsreader and Inter fonts, and the background is `paper` (#FAFAF8), not white.
- Every PR must build for iOS and macOS in CI and keep tests green.

Release applet exception: Max explicitly requires the existing Carnet de Recettes release applet template. `Release/PocketMeRelease` retains that separate developer tool’s UI; do not restyle it to match the product or invent a new UI. See `Release/TEMPLATE.md`.

CI parity: GitHub runs `Scripts/ci.sh --ui` on the Xcode named in `.xcode-version` (the newest GitHub offers), which can be older than the Mac's. Run `Scripts/ci.sh --ui` on the Mac before every push to main; the pre-push hook it installs runs `Scripts/ci.sh` automatically and blocks the push on failure. Any API newer than that Xcode's SDK goes inside `#if compiler(>=…)` as well as `#available`; `Scripts/check_sdk.sh` enforces this. Fix any failure before pushing. Mac UI tests are excluded because the unsigned runner is blocked by Gatekeeper; the iPhone simulator runs them.
