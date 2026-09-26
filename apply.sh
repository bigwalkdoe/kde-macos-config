#!/usr/bin/env bash
# kde-macos-config -- apply.sh
# macOS-inspired Plasma, applied safely & reversibly:
#   preflight -> verified timestamped backup -> theme/colors/icons/cursor ->
#   kwin (decoration/workspaces/effects) -> GTK -> plasmashell restart ->
#   native scripting layout -> wallpaper -> verification.
# On failure before completion, the backup is restored automatically.
# Usage: ./apply.sh [--light|--dark]
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)" && cd "$ROOT" || exit 1

MODE="${1:---light}"
case "$MODE" in
  --light) LNF=Orchis; LNF_PKG="com.github.vinceliuice.Orchis";       COLORS=Orchis;      ICONS=FairyWren_Light; CURSOR=Bibata-Modern-Ice; SFX="light" ;;
  --dark)  LNF=Orchis-dark; LNF_PKG="com.github.vinceliuice.Orchis-dark"; COLORS=OrchisDark;  ICONS=FairyWren_Dark;  CURSOR=Bibata-Modern-Ice; SFX="dark" ;;
  *) echo "usage: $0 [--light|--dark]"; exit 2 ;;
esac
# Plasma panel visibility enum ([PlasmaViews][Panel N] panelVisibility):
# 0=NormalPanel 1=AutoHide 2=DodgeWindows 3=WindowsGoBelow. 2 = macOS-style
# (hidden until the mouse reaches the screen edge; fullscreen dodges the bar).
PANEL_VISIBILITY="${PANEL_VISIBILITY:-2}"
SPLASH="${SPLASH:-AppleSplash}"
WALLPAPER="$HOME/.local/share/wallpapers/kde-setup-02/wavy_lines_v01_5120x2880.png"
BACKUP=""; FAIL=0
say(){ echo; echo "### $*"; }
die(){ echo "FAIL: $*" >&2; FAIL=1; exit 1; }

# The restore path and the plasmashell lifecycle both live in
# scripts/restore-backup.sh, so rollback.sh and the fail-safe below can never
# drift apart. (A file written by apply.sh but missing from the restore list is
# silently irreversible - that is exactly how fontconfig/fonts.conf was
# orphaned, and why the list now lives in one place.)
# shellcheck source=scripts/restore-backup.sh
. "$ROOT/scripts/restore-backup.sh"
trap 'if [ "$FAIL" -ne 0 ] && [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then say "FAILED - rolling back to $BACKUP"; restore_backup "$BACKUP"; fi; exit $FAIL' EXIT

say "Preflight"
command -v plasmashell >/dev/null || die "plasmashell not found - not a Plasma session"
command -v kwriteconfig6 plasma-apply-colorscheme plasma-apply-desktoptheme plasma-apply-lookandfeel plasma-apply-wallpaperimage >/dev/null || die "missing plasma tooling"
command -v gdbus >/dev/null && command -v busctl >/dev/null && command -v uuidgen >/dev/null || die "missing dbus tooling"
command -v flock >/dev/null || die "missing flock (util-linux) - cannot serialize applies"
plasmashell --version | grep -q '^plasmashell 6\.' || die "unsupported Plasma version (need 6.x)"
busctl --user list --no-pager 2>/dev/null | grep -q org.kde.plasmashell || die "plasmashell not on the session bus"
echo "Plasma: $(plasmashell --version)  Mode: $MODE"

# Serialize applies. switch.sh --auto runs from a systemd timer every 15 min, so
# a scheduled switch landing on top of a manual ./apply.sh would otherwise have
# two runs rewriting kwinrc/plasmashellrc and restarting plasmashell at once.
LOCK="$ROOT/.apply.lock"
exec 9>"$LOCK" || die "cannot open lock file $LOCK"
if ! flock -n 9; then
  die "another apply.sh/switch.sh run holds $LOCK - refusing to run concurrently"
fi
# Keep the lock for the lifetime of this script (fd 9 stays open).
echo "Lock acquired: $LOCK"

# ---- Asset preflight -----------------------------------------------------
# The tool checks above only prove Plasma is installed. Without these, a clean
# machine fails much later with an opaque error from plasma-apply-lookandfeel,
# long after the backup and the LNF patch have already been written.
#
# _has <XDG-relative-dir> <name>: is the asset present, user dir first?
# Note the dir is the full path under the XDG data dirs - only some assets live
# under plasma/ (look-and-feel, splash), while color-schemes and icons sit
# directly in the data root.
_has(){ for d in "$HOME/.local/share/$1" "/usr/share/$1"; do [ -e "$d/$2" ] && return 0; done; return 1; }

MISSING=()
_has plasma/look-and-feel "$LNF_PKG"           || MISSING+=("look-and-feel $LNF_PKG")
_has color-schemes "$COLORS.colors"             || MISSING+=("color scheme $COLORS")
_has icons "$ICONS"                             || MISSING+=("icon theme $ICONS")
_has icons "$CURSOR"                            || MISSING+=("cursor theme $CURSOR")
if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "missing theme assets required by --$MODE:" >&2
  printf '  - %s\n' "${MISSING[@]}" >&2
  echo "Install the Orchis look-and-feel + FairyWren icons + Bibata cursor" >&2
  echo "(e.g. via KDE's 'Get New...' / your distro's theme packages) and re-run." >&2
  die "preflight failed (nothing has been changed yet)"
fi
echo "Theme assets present: $LNF_PKG, $COLORS, $ICONS, $CURSOR"
# The opposite mode is only needed for switching; warn but keep going.
case "$SFX" in
  dark) OTHER_PKG="com.github.vinceliuice.Orchis";     OTHER_COLORS="Orchis";     OTHER_ICONS="FairyWren_Light" ;;
  *)    OTHER_PKG="com.github.vinceliuice.Orchis-dark"; OTHER_COLORS="OrchisDark"; OTHER_ICONS="FairyWren_Dark" ;;
esac
OTHER_MODE="$( [ "$SFX" = dark ] && echo light || echo dark )"
_has plasma/look-and-feel "$OTHER_PKG" >/dev/null 2>&1 \
  || echo "note: $OTHER_PKG not installed - ./switch.sh cannot switch to $OTHER_MODE" >&2
_has color-schemes "$OTHER_COLORS.colors" >/dev/null 2>&1 \
  || echo "note: color scheme $OTHER_COLORS not installed - switching to $OTHER_MODE will fail" >&2
_has icons "$OTHER_ICONS" >/dev/null 2>&1 \
  || echo "note: icon theme $OTHER_ICONS not installed - switching to $OTHER_MODE will fall back" >&2

say "Backup"
BACKUP="$(bash "$ROOT/backup.sh" | grep '^BackUp=' | cut -d= -f2-)"
[ -d "$BACKUP" ] || die "backup failed"
echo "Backup directory: $BACKUP"; sleep 1

say "Look-and-feel: $LNF ($LNF_PKG)"
# Patch user-local Orchis LNF defaults FIRST, so applying the Global Theme
# (plasma-apply-lookandfeel) uses the repo's icons/cursor ...
bash "$ROOT/scripts/patch-lnf.sh" || die "LNF patch failed"
# Apply the FULL Global Theme — the only call KDE recognizes as changing
# the look-and-feel.  It records kdeglobals [KDE] LookAndFeelPackage and
# applies the patched defaults (icons/cursor/kwin aurorae decoration/
# kvantum widgets).  plasma-apply-desktoptheme alone left LookAndFeelPackage
# stale, so the built-in lookandfeelautoswitcher kept snapping back to
# breeze/breezedark snapshots (Breeze icon shapes/outlines).
plasma-apply-lookandfeel -a "$LNF_PKG" || die "plasma-apply-lookandfeel failed"
plasma-apply-desktoptheme "$LNF"  || die "plasma-apply-desktoptheme failed"
plasma-apply-colorscheme "$COLORS" || die "plasma-apply-colorscheme failed"
# Disarm KDE 6.7's built-in auto dark/light theme switcher (kded module
# lookandfeelautoswitcher applies DefaultDark/LightLookAndFeel on idle +
# schedule boundaries). Pin defaults at the Orchis pair so even a manual
# re-enable can never land on stock Breeze.
for _k in AutomaticLookAndFeel AutomaticLookAndFeelOnIdle; do
  kwriteconfig6 --file kdeglobals --group KDE --key "$_k" false || die "$_k"
done
kwriteconfig6 --file kdeglobals --group KDE --key DefaultLightLookAndFeel  com.github.vinceliuice.Orchis       || die "DefaultLightLookAndFeel"
kwriteconfig6 --file kdeglobals --group KDE --key DefaultDarkLookAndFeel  com.github.vinceliuice.Orchis-dark || die "DefaultDarkLookAndFeel"

say "Icons, cursor, fonts"
kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ICONS" || die "icons"
kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$CURSOR" || die "cursor theme"
kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize 24 || die "cursor size"
kwriteconfig6 --file kdeglobals --group General --key font "Noto Sans,10,-1,5,50,0,0,0,0,0" || die "font"
# Splash: only write it when the theme actually resolves. Writing an
# uninstalled name leaves ksplashrc pointing at nothing, so KSplash silently
# uses the stock splash while the config claims otherwise.
# Resolution goes through scripts/splash-theme-path.sh: on Plasma 6.7 a splash
# is a plasma/look-and-feel package providing contents/splash/Splash.qml, not a
# package under plasma/splash/themes - a root that no longer exists. Checking the
# old path is why apply.sh kept skipping AppleSplash even though it is installed.
if SPLASH_DIR="$(bash "$ROOT/scripts/splash-theme-path.sh" "$SPLASH")"; then
  kwriteconfig6 --file ksplashrc --group KSplash --key Theme  "$SPLASH"    || die "splash theme"
  kwriteconfig6 --file ksplashrc --group KSplash --key Engine KSplashQML || die "splash engine"
  echo "splash: $SPLASH ($SPLASH_DIR)"
else
  echo "note: splash theme '$SPLASH' is not installed - leaving the existing ksplashrc value alone"
fi

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
case "$SFX" in
  dark) DECO=__aurorae__svg__Orchis-dark ;;
  *)    DECO=__aurorae__svg__Orchis ;;
esac
# Aurorae ships TWO decoration plugins in the same directory
# (/usr/lib64/qt6/plugins/org.kde.kdecoration3/): org.kde.kwin.aurorae.so and
# org.kde.kwin.aurorae.v2.so, and each registers its own id. Both load, so this
# is not a "v1 is broken" situation - it is that the live Plasma 6.7 session
# (aurorae 6.7.5) resolves the v2 id, while the Orchis LNF defaults still
# declare the v1 id. Write the id the session actually uses, and let
# scripts/patch-lnf.sh keep the LNF defaults in sync so the other switch paths
# (System Settings, plasma-apply-lookandfeel) cannot silently swap in the other
# plugin the next time the LNF is applied.
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae.v2 || die "kwin decoration library"
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "$DECO" || die "kwin decoration theme"
kwriteconfig6 --file kwinrc --group General --key BorderlessMaximizedWindows true || die "borderless"
kwriteconfig6 --file kwinrc --group Desktops --key Number 4 || die "desktops number"
kwriteconfig6 --file kwinrc --group Desktops --key Rows 1 || die "desktops rows"
# Desktop UUIDs: PRESERVE the ids already in use. An earlier revision minted a
# fresh uuidgen for Id_2..Id_4 on every run, which was wrong twice over:
#   * desktop-scoped KWin rules (per-desktop wallpaper, noanimation, keep-above)
#     are keyed on the desktop UUID, so regenerating orphaned every one of them;
#   * it made the apply non-idempotent, and switch.sh --auto runs apply.sh twice
#     a day, so the UUIDs churned 48x/day and the config diff was pure noise.
# So: reuse a non-empty, unique existing id, and only mint one for a slot that is
# missing, empty, or already used by another desktop (which KWin would mis-bind).
SEEN=""
dup_seen(){ case " $SEEN " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
for n in 1 2 3 4; do
  cur="$(kreadconfig6 --file kwinrc --group Desktops --key "Id_$n")"
  if [ -n "$cur" ] && ! dup_seen "$cur"; then
    SEEN="$SEEN $cur"
    echo "  desktop $n: keeping existing id $cur"
  else
    new="$(uuidgen)"
    while dup_seen "$new"; do new="$(uuidgen)"; done
    SEEN="$SEEN $new"
    kwriteconfig6 --file kwinrc --group Desktops --key "Id_$n" "$new" || die "desktop id $n"
    echo "  desktop $n: new id $new"
  fi
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
gtk-cursor-theme-name=$CURSOR
gtk-cursor-theme-size=24
gtk-decoration-layout=icon:minimize,maximize,close
gtk-enable-animations=true
gtk-font-name=Noto Sans,  10
gtk-icon-theme-name=$ICONS
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
  # Convert the desktop's legacy folder view to the icon-less containment, the
  # exact value System Settings writes. This plugin string is not reachable from
  # the Plasma scripting API, so it has to be a text edit - but it must be
  # TARGETED, not a blanket `s/plugin=org.kde.plasma.folder/.../g`: a user who
  # deliberately put a Folder View (with desktop icons) on some *other* screen
  # would silently lose it.
  #
  # Discriminator: a containment that owns no [Applets] section is an empty
  # folder view - the one this project wants replaced. One that does own applets
  # is a real user-configured Folder View, so it is left alone and reported.
  # (Plasma writes the applet sections *after* the plugin= line of the same
  # containment, hence the two-pass read below.)
  FOLDERS="$HOME/.config/$APP.folders.$$"
  awk '
    { line[NR] = $0
      if (match($0, /^\[Containments\]\[[0-9]+\]\[Applets\]\[/)) {
        id = $0
        sub(/^\[Containments\]\[/, "", id); sub(/\]\[Applets\]\[.*$/, "", id)
        hasApplets[id] = 1
      }
    }
    END {
      cur = ""
      for (i = 1; i <= NR; i++) {
        l = line[i]
        if (match(l, /^\[Containments\]\[[0-9]+\]$/)) {
          cur = l
          sub(/^\[Containments\]\[/, "", cur); sub(/\]$/, "", cur)
        }
        if (l ~ /^plugin=org\.kde\.plasma\.folder$/) {
          if (cur in hasApplets) skipped[++nskip] = cur
          else { sub(/^plugin=.*/, "plugin=org.kde.desktopcontainment", l); nconv++ }
        }
        print l
      }
      printf "converted=%d\n", nconv + 0 > "/dev/stderr"
      printf "skipped=%d\n", nskip + 0 > "/dev/stderr"
      for (i = 1; i <= nskip; i++) printf "skipped_id=%s\n", skipped[i] > "/dev/stderr"
    }
  ' "$HOME/.config/$APP" 2>"$FOLDERS" > "$HOME/.config/$APP.new" || {
    rm -f "$HOME/.config/$APP.new" "$FOLDERS"
    die "folder-view conversion failed; $APP left untouched"
  }
  # Only replace the live file if awk succeeded, and report what it did.
  mv "$HOME/.config/$APP.new" "$HOME/.config/$APP"
  CONV="$(sed -n 's/^converted=//p' "$FOLDERS")"
  SKIP="$(sed -n 's/^skipped=//p' "$FOLDERS")"
  echo "  converted $CONV folder view(s) to org.kde.desktopcontainment"
  if [ "${SKIP:-0}" -gt 0 ]; then
    echo "  left $SKIP configured Folder View(s) alone - containment id(s) $(sed -n 's/^skipped_id=//p' "$FOLDERS" | tr '\n' ' ')"
    echo "  have desktop icons, so this project does not touch them (delete them by hand if unwanted)"
  fi
  rm -f "$FOLDERS"
  echo "desktopcontainment plugin lines: $(grep -c '^plugin=org.kde.desktopcontainment' "$HOME/.config/$APP") (one per screen)"
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
# Plasma 6.7's scripting API has no usable visibility property (assignments are
# silently dropped). Fullscreen windows therefore stay BELOW the panels with the
# default view config. The real, Plasma-owned config key is:
#   [PlasmaViews][Panel N] panelVisibility=<n>
# with the enum the shipped Panel View KCM uses (PanelConfiguration.qml):
#   0 = NormalPanel (always visible)   1 = AutoHide
#   2 = DodgeWindows                   3 = WindowsGoBelow
# 2 gives macOS-style fullscreen: menubar/dock stay hidden until the mouse
# touches the screen edge, and fullscreen surfaces dodge them.
#
# The panel ids must come from layout.js, not from grepping plasmashellrc. This
# script removes every panel and creates two new ones, which means NEW ids -
# and plasmashell only flushes plasmashellrc asynchronously. Two earlier
# revisions wrote to the stale on-disk ids (707/728) while the live panels were
# 736/757, so the write "succeeded" and the setting never took effect.
# So: take the ids layout.js reports, wait for plasmashellrc to catch up, write,
# then read back and confirm. Because Plasma itself owns and re-serialises
# panelVisibility, the value survives the shell restarts below.
say "Panel visibility mode (fullscreen-aware)"
PANEL_RC_FILE="$HOME/.config/plasmashellrc"
disk_panel_ids(){ grep -oE '^\[PlasmaViews\]\[Panel [0-9]+\]' "$PANEL_RC_FILE" \
                    | grep -oE '[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
WANT_IDS="$(printf '%s' "$LAYOUT_OUT" | grep -oE 'panelIds=[0-9]+,[0-9]+' | head -1 | cut -d= -f2 | tr ',' ' ')"
if [ -n "$WANT_IDS" ]; then
  echo "  layout.js created panel(s): $WANT_IDS"
else
  WANT_IDS="$(disk_panel_ids)"
  echo "  WARNING: layout.js did not report panel ids; falling back to on-disk ids ($WANT_IDS)"
fi
[ -n "$WANT_IDS" ] || die "no panel ids available - cannot set panel visibility"

attempt=0
while :; do
  attempt=$((attempt + 1))
  [ "$attempt" -le 15 ] || die "plasmashellrc never contained panels [$WANT_IDS] after 15s (on disk: $(disk_panel_ids))"
  HAVE_IDS=" $(disk_panel_ids) "
  all_present=1
  for w in $WANT_IDS; do case "$HAVE_IDS" in *" $w "*) ;; *) all_present=0 ;; esac; done
  if [ "$all_present" -eq 0 ]; then
    sleep 1
    continue
  fi
  for pid in $WANT_IDS; do
    kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $pid" \
      --key panelVisibility "$PANEL_VISIBILITY" || die "panelVisibility for panel $pid"
  done
  # Read back: kwriteconfig6 exiting 0 only means the file was written, not that
  # Plasma kept the key.
  ok=1
  for pid in $WANT_IDS; do
    got="$(kreadconfig6 --file plasmashellrc --group PlasmaViews --group "Panel $pid" \
            --key panelVisibility 2>/dev/null || true)"
    if [ "$got" = "$PANEL_VISIBILITY" ]; then
      echo "  Panel $pid: panelVisibility=$got (dodge windows)"
    else
      echo "  Panel $pid: read back '$got' (expected $PANEL_VISIBILITY) - retrying"
      ok=0
    fi
  done
  [ "$ok" -eq 1 ] && break
  sleep 1
done


say "Wallpaper"
WALLPAPER_DIR="$HOME/.local/share/wallpapers/kde-setup-02"
WALLPAPER_NAME="wavy_lines_v01_5120x2880.png"
if [ ! -f "$WALLPAPER" ]; then
  # Self-heal: install the vendored asset from assets/wallpapers/ (committed
  # to this repo so apply.sh is reproducible on a clean machine without the
  # original Downloads zip).
  VENDORED="$ROOT/assets/wallpapers/$WALLPAPER_NAME"
  if [ -f "$VENDORED" ]; then
    mkdir -p "$WALLPAPER_DIR"
    cp -f "$VENDORED" "$WALLPAPER" && echo "installed vendored wallpaper: $WALLPAPER"
  else
    die "wallpaper file missing: $WALLPAPER (and no vendored copy at $VENDORED)"
  fi
fi
[ -f "$WALLPAPER" ] || die "wallpaper file missing: $WALLPAPER"
plasma-apply-wallpaperimage "$WALLPAPER" || say "note: set wallpaper via Desktop right-click if needed"
sleep 2

say "Verification (pass 1)"
# Tell verify.sh an apply is in flight, so it defers the reboot-persistence check
# instead of judging the PREVIOUS run's marker. Also: plasmashell persists several
# of these settings asynchronously, so this pass can still observe pre-restart
# state (a stale panel section, an unserialised key) on an otherwise correct
# apply. Rolling back a good desktop because of that is worse than the flake;
# pass 2 below runs after a full restart and is the authoritative gate. Results
# are still printed either way.
export KDE_APPLY_IN_PROGRESS=1
if ! bash "$ROOT/verify.sh"; then
  say "NOTE: pass 1 reported failures; pass 2 after restart is authoritative"
fi

say "Persistence check (reload plasmashell once more)"
shutdown_shell graceful || die "could not stop plasmashell"
start_shell || die "plasmashell did not come back"
sleep 3
bash "$ROOT/verify.sh" || FAIL=1

if [ "$FAIL" -eq 0 ]; then
  {
    echo "APPLIED=$BACKUP"
    echo "BOOT=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
  } > "$ROOT/.applied-$SFX"
  say "DONE — configuration applied and verified."
  echo "Backup : $BACKUP"
  echo "Rollback: $ROOT/rollback.sh"
  exit 0
fi
