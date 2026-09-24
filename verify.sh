#!/usr/bin/env bash
# kde-macos-config -- verify.sh
# Checks the applied result: file-level config + live plasmashell probing.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
CFG="$HOME/.config"
FAILED=0
CHK(){ if [ "$3" = "$2" ]; then echo "PASS  $1"; else echo "FAIL  $1  (expected '$2', got '$3')"; FAILED=1; fi; }
# range check for values that Plasma snaps (e.g. panel heights); usage: CHKR <label> <min> <max> <value>
CHKR(){ if [ "$4" -ge "$2" ] 2>/dev/null && [ "$4" -le "$3" ] 2>/dev/null; then echo "PASS  $1 ($4)"; else echo "FAIL  $1  (expected $2..$3, got '$4')"; FAILED=1; fi; }
q(){ kreadconfig6 --file "$1" --group "$2" --key "$3" 2>/dev/null || echo "(unset)"; }

echo "=== kde-macos-config: verification ==="
echo "Plasma: $(plasmashell --version 2>/dev/null)"

echo "--- desktop ---"
CHK "clean desktop containment (no icons)" "1" \
  "$(grep -c '^plugin=org.kde.desktopcontainment' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"
CHK "no folder-view desktop remaining" "0" \
  "$(grep -c '^plugin=org.kde.plasma.folder' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"
CHK "wallpaper configured on desktop" "1" \
  "$(grep -c 'wavy_lines_v01_5120x2880.png' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"

echo "--- panels (live) ---"
cat > /tmp/kde-macos-verify.js <<EOF
var log = [];
var ids = panelIds.slice();
log.push("count=" + ids.length);
for (var i = 0; i < ids.length; i++) {
    var p = panelById(ids[i]);
    if (!p) { continue; }
    var wt = [];
    var wids = p.widgetIds;
    for (var w = 0; w < wids.length; w++) {
        var wid = p.widgetById(wids[w]);
        if (wid) { wt.push(wid.type); }
    }
    log.push(p.location + ";h=" + Math.round(p.height) + ";float=" + p.floating +
             ";widgets=" + wt.join(","));
}
print(log.join("|"));
EOF
RAW="$(
  gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
    --method org.kde.PlasmaShell.evaluateScript "$(cat /tmp/kde-macos-verify.js)" 2>/dev/null
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
CHK "look-and-feel = Orchis (plasmarc)" "Orchis" "$(q plasmarc Theme name)"
CHK "color scheme = Orchis" "Orchis" "$(q kdeglobals General ColorScheme)"
CHK "icons = FairyWren_Light" "FairyWren_Light" "$(q kdeglobals Icons Theme)"
CHK "cursor = Breeze_Light" "Breeze_Light" "$(q kcminputrc Mouse cursorTheme)"
CHK "font = Noto Sans 10" "Noto Sans,10,-1,5,50,0,0,0,0,0" "$(q kdeglobals General font)"

echo "--- gtk ---"
CHK "gtk-3.0 theme" "Breeze" "$(grep '^gtk-theme-name=' "$CFG/gtk-3.0/settings.ini" 2>/dev/null | cut -d= -f2)"
CHK "gtk icons" "FairyWren_Light" "$(grep '^gtk-icon-theme-name=' "$CFG/gtk-3.0/settings.ini" 2>/dev/null | cut -d= -f2)"

echo "--- backup present ---"
BKL="$(ls -1dt "$HOME"/.config/kde-backups/*/ 2>/dev/null | head -1)"
CHK "timestamped backup exists" "yes" "$([ -n "$BKL" ] && echo yes || echo no)"
[ -n "$BKL" ] && echo "  latest: $BKL"

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

echo "=== result ==="
if [ "$FAILED" -eq 0 ]; then echo "VERIFY: ALL PASS"; else echo "VERIFY: $FAILED FAILURE(S)"; fi
exit "$FAILED"