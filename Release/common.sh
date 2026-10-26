#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
# Keep build products outside Documents: iCloud attributes can break signing.
CACHE_DIR="${POCKETME_BUILD_ROOT:-${HOME}/Library/Caches/PocketMe}"
mkdir -p "${CACHE_DIR}"
# Download this checkout's evicted iCloud files before Xcode or config reads can stall.
/usr/bin/python3 - "${ROOT_DIR}" <<'MATERIALIZE'
from pathlib import Path
import subprocess, sys
root = Path(sys.argv[1])
files = [root / 'project.yml']
for name in ['App', 'Shared', 'Tests', 'Config', 'Release', 'ShareExtension-iOS', 'ShareExtension-macOS']:
    files.extend((root / name).rglob('*'))
requested = [p for p in files if p.is_file() and p.stat().st_flags & 0x40000000]
if requested:
    print('==> Downloading project files from iCloud Drive', flush=True)
    for path in requested:
        subprocess.run(['/usr/bin/brctl', 'download', str(path)], check=False)
MATERIALIZE
fail() { echo "error: $*" >&2; exit 1; }
step() { echo "==> $*"; }
PROJECT_PATH="${CACHE_DIR}/Project/PocketMe.xcodeproj"
generate() {
  mkdir -p "${CACHE_DIR}/Project"
  xcodegen generate --spec "${ROOT_DIR}/project.yml" --project "${CACHE_DIR}/Project"
  if [[ ! -e "${CACHE_DIR}/Project/Config" ]]; then ln -s "${ROOT_DIR}/Config" "${CACHE_DIR}/Project/Config"; fi
}
config_value() {
  /usr/bin/python3 - "${ROOT_DIR}" "$1" <<'PY'
from pathlib import Path
import sys
value = ''
for name in ['Shared.xcconfig', 'Local.xcconfig']:
    p = Path(sys.argv[1]) / 'Config' / name
    if not p.exists(): continue
    for line in p.read_text().splitlines():
        key, separator, item = line.partition('=')
        if separator and key.strip() == sys.argv[2]: value = item.split('//')[0].strip()
print(value)
PY
}
run_tests() {
  step 'Running the PocketMe tests'
  xcodebuild test -quiet -project "${PROJECT_PATH}" -scheme PocketMe \
    -destination 'platform=macOS' -derivedDataPath "${CACHE_DIR}/Tests" CODE_SIGNING_ALLOWED=NO
}
