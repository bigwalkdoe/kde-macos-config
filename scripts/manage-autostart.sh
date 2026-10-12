#!/usr/bin/env bash
# kde-macos-config -- manage-autostart.sh
# Reads scripts/autostart.list and ensures ~/.config/autostart/ matches exactly.
# Creates symlinks to .desktop files in /usr/share/applications/ or /etc/xdg/autostart/.
# Removes any autostart entries not listed (opt-in declarative model).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LIST_FILE="$ROOT/autostart.list"
AUTOSTART_DIR="$HOME/.config/autostart"

[ -f "$LIST_FILE" ] || { echo "List file not found: $LIST_FILE" >&2; exit 1; }

mkdir -p "$AUTOSTART_DIR"

# Parse the list file: ignore blanks and comments, collect desktop IDs
mapfile -t DESKTOP_IDS < <(grep -vE '^\s*(#|$)' "$LIST_FILE" | awk '{print $1}')

# Find the .desktop file for a given ID
find_desktop_file() {
    local id="$1"
    local paths=(
        "/usr/share/applications/$id"
        "/usr/local/share/applications/$id"
        "/etc/xdg/autostart/$id"
        "$HOME/.local/share/applications/$id"
    )
    for p in "${paths[@]}"; do
        [ -f "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

# Track which files we want to keep (by basename)
want=()

echo "Managing autostart from $LIST_FILE"
for id in "${DESKTOP_IDS[@]}"; do
    if desktop_path="$(find_desktop_file "$id")"; then
        target="$AUTOSTART_DIR/$id"
        if [ -L "$target" ] || [ -f "$target" ]; then
            # Check if it points to the right place
            if [ "$(readlink -f "$target" 2>/dev/null || echo "$target")" = "$(readlink -f "$desktop_path")" ]; then
                echo "  ✓ $id (already linked)"
            else
                ln -sf "$desktop_path" "$target"
                echo "  ↻ $id (updated symlink)"
            fi
        else
            ln -s "$desktop_path" "$target"
            echo "  + $id (linked)"
        fi
        want+=("$id")
    else
        echo "  ✗ $id (desktop file not found, skipping)" >&2
    fi
done

# Remove any .desktop files in autostart dir that we don't want
shopt -s nullglob
for existing in "$AUTOSTART_DIR"/*.desktop; do
    base="$(basename "$existing")"
    keep=0
    for w in "${want[@]}"; do
        [ "$w" = "$base" ] && { keep=1; break; }
    done
    if [ "$keep" -eq 0 ]; then
        rm -f "$existing"
        echo "  - $base (removed, not in list)"
    fi
done

echo "Autostart sync complete. Active: ${#want[@]} entries."