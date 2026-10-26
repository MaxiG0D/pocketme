#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME='PocketMe Release'
APP_DIR="${ROOT_DIR}/${APP_NAME}.app"
BUILD_DIR="$(mktemp -d /private/tmp/pocketme-release-app.XXXXXX)"
trap 'rm -rf "${BUILD_DIR}"' EXIT
STAGED_APP="${BUILD_DIR}/${APP_NAME}.app"
ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
mkdir -p "${STAGED_APP}/Contents/MacOS" "${STAGED_APP}/Contents/Resources" "${ICONSET_DIR}"
swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -O -target "$(uname -m)-apple-macosx15.0" \
  -module-cache-path "${BUILD_DIR}/module-cache" \
  "${ROOT_DIR}"/Release/PocketMeRelease/*.swift -o "${STAGED_APP}/Contents/MacOS/PocketMeRelease"
for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${ROOT_DIR}/Release/Resources/release-icon-1024.png" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "${ROOT_DIR}/Release/Resources/release-icon-1024.png" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET_DIR}" -o "${STAGED_APP}/Contents/Resources/AppIcon.icns"
/usr/bin/python3 - "${STAGED_APP}/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump(dict(CFBundleExecutable='PocketMeRelease', CFBundleIdentifier='com.maxigariepy.pocketme.release-tool',
        CFBundleName='PocketMe Release', CFBundleIconFile='AppIcon', CFBundlePackageType='APPL',
        CFBundleShortVersionString='1.0', CFBundleVersion='1', LSMinimumSystemVersion='15.0', NSHighResolutionCapable=True),f)
PY
codesign --force --sign - "${STAGED_APP}"
# Replace only our own generated bundle; sources and other apps are untouched.
if [[ -e "${APP_DIR}" ]]; then
  [[ -f "${APP_DIR}/Contents/MacOS/PocketMeRelease" ]] || { echo 'error: Unexpected existing app bundle.' >&2; exit 1; }
  rm -rf "${APP_DIR}"
fi
ditto --noextattr --noqtn "${STAGED_APP}" "${APP_DIR}"
echo "Built ${APP_DIR}"
