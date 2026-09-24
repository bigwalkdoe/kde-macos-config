#!/usr/bin/env bash
# kde-macos-config -- scripts/patch-lnf.sh
# The Orchis look-and-feel packages (both the system copy and any user-local
# shadow installed by the Global Theme KCM) ship contents/defaults that point
# at cursors/icons which are NOT installed here:
#   light: Vimix cursor + Tela-circle icons
#   dark:  Vimix-dark cursor + Tela-circle-dark icons
# All absent, so KDE silently falls back to Breeze whenever the global theme is
# applied through System Settings or lookandfeeltool -- which is why switching
# dark/light "reverted icons and changed the cursor".
#
# This script patches the USER-LEVEL copy (~/.local/share/plasma/look-and-feel/)
# so any apply path keeps the repo's chosen assets. System files are untouched.
set -euo pipefail
CFG_DIR="$HOME/.local/share/plasma/look-and-feel"

ld() { # ld <asset-type> <name>: print 1 if a user-local LNF dir exists
  [ -d "$CFG_DIR/$1" ]
}

patch_defaults() { # patch_defaults <lnf-dir> <cursor> <icons>
  local lnf="$CFG_DIR/$1" cur="$2" ico="$3" f="$CFG_DIR/$1/contents/defaults"
  [ -f "$f" ] || { echo "skip: $f missing"; return 0; }
  sed -i "s/^cursorTheme=.*/cursorTheme=$cur/" "$f"
  sed -i "s|^Theme=Tela-circle.*|Theme=$ico|" "$f"
  echo "patched $(basename "$lnf") -> cursor=$cur icons=$ico"
}

say() { echo "### $*"; }

say "Patching user-local Orchis look-and-feel defaults"
for l in \
  "com.github.vinceliuice.Orchis Breeze_Light FairyWren_Light" \
  "com.github.vinceliuice.Orchis-dark breeze_cursors FairyWren_Dark"; do
  set -- $l
  if ! ld "$1"; then
    say "no user-local $1 -- copying system LNF so the patch sticks"
    if [ -d "/usr/share/plasma/look-and-feel/$1" ]; then
      mkdir -p "$CFG_DIR"
      cp -a "/usr/share/plasma/look-and-feel/$1" "$CFG_DIR/"
    else
      echo "skip: system LNF $1 also missing"
      continue
    fi
  fi
  patch_defaults "$1" "$2" "$3"
done
echo "=== resulting defaults (icons/cursor lines) ==="
grep -rE "^cursorTheme=|^Theme=" "$CFG_DIR"/com.github.vinceliuice.Orchis*/contents/defaults 2>/dev/null || echo "none"