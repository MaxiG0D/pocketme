#!/bin/zsh
set -euo pipefail
source "$(dirname "$0")/common.sh"
platform="$1"; shift
version="$(config_value MARKETING_VERSION)"
build=$(( $(config_value CURRENT_PROJECT_VERSION) + 1 ))
notes_file=''
do_tests=1
with_ios=0
mac_notes=''
while (( $# )); do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --build) build="$2"; shift 2 ;;
    --notes-file) notes_file="$2"; shift 2 ;;
    --no-tests) do_tests=0; shift ;;
    --ios) with_ios=1; shift ;;
    --no-upload|--no-publish|--no-git) shift ;;
    --mac-notes-file) mac_notes="$2"; shift 2 ;;
    *) fail "Unknown option: $1" ;;
  esac
done
[[ "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail 'Version must look like 0.1.0.'
[[ "${build}" =~ '^[0-9]+$' ]] || fail 'The build must be a positive number.'
generate
if (( do_tests )); then run_tests; fi
archive_root="${ROOT_DIR}/Release Archive"
mkdir -p "${archive_root}"
archive_dir="$(mktemp -d "${archive_root}/${platform} ${version} (${build}).XXXXXX")"
[[ -z "${notes_file}" ]] || cp "${notes_file}" "${archive_dir}/release-notes.txt"
archive_platform() {
  local name="$1" destination="$2"
  step "Archiving ${name} ${version} (${build}) locally"
  xcodebuild archive -quiet -project "${PROJECT_PATH}" -scheme PocketMe -configuration Release \
    -destination "${destination}" -derivedDataPath "${CACHE_DIR}/Archive-${name}" \
    -archivePath "${archive_dir}/${name}.xcarchive" CODE_SIGNING_ALLOWED=NO \
    "MARKETING_VERSION=${version}" "CURRENT_PROJECT_VERSION=${build}"
}
if [[ "${platform}" == Mac ]]; then
  archive_platform Mac 'generic/platform=macOS'
  if (( with_ios )); then archive_platform iOS 'generic/platform=iOS'; fi
else
  archive_platform iOS 'generic/platform=iOS'
  [[ -z "${mac_notes}" ]] || archive_platform Mac 'generic/platform=macOS'
fi
cat > "${archive_dir}/README.txt" <<TEXT
PocketMe ${version} (${build}) — unsigned local archive.
Nothing was uploaded, published, committed or tagged.
Installable distribution requires signing, app icons and PocketMe's App Store setup (M7).
The source version and build counter were not changed by this dry run.
TEXT
step 'Local archive complete; nothing was uploaded'
echo "Release archive: ${archive_dir}"
