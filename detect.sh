#!/usr/bin/env bash
# kde-macos-config — detect.sh
# Non-destructive inventory of the desktop environment. Prints everything the
# project's apply/verify scripts need to know.
set -u

echo "=== host ==="
uname -srm
. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME"

echo "=== plasma / frameworks / qt ==="
plasmashell --version 2>/dev/null || true
kwin_wayland --version 2>/dev/null || true
rpm -q --qf '%{name} %{version}\n' kf6-kconfig 2>/dev/null || true
rpm -q --qf 'qt6-qtbase %{version}\n' qt6-qtbase 2>/dev/null || true

echo "=== session ==="
echo "XDG_SESSION_TYPE=$XDG_SESSION_TYPE XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP WAYLAND_DISPLAY=$WAYLAND_DISPLAY"

echo "=== displays (kscreen-doctor -o) ==="
kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | head -30

echo "=== running plasma components ==="
ps -e -o comm= | grep -E '^(plasmashell|kwin_wayland|krunner|kded6)$' | sort -u

echo "=== look-and-feel ==="
ls ~/.local/share/plasma/look-and-feel/ 2>/dev/null
echo "--- active (kdeglobals [KDE] LookAndFeelPackage):"
kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage 2>/dev/null || echo "(unset)"

echo "=== color scheme ==="
kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || echo "(unset)"

echo "=== icons ==="
kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || echo "(unset)"
echo "installed: $(ls ~/.local/share/icons/ 2>/dev/null | tr '\n' ' ')"

echo "=== cursor ==="
kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme 2>/dev/null || echo "(unset)"

echo "=== fonts ==="
kreadconfig6 --file kdeglobals --group General --key font 2>/dev/null || echo "(default)"

echo "=== window decoration ==="
kreadconfig6 --file kwinrc --group General --key decorationTheme 2>/dev/null || echo "(default)"
echo "available: $(ls ~/.local/share/aurorae/themes/ 2>/dev/null | tr '\n' ' ')"

echo "=== virtual desktops (kwinrc [Desktops]) ==="
kreadconfig6 --file kwinrc --group Desktops --key Number 2>/dev/null || echo 1
kreadconfig6 --file kwinrc --group Desktops --key Rows 2>/dev/null || echo 0

echo "=== panels (read-only plasmashell probe) ==="
cat > /tmp/kde-macos-probe.js <<'EOF'
var log = [];
var ids = panelIds.slice();
log.push("panelCount=" + ids.length);
for (var i = 0; i < ids.length; i++) {
    var p = panelById(ids[i]);
    if (!p) { continue; }
    var wtypes = [];
    var wids = p.widgetIds;
    for (var w = 0; w < wids.length; w++) {
        var wid = p.widgetById(wids[w]);
        if (wid) { wtypes.push(wid.type); }
    }
    log.push("panel " + p.location + " h=" + p.height + " floating=" + p.floating +
             " widgets=" + wtypes.join(","));
}
print(log.join("|"));
EOF
gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
  --method org.kde.PlasmaShell.evaluateScript "$(cat /tmp/kde-macos-probe.js)" 2>&1 \
  | sed -e "1s/^('//" -e "\$s/',)\$//" | tr '|' '\n' || echo "(cannot reach plasmashell)"

echo "=== gtk theme settings ==="
grep -E 'gtk-theme-name|gtk-icon-theme-name|gtk-cursor-theme-name' ~/.config/gtk-3.0/settings.ini 2>/dev/null || echo "(default)"

echo "=== backup dirs ==="
ls -1dt ~/.config/kde-backups/*/ 2>/dev/null | head -5

echo "=== done ==="