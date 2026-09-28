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
# A check that could not read its data source is neither evidence of the fault
# nor evidence of health, so it must not print PASS. Counted as a failure so the
# exit code cannot read as "all clear" -- the rule scripts/check-storage.sh
# already follows: absence of data is never a clean verdict.
UNVERIFIED(){ echo "UNVERIFIED  $1  -- $2"; FAILED=$((FAILED+1)); }
q(){ kreadconfig6 --file "$1" --group "$2" --key "$3" 2>/dev/null || echo "(unset)"; }

echo "=== kde-macos-config: verification ==="
echo "Plasma: $(plasmashell --version 2>/dev/null)"

echo "--- desktop ---"
FV="$(grep -c '^plugin=org.kde.plasma.folder' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"
CHK "no folder-view desktop remaining" "0" "$FV"
DC="$(grep -c '^plugin=org.kde.desktopcontainment' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"
CHKR "clean desktop containment on every screen (>=1)" "1" "32" "$DC"
WALL="$(grep -c 'wavy_lines_v02_5120x2880.png' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"
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
CHK "top bar found"          "1" "$([ -n "$TP" ] && echo 1 || echo 0)"
CHK "dock found"             "1" "$([ -n "$DP" ] && echo 1 || echo 0)"
CHK "global menu in top bar" "1" "$(printf '%s' "$TP" | grep -c 'org.kde.plasma.appmenu')"
CHK "system tray in top bar" "1" "$(printf '%s' "$TP" | grep -c 'org.kde.plasma.systemtray')"
CHK "clock in top bar"        "1" "$(printf '%s' "$TP" | grep -c 'org.kde.plasma.digitalclock')"
CHK "workspace pager in top bar" "1" "$(printf '%s' "$TP" | grep -c 'org.kde.plasma.pager')"
CHK "bottom dock present"     "1" "$(printf '%s' "$DP" | grep -c 'org.kde.plasma.icontasks')"
CHK "launcher at start of dock" "1" "$(printf '%s' "$DP" | grep -c 'org.kde.plasma.kickoff')"
CHK "icons-only task manager in dock" "1" "$(printf '%s' "$DP" | grep -c 'org.kde.plasma.icontasks')"
CHK "trash at end of dock"    "1" "$(printf '%s' "$DP" | grep -c 'org.kde.plasma.trash')"
CHK "dock is floating"        "1" "$(printf '%s' "$DP" | grep -c 'float=true')"

# Every pinned launcher must resolve to a real .desktop file. An
# "applications:<id>" entry with no desktop file is drawn by Plasma as a generic
# "Unknown application" tile, and because layout.js rewrites the whole launcher
# list on every apply, such a tile cannot be removed by hand. This repo shipped
# applications:code.desktop while VS Code installs com.microsoft.VSCode.desktop,
# which is exactly how that happened. Check the live list against the same
# resolver apply.sh pins from, so the two cannot disagree.
echo "--- dock launchers resolve to installed apps ---"
DOCK_LAUNCHERS="$(awk '
  /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { applet = $0; next }
  /^plugin=org\.kde\.plasma\.icontasks$/ { target = applet; next }
  /^\[/ { cur = $0; next }
  /^launchers=/ {
    if (target != "" && cur == target "[Configuration][General]") {
      sub(/^launchers=/, ""); print; exit
    }
  }
' "$CFG/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null)"
if [ -z "$DOCK_LAUNCHERS" ]; then
  echo "FAIL  could not read the dock launcher list from plasma-org.kde.plasma.desktop-appletsrc"
  FAILED=$((FAILED+1))
else
  n=0
  for entry in ${DOCK_LAUNCHERS//,/ }; do
    case "$entry" in applications:*) ;; *) continue ;; esac
    id="${entry#applications:}"
    n=$((n + 1))
    if dock_app="$(bash "$ROOT/scripts/desktop-file-path.sh" "$id")"; then
      echo "PASS  dock launcher $id -> ${dock_app/#$HOME/~}"
    else
      echo "FAIL  dock launcher $id has no installed .desktop file (Plasma draws \"Unknown application\")"
      FAILED=$((FAILED+1))
    fi
  done
  [ "$n" -gt 0 ] || echo "INFO  no pinned dock launchers configured"
fi
TPH="$(printf '%s' "$TP" | sed -n 's/.*;h=\([0-9]*\);.*/\1/p' | head -1)"
DPH="$(printf '%s' "$DP" | sed -n 's/.*;h=\([0-9]*\);.*/\1/p' | head -1)"
echo "  [debug] top height value seen: '$TPH' | dock height value seen: '$DPH'"
CHKR "top bar height 24..44px (target ~30)" "24" "44" "$TPH"
CHKR "dock height 44..66px (target ~52)" "44" "66" "$DPH"

# Panel visibility: 0=NormalPanel 1=AutoHide 2=DodgeWindows 3=WindowsGoBelow.
# apply.sh writes this key (the scripting API cannot) and Plasma re-serialises it
# on every plasmashellrc write, so it must read back as 2 after an apply.
#
# Check the LIVE panel ids from the probe, not every [PlasmaViews][Panel N]
# section on disk: plasmashellrc is written asynchronously, so right after
# layout.js runs it can still list panels that were just removed. Checking the
# stale ones produced a false failure (and a needless rollback) on a correct
# apply.
echo "--- panel visibility (dodge windows) ---"
EXP_VIS="${PANEL_VISIBILITY:-2}"
LIVE_PIDS="$(printf '%s\n' "$PROBE" | sed -n 's/^panelids=//p' | tail -1 | tr ',' ' ')"
DISK_PIDS="$(grep -oE '^\[PlasmaViews\]\[Panel [0-9]+\]' "$CFG/plasmashellrc" 2>/dev/null \
            | grep -oE '[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ $//')"
if [ -z "$LIVE_PIDS" ]; then
  echo "FAIL  panel visibility  (probe reported no live panel ids)"
  FAILED=$((FAILED+1))
else
  for pid in $LIVE_PIDS; do
    CHK "panel $pid visibility = $EXP_VIS (dodge windows)" "$EXP_VIS" \
      "$(kreadconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $pid" --key panelVisibility 2>/dev/null || echo "(unset)")"
  done
  # Leftover on-disk sections for panels that no longer exist are Plasma's to
  # reap; report them, but they are not a failure of this config.
  STALE=""
  for pid in $DISK_PIDS; do
    case " $LIVE_PIDS " in *" $pid "*) ;; *) STALE="$STALE $pid" ;; esac
  done
  [ -z "$STALE" ] || echo "INFO  stale [PlasmaViews][Panel N] section(s) awaiting Plasma reap:$STALE"
fi

echo "--- kwin ---"
# Aurorae installs two decoration plugins side by side (org.kde.kwin.aurorae and
# .v2), both loadable; the live session resolves the .v2 id, so that is what this
# project pins in kwinrc and in the LNF defaults.
CHK "kwin decoration library = aurorae.v2" "org.kde.kwin.aurorae.v2" "$(q kwinrc org.kde.kdecoration2 library)"
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
  Orchis)      SUPPORTED="yes"; EXP_LNF=com.github.vinceliuice.Orchis;      EXP_COLOR=Orchis;     EXP_ICONS=FairyWren_Light; EXP_CURSOR=Bibata-Modern-Ice;  EXP_GTK=Breeze;       EXP_DECO=__aurorae__svg__Orchis ;;
  Orchis-dark) SUPPORTED="yes"; EXP_LNF=com.github.vinceliuice.Orchis-dark; EXP_COLOR=OrchisDark; EXP_ICONS=FairyWren_Dark;  EXP_CURSOR=Bibata-Modern-Ice; EXP_GTK=Orchis-Dark; EXP_DECO=__aurorae__svg__Orchis-dark ;;
  *) EXP_LNF="($LNF)"; EXP_COLOR="($LNF)"; EXP_ICONS="($LNF)"; EXP_CURSOR="($LNF)"; EXP_GTK="($LNF)"; EXP_DECO="($LNF)"; echo "note: unknown look-and-feel '$LNF' (expected Orchis or Orchis-dark)"; ;;
esac
# Persisted for the reboot-persistence check further down.
SFX="$(printf '%s' "$LNF" | sed -e 's/.*-dark/dark/' -e 's/.*/light/')"
CHK "look-and-feel is a supported mode" "yes" "$SUPPORTED"
CHK "global theme package" "$EXP_LNF" "$(q kdeglobals KDE LookAndFeelPackage)"
CHK "auto theme switching off" "false" "$(q kdeglobals KDE AutomaticLookAndFeel)"
CHK "auto theme switching on idle off" "false" "$(q kdeglobals KDE AutomaticLookAndFeelOnIdle)"
# Pinning the defaults is what stops a re-enabled autoswitcher from snapping
# back to the stock Breeze look-and-feels, so assert the pair, not just the flags.
CHK "pinned light look-and-feel" "com.github.vinceliuice.Orchis" "$(q kdeglobals KDE DefaultLightLookAndFeel)"
CHK "pinned dark look-and-feel"  "com.github.vinceliuice.Orchis-dark" "$(q kdeglobals KDE DefaultDarkLookAndFeel)"
CHK "kwin decoration theme" "$EXP_DECO" "$(q kwinrc org.kde.kdecoration2 theme)"
CHK "color scheme ($LNF)" "$EXP_COLOR" "$(q kdeglobals General ColorScheme)"
CHK "icons ($LNF)" "$EXP_ICONS" "$(q kdeglobals Icons Theme)"
CHK "cursor ($LNF)" "$EXP_CURSOR" "$(q kcminputrc Mouse cursorTheme)"
CHK "cursor size = 24" "24" "$(q kcminputrc Mouse cursorSize)"
CHK "font = Noto Sans 10" "Noto Sans,10,-1,5,50,0,0,0,0,0" "$(q kdeglobals General font)"

# Splash: verify the configured theme actually resolves. plasma-ksplash.service
# runs ksplashqml with no arguments, so ksplashqml resolves the name itself from
# ksplashrc and falls back silently - a name pointing at nothing means the config
# claims a splash the user never sees.
# Resolution goes through scripts/splash-theme-path.sh: on Plasma 6.7 a splash is
# a plasma/look-and-feel package providing contents/splash/Splash.qml, and the
# legacy plasma/splash/themes root does not exist. Checking it here is what
# reported a working Orchis splash as a dangling reference.
CUR_SPLASH="$(q ksplashrc KSplash Theme)"
if [ "$CUR_SPLASH" = "(unset)" ] || [ -z "$CUR_SPLASH" ]; then
  echo "INFO  no splash theme configured (KSplash uses the active look-and-feel's splash)"
elif SPLASH_DIR="$(bash "$ROOT/scripts/splash-theme-path.sh" "$CUR_SPLASH")"; then
  echo "PASS  splash theme resolves: $CUR_SPLASH ($SPLASH_DIR)"
  CHK "splash engine = KSplashQML" "KSplashQML" "$(q ksplashrc KSplash Engine)"
else
  echo "WARN  ksplashrc references '$CUR_SPLASH' but no look-and-feel package provides contents/splash/Splash.qml for it (KSplash falls back to the stock splash)"
fi

echo "--- gtk ($LNF) ---"
# apply.sh writes gtk-3.0 AND gtk-4.0; both must agree or GTK4 apps look wrong.
for g in gtk-3.0 gtk-4.0; do
  CHK "$g theme"    "$EXP_GTK"  "$(grep '^gtk-theme-name=' "$CFG/$g/settings.ini" 2>/dev/null | cut -d= -f2)"
  CHK "$g icons"    "$EXP_ICONS" "$(grep '^gtk-icon-theme-name=' "$CFG/$g/settings.ini" 2>/dev/null | cut -d= -f2)"
  CHK "$g cursor"   "$EXP_CURSOR" "$(grep '^gtk-cursor-theme-name=' "$CFG/$g/settings.ini" 2>/dev/null | cut -d= -f2)"
done

echo "--- LNF defaults patched (survives package updates + other switch paths?) ---"
LNFD="$HOME/.local/share/plasma/look-and-feel"
for pair in "com.github.vinceliuice.Orchis Bibata-Modern-Ice FairyWren_Light" \
             "com.github.vinceliuice.Orchis-dark Bibata-Modern-Ice FairyWren_Dark"; do
  set -- $pair
  D="$LNFD/$1/contents/defaults"
  CUR="$(grep '^cursorTheme=' "$D" 2>/dev/null | cut -d= -f2)"
  ICO="$(grep '^Theme=' "$D" 2>/dev/null | cut -d= -f2)"
  LIB="$(grep '^library=' "$D" 2>/dev/null | cut -d= -f2)"
  CHK "LNF $1: cursor=$2 icons=$3" "yes" "$([ "$CUR" = "$2" ] && [ "$ICO" = "$3" ] && echo yes || echo no)"
  CHK "LNF $1: decoration library = aurorae.v2" "org.kde.kwin.aurorae.v2" "${LIB:-(unset)}"
done

echo "--- fontconfig (Inter web subsets excluded) ---"
FCF="$CFG/fontconfig/fonts.conf"
if [ -f "$FCF" ]; then
  CHK "fontconfig rejectfont present" "yes" \
    "$([ -f "$FCF" ] && grep -q '<rejectfont>' "$FCF" && echo yes || echo no)"
  CHK "Inter web subset rejected" "yes" \
    "$(grep -q 'Inter/web' "$FCF" && echo yes || echo no)"
  CHK "Inter woff-hinted subset rejected" "yes" \
    "$(grep -q 'Inter/extras/woff-hinted' "$FCF" && echo yes || echo no)"
else
  echo "FAIL  $FCF missing (apply.sh writes it to avoid the fontconfig cache corruption that crashes plasmashell)"
  FAILED=$((FAILED+1))
fi

echo "--- wallpaper ---"
WALL_NAME="wavy_lines_v02_5120x2880.png"
WALL_LIVE="$HOME/.local/share/wallpapers/kde-setup-02/$WALL_NAME"
WALL_VENDORED="$ROOT/assets/wallpapers/$WALL_NAME"
  CHK "wallpaper present (live or vendored copy)" "yes" \
    "$([ -f "$WALL_LIVE" ] || [ -f "$WALL_VENDORED" ] && echo yes || echo no)"
  # Presence alone is not enough. A stale file with the correct name used to
  # satisfy the check above, so apply.sh would apply the wrong image and verify
  # would still report PASS. Compare the bytes: the live copy must be the
  # vendored asset.
  if [ -f "$WALL_LIVE" ] && [ -f "$WALL_VENDORED" ]; then
    CHK "live wallpaper matches the vendored asset" "same" \
      "$(cmp -s "$WALL_LIVE" "$WALL_VENDORED" && echo same || echo differs)"
  else
    CHK "live wallpaper matches the vendored asset" "n/a" "no live copy"
  fi

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
# journalctl prints nothing and still exits 0 when it cannot open the journal, so
# an unreadable log and a genuinely quiet one both count as zero matches and the
# old code reported the second as the first -- a blind spot on the very check
# meant to catch a crash-loop. Probe readability first, over a window wide enough
# that a running unit always has entries in it.
JLINES="$(
  journalctl --user -u plasma-plasmashell --since '24 hours ago' -o cat 2>/dev/null \
    | grep -c . || true
)"
if [ "$JLINES" -gt 0 ] 2>/dev/null; then
  RECENT="$(
    journalctl --user -u plasma-plasmashell --since '10 minutes ago' -o cat 2>/dev/null \
      | grep -cE 'code=dumped|SIGSEGV|Failed to start' || true
  )"
  CHK "no plasmashell crash-loop in last 10 min" "0" "$RECENT"
else
  UNVERIFIED "no plasmashell crash-loop in last 10 min" \
    "the plasma-plasmashell user journal yielded no entries over 24h, so it was not read (journal not readable by this user, or rotated away); a crash in that window would be invisible"
fi
# Same rule for fontconfig: the old pipeline threw fc-cache's exit status away
# with the rest of its output, so a fc-cache that could not run counted as zero
# invalid caches. Keep the status.
FC_OUT="$(fc-cache -f 2>&1)"; FC_RC=$?
if [ "$FC_RC" -ne 0 ]; then
  UNVERIFIED "no invalid fontconfig caches" "fc-cache -f exited $FC_RC, so the caches were not checked"
else
  CHK "no invalid fontconfig caches" "0" "$(printf '%s' "$FC_OUT" | grep -c 'invalid cache' || true)"
fi
# fs-verity reports a digest mismatch whenever a read returns bytes that differ
# from the digest recorded for the file. Two very different situations produce
# that same line, so they are counted separately:
#   * reads that return exactly one 4 KiB block of zeros (btrfs handing back an
#     extent that was never written, or a stale page-cache page), and
#   * everything else, i.e. reads that differ from the digest in a
#     non-repeating way.
# On this machine the first kind dominates, the affected inodes no longer resolve
# to any live file, and neither the NVMe nor btrfs logged a single I/O, checksum
# or medium error over the same window - so the zero-fill reads are a read-path
# artifact, not evidence of failing hardware. Only the second kind is worth
# escalating, and it is a WARN rather than a failure because a btrfs read-path
# bug can produce it too. The commands that actually settle it are in the message
# and in README section 10.
FSEV_KLOG="$(journalctl -k --since '24 hours ago' -o cat 2>/dev/null || true)"
FSEV="$(printf '%s' "$FSEV_KLOG" | grep -E 'fs-verity.*CORRUPTED|FILE CORRUPTED' || true)"
ZERO_BLOCK="$(head -c 4096 /dev/zero | sha256sum | cut -d' ' -f1)"
FSEV_TOTAL="$(printf '%s' "$FSEV" | grep -c . || true)"
FSEV_ZERO="$(printf '%s' "$FSEV" | grep -c "real_hash=sha256:$ZERO_BLOCK" || true)"
FSEV_OTHER=$((FSEV_TOTAL - FSEV_ZERO))
if [ "$FSEV_OTHER" -gt 0 ]; then
  echo "WARN  $FSEV_OTHER fs-verity digest mismatches in last 24h that are not zero-fill"
  echo "      (+$FSEV_ZERO zero-fill reads, which are benign). No I/O, checksum or"
  echo "      medium error was logged by the NVMe or btrfs over the same window, so"
  echo "      this is unconfirmed. To settle it, run the checker that actually"
  echo "      scrubs the data and interprets the result:"
  echo "        ./scripts/check-storage.sh"
  echo "      and boot memtest86+ to rule out RAM. See README section 10."
elif [ "$FSEV_TOTAL" -gt 0 ]; then
  echo "INFO  $FSEV_TOTAL fs-verity zero-fill reads in last 24h (btrfs read-path artifact; no I/O error)"
elif [ "$(printf '%s' "$FSEV_KLOG" | grep -c . || true)" -gt 0 ] 2>/dev/null; then
  echo "PASS  no fs-verity digest mismatch in last 24h"
else
  # An empty kernel log is indistinguishable from an unreadable one, and
  # "no mismatch" derived from it would be a claim about nothing.
  UNVERIFIED "no fs-verity digest mismatch in last 24h" \
    "the kernel journal yielded no entries over 24h, so it was not read; mismatches in that window would be invisible"
fi

echo "--- reboot persistence ---"
# Read the marker for the mode that is actually applied. Picking the newest
# .applied-* file regardless of mode reported on the wrong marker whenever the
# two modes were applied out of order.
MRK="$ROOT/.applied-$SFX"
CUR_BOOT="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo none)"
# During an apply the marker on disk still belongs to the PREVIOUS run, because
# apply.sh only writes it after verification succeeds. Comparing that stale
# marker to the current boot produced a bogus "settings survived a full reboot"
# PASS for a config that had just been written. Defer instead.
if [ -n "${KDE_APPLY_IN_PROGRESS:-}" ]; then
  echo "INFO  reboot persistence deferred: apply.sh writes .applied-$SFX after verification passes"
elif [ -n "$SFX" ] && [ -f "$MRK" ]; then
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
elif [ -n "$SFX" ]; then
  echo "SKIP  no .applied-$SFX marker (this mode has not been applied by apply.sh yet)"
else
  echo "SKIP  look-and-feel is not a supported mode, cannot pick a marker"
fi

echo "=== result ==="
if [ "$FAILED" -eq 0 ]; then echo "VERIFY: ALL PASS"; else echo "VERIFY: $FAILED FAILURE(S)"; fi
exit $(( FAILED > 0 ? 1 : 0 ))
