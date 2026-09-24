#!/usr/bin/env bash
# kde-macos-config — backup.sh
# Creates a timestamped, single-directory backup of every configuration file
# that this project can touch. Prints the backup directory path on stdout.
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
BK="$HOME/.config/kde-backups/$TS"
mkdir -p "$BK"

# Affected configuration files (only those that exist are copied).
FILES=(
  plasma-org.kde.plasma.desktop-appletsrc
  plasmashellrc
  kdeglobals
  kwinrc
  kglobalshortcutsrc
  kcminputrc
  ksplashrc
  plasmarc
  dolphinrc
  gwenviewrc
  kwinrulesrc
  kwinoutputconfig.json
  plasma-localerc
  plasma.keybindings
)
for f in "${FILES[@]}"; do
  if [ -f "$HOME/.config/$f" ]; then
    cp -a "$HOME/.config/$f" "$BK/"
  fi
done

# GTK theme settings
for g in gtk-3.0 gtk-4.0; do
  if [ -f "$HOME/.config/$g/settings.ini" ]; then
    mkdir -p "$BK/$g"
    cp -a "$HOME/.config/$g/settings.ini" "$BK/$g/"
  fi
done

# Pristine look-and-feel defaults (snapshotted BEFORE apply.sh runs the LNF
# patch, so this is the exact undo for rollback.sh).
LNFD="$HOME/.local/share/plasma/look-and-feel"
for l in com.github.vinceliuice.Orchis com.github.vinceliuice.Orchis-dark; do
  if [ -f "$LNFD/$l/contents/defaults" ]; then
    mkdir -p "$BK/lnf/$l/contents"
    cp -a "$LNFD/$l/contents/defaults" "$BK/lnf/$l/contents/"
  fi
done

# Self-verification: the critical files must have landed.
CRITICAL=("$BK/plasma-org.kde.plasma.desktop-appletsrc" "$BK/plasmashellrc" "$BK/kdeglobals" "$BK/kwinrc")
for c in "${CRITICAL[@]}"; do
  if [ ! -f "$c" ]; then
    echo "FAIL: backup missing $c" >&2
    exit 1
  fi
done

echo "BackUp=$BK"
find "$BK" -type f | sort | sed "s|$HOME|~|"