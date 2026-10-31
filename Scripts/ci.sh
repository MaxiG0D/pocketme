#!/bin/zsh
# The exact build and test sequence GitHub Actions runs. The pre-push hook runs it before every push to main.
# Scripts/ci.sh        iOS build, macOS build, macOS unit tests
# Scripts/ci.sh --ui   also the iPhone simulator UI tests (row tap, swipe)
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
# GitHub builds with the Xcode in .xcode-version. Use it here too when installed; otherwise
# check_sdk.sh catches code that only compiles with a newer SDK.
pinned="/Applications/Xcode_$(<.xcode-version).app"
[[ -d "${pinned}" ]] && export DEVELOPER_DIR="${pinned}/Contents/Developer"
version="$(xcodebuild -version)"; echo "${version%%$'\n'*}"
Scripts/check_sdk.sh
build_dir="${TMPDIR:-/tmp}/pocketme-ci"
project="${build_dir}/Project/PocketMe.xcodeproj"
mkdir -p "${build_dir}/Project"
xcodegen generate --spec project.yml --project "${build_dir}/Project"
[[ -e "${build_dir}/Project/Config" ]] || ln -s "${PWD}/Config" "${build_dir}/Project/Config"
build() { xcodebuild "$@" -project "${project}" -scheme PocketMe -derivedDataPath "${build_dir}/Derived" CODE_SIGNING_ALLOWED=NO -quiet }
build build -destination 'generic/platform=iOS Simulator'
build build -destination 'platform=macOS'
# The unsigned Mac UI runner is rejected by Gatekeeper, so Mac runs unit tests only.
build test -destination 'platform=macOS' -skip-testing:PocketMeUITests
if [[ "${1:-}" == --ui ]]; then
  sim="$(xcrun simctl list devices available | sed -nE 's/^ *(iPhone [^(]*[^ (]) \(.*/\1/p' | head -1)"
  # Not -quiet: on failure GitHub's log must show which assertion failed (and the hierarchy), not only the test's name.
  log="${build_dir}/ui-tests.log"
  xcodebuild test -project "${project}" -scheme PocketMe -derivedDataPath "${build_dir}/Derived" CODE_SIGNING_ALLOWED=NO \
    -destination "platform=iOS Simulator,name=${sim}" -only-testing:PocketMeUITests > "${log}" 2>&1 || {
    grep -A60 -E 'error: -\[|error:.*XCT|Test Case .* failed' "${log}" | cut -c1-600 | head -400; tail -30 "${log}"; exit 65
  }
fi
# Lets the pre-push hook skip a second run for a commit that already passed.
git diff --quiet HEAD && git rev-parse 'HEAD^{tree}' > "$(git rev-parse --git-dir)/ci-passed" || true
echo 'CI checks passed'
