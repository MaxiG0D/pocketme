#!/bin/zsh
set -euo pipefail
# Local, unsigned dry run: --no-upload. Otherwise archives iOS signed and uploads to TestFlight.
if [[ " $* " == *' --no-upload '* ]]; then
  exec /bin/zsh "$(dirname "$0")/archive.sh" TestFlight "$@"
fi
source "$(dirname "$0")/common.sh"
version="$(config_value MARKETING_VERSION)"
build=$(( $(config_value CURRENT_PROJECT_VERSION) + 1 ))
do_tests=1
while (( $# )); do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --build) build="$2"; shift 2 ;;
    --no-tests) do_tests=0; shift ;;
    --notes-file|--mac-notes-file) shift 2 ;;
    --no-publish|--no-git|--ios) shift ;;
    *) fail "Unknown option: $1" ;;
  esac
done
[[ "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail 'Version must look like 0.1.0.'
[[ "${build}" =~ '^[0-9]+$' ]] || fail 'The build must be a positive number.'
team="$(config_value DEVELOPMENT_TEAM)"
[[ -n "${team}" ]] || fail 'Set DEVELOPMENT_TEAM in Config/Local.xcconfig.'
[[ ! -f "${HOME}/.appstoreconnect/env" ]] || source "${HOME}/.appstoreconnect/env"
# App Store Connect API key: ASC_KEY_ID + ASC_ISSUER_ID, key at ASC_KEY_PATH or ~/.appstoreconnect/private_keys/AuthKey_<id>.p8.
key_id="${ASC_KEY_ID:-}"
if [[ -z "${key_id}" ]]; then
  keys=(${HOME}/.appstoreconnect/private_keys/AuthKey_*.p8(N))
  (( ${#keys} == 1 )) && key_id="${${keys[1]:t:r}#AuthKey_}"
fi
[[ -n "${key_id}" ]] || fail 'Set ASC_KEY_ID (App Store Connect API key id).'
key_path="${ASC_KEY_PATH:-${HOME}/.appstoreconnect/private_keys/AuthKey_${key_id}.p8}"
[[ -f "${key_path}" ]] || fail "API key not found at ${key_path}."
[[ -n "${ASC_ISSUER_ID:-}" ]] || fail 'Set ASC_ISSUER_ID (App Store Connect issuer id).'
auth=(-authenticationKeyPath "${key_path}" -authenticationKeyID "${key_id}" -authenticationKeyIssuerID "${ASC_ISSUER_ID}")
# ARCHIVE_WITH_ACCOUNT=1 archives with Xcode's signed-in Apple account (registers new App IDs); upload still uses the API key.
archive_auth=("${auth[@]}")
[[ -z "${ARCHIVE_WITH_ACCOUNT:-}" ]] || archive_auth=()
generate
if (( do_tests )); then run_tests; fi
archive_root="${ROOT_DIR}/Release Archive"
mkdir -p "${archive_root}"
archive_dir="$(mktemp -d "${archive_root}/TestFlight ${version} (${build}).XXXXXX")"
step "Archiving iOS ${version} (${build})"
xcodebuild archive -quiet -project "${PROJECT_PATH}" -scheme PocketMe -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "${CACHE_DIR}/Archive-iOS" \
  -archivePath "${archive_dir}/iOS.xcarchive" -allowProvisioningUpdates "${archive_auth[@]}" \
  "MARKETING_VERSION=${version}" "CURRENT_PROJECT_VERSION=${build}"
cat > "${archive_dir}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${team}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
step 'Uploading to App Store Connect'
xcodebuild -exportArchive -archivePath "${archive_dir}/iOS.xcarchive" -exportPath "${archive_dir}/Export" \
  -exportOptionsPlist "${archive_dir}/ExportOptions.plist" -allowProvisioningUpdates "${auth[@]}"
step "Uploaded ${version} (${build}). It appears in TestFlight after processing."
echo "Bump CURRENT_PROJECT_VERSION in Config/Shared.xcconfig to ${build} before the next upload."
