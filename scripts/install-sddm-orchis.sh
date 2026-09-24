#!/usr/bin/env bash
# kde-macos-config -- scripts/install-sddm-orchis.sh
# Installs the Orchis SDDM (login screen) theme and switches the greeter to it.
#
# Unlike every other script in this repo this one DOES touch system files
# (/usr/share/sddm/themes, /etc/sddm.conf.d), so it runs as root. It still
# stages and verifies everything first, is idempotent, and preserves the
# existing CursorTheme/Font settings it finds in /etc/sddm.conf.d.
#
# Usage: sudo ./scripts/install-sddm-orchis.sh   (or plain, it prompts for sudo)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Stage under the invoking (human) user even though this script runs as root.
UUSER="${SUDO_USER:-$USER}"
STAGE="/home/$UUSER/.local/share/sddm-src"
THEME_DIR="/usr/share/sddm/themes"
CONF="/etc/sddm.conf.d/theme.conf"
NAME="Orchis"
SRC_REPO="https://github.com/vinceliuice/Orchis-kde.git"
TMP="$(mktemp -d)" ; trap 'rm -rf "$TMP"' EXIT

say(){ echo; echo "### $*"; }

say "Root check"
if [ "$(id -u)" -ne 0 ]; then
  echo "note: needs root for $THEME_DIR and $CONF"
  exec sudo -H "$0" "$@"
fi

command -v git >/dev/null || { echo "FAIL: git required" >&2; exit 1; }

say "Stage Orchis SDDM theme (6.0 / Qt6)"
if [ -d "$STAGE/$NAME" ]; then
  rm -rf "$STAGE/$NAME"; fi
git clone --depth 1 "$SRC_REPO" "$TMP/Orchis-kde" >/dev/null 2>&1 \
  || { echo "FAIL: clone from $SRC_REPO" >&2; exit 1; }
[ -d "$TMP/Orchis-kde/sddm/6.0/$NAME" ] || { echo "FAIL: sddm/6.0/$NAME missing in repo" >&2; exit 1; }
mkdir -p "$STAGE"
cp -a "$TMP/Orchis-kde/sddm/6.0/$NAME" "$STAGE/$NAME"
grep -q "Name=$NAME" "$STAGE/$NAME/metadata.desktop" || { echo "FAIL: metadata check" >&2; exit 1; }
echo "staged: $STAGE/$NAME ($(du -sh "$STAGE/$NAME" | cut -f1))"

say "Install to $THEME_DIR/$NAME"
mkdir -p "$THEME_DIR"
[ -d "$THEME_DIR/$NAME" ] && rm -rf "$THEME_DIR/$NAME"
cp -a "$STAGE/$NAME" "$THEME_DIR/$NAME"
[ -f "$THEME_DIR/$NAME/metadata.desktop" ] || { echo "FAIL: install" >&2; exit 1; }
echo "installed."

say "Switch greeter to $NAME (preserving cursor/font)"
CURSOR="$(grep '^CursorTheme=' "$CONF" 2>/dev/null | cut -d= -f2)"
FONT="$(grep '^Font=' "$CONF" 2>/dev/null | cut -d= -f2-)"
mkdir -p /etc/sddm.conf.d
cat > "$CONF" <<EOF
[Theme]
Current=$NAME
CursorTheme=${CURSOR:-Bibata-Modern-Ice}
Font=${FONT:-Inter,10,-1,5,50,0,0,0,0,0}
EOF
echo "written: $CONF"

say "Verify"
grep -q "^Current=$NAME$" "$CONF" && echo "PASS  greeter config -> Current=$NAME"
grep -q "^CursorTheme=" "$CONF" && echo "PASS  CursorTheme preserved: $(grep '^CursorTheme=' "$CONF" | cut -d= -f2)"
grep -q "^Font=" "$CONF" && echo "PASS  Font preserved: $(grep '^Font=' "$CONF" | cut -d= -f2-)"
echo
echo "Preview without logging out:"
echo "  sddm-greeter-qt6 --test-mode --theme $THEME_DIR/$NAME &"
echo "Takes effect at next login."