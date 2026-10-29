#!/bin/zsh
set -euo pipefail
source "$(dirname "$0")/common.sh"
APP="/Applications/PocketMe.app"
PREFIX="$(config_value BUNDLE_ID_PREFIX)"
# Release by default: a Debug build is unoptimized and its SwiftUI overhead makes scrolling feel worse than what ships.
# Pass --debug to install a Debug build instead.
CONFIG=Release
[[ " $* " == *' --debug '* ]] && CONFIG=Debug
install_devices() {
  [[ -n "$(config_value DEVELOPMENT_TEAM)" ]] || fail 'Set DEVELOPMENT_TEAM in Config/Local.xcconfig before device installation.'
  local device_list
  device_list="$(mktemp "${TMPDIR:-/tmp/}pocketme-devices.XXXXXX")"
  xcrun devicectl list devices --json-output "${device_list}" >/dev/null
  local devices
  devices="$(/usr/bin/python3 - "${device_list}" <<'PY'
import json,sys
for d in json.load(open(sys.argv[1]))['result']['devices']:
    h,c=d.get('hardwareProperties',{}),d.get('connectionProperties',{})
    if h.get('reality')!='simulated' and h.get('platform')=='iOS' and c.get('pairingState')=='paired':
        print(d['identifier']+'\t'+d['deviceProperties']['name'])
PY
)"
  rm -f "${device_list}"
  [[ -n "${devices}" ]] || fail 'No paired iPhone or iPad. Pair a device in Xcode first.'
  local device_id device_name installed=0 failed=0
  local -a results=()
  local derived="${CACHE_DIR}/Device"
  step 'Building for iPhone and iPad'
  xcodebuild build -quiet -project "${PROJECT_PATH}" -scheme PocketMe \
    -configuration ${CONFIG} -destination 'generic/platform=iOS' -derivedDataPath "${derived}" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration
  while IFS=$'\t' read -r device_id device_name; do
    if xcrun devicectl device install app --device "${device_id}" "${derived}/Build/Products/${CONFIG}-iphoneos/PocketMe.app"; then
      results+=("OK      ${device_name}")
      installed=$((installed + 1))
    else
      results+=("FAILED  ${device_name} (unlocked, trusted, Developer Mode on, and registered in the provisioning profile?)")
      failed=$((failed + 1))
    fi
  done <<< "${devices}"
  step 'Device install results'
  printf '%s\n' "${results[@]}"
  (( installed > 0 )) || fail 'No devices could be installed. See the log.'
  (( failed == 0 ))
}
install_mac() {
  step 'Building the Mac app'
  typeset -a mac_signing=(CODE_SIGNING_ALLOWED=NO)
  if [[ -n "$(config_value DEVELOPMENT_TEAM)" ]]; then
    mac_signing=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)
  fi
  xcodebuild build -quiet -project "${PROJECT_PATH}" -scheme PocketMe -configuration ${CONFIG} \
    -destination 'platform=macOS' -derivedDataPath "${CACHE_DIR}/Mac" \
    "${mac_signing[@]}"
  staged="${CACHE_DIR}/Mac/Build/Products/${CONFIG}/PocketMe.app"
  # Keep the signed CloudKit entitlement when a development team is configured.
  # Without one, the local-only app remains runnable via an ad-hoc signature.
  if [[ -z "$(config_value DEVELOPMENT_TEAM)" ]]; then
    codesign --force --deep --sign - "${staged}"
  fi
  if [[ -e "${APP}" ]]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist")"
    [[ "${existing_id}" == "${PREFIX}" ]] || fail 'Another app is already at /Applications/PocketMe.app.'
    # Restart only this built copy so Open cannot reuse the previous binary.
    /usr/bin/pkill -TERM -f "^${APP}/Contents/MacOS/PocketMe$" 2>/dev/null || true
    rm -rf "${APP}"
  fi
  ditto --noextattr --noqtn "${staged}" "${APP}"
  # The build-products copy registers its extensions too, which shows duplicates in Safari.
  lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  for appex in "${staged}"/Contents/PlugIns/*.appex(N); do pluginkit -r "${appex}" 2>/dev/null || true; done
  "${lsregister}" -u "${staged}" 2>/dev/null || true
  for appex in "${APP}"/Contents/PlugIns/*.appex(N); do pluginkit -a "${appex}" 2>/dev/null || true; done
  step 'Mac app installed in Applications'
}
generate
case "${1:-}" in
  open|build)
    install_mac
    if [[ "$1" == open ]]; then open "${APP}"; fi
    if [[ " $* " == *' --devices '* ]]; then install_devices "$@"; fi
    ;;
  devices)
    # Duo, iPad Pro and every other paired iPhone/iPad, then the Mac. One failure never masks another.
    device_status=OK
    (install_devices) || device_status=FAILED
    mac_status=OK
    (install_mac) || mac_status=FAILED
    step 'Mac install result'
    echo "${mac_status}  Mac (devices: ${device_status})"
    [[ "${device_status}" == OK && "${mac_status}" == OK ]] || fail 'One or more installs failed. See results above.'
    ;;
  test) run_tests ;;
  *) fail 'Use Release/dev.sh build, open [--devices], devices, or test. Add --debug for a Debug build (default is Release).' ;;
esac
