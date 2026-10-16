#!/usr/bin/env bash
# spectre-kde-config -- switch.sh
# Automates dark/light mode on a daily schedule without a cron entry:
#   ./switch.sh --install        # install user systemd timer + service
#   ./switch.sh --uninstall      # remove them
#   ./switch.sh --auto           # switch mode if the clock crossed a boundary
#   ./switch.sh --check          # report desired vs current mode, change nothing
#   ./switch.sh --light | --dark # explicit switch (delegates to apply.sh) and pin
#   ./switch.sh --follow-schedule  # drop the pin, hand control back to the timer
#
# Times default to sunrise/sunset and can be overridden per-machine in
#   ~/.config/kde-macos/switch.conf   ->   SUNRISE=06:30   SUNSET=19:30
# A manual --light/--dark pins that mode in the same file (OVERRIDE=light|dark),
# which --auto then honours until --follow-schedule clears it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"
UCFG="$HOME/.config/kde-macos"
SVC=kde-macos-switch.service
TIM=kde-macos-switch.timer

# ---- configuration --------------------------------------------------------
SUNRISE="06:30"
SUNSET="19:30"
# Empty means "follow the schedule"; light/dark pins the mode regardless of the
# clock. Defaulted here rather than only in switch.conf so an absent key and an
# absent file behave the same under `set -u`.
OVERRIDE=""
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
# Same reasoning for the pin: an unrecognised value has to stop the run. Silently
# ignoring it would leave the user with a switcher that neither follows the
# schedule nor does what they asked, and nothing in the log to explain why.
case "$OVERRIDE" in
  ""|light|dark) ;;
  *) echo "FAIL: OVERRIDE='$OVERRIDE' in $UCFG/switch.conf must be empty, light or dark" >&2; exit 1 ;;
esac

LOGDIR="$UCFG"
LOGFILE="$LOGDIR/switch.log"
# Audit trail for timer-driven switches: apply.sh's output otherwise only ends
# up in the journal, where it is easy to miss. Never let logging break a switch.
log(){ printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >&2
      mkdir -p "$LOGDIR" 2>/dev/null && printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >> "$LOGFILE" 2>/dev/null || true
    }

# Record the pin in switch.conf. The file is sourced, so it is written whole and
# swapped in atomically - a half-written switch.conf would fail to source and
# silently disable switching from then on. Only OVERRIDE= lines are rewritten, so
# hand-edited times and comments survive. Called only after a mode actually
# applied: a pin on a mode we failed to reach would be a lie.
set_override() { # set_override <""|light|dark>
  local v="$1" tmp
  mkdir -p "$UCFG"
  [ -f "$UCFG/switch.conf" ] || printf 'SUNRISE=%s\nSUNSET=%s\n' "$SUNRISE" "$SUNSET" > "$UCFG/switch.conf"
  tmp="$UCFG/switch.conf.tmp.$$"
  grep -v '^OVERRIDE=' "$UCFG/switch.conf" > "$tmp" || true
  printf 'OVERRIDE=%s\n' "$v" >> "$tmp"
  mv -f "$tmp" "$UCFG/switch.conf"
}

override_label() { [ -n "$OVERRIDE" ] && echo "$OVERRIDE" || echo none; }

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
    apply_mode "${1#--}" || exit $?   # only pin a mode that actually applied
    set_override "${1#--}"
    log "override pinned to ${1#--} (schedule paused until --follow-schedule)"
    echo "pinned override=${1#--} - the timer will leave this alone"
    echo "hand control back to the schedule with: $0 --follow-schedule"
    ;;
  --auto)
    # The pin is checked before anything is applied. This is the timer's only
    # entry point and it fires every 15 min, so a pin honoured after the apply
    # would simply be undone on the next tick.
    if [ -n "$OVERRIDE" ]; then
      echo "override=$OVERRIDE is pinned; not switching (clear with: $0 --follow-schedule)"
      log "override $OVERRIDE pinned: --auto is a no-op (clear with --follow-schedule)"
      exit 0
    fi
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
    echo "desired=$D current=$C sunrise=$SUNRISE sunset=$SUNSET override=$(override_label)"
    ;;
  --follow-schedule)
    if [ -z "$OVERRIDE" ]; then
      echo "no override set - already following the schedule"
      exit 0
    fi
    prev="$OVERRIDE"; set_override ""
    log "override cleared (was $prev): following the schedule again"
    echo "override cleared (was $prev)"
    echo "next timer tick (within 15 min) will apply $(desired_mode)"
    ;;
  --install)
    mkdir -p "$UCFG" "$HOME/.config/systemd/user"
    [ -f "$UCFG/switch.conf" ] && echo "kept $UCFG/switch.conf" \
      || { printf 'SUNRISE=%s\nSUNSET=%s\nOVERRIDE=\n' "$SUNRISE" "$SUNSET" > "$UCFG/switch.conf"; echo "wrote $UCFG/switch.conf"; }
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
Description=Check dark/light boundary for spectre-kde-config

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
    echo "config:    $UCFG/switch.conf  (SUNRISE/SUNSET; OVERRIDE=light|dark pins a mode)"
    echo "override:  $0 --light|--dark to pin, $0 --follow-schedule to clear"
    ;;
  --uninstall)
    systemctl --user disable --now "$TIM" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/$SVC" "$HOME/.config/systemd/user/$TIM"
    systemctl --user daemon-reload
    echo "uninstalled: $TIM"
    ;;
  *)
    echo "usage: $0 [--auto|--check|--install|--uninstall|--light|--dark|--follow-schedule]"
    exit 2
    ;;
esac
