#!/usr/bin/env bash
# kde-macos-config -- scripts/desktop-file-path.sh
# Print the path of the installed .desktop file for <desktop-file-id>, or exit 1
# if no such desktop file exists.
#
# It is both sourceable and executable:
#   source scripts/desktop-file-path.sh     # defines desktop_file_path
#   ./scripts/desktop-file-path.sh NAME     # prints the path, or exits 1
#
# WHY THIS EXISTS: a task manager's "launchers" list holds
# "applications:<desktop-file-id>" entries. Pinning an id that has no desktop file
# makes Plasma draw a generic "Unknown application" tile - no name, no icon - and
# because layout.js rewrites the whole list on every apply, that tile cannot be
# unpinned by hand. This repo shipped applications:code.desktop while VS Code
# installs com.microsoft.VSCode.desktop, so the dock carried a broken entry that
# survived every attempt to remove it. Validate the id before pinning it.
#
# Only the XDG application directories are searched, because those are the only
# ones Plasma consults when resolving "applications:<id>". A desktop file that
# sits somewhere else (hand-copied, or a flatpak export missing from
# XDG_DATA_DIRS) would resolve here but still render as "Unknown application", so
# searching wider would reintroduce the exact bug this prevents.

_desktop_dirs(){
  # XDG_DATA_DIRS is a colon-separated LIST, so it has to be split before use.
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share} \
    | tr ':' '\n' | sed '/^$/d; s|$|/applications|'
}

# desktop_file_path <id> -> prints the resolved path on stdout.
desktop_file_path(){
  local id="${1:-}" dir
  [ -n "$id" ] || return 1
  case "$id" in
    */*|*[!A-Za-z0-9._-]*) return 1 ;;   # a desktop-file id, never a path
  esac
  while IFS= read -r dir; do
    [ -f "$dir/$id" ] || continue
    printf '%s\n' "$dir/$id"
    return 0
  done < <(_desktop_dirs)
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  desktop_file_path "$@"
fi
