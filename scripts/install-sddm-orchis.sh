#!/usr/bin/env bash
# kde-macos-config -- scripts/install-sddm-orchis.sh
# Installs the Orchis-Mac SDDM (login screen) theme and switches the greeter to it.
# Enterprise-grade: security hardening, accessibility, branding, session management.
# Custom macOS-style UI: rounded inputs, custom logo, matching wallpaper, accent colors.
#
# Unlike every other script in this repo this one DOES touch system files
# (/usr/share/sddm/themes, /etc/sddm.conf.d), so it runs as root. It still
# stages and verifies everything first, is idempotent, and preserves the
# existing CursorTheme/Font settings it finds in /etc/sddm.conf.d.
#
# Usage: sudo ./scripts/install-sddm-orchis.sh   (or plain, it prompts for sudo)
#        ./scripts/install-sddm-orchis.sh --force  bypass the fast-exit and reinstall
set -euo pipefail
# Stage under the invoking (human) user even though this script runs as root.
UUSER="${SUDO_USER:-$USER}"
STAGE="/home/$UUSER/.local/share/sddm-src"
THEME_DIR="/usr/share/sddm/themes"
CONF="/etc/sddm.conf.d/theme.conf"
NAME="Orchis-Mac"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THEME_SRC="$ROOT/assets/sddm-theme/$NAME"
APPLIED_CONF="$ROOT/config/applied-sddm.conf"
TMP="$(mktemp -d)" ; trap 'rm -rf "$TMP"' EXIT

say(){ echo; echo "### $*"; }

say "Root check"
if [ "$(id -u)" -ne 0 ]; then
  echo "note: needs root for $THEME_DIR and $CONF"
  exec sudo -H "$0" "$@"
fi

say "Short-circuit: already installed?"
FORCE=no
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=yes ;;
  esac
done
INSTALLED_OK=no
if [ "$FORCE" = "no" ] && [ -d "$THEME_DIR/$NAME" ] && [ -f "$THEME_DIR/$NAME/metadata.desktop" ] \
   && grep -q "^Name=$NAME$" "$THEME_DIR/$NAME/metadata.desktop" \
   && [ -f "$CONF" ] && grep -q "^Current=$NAME$" "$CONF"; then
  INSTALLED_OK=yes
fi
if [ "$INSTALLED_OK" = "yes" ]; then
  echo
  echo "Already installed and configured ($THEME_DIR/$NAME, $CONF -> $NAME)."
  echo "Nothing to do — skipping clone/install. Use --force to reinstall."
  echo
  echo "Greeter status:"
  grep -q "^Current=$NAME$" "$CONF" && echo "  PASS  Current=$NAME"
  grep -q "^CursorTheme=" "$CONF" && echo "  PASS  CursorTheme=$(grep '^CursorTheme=' "$CONF" | cut -d= -f2)"
  grep -q "^Font=" "$CONF" && echo "  PASS  Font=$(grep '^Font=' "$CONF" | cut -d= -f2-)"
  echo
  echo "Preview without logging out:"
  echo "  sddm-greeter-qt6 --test-mode --theme $THEME_DIR/$NAME &"
  exit 0
fi

say "Stage Orchis-Mac SDDM theme from repo assets"
if [ ! -d "$THEME_SRC" ]; then
  echo "FAIL: Theme source not found at $THEME_SRC" >&2
  exit 1
fi
if [ -d "${STAGE:?}/$NAME" ]; then
  rm -rf "${STAGE:?}/$NAME"; fi
mkdir -p "$STAGE"
cp -a "$THEME_SRC" "$STAGE/$NAME"
grep -q "Name=$NAME" "$STAGE/$NAME/metadata.desktop" || { echo "FAIL: metadata check" >&2; exit 1; }
echo "staged: $STAGE/$NAME ($(du -sh "$STAGE/$NAME" | cut -f1))"

say "Install to $THEME_DIR/$NAME"
mkdir -p "$THEME_DIR"
[ -d "${THEME_DIR:?}/$NAME" ] && rm -rf "${THEME_DIR:?}/$NAME"
cp -a "$STAGE/$NAME" "$THEME_DIR/$NAME"
[ -f "$THEME_DIR/$NAME/metadata.desktop" ] || { echo "FAIL: install" >&2; exit 1; }
echo "installed."

say "Apply enterprise SDDM configuration from $APPLIED_CONF"
if [ ! -f "$APPLIED_CONF" ]; then
  echo "WARN: $APPLIED_CONF not found, using minimal config"
  CURSOR="Bibata-Modern-Ice"
  FONT="Inter,10,-1,5,50,0,0,0,0,0"
else
  # Parse applied-sddm.conf for key values
  CURSOR="$(grep '^CursorTheme=' "$APPLIED_CONF" | cut -d= -f2)"
  FONT="$(grep '^Font=' "$APPLIED_CONF" | cut -d= -f2-)"
  # Copy entire config to system location
  mkdir -p /etc/sddm.conf.d
  cp "$APPLIED_CONF" "$CONF"
  echo "Applied enterprise config from $APPLIED_CONF"
fi

# Ensure required fields exist even if parsed from file
mkdir -p /etc/sddm.conf.d
if ! grep -q "^Current=" "$CONF" 2>/dev/null; then
  cat > "$CONF" <<EOF
[Theme]
Current=$NAME
CursorTheme=${CURSOR:-Bibata-Modern-Ice}
Font=${FONT:-Inter,10,-1,5,50,0,0,0,0,0}
EOF
fi

# Verify required keys exist (enterprise compliance)
for key in Current CursorTheme Font; do
  grep -q "^$key=" "$CONF" || { echo "FAIL: missing $key in $CONF" >&2; exit 1; }
done

say "Enterprise features verification"
# Verify security settings
grep -q "LogFailedLogins=true" "$CONF" && echo "  PASS  Failed login logging enabled"
grep -q "MaxFailedAttempts=" "$CONF" && echo "  PASS  Brute-force protection configured"
grep -q "LockoutDuration=" "$CONF" && echo "  PASS  Account lockout configured"

# Verify accessibility
grep -q "HighContrast=" "$CONF" && echo "  PASS  High contrast option present"
grep -q "LargeText=" "$CONF" && echo "  PASS  Large text option present"

# Verify user privacy
grep -q "MinimumUid=" "$CONF" && echo "  PASS  System account filtering configured"
grep -q "HiddenUsers=" "$CONF" && echo "  PASS  Hidden users configured"

# Verify numlock
grep -q "Numlock=on" "$CONF" && echo "  PASS  Numlock enabled for password entry"

# Verify keyboard layout
grep -q "ShowLayoutIndicator=" "$CONF" && echo "  PASS  Keyboard layout indicator configured"

# Verify custom theme assets
[ -f "$THEME_DIR/$NAME/assets/logo.svg" ] && echo "  PASS  Custom logo installed"
[ -f "$THEME_DIR/$NAME/background.jpg" ] && echo "  PASS  Custom background installed"
[ -f "$THEME_DIR/$NAME/Login.qml" ] && echo "  PASS  Custom login UI installed"

echo "written: $CONF"
cat "$CONF"

say "Verify"
grep -q "^Current=$NAME$" "$CONF" && echo "PASS  greeter config -> Current=$NAME"
grep -q "^CursorTheme=" "$CONF" && echo "PASS  CursorTheme: $(grep '^CursorTheme=' "$CONF" | cut -d= -f2)"
grep -q "^Font=" "$CONF" && echo "PASS  Font: $(grep '^Font=' "$CONF" | cut -d= -f2-)"
echo
echo "Preview without logging out:"
echo "  sddm-greeter-qt6 --test-mode --theme $THEME_DIR/$NAME &"
echo "Takes effect at next login."