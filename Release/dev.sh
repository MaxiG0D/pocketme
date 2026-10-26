#!/bin/zsh
set -euo pipefail
source "$(dirname "$0")/common.sh"
DEV_APP="${ROOT_DIR}/PocketMe - Dev.app"
DEV_PREFIX="$(config_value BUNDLE_ID_PREFIX).dev"
install_devices() {
  [[ -n "$(config_value DEVELOPMENT_TEAM)" ]] || fail 'Set DEVELOPMENT_TEAM in Config/Local.xcconfig before device installation.'
  local configurations=(Debug) prefixes=("${DEV_PREFIX}")
  if [[ " $* " == *' --normal '* ]]; then
    configurations+=(Release)
    prefixes+=("$(config_value BUNDLE_ID_PREFIX)")
  fi
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
  local i device_id device_name installed=0
  for i in {1..${#configurations}}; do
    local configuration="${configurations[$i]}" prefix="${prefixes[$i]}"
    local derived="${CACHE_DIR}/Device-${configuration}"
    step "Building ${configuration} for iPhone and iPad"
    xcodebuild build -quiet -project "${PROJECT_PATH}" -scheme PocketMe \
      -configuration "${configuration}" -destination 'generic/platform=iOS' -derivedDataPath "${derived}" \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration "BUNDLE_ID_PREFIX=${prefix}" \
      "APP_DISPLAY_NAME=$([[ ${configuration} == Debug ]] && echo 'PocketMe Dev' || echo 'PocketMe')"
    while IFS=$'\t' read -r device_id device_name; do
      if xcrun devicectl device install app --device "${device_id}" "${derived}/Build/Products/${configuration}-iphoneos/PocketMe.app"; then
        echo "Installed on ${device_name}"
        installed=$((installed + 1))
      else
        echo "warning: Couldn't reach ${device_name}. Is it unlocked and connected?"
      fi
    done <<< "${devices}"
  done
  (( installed > 0 )) || fail 'No devices could be installed. See the log.'
}
generate
case "${1:-}" in
  open|build)
    step 'Building the dev app'
    typeset -a mac_signing=(CODE_SIGNING_ALLOWED=NO)
    if [[ -n "$(config_value DEVELOPMENT_TEAM)" ]]; then
      mac_signing=(-allowProvisioningUpdates)
    fi
    xcodebuild build -quiet -project "${PROJECT_PATH}" -scheme PocketMe -configuration Debug \
      -destination 'platform=macOS' -derivedDataPath "${CACHE_DIR}/Dev" \
      "${mac_signing[@]}" "BUNDLE_ID_PREFIX=${DEV_PREFIX}" "APP_DISPLAY_NAME=PocketMe - Dev"
    staged="${CACHE_DIR}/Dev/Build/Products/Debug/PocketMe.app"
    # Keep the signed CloudKit entitlement when a development team is configured.
    # Without one, the local-only app remains runnable via an ad-hoc signature.
    if [[ -z "$(config_value DEVELOPMENT_TEAM)" ]]; then
      codesign --force --deep --sign - "${staged}"
    fi
    if [[ -e "${DEV_APP}" ]]; then
      existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${DEV_APP}/Contents/Info.plist")"
      [[ "${existing_id}" == "${DEV_PREFIX}" ]] || fail 'Unexpected app at the dev build path.'
      # Restart only this generated dev app so Open cannot reuse the previous binary.
      /usr/bin/pkill -TERM -f "^${DEV_APP}/Contents/MacOS/PocketMe$" 2>/dev/null || true
      rm -rf "${DEV_APP}"
    fi
    ditto --noextattr --noqtn "${staged}" "${DEV_APP}"
    step 'Dev app built'
    if [[ "$1" == open ]]; then open "${DEV_APP}"; fi
    if [[ " $* " == *' --devices '* ]]; then install_devices "$@"; fi
    ;;
  devices) install_devices "$@" ;;
  test) run_tests ;;
  *) fail 'Use Release/dev.sh build, open [--devices] [--normal], devices [--normal], or test.' ;;
esac
