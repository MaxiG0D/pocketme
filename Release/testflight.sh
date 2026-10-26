#!/bin/zsh
set -euo pipefail
# Matches the original Carnet applet's arguments; uploads are unavailable in M1.
if [[ " $* " != *' --no-upload '* ]]; then
  echo 'error: PocketMe TestFlight needs its own App Store listing, signing, icons and distribution setup (M7).' >&2
  exit 1
fi
exec /bin/zsh "$(dirname "$0")/archive.sh" TestFlight "$@"
