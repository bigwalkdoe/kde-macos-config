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
[ -f "$UCFG/switch.conf" ] && . "$UCFG/switch.conf"

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
  "$ROOT/apply.sh" "--$1"
}

# ---- actions ---------------------------------------------------------------
case "${1:---auto}" in
  --light|--dark)
    apply_mode "${1#--}"
    ;;
  --auto)
    D="$(desired_mode)"; C="$(current_mode)"
    echo "switch: desired=$D current=$C (sunrise=$SUNRISE sunset=$SUNSET)"
    if [ "$D" != "$C" ]; then apply_mode "$D"; else echo "no change needed"; fi
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