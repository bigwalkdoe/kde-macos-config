#!/usr/bin/env bash
# kde-macos-config -- apply.sh
# macOS-inspired Plasma, applied safely & reversibly:
#   preflight -> verified timestamped backup -> theme/colors/icons/cursor ->
#   kwin (decoration/workspaces/effects) -> GTK -> plasmashell restart ->
#   native scripting layout -> wallpaper -> verification.
# On failure before completion, the backup is restored automatically.
# Usage: ./apply.sh [--light|--dark]
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"

MODE="${1:---light}"
case "$MODE" in
  --light) LNF=Orchis;         COLORS=Orchis;      SFX="light" ;;
  --dark)  LNF=Orchis-dark;    COLORS=OrchisDark;  SFX="dark" ;;
  *) echo "usage: $0 [--light|--dark]"; exit 2 ;;
esac
WALLPAPER="$HOME/.local/share/wallpapers/kde-setup-02/wavy_lines_v01_5120x2880.png"
BACKUP=""; FAIL=0
say(){ echo; echo "### $*"; }
die(){ echo "FAIL: $*" >&2; FAIL=1; exit 1; }

restore_backup(){
  [ -n "$BACKUP" ] || return 0
  say "Rolling back to $BACKUP"
  shutdown_shell graceful
  [ -d "$BACKUP/gtk-3.0" ] && cp -a "$BACKUP/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
  [ -d "$BACKUP/gtk-4.0" ] && cp -a "$BACKUP/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
  AFFECTED=(
    plasma-org.kde.plasma.desktop-appletsrc plasmarc plasmashellrc kdeglobals kwinrc
    kglobalshortcutsrc kcminputrc ksplashrc dolphinrc gwenviewrc kwinrulesrc
    kwinoutputconfig.json plasma-localerc
  )
  for f in "${AFFECTED[@]}"; do
    if [ -f "$BACKUP/$f" ]; then
      cp -a "$BACKUP/$f" "$HOME/.config/" 2>/dev/null || true
    else
      rm -f "$HOME/.config/$f"
    fi
  done
  start_shell || true
  say "Rollback complete - previous configuration restored."
}

# plasmashell is a systemd user unit (plasma-plasmashell.service, Type=dbus).
# shutdown_shell [graceful|hard]  -> stop plasmashell and wait for the bus name
# NOTE: the bus-name checks anchor on "org.kde.plasmashell" + whitespace so the
# kded6-owned name "org.kde.plasmashell.accentColor" can never match.
wait_shell_up() {
  for i in $(seq 1 30); do
    busctl --user list --no-pager 2>/dev/null | grep -q '^org\.kde\.plasmashell[[:space:]]' && return 0
    sleep 1
  done
  return 1
}
wait_shell_down() {
  for i in $(seq 1 20); do
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
trap 'if [ "$FAIL" -ne 0 ]; then restore_backup; fi; exit $FAIL' EXIT

say "Preflight"
command -v plasmashell >/dev/null || die "plasmashell not found - not a Plasma session"
command -v kwriteconfig6 plasma-apply-colorscheme plasma-apply-desktoptheme plasma-apply-wallpaperimage >/dev/null || die "missing plasma tooling"
command -v gdbus >/dev/null && command -v busctl >/dev/null && command -v uuidgen >/dev/null || die "missing dbus tooling"
plasmashell --version | grep -q '^plasmashell 6\.' || die "unsupported Plasma version (need 6.x)"
busctl --user list --no-pager 2>/dev/null | grep -q org.kde.plasmashell || die "plasmashell not on the session bus"
echo "Plasma: $(plasmashell --version)  Mode: $MODE"

say "Backup"
BACKUP="$(bash "$ROOT/backup.sh" | grep '^BackUp=' | cut -d= -f2-)"
[ -d "$BACKUP" ] || die "backup failed"
echo "Backup directory: $BACKUP"; sleep 1

say "Look-and-feel: $LNF"
plasma-apply-desktoptheme "$LNF"  || die "plasma-apply-desktoptheme failed"
plasma-apply-colorscheme "$COLORS" || die "plasma-apply-colorscheme failed"

say "Icons, cursor, fonts"
kwriteconfig6 --file kdeglobals --group Icons --key Theme FairyWren_Light || die "icons"
kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme Breeze_Light || die "cursor theme"
kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize 24 || die "cursor size"
kwriteconfig6 --file kdeglobals --group General --key font "Noto Sans,10,-1,5,50,0,0,0,0,0" || die "font"
kwriteconfig6 --file ksplashrc --group KSplash --key Theme AppleSplash || die "splash"

say "Fontconfig: rebuild cache + exclude web-only fonts"
# Rebuild the font cache so a stale/corrupt cache can never take down plasmashell
# again (it crashed in FcCharSetHasChar during Klipper popup text shaping).
fc-cache -f >/dev/null 2>&1 || die "fc-cache failed"
# Exclude the Inter web/woff-hinted subsets: they are redundant duplicates of
# the same family and are a known fontconfig cache-corruption trigger.
FCDIR="$HOME/.config/fontconfig"; mkdir -p "$FCDIR"
cat > "$FCDIR/fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <selectfont>
    <rejectfont>
      <glob>*/Inter/web/*</glob>
      <glob>*/Inter/extras/woff-hinted/*</glob>
    </rejectfont>
  </selectfont>
</fontconfig>
EOF
fc-cache -f >/dev/null 2>&1 || die "fc-cache failed"

say "KWin: window decoration, workspaces, effects"
kwriteconfig6 --file kwinrc --group General --key decorationTheme Orchis || die "decoration"
kwriteconfig6 --file kwinrc --group General --key BorderlessMaximizedWindows true || die "borderless"
kwriteconfig6 --file kwinrc --group Desktops --key Number 4 || die "desktops number"
kwriteconfig6 --file kwinrc --group Desktops --key Rows 1 || die "desktops rows"
for n in 2 3 4; do
  kwriteconfig6 --file kwinrc --group Desktops --key "Id_$n" "$(uuidgen)" || die "desktop id $n"
done
# Curated KWin effects: subtle on, GPU-heavy/legacy off (stable effect IDs only)
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true || die "fx blur"
kwriteconfig6 --file kwinrc --group Plugins --key overviewEnabled true || die "fx overview"
kwriteconfig6 --file kwinrc --group Plugins --key slidingpopupsEnabled true || die "fx sliding"
kwriteconfig6 --file kwinrc --group Plugins --key fadeEnabled true || die "fx fade"
kwriteconfig6 --file kwinrc --group Plugins --key glideEnabled true || die "fx glide"
kwriteconfig6 --file kwinrc --group Plugins --key maximizeEnabled true || die "fx maximize"
kwriteconfig6 --file kwinrc --group Plugins --key minimizeEnabled true || die "fx minimize"
kwriteconfig6 --file kwinrc --group Plugins --key scaleEnabled true || die "fx scale"
kwriteconfig6 --file kwinrc --group Plugins --key resizeEnabled true || die "fx resize"
kwriteconfig6 --file kwinrc --group Plugins --key wobblywindowsEnabled false || die "fx wobbly off"
kwriteconfig6 --file kwinrc --group Plugins --key kwin4_effect_magiclampEnabled false || die "fx magiclamp off"
kwriteconfig6 --file kwinrc --group Plugins --key kwin4_effect_ballEnabled false || die "fx ball off"
kwriteconfig6 --file kwinrc --group Plugins --key kwin4_effect_kcubeEnabled false || die "fx cube off"
busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure 2>/dev/null \
  || say "note: kwin reconfigure deferred to next login"

say "GTK theme wiring ($SFX mode)"
for g in gtk-3.0 gtk-4.0; do
  mkdir -p "$HOME/.config/$g"
  if [ "$SFX" = "dark" ]; then GTK_THEME="Orchis-Dark"; else GTK_THEME="Breeze"; fi
  cat > "$HOME/.config/$g/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=false
gtk-button-images=true
gtk-cursor-blink=true
gtk-cursor-blink-time=1000
gtk-cursor-theme-name=Breeze_Light
gtk-cursor-theme-size=24
gtk-decoration-layout=icon:minimize,maximize,close
gtk-enable-animations=true
gtk-font-name=Noto Sans,  10
gtk-icon-theme-name=FairyWren_Light
gtk-menu-images=true
gtk-modules=window-decorations-gtk-module:colorreload-gtk-module
gtk-primary-button-warps-slider=true
gtk-sound-theme-name=ocean
gtk-theme-name=$GTK_THEME
gtk-toolbar-style=3
gtk-xft-dpi=98304
EOF
done

say "Desktop: clean (no icons) containment"
APP=plasma-org.kde.plasma.desktop-appletsrc
if [ -f "$HOME/.config/$APP" ]; then
  sed -i 's/^plugin=org\.kde\.plasma\.folder$/plugin=org.kde.desktopcontainment/' "$HOME/.config/$APP"
  echo "desktopcontainment plugin lines: $(grep -c '^plugin=org.kde.desktopcontainment' "$HOME/.config/$APP") (expect 1)"
fi

say "Restarting plasmashell (systemd unit)"
shutdown_shell graceful || die "could not stop plasmashell"
start_shell || die "plasmashell did not come back"

say "Applying panel layout (scripts/layout.js)"
LAYOUT_OUT="$(gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
  --method org.kde.PlasmaShell.evaluateScript "$(cat "$ROOT/scripts/layout.js")" 2>&1)" || die "layout script failed: $LAYOUT_OUT"
echo "$LAYOUT_OUT"
echo "$LAYOUT_OUT" | grep -q "layout complete" || die "layout did not complete"
echo "$LAYOUT_OUT" | grep -qi "ERROR" && die "layout reported an error"

say "Curating system tray (scripts/tray-config.js)"
TRAY_OUT="$(gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
  --method org.kde.PlasmaShell.evaluateScript "$(cat "$ROOT/scripts/tray-config.js")" 2>&1)" || die "tray script failed: $TRAY_OUT"
echo "$TRAY_OUT"
echo "$TRAY_OUT" | grep -qi "ERROR" && die "tray script reported an error"

# ---- Panel visibility on Wayland -----------------------------------------
# Plasma 6.7's scripting API has no usable `hiding` property (assignments are
# silently dropped; it always reads back "none"). Fullscreen windows therefore
# stay BELOW the panels with the default view config. To get macOS-style
# fullscreen (menubar/dock hidden), write the view-level key directly:
#   [PlasmaViews][Panel N] hiding=1  ("Dodge windows": hidden unless the mouse
#   touches the screen edge; also dodges fullscreen surfaces).
# Panel view IDs are read from plasmashellrc ([PlasmaViews][Panel <id>]).
say "Panel hiding mode (fullscreen-aware)"
PIDS=$(grep -oE '^\\[PlasmaViews\\]\\[Panel [0-9]+\\]' "$HOME/.config/plasmashellrc" \
       | grep -oE '[0-9]+' | sort -u)
for pid in $PIDS; do
  kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $pid" --key hiding 1
  echo "  Panel $pid: hiding=1 (dodge windows)"
done

say "Wallpaper"
[ -f "$WALLPAPER" ] || die "wallpaper file missing: $WALLPAPER"
plasma-apply-wallpaperimage "$WALLPAPER" || say "note: set wallpaper via Desktop right-click if needed"
sleep 2

say "Verification (pass 1)"
bash "$ROOT/verify.sh" || FAIL=1

say "Persistence check (reload plasmashell once more)"
shutdown_shell graceful || die "could not stop plasmashell"
start_shell || die "plasmashell did not come back"
sleep 3
bash "$ROOT/verify.sh" || FAIL=1

if [ "$FAIL" -eq 0 ]; then
  echo "APPLIED=$BACKUP" > "$ROOT/.applied-$SFX"
  say "DONE — configuration applied and verified."
  echo "Backup : $BACKUP"
  echo "Rollback: $ROOT/rollback.sh"
  exit 0
fi