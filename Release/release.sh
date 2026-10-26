#!/bin/zsh
set -euo pipefail
# Matches the original Carnet applet's arguments; publishing requires distribution setup.
if [[ " $* " != *' --no-publish '* ]]; then
  echo 'error: PocketMe publishing needs distribution setup in M7. Uncheck Publish for a local archive.' >&2
  exit 1
fi
exec /bin/zsh "$(dirname "$0")/archive.sh" Mac "$@"
