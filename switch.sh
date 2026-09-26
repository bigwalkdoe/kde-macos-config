#!/usr/bin/env bash
# kde-macos-config -- switch.sh
# Automates dark/light mode on a daily schedule without a cron entry:
#   ./switch.sh --install        # install user systemd timer + service
#   ./switch.sh --uninstall      # remove them
#   ./switch.sh --auto           # switch mode if the clock crossed a boundary
#   ./switch.sh --check          # report desired vs current mode, change nothing
#   ./switch.sh --light | --dark # explicit switch (delegates to apply.sh)
#
# Times default to sunrise/sunset and can be overridden per-machine in
#   ~/.config/kde-macos/switch.conf   ->   SUNRISE=06:30   SUNSET=19:30
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"
UCFG="$HOME/.config/kde-macos"
SVC=kde-macos-switch.service
TIM=kde-macos-switch.timer

# ---- configuration --------------------------------------------------------
SUNRISE="06:30"
SUNSET="19:30"
if [ -f "$UCFG/switch.conf" ]; then
  # shellcheck source=/dev/null
  . "$UCFG/switch.conf"
fi

# Validate the schedule. switch.conf is sourced, so a typo there (empty value,
# "7:00" without the leading zero, sunset before sunrise) would otherwise make
# the comparison below fail on every single timer run - i.e. silently forever.
_valid_time(){ [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; }
for _t in SUNRISE SUNSET; do
  _v="${!_t}"
  _valid_time "$_v" || { echo "FAIL: $_t='$_v' in $UCFG/switch.conf is not HH:MM (00:00-23:59)" >&2; exit 1; }
done
_su="${SUNRISE//:/}"; _ss="${SUNSET//:/}"
[ "$_su" -lt "$_ss" ] || { echo "FAIL: SUNRISE ($SUNRISE) must be earlier than SUNSET ($SUNSET)" >&2; exit 1; }

LOGDIR="$UCFG"
LOGFILE="$LOGDIR/switch.log"
# Audit trail for timer-driven switches: apply.sh's output otherwise only ends
# up in the journal, where it is easy to miss. Never let logging break a switch.
log(){ printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >&2
      mkdir -p "$LOGDIR" 2>/dev/null && printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >> "$LOGFILE" 2>/dev/null || true
    }

desired_mode() {
  local now up dn
  now="$(date +%H%M)" up="${SUNRISE//:/}" dn="${SUNSET//:/}"
  [ "$now" -ge "$up" ] && [ "$now" -lt "$dn" ] && echo light || echo dark
}

current_mode() {
  local ico lnf
  ico="$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || echo)"
  lnf="$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage 2>/dev/null || echo)"
  case "$ico" in
    FairyWren_Dark)  echo dark ;;
    FairyWren_Light) echo light ;;
    *) case "$lnf" in
         com.github.vinceliuice.Orchis-dark) echo dark ;;
         com.github.vinceliuice.Orchis)     echo light ;;
         *) echo "unknown($ico/$lnf)" ;;
       esac ;;
  esac
}

apply_mode() { # apply_mode <light|dark>
  log "applying $1 (current=$(current_mode))"
  if "$ROOT/apply.sh" "--$1"; then
    log "applied $1 ok"
  else
    # apply.sh rolls back its own backup if it failed after starting to change
    # things, and exits non-zero either way (a preflight failure changes nothing).
    log "apply --$1 did not complete (see apply.sh output above)"
    return 1
  fi
}

# Restarting plasmashell visibly drops whatever the user is looking at, so a
# timer-driven switch must not fire on an unattended/locked screen. (KWin's
# queryWindowInfo is interactive - it asks you to click a window - so it cannot
# be used to detect a fullscreen/presentation window here; see README
# "Known limitations".)
session_busy() {
  command -v loginctl >/dev/null 2>&1 || return 1
  local sess
  sess="$(loginctl 2>/dev/null | awk -v u="$USER" '$3==u {print $1; exit}')"
  [ -n "$sess" ] || return 1
  [ "$(loginctl show-session "$sess" -p LockHint --value 2>/dev/null)" = "yes" ]
}

# ---- actions ---------------------------------------------------------------
case "${1:---auto}" in
  --light|--dark)
    apply_mode "${1#--}"
    ;;
  --auto)
    D="$(desired_mode)"; C="$(current_mode)"
    echo "switch: desired=$D current=$C (sunrise=$SUNRISE sunset=$SUNSET)"
    if [ "$D" = "$C" ]; then echo "no change needed"; exit 0; fi
    if session_busy; then
      # Retry on the next 15 min tick rather than forcing it now.
      log "deferring $D: session is locked (plasmashell restart would be disruptive)"
      exit 0
    fi
    apply_mode "$D"
    ;;
  --check)
    D="$(desired_mode)"; C="$(current_mode)"
    echo "desired=$D current=$C sunrise=$SUNRISE sunset=$SUNSET"
    ;;
  --install)
    mkdir -p "$UCFG" "$HOME/.config/systemd/user"
    [ -f "$UCFG/switch.conf" ] && echo "kept $UCFG/switch.conf" \
      || { printf 'SUNRISE=%s\nSUNSET=%s\n' "$SUNRISE" "$SUNSET" > "$UCFG/switch.conf"; echo "wrote $UCFG/switch.conf"; }
    cat > "$HOME/.config/systemd/user/$SVC" <<EOF
[Unit]
Description=kde-macos dark/light switcher
After=plasma-plasmashell.service

[Service]
Type=oneshot
ExecStart=$ROOT/switch.sh --auto
EOF
    cat > "$HOME/.config/systemd/user/$TIM" <<EOF
[Unit]
Description=Check dark/light boundary for kde-macos-config

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now "$TIM"
    echo "installed: $TIM (runs every 15 min, first fire 2 min after login)"
    echo "config:    $UCFG/switch.conf"
    ;;
  --uninstall)
    systemctl --user disable --now "$TIM" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$SVC" "$HOME/.config/systemd/user/$TIM"
    systemctl --user daemon-reload
    echo "uninstalled: $TIM"
    ;;
  *)
    echo "usage: $0 [--auto|--check|--install|--uninstall|--light|--dark]"
    exit 2
    ;;
esac
