#!/bin/zsh
set -euo pipefail
source "$(dirname "$0")/common.sh"
# Usage: publish_mac.sh keys | publish_mac.sh [--version X.Y.Z] [--build N] [--notes-file F] [--no-tests]
# Signs with Developer ID, notarizes, publishes the zip and appcast.xml to GitHub Releases, which Sparkle reads.
# Needs: a Developer ID Application certificate, DEVELOPMENT_TEAM in Config/Local.xcconfig, a notarytool Keychain
# profile (default "pocketme-notary"), `gh` signed in, and the Sparkle EdDSA private key in the Keychain.
REPO='maxig0d/pocketme'
NOTARY_PROFILE="${POCKETME_NOTARY_PROFILE:-pocketme-notary}"
resolve_sparkle() {
  step 'Resolving Sparkle'
  xcodebuild -resolvePackageDependencies -quiet -project "${PROJECT_PATH}" -scheme PocketMe \
    -clonedSourcePackagesDirPath "${CACHE_DIR}/Packages" >/dev/null
  SPARKLE_BIN="$(dirname "$(find "${CACHE_DIR}/Packages/artifacts" -name sign_update -type f | head -1)")"
  [[ -x "${SPARKLE_BIN}/sign_update" ]] || fail 'Sparkle tools were not found after resolving packages.'
}
set_xcconfig() { # key value
  /usr/bin/python3 - "${ROOT_DIR}/Config/Shared.xcconfig" "$1" "$2" <<'PY'
import re, sys
path, key, value = sys.argv[1:]
text = open(path).read()
text = re.sub(rf'^{key} =.*$', f'{key} = {value}', text, flags=re.M)
open(path, 'w').write(text)
PY
}
generate
resolve_sparkle
if [[ "${1:-}" == keys ]]; then
  # Creates the EdDSA key pair on first run (private half goes to the Keychain), then prints the public half.
  "${SPARKLE_BIN}/generate_keys" >/dev/null 2>&1 || true
  public_key="$("${SPARKLE_BIN}/generate_keys" -p)"
  [[ -n "${public_key}" ]] || fail 'Could not read the Sparkle public key.'
  set_xcconfig SPARKLE_PUBLIC_ED_KEY "${public_key}"
  echo "Sparkle public key saved to Config/Shared.xcconfig: ${public_key}"
  exit 0
fi
version="$(config_value MARKETING_VERSION)"
build=$(( $(config_value CURRENT_PROJECT_VERSION) + 1 ))
notes_file="${ROOT_DIR}/release-notes.md"
do_tests=1
while (( $# )); do
  case "$1" in
    --version) version="$2"; shift 2 ;;
    --build) build="$2"; shift 2 ;;
    --notes-file) notes_file="$2"; shift 2 ;;
    --no-tests) do_tests=0; shift ;;
    --no-publish|--no-git|--no-upload) shift ;;
    *) fail "Unknown option: $1" ;;
  esac
done
[[ "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail 'Version must look like 0.1.0.'
[[ "${build}" =~ '^[0-9]+$' ]] || fail 'The build must be a positive number.'
team="$(config_value DEVELOPMENT_TEAM)"
[[ -n "${team}" ]] || fail 'Set DEVELOPMENT_TEAM in Config/Local.xcconfig.'
[[ -n "$(config_value SPARKLE_PUBLIC_ED_KEY)" ]] || fail 'Run Release/publish_mac.sh keys first, then commit Config/Shared.xcconfig.'
security find-identity -v -p codesigning | grep -q 'Developer ID Application' || fail 'No Developer ID Application certificate in the Keychain.'
xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
  || fail "No notarytool profile \"${NOTARY_PROFILE}\". Run: xcrun notarytool store-credentials ${NOTARY_PROFILE}"
command -v gh >/dev/null || fail 'Install the GitHub CLI (brew install gh) and run gh auth login.'
gh auth status >/dev/null 2>&1 || fail 'Run gh auth login.'
if (( do_tests )); then run_tests; fi

work="$(mktemp -d /private/tmp/pocketme-publish.XXXXXX)"
trap 'rm -rf "${work}"' EXIT
step "Archiving Mac ${version} (${build})"
xcodebuild archive -quiet -project "${PROJECT_PATH}" -scheme PocketMe -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "${CACHE_DIR}/Archive-Mac" \
  -clonedSourcePackagesDirPath "${CACHE_DIR}/Packages" -archivePath "${work}/Mac.xcarchive" \
  -allowProvisioningUpdates "MARKETING_VERSION=${version}" "CURRENT_PROJECT_VERSION=${build}"
cat > "${work}/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>${team}</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
step 'Signing with Developer ID'
xcodebuild -exportArchive -quiet -archivePath "${work}/Mac.xcarchive" -exportPath "${work}/export" \
  -exportOptionsPlist "${work}/export.plist" -allowProvisioningUpdates
app="${work}/export/PocketMe.app"
[[ -d "${app}" ]] || fail 'Export did not produce PocketMe.app.'
step 'Notarizing (this takes a few minutes)'
ditto -c -k --keepParent "${app}" "${work}/notarize.zip"
xcrun notarytool submit "${work}/notarize.zip" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${app}"
spctl --assess --type execute "${app}" || fail 'Gatekeeper rejected the notarized app.'
zip_name="PocketMe-${version}.zip"
ditto -c -k --keepParent "${app}" "${work}/${zip_name}"

step 'Writing the update feed'
signature_attrs="$("${SPARKLE_BIN}/sign_update" "${work}/${zip_name}")"
/usr/bin/python3 - "${work}/appcast.xml" "${REPO}" "${version}" "${build}" "${zip_name}" "${notes_file}" "${signature_attrs}" <<'PY'
import sys, html, email.utils, re
out, repo, version, build, zip_name, notes_file, attrs = sys.argv[1:]
notes = []
try:
    section = None
    for line in open(notes_file).read().splitlines():
        if line.startswith('# '): section = line[2:].strip()
        elif section == version and line.startswith('- '): notes.append(line[2:].strip())
except OSError:
    pass
body = ''.join(f'<li>{html.escape(n)}</li>' for n in notes)
description = f'<description><![CDATA[<ul>{body}</ul>]]></description>' if body else ''
open(out, 'w').write(f'''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>PocketMe</title>
    <item>
      <title>{version}</title>
      <pubDate>{email.utils.formatdate()}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      {description}
      <enclosure url="https://github.com/{repo}/releases/download/v{version}/{zip_name}" type="application/octet-stream" {attrs}/>
    </item>
  </channel>
</rss>
''')
PY
notes_body="$(/usr/bin/python3 - "${notes_file}" "${version}" <<'PY'
import sys
section = None
for line in open(sys.argv[1]).read().splitlines():
    if line.startswith('# '): section = line[2:].strip()
    elif section == sys.argv[2] and line.startswith('- '): print(line)
PY
)"
step "Publishing v${version} to GitHub Releases"
gh release create "v${version}" "${work}/${zip_name}" "${work}/appcast.xml" --repo "${REPO}" \
  --title "PocketMe ${version}" --notes "${notes_body:-PocketMe ${version}}" --latest
set_xcconfig CURRENT_PROJECT_VERSION "${build}"
echo "Published: https://github.com/${REPO}/releases/tag/v${version}"
echo "Commit Config/Shared.xcconfig to record build ${build}."
