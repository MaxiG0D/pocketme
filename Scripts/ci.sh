#!/bin/zsh
# The exact build and test sequence GitHub Actions runs. Run it before every push to main.
# Scripts/ci.sh        iOS build, macOS build, macOS unit tests
# Scripts/ci.sh --ui   also the iPhone simulator UI tests (row tap, swipe)
set -euo pipefail
cd "$(dirname "$0")/.."
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
  build test -destination "platform=iOS Simulator,name=${sim}" -only-testing:PocketMeUITests
fi
echo 'CI checks passed'
