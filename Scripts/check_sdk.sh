#!/bin/zsh
# GitHub builds with the Xcode in .xcode-version, which can be older than the one on the Mac.
# Code behind `#available(iOS N)` for an OS newer than that Xcode's SDK must also sit inside
# `#if compiler(>=…)`, or it compiles here and fails on GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."
sdk_major="$(cut -d. -f1 .xcode-version)"
find App Shared ShareExtension-iOS ShareExtension-macOS SafariExtension-macOS Tests -name '*.swift' -print0 2>/dev/null |
  xargs -0 awk -v max="${sdk_major}" '
    FNR == 1 { depth = 0; delete guarded }
    /^[ \t]*#if/ { depth++; guarded[depth] = ($0 ~ /compiler\(/) }
    /^[ \t]*#endif/ { delete guarded[depth]; depth-- }
    /available\(/ {
      line = $0
      while (match(line, /(iOS|macOS|watchOS|tvOS|visionOS) [0-9]+/)) {
        split(substr(line, RSTART, RLENGTH), part, " ")
        if (part[2] + 0 > max + 0) {
          ok = 0
          for (d = 1; d <= depth; d++) if (guarded[d]) ok = 1
          if (!ok) { printf "%s:%d: %s %s is newer than the Xcode %s GitHub builds with. Wrap it in #if compiler(>=…) … #endif.\n", FILENAME, FNR, part[1], part[2], max; bad = 1 }
        }
        line = substr(line, RSTART + RLENGTH)
      }
    }
    END { exit bad }'
