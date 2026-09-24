#!/usr/bin/env bash
# kde-macos-config -- verify.sh
# Checks the applied result: file-level config + live plasmashell probing.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
CFG="$HOME/.config"
FAILED=0
CHK(){ if [ "$3" = "$2" ]; then echo "PASS  $1"; else echo "FAIL  $1  (expected '$2', got '$3')"; FAILED=$((FAILED+1)); fi; }
# range check for values that Plasma snaps (e.g. panel heights); usage: CHKR <label> <min> <max> <value>
CHKR(){ if [ "$4" -ge "$2" ] 2>/dev/null && [ "$4" -le "$3" ] 2>/dev/null; then echo "PASS  $1 ($4)"; else echo "FAIL  $1  (expected $2..$3, got '$4')"; FAILED=$((FAILED+1)); fi; }
q(){ kreadconfig6 --file "$1" --group "$2" --key "$3" 2>/dev/null || echo "(unset)"; }

echo "=== kde-macos-config: verification ==="
echo "Plasma: $(plasmashell --version 2>/dev/null)"

echo "--- desktop ---"
FV="$(grep -c '^plugin=org.kde.plasma.folder' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"
CHK "no folder-view desktop remaining" "0" "$FV"
DC="$(grep -c '^plugin=org.kde.desktopcontainment' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"
CHKR "clean desktop containment on every screen (>=1)" "1" "32" "$DC"
WALL="$(grep -c 'wavy_lines_v01_5120x2880.png' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"
CHKR "wallpaper configured on every screen (>=1)" "1" "32" "$WALL"

echo "--- panels (live) ---"
RAW="$(
  gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
    --method org.kde.PlasmaShell.evaluateScript "$(cat "$ROOT/scripts/probe-panels.js")" 2>/dev/null
)"
# strip the gdbus '(...)' wrapper and split the log on the '|' separator
PROBE="$(printf '%s' "$RAW" | sed -e "1s/^('//" -e "\$s/',)\$//" | tr '|' '\n')"
echo "$PROBE"
CNT="$(printf '%s\n' "$PROBE" | sed -n 's/^count=\([0-9]*\)$/\1/p' | tail -1)"
CHK "exactly two panels (no duplicates)" "2" "${CNT:-not-found}"

TP="$(printf '%s\n' "$PROBE" | grep '^top;' | tr -d '\n')"
DP="$(printf '%s\n' "$PROBE" | grep '^bottom;' | tr -d '\n')"
CHK "top menu bar present"  "1" "$(printf '%s' "$TP" | grep -c 'org.kde.plasma.appmenu')"
CHK "global menu in top bar" "1" "$(printf '%s' "$TP" | grep -c 'org.kde.plasma.appmenu')"
CHK "system tray in top bar" "1" "$(printf '%s' "$TP" | grep -c 'org.kde.plasma.systemtray')"
CHK "clock in top bar"        "1" "$(printf '%s' "$TP" | grep -c 'org.kde.plasma.digitalclock')"
CHK "workspace pager in top bar" "1" "$(printf '%s' "$TP" | grep -c 'org.kde.plasma.pager')"
CHK "bottom dock present"     "1" "$(printf '%s' "$DP" | grep -c 'org.kde.plasma.icontasks')"
CHK "launcher at start of dock" "1" "$(printf '%s' "$DP" | grep -c 'org.kde.plasma.kickoff')"
CHK "icons-only task manager in dock" "1" "$(printf '%s' "$DP" | grep -c 'org.kde.plasma.icontasks')"
CHK "trash at end of dock"    "1" "$(printf '%s' "$DP" | grep -c 'org.kde.plasma.trash')"
CHK "dock is floating"        "1" "$(printf '%s' "$DP" | grep -c 'float=true')"
TPH="$(printf '%s' "$TP" | sed -n 's/.*;h=\([0-9]*\);.*/\1/p' | head -1)"
DPH="$(printf '%s' "$DP" | sed -n 's/.*;h=\([0-9]*\);.*/\1/p' | head -1)"
echo "  [debug] top height value seen: '$TPH' | dock height value seen: '$DPH'"
CHKR "top bar height 24..44px (target ~30)" "24" "44" "$TPH"
CHKR "dock height 44..66px (target ~52)" "44" "66" "$DPH"

echo "--- kwin ---"
CHK "window decoration = Orchis" "Orchis" "$(q kwinrc General decorationTheme)"
CHK "virtual desktops = 4" "4" "$(q kwinrc Desktops Number)"
CHK "desktop rows = 1" "1" "$(q kwinrc Desktops Rows)"
CHK "wobbly windows off" "false" "$(q kwinrc Plugins wobblywindowsEnabled)"
CHK "blur on" "true" "$(q kwinrc Plugins blurEnabled)"
CHK "borderless maximized (macOS-like)" "true" "$(q kwinrc General BorderlessMaximizedWindows)"

echo "--- theme ---"
# Determine the active mode from the look-and-feel actually in use; both the
# light (Orchis) and dark (Orchis-dark) variants must be independently verified.
Q(){ q plasmarc Theme name; }
LNF="$(Q)"
SUPPORTED="no"
case "$LNF" in
  Orchis)      SUPPORTED="yes"; EXP_COLOR=Orchis;     EXP_ICONS=FairyWren_Light; EXP_CURSOR=Breeze_Light;  EXP_GTK=Breeze; ;;
  Orchis-dark) SUPPORTED="yes"; EXP_COLOR=OrchisDark; EXP_ICONS=FairyWren_Dark;  EXP_CURSOR=breeze_cursors; EXP_GTK=Orchis-Dark; ;;
  *) EXP_COLOR="($LNF)"; EXP_ICONS="($LNF)"; EXP_CURSOR="($LNF)"; EXP_GTK="($LNF)"; echo "note: unknown look-and-feel '$LNF' (expected Orchis or Orchis-dark)"; ;;
esac
CHK "look-and-feel is a supported mode" "yes" "$SUPPORTED"
CHK "color scheme ($LNF)" "$EXP_COLOR" "$(q kdeglobals General ColorScheme)"
CHK "icons ($LNF)" "$EXP_ICONS" "$(q kdeglobals Icons Theme)"
CHK "cursor ($LNF)" "$EXP_CURSOR" "$(q kcminputrc Mouse cursorTheme)"
CHK "font = Noto Sans 10" "Noto Sans,10,-1,5,50,0,0,0,0,0" "$(q kdeglobals General font)"

echo "--- gtk ($LNF) ---"
CHK "gtk-3.0 theme" "$EXP_GTK" "$(grep '^gtk-theme-name=' "$CFG/gtk-3.0/settings.ini" 2>/dev/null | cut -d= -f2)"
CHK "gtk icons" "$EXP_ICONS" "$(grep '^gtk-icon-theme-name=' "$CFG/gtk-3.0/settings.ini" 2>/dev/null | cut -d= -f2)"

echo "--- LNF defaults patched (survives package updates?) ---"
LNFD="$HOME/.local/share/plasma/look-and-feel"
for pair in "com.github.vinceliuice.Orchis Breeze_Light FairyWren_Light" \
            "com.github.vinceliuice.Orchis-dark breeze_cursors FairyWren_Dark"; do
  set -- $pair
  D="$LNFD/$1/contents/defaults"
  CUR="$(grep '^cursorTheme=' "$D" 2>/dev/null | cut -d= -f2)"
  ICO="$(grep '^Theme=' "$D" 2>/dev/null | cut -d= -f2)"
  CHK "LNF $1: cursor=$2 icons=$3" "yes" "$([ "$CUR" = "$2" ] && [ "$ICO" = "$3" ] && echo yes || echo no)"
done

echo "--- backup present ---"
BKL="$(ls -1dt "$HOME"/.config/kde-backups/*/ 2>/dev/null | head -1)"
CHK "timestamped backup exists" "yes" "$([ -n "$BKL" ] && echo yes || echo no)"
[ -n "$BKL" ] && echo "  latest: $BKL"

echo "--- sddm-login (optional extra; install: sudo ./scripts/install-sddm-orchis.sh) ---"
SDDM_THEME="/usr/share/sddm/themes/Orchis"
SDDM_CONF="/etc/sddm.conf.d/theme.conf"
if [ -d "$SDDM_THEME" ] && [ -f "$SDDM_CONF" ]; then
  CHK "sddm theme installed (metadata Name=Orchis)" "yes" \
    "$([ -f "$SDDM_THEME/metadata.desktop" ] && grep -q '^Name=Orchis$' "$SDDM_THEME/metadata.desktop" && echo yes || echo no)"
  CHK "sddm greeter config -> current=Orchis" "Orchis" \
    "$(sed -n 's/^Current=//p' "$SDDM_CONF" | head -1)"
  CHK "sddm cursor preserved (not empty)" "yes" \
    "$([ -n "$(sed -n 's/^CursorTheme=//p' "$SDDM_CONF")" ] && echo yes || echo no)"
  CHK "sddm font preserved (not empty)" "yes" \
    "$([ -n "$(sed -n 's/^Font=//p' "$SDDM_CONF")" ] && echo yes || echo no)"
  if command -v sddm-greeter-qt6 >/dev/null && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    timeout 5 sddm-greeter-qt6 --test-mode --theme "$SDDM_THEME" &>/dev/null &
    SPID=$!
    sleep 3
    if kill -0 "$SPID" 2>/dev/null; then
      echo "PASS  sddm greeter smoke test (alive after 3s)"
      kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
    else
      RC=0; wait "$SPID" 2>/dev/null || RC=$?
      echo "FAIL  sddm greeter smoke test (exited early, rc=$RC)"
      FAILED=$((FAILED+1))
    fi
  else
    echo "SKIP  sddm greeter smoke test (no sddm-greeter-qt6 or no display)"
  fi
else
  echo "SKIP  SDDM login theme not installed (optional: sudo ./scripts/install-sddm-orchis.sh)"
fi

echo "--- health (crash-loop + hardware) ---"
CHK "plasmashell unit active" "active" "$(systemctl --user is-active plasma-plasmashell 2>/dev/null)"
RECENT="$(
  journalctl --user -u plasma-plasmashell --since '10 minutes ago' -o cat 2>/dev/null \
    | grep -cE 'code=dumped|SIGSEGV|Failed to start' || true
)"
CHK "no plasmashell crash-loop in last 10 min" "0" "$RECENT"
INVALID="$(
  fc-cache -f 2>&1 | grep -c 'invalid cache' || true
)"
CHK "no invalid fontconfig caches" "0" "$INVALID"
FSVERITY="$(
  journalctl -k --since '24 hours ago' -o cat 2>/dev/null \
    | grep -cE 'fs-verity.*CORRUPTED|FILE CORRUPTED' || true
)"
if [ "$FSVERITY" -gt 0 ]; then
  echo "WARN  $FSVERITY fs-verity corruption entries in last 24h (likely disk/RAM fault)"
else
  echo "PASS  no fs-verity corruption in last 24h"
fi

echo "--- reboot persistence ---"
MRK="$(ls -1t "$ROOT"/.applied-* 2>/dev/null | head -1)"
CUR_BOOT="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo none)"
if [ -n "$MRK" ] && [ -f "$MRK" ]; then
  APP_BOOT="$(grep '^BOOT=' "$MRK" 2>/dev/null | cut -d= -f2)"
  APP_BK="$(grep '^APPLIED=' "$MRK" 2>/dev/null | cut -d= -f2)"
  if [ -n "$APP_BOOT" ] && [ "$APP_BOOT" != "$CUR_BOOT" ]; then
    echo "PASS  applied by a previous boot: current boot ($CUR_BOOT) differs from apply boot ($APP_BOOT) — settings survived a full reboot"
  elif [ "$APP_BOOT" = "$CUR_BOOT" ]; then
    echo "INFO  last apply happened this boot ($CUR_BOOT); reboot persistence confirmed after next login"
  else
    echo "SKIP  $MRK has no BOOT= line (marked before this feature)"
  fi
  [ -n "$APP_BK" ] && [ -d "$APP_BK" ] && echo "INFO  applied backup on record: $APP_BK"
else
  echo "SKIP  no .applied-* marker (apply.sh has not completed yet)"
fi

echo "=== result ==="
if [ "$FAILED" -eq 0 ]; then echo "VERIFY: ALL PASS"; else echo "VERIFY: $FAILED FAILURE(S)"; fi
exit $(( FAILED > 0 ? 1 : 0 ))