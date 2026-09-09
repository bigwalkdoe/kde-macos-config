#!/usr/bin/env bash
# kde-macos-config -- rollback.sh
# Restores the most recent timestamped backup and reloads the desktop shell.
# No manual bookkeeping needed: backups are chronological directories under
# ~/.config/kde-backups/YYYYmmdd-HHMMSS/.
set -euo pipefail

BK="$(ls -1dt "$HOME"/.config/kde-backups/*/ 2>/dev/null | head -1)"
if [ -z "$BK" ]; then
  echo "No backups found under ~/.config/kde-backups/ — nothing to restore." >&2
  exit 1
fi

echo "Restoring from: $BK"
systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
pkill -9 -x plasmashell 2>/dev/null || true
for i in $(seq 1 20); do
  # exact-name match: org.kde.plasmashell.accentColor (kded6) must NOT count
  busctl --user list --no-pager 2>/dev/null | grep -q '^org\.kde\.plasmashell[[:space:]]' || break
  sleep 1
done

if [ -d "$BK/gtk-3.0" ]; then
  mkdir -p "$HOME/.config/gtk-3.0"
  cp -a "$BK/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
fi
if [ -d "$BK/gtk-4.0" ]; then
  mkdir -p "$HOME/.config/gtk-4.0"
  cp -a "$BK/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
fi

# Restore: files present in the backup are copied back; files that were absent
# when the backup was taken are removed, so the restore is exactly reversible.
AFFECTED=(
  plasma-org.kde.plasma.desktop-appletsrc plasmarc plasmashellrc kdeglobals kwinrc
  kglobalshortcutsrc kcminputrc ksplashrc dolphinrc gwenviewrc kwinrulesrc
  kwinoutputconfig.json plasma-localerc
)
for f in "${AFFECTED[@]}"; do
  if [ -f "$BK/$f" ]; then
    cp -a "$BK/$f" "$HOME/.config/" 2>/dev/null || true
  else
    rm -f "$HOME/.config/$f"
  fi
done

busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure 2>/dev/null || true

systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
systemctl --user start plasma-plasmashell.service 2>/dev/null || { ( setsid nohup plasmashell >/dev/null 2>&1 & ) || true; }
for i in $(seq 1 30); do
  busctl --user list --no-pager 2>/dev/null | grep -q '^org\.kde\.plasmashell[[:space:]]' && break
  sleep 1
done

echo "Rollback complete — desktop reloading with the previous configuration."