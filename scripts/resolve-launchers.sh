#!/usr/bin/env bash
# kde-macos-config -- scripts/resolve-launchers.sh [LISTFILE]
# Print the pinned dock launcher list for layout.js on stdout, as a single
# comma-separated line of "applications:<desktop-file-id>" entries.
# Progress and skipped entries go to stderr, so apply.sh can capture stdout alone.
#
# Only ids with an installed .desktop file are emitted (see
# scripts/desktop-file-path.sh). An empty result is an error rather than an empty
# dock: that means the list is wrong, and silently pinning nothing would look
# like a successful apply while quietly clearing the dock.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="${1:-$ROOT/scripts/dock-launchers.list}"

if [ ! -f "$LIST" ]; then
  echo "resolve-launchers: no such list: $LIST" >&2
  exit 1
fi

out=""
pinned=0
skipped=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"                            # strip comments
  line="${line#"${line%%[![:space:]]*}"}"      # trim leading space
  line="${line%"${line##*[![:space:]]}"}"      # trim trailing space
  [ -n "$line" ] || continue

  picked=""
  IFS='|' read -r -a cands <<< "$line"
  for id in "${cands[@]}"; do
    id="${id//[[:space:]]/}"
    [ -n "$id" ] || continue
    if bash "$ROOT/scripts/desktop-file-path.sh" "$id" >/dev/null 2>&1; then
      picked="$id"
      break
    fi
  done

  if [ -z "$picked" ]; then
    echo "  launchers: not installed, skipping '$line'" >&2
    skipped=$((skipped + 1))
    continue
  fi
  out="${out:+$out,}applications:$picked"
  pinned=$((pinned + 1))
done < "$LIST"

if [ "$pinned" -eq 0 ]; then
  echo "resolve-launchers: nothing in $LIST resolved to an installed desktop file" >&2
  exit 1
fi
if [ "$skipped" -gt 0 ]; then
  echo "  launchers: $pinned pinned, $skipped skipped as not installed" >&2
fi
printf '%s\n' "$out"
