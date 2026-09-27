#!/usr/bin/env bash
# kde-macos-config — backup.sh
# Creates a timestamped, single-directory backup of every configuration file
# that this project can touch. Prints the backup directory path on stdout.
#
# INVARIANT: the FILES list below is exactly the set that apply.sh may write,
# and exactly the set that rollback.sh / apply.sh's fail-safe restore. A file
# that is written but neither listed here nor in the AFFECTED restore lists is
# an irreversible change - do not add one without adding it to both.
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

# fontconfig: apply.sh OVERWRITES ~/.config/fontconfig/fonts.conf to reject the
# Inter web/woff-hinted subsets (a known fontconfig cache-corruption trigger).
# It was previously not backed up, so a rollback left the rejectfont in place.
FCT="$HOME/.config/fontconfig/fonts.conf"
if [ -f "$FCT" ]; then
  mkdir -p "$BK/fontconfig"
  cp -a "$FCT" "$BK/fontconfig/"
fi

# Pristine look-and-feel defaults (snapshotted BEFORE apply.sh runs the LNF
# patch, so this is the exact undo for rollback.sh).
LNFD="$HOME/.local/share/plasma/look-and-feel"
for l in com.github.vinceliuice.Orchis com.github.vinceliuice.Orchis-dark; do
  if [ -f "$LNFD/$l/contents/defaults" ]; then
    mkdir -p "$BK/lnf/$l/contents"
    cp -a "$LNFD/$l/contents/defaults" "$BK/lnf/$l/contents/"
  fi
done

# Record whether the vendored wallpaper was already installed BEFORE apply.sh
# runs. apply.sh self-heals a missing wallpaper by copying it out of assets/,
# which is a write outside ~/.config that nothing could undo; recording the
# prior state lets rollback remove it again if we were the ones who put it there.
WALL="$HOME/.local/share/wallpapers/kde-setup-02/wavy_lines_v02_5120x2880.png"
[ -f "$WALL" ] && echo "present" > "$BK/wallpaper.state" || echo "absent" > "$BK/wallpaper.state"

# Self-verification: the critical files must have landed.
CRITICAL=("$BK/plasma-org.kde.plasma.desktop-appletsrc" "$BK/plasmashellrc" "$BK/kdeglobals" "$BK/kwinrc")
for c in "${CRITICAL[@]}"; do
  if [ ! -f "$c" ]; then
    echo "FAIL: backup missing $c" >&2
    exit 1
  fi
done

# Retention: switch.sh --auto can apply twice a day, so prune old directories
# instead of letting ~/.config/kde-backups grow without bound. KEEP may be
# overridden (KDE_BACKUP_KEEP); the newest KEEP timestamped backups survive.
# Only YYYYMMDD-HHMMSS directories are ever considered, so anything a human
# put in that directory by hand is never a deletion candidate.
KEEP="${KDE_BACKUP_KEEP:-20}"
if [ "$KEEP" -ge 1 ] 2>/dev/null; then
  # -1dt sorts by mtime, newest first; skip the first KEEP, delete the rest.
  ls -1dt "$HOME"/.config/kde-backups/[0-9]*/ 2>/dev/null | tail -n "+$((KEEP + 1))" | while read -r old; do
    rm -rf "$old" && echo "pruned old backup: $(basename "$old")"
  done
fi

echo "BackUp=$BK"
find "$BK" -type f | sort | sed "s|$HOME|~|"
