# Production iCloud sync review — 2026-10-29

Reviewed commit `014a56f7d6f4d2befa308dc198b5ff45ffcc2fc7` on `main`. The same commit was already on `origin/main` when checked. No product views or data-model changes were made during this review.

## Finding

The configuration change is valid: Debug resolves to CloudKit Development, Release to Production. The installed signed Mac app and the signed Release iOS build both carry `com.apple.developer.icloud-container-environment = Production`, with the expected PocketMe container. The installed Mac app's signature also passes strict verification.

The initial review blocked release because the Production CloudKit schema was incomplete. Launching the signed Mac app produced a CloudKit export failure:

```text
CKError: Partial Failure (2/1011)
Invalid Arguments (12/2006)
Cannot create or modify field 'CD_contentHTML_ckAsset' in record 'CD_Article' in production schema
```

Core Data then reported that its mirroring delegate never successfully initialized. Correct entitlements and green builds did not establish working sync in that state.

## Production deployment — 2026-10-30

CloudKit Console confirmed **Changes Deployed — The schema is deployed to Production**. The reviewed deployment added `CD_contentHTML_ckAsset` (Asset), `CD_failureReason` (String), and three indexes on `CD_Article`. Security roles were unchanged. No environment was reset and no existing records were deleted.

After restarting the installed signed Release Mac app, system logs confirmed successful Production exports and imports. An initial recoverable import error for the separate `WebSaves` zone recovered automatically, followed by successful imports and exports. The former fatal missing-asset-field error no longer occurs.

The full local `Scripts/ci.sh --ui` command completed successfully for 0.1.12 (15) on 2026-10-30: iOS Simulator and macOS builds, macOS unit tests, and all 7 iPhone UI tests. This final run completed without intervention and exited 0 with `CI checks passed`. The required test suites were unchanged.

The exported Developer ID Mac app passes strict signature verification and carries both Production iCloud and production push entitlements. The signed iOS archive also carries Production iCloud. The version/build is 0.1.12 (15).

## Required follow-up

1. **TestFlight is blocked by Apple's updated Program License Agreement.** The iOS archive built, but export/upload failed with `PLA Update available` and unavailable iOS Distribution signing credentials. The account holder must review and accept the agreement in [Apple Developer Account](https://developer.apple.com/account/); an agent cannot accept it for them. No upload completed. The prepared archive is in ignored `Release Archive/TestFlight 0.1.12 (15).Geqbuz/iOS.xcarchive`.
2. After acceptance, retry `Release/testflight.sh --version 0.1.12 --build 15 --no-tests` for this unchanged source, or re-export the prepared archive with its adjacent `ExportOptions.plist` and the existing App Store Connect API credentials. Verify distribution entitlements and Apple's upload result. Resolve any remaining distribution certificate error after account access is restored.
3. Complete the physical-device regression: verify article text, favorite/archive changes and reading progress in each direction between Mac and iPhone/iPad. The Mac exported and rendered the temporary `Announcing Swift 6` article, but paired devices were unavailable to `devicectl` and manual device confirmation remains outstanding. Do not describe that check as passed.

Existing personal articles and the unrelated untracked `.build-diag/` directory were left intact. Two temporary URLs with `pocketme_sync_check=20261030` were saved: the initial `/blog/swift-6-released/` URL returned 404 and was archived; the verified `/blog/announcing-swift-6/` URL extracted successfully and remains available for the manual sync check. No personal article was deleted.

## Build validation

- Local Xcode: 27.1; the pinned CI Xcode 26.6 is not installed on this Mac.
- `Scripts/check_sdk.sh`, iOS Simulator build and macOS build passed via `Scripts/ci.sh --ui`.
- macOS unit tests passed: 34 tests, including parameterized cases (56 individual runs).
- [GitHub CI for the reviewed commit](https://github.com/MaxiG0D/pocketme/actions/runs/40982312005) passed on pinned Xcode 26.6, including `Scripts/ci.sh --ui` and the release applet build.
- Earlier local runs stalled while Xcode collected simulator diagnostics. A process sample identified `collectSimulatorDiagnostics`, and stopping the optional `simctl diagnose` child let one run finalize successfully. The final 0.1.12 run completed normally, superseding the earlier interrupted attempts. Xcode 27.1's `invalidDigitCount` simulator warnings remain nonfatal.

Apple documents the environment entitlement [here](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-container-environment) and schema deployment [here](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
