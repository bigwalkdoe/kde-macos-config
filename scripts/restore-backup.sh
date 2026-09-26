#!/usr/bin/env bash
# kde-macos-config -- scripts/restore-backup.sh
# The ONE implementation of "put a backup back". Both rollback.sh and
# apply.sh's automatic fail-safe go through here, so the list of restored files
# exists exactly once and cannot drift between the two callers.
#
# It is both sourceable and executable:
#   source scripts/restore-backup.sh   # defines shutdown_shell/start_shell/restore_backup
#   ./scripts/restore-backup.sh [DIR]  # restore DIR (default: newest backup)
#
# INVARIANT: AFFECTED lists every top-level ~/.config file apply.sh may write
# (backup.sh copies the same set). The three writes that live outside that
# flat set are handled explicitly further down: fontconfig/fonts.conf, the
# vendored wallpaper, and the user-local Orchis LNF defaults. Adding a write to
# apply.sh means adding it here (or to one of those explicit blocks) AND to
# backup.sh, so the restore stays the exact inverse of the apply.
#
# plasmashell is a systemd user unit (plasma-plasmashell.service, Type=dbus).
# shutdown_shell [graceful|hard]  -> stop plasmashell and wait for the bus name
# NOTE: the bus-name checks anchor on "org.kde.plasmashell" + whitespace so the
# kded6-owned name "org.kde.plasmashell.accentColor" can never match.
AFFECTED=(
  plasma-org.kde.plasma.desktop-appletsrc plasmarc plasmashellrc kdeglobals kwinrc
  kglobalshortcutsrc kcminputrc ksplashrc dolphinrc gwenviewrc kwinrulesrc
  kwinoutputconfig.json plasma-localerc
)
ORCHIS_LNFS="com.github.vinceliuice.Orchis com.github.vinceliuice.Orchis-dark"

wait_shell_up() {
  local _
  for _ in $(seq 1 30); do
    busctl --user list --no-pager 2>/dev/null | grep -q '^org\.kde\.plasmashell[[:space:]]' && return 0
    sleep 1
  done
  return 1
}
wait_shell_down() {
  local _
  for _ in $(seq 1 20); do
    busctl --user list --no-pager 2>/dev/null | grep -q '^org\.kde\.plasmashell[[:space:]]' || return 0
    sleep 1
  done
  return 1
}
start_shell() {
  systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
  if ! systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1; then
    systemctl --user start plasma-plasmashell.service 2>/dev/null \
      || { ( setsid nohup plasmashell >"$HOME/.local/share/plasmashell-kde-macos.log" 2>&1 & ) || return 1; }
  fi
  wait_shell_up
}
shutdown_shell() {
  # NOTE: a second start of plasma-plasmashell.service within ~10s trips
  # systemd's user-unit start-rate-limit, leaving the unit "failed" while a
  # stray plasmashell keeps running detached. Always reset-failed and pace
  # restarts; fall back to a manual spawn when the unit cannot be started.
  if [ "${1:-graceful}" = "graceful" ]; then
    systemctl --user stop plasma-plasmashell.service 2>/dev/null || true
  else
    systemctl --user kill -s KILL --kill-whom=main plasma-plasmashell.service 2>/dev/null || true
  fi
  # mop up any orphaned instances (unit failed / manually spawned shells)
  pkill -x plasmashell 2>/dev/null || true
  wait_shell_down
  pkill -9 -x plasmashell 2>/dev/null || true
  systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
  sleep 2
}

# restore_backup <backup-dir> [quiet]
# Files present in the backup are copied back; files that were absent when the
# backup was taken are removed, so the restore is exactly reversible.
restore_backup() {
  local BK="${1:?restore_backup needs a backup dir}"
  local QUIET="${2:-}"
  # Resolve $HOME-derived paths HERE, not at source time. This file is sourced by
  # apply.sh/rollback.sh, and a caller (or a test harness) that changes $HOME
  # after sourcing would otherwise make the restore write outside the intended
  # home - a silent, hard-to-spot data-loss bug.
  local LNFD="$HOME/.local/share/plasma/look-and-feel"
  local WALLPAPER="$HOME/.local/share/wallpapers/kde-setup-02/wavy_lines_v01_5120x2880.png"
  [ -d "$BK" ] || { echo "restore_backup: no such backup: $BK" >&2; return 1; }
  if [ -z "$QUIET" ]; then echo; echo "### Restoring from $BK"; fi
  shutdown_shell graceful

  for g in gtk-3.0 gtk-4.0; do
    if [ -d "$BK/$g" ]; then
      mkdir -p "$HOME/.config/$g"
      cp -a "$BK/$g/settings.ini" "$HOME/.config/$g/settings.ini"
    fi
  done

  for f in "${AFFECTED[@]}"; do
    if [ -f "$BK/$f" ]; then
      # Deliberately best-effort: in the fail-safe path we would rather restore
      # 13 of 14 files and get plasmashell back than abort half-way. But do not
      # let a failure be invisible.
      cp -a "$BK/$f" "$HOME/.config/" 2>/dev/null || echo "  WARN: could not restore $f" >&2
    else
      rm -f "$HOME/.config/$f"
    fi
  done

  # fontconfig: apply.sh overwrites this file, so restore (or remove) it too.
  if [ -d "$BK/fontconfig" ]; then
    mkdir -p "$HOME/.config/fontconfig"
    cp -a "$BK/fontconfig/fonts.conf" "$HOME/.config/fontconfig/fonts.conf"
    [ -n "$QUIET" ] || echo "  restored fontconfig/fonts.conf"
  else
    rm -f "$HOME/.config/fontconfig/fonts.conf"
    [ -n "$QUIET" ] || echo "  removed fontconfig/fonts.conf (absent before this apply)"
  fi
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true

  # Wallpaper: apply.sh self-heals a missing vendored wallpaper. If the backup
  # recorded it as absent, we were the ones who installed it - remove it.
  if [ -f "$BK/wallpaper.state" ] && [ "$(cat "$BK/wallpaper.state")" = "absent" ]; then
    rm -f "$WALLPAPER"
    [ -n "$QUIET" ] || echo "  removed wallpaper installed by this apply"
  fi

  # Undo the LNF defaults patch (cursor/icons/decoration) this apply wrote.
  for l in $ORCHIS_LNFS; do
    if [ -f "$BK/lnf/$l/contents/defaults" ]; then
      mkdir -p "$LNFD/$l/contents"
      cp -a "$BK/lnf/$l/contents/defaults" "$LNFD/$l/contents/"
    fi
  done

  busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure 2>/dev/null || true
  start_shell || true
  [ -n "$QUIET" ] || echo "### Restore complete."
  return 0
}

# Executed directly: restore a backup (default: the newest one).
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  set -euo pipefail
  BK="${1:-$(ls -1dt "$HOME"/.config/kde-backups/*/ 2>/dev/null | head -1)}"
  if [ -z "$BK" ]; then
    echo "No backups found under ~/.config/kde-backups/ - nothing to restore." >&2
    exit 1
  fi
  restore_backup "$BK"
fi
