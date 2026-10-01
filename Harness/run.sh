#!/bin/bash
# Headless logic tests: compile the real source files with a harness main and run it.
#   Harness/run.sh phase1
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="${1:?usage: run.sh <phase1|...>}"
S=Sources/MDmaster
case "$NAME" in
  phase1) FILES="$S/SheetMeta.swift $S/LibraryScanner.swift $S/LibraryFileOps.swift $S/Debouncer.swift $S/SheetIO.swift $S/FolderWatcher.swift" ;;
  session) FILES="$S/SheetSession.swift $S/SheetIO.swift $S/Debouncer.swift $S/SheetMeta.swift" ;;
  phase2) FILES="$S/MarkdownFormatting.swift" ;;
  *) echo "unknown harness"; exit 2 ;;
esac
OUT="$(mktemp -d)/harness"
cp "Harness/$NAME.swift" "$(dirname "$OUT")/main.swift"
swiftc -O -o "$OUT" $FILES "$(dirname "$OUT")/main.swift"
"$OUT"
