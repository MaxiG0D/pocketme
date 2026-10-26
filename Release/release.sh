#!/bin/zsh
set -euo pipefail
# Matches the original Carnet applet's arguments. Publishing signs, notarizes and uploads to GitHub Releases.
if [[ " $* " != *' --no-publish '* ]]; then
  exec /bin/zsh "$(dirname "$0")/publish_mac.sh" "$@"
fi
exec /bin/zsh "$(dirname "$0")/archive.sh" Mac "$@"
