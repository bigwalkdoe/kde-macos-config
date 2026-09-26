#!/usr/bin/env bash
# kde-macos-config -- scripts/splash-theme-path.sh
# Resolve a Plasma 6 splash theme name to its package directory (stdout).
# Exit 0 = resolved, 1 = not found.
#
# It is both sourceable and executable:
#   source scripts/splash-theme-path.sh        # defines splash_theme_path
#   ./scripts/splash-theme-path.sh NAME       # prints the dir, or exits 1
#
# WHY THIS EXISTS: Plasma 6.7 dropped libksplash, and with it the
# "Plasma/SplashTheme" packages that used to live in plasma/splash/themes/ -
# a root that no longer exists on a current install. A splash is now an ordinary
# plasma/look-and-feel package shipping contents/splash/Splash.qml, which is how
# the bundled Breeze/Fedora themes and Orchis ship theirs, and how a
# user-installed AppleSplash is laid out. Checking plasma/splash/themes/ made
# every splash look uninstalled: apply.sh concluded AppleSplash was missing and
# never configured it, while verify.sh warned that a perfectly resolvable theme
# was dangling. Both were wrong about a system that works.
#
# ksplashqml takes no theme argument (plasma-ksplash.service runs it bare), so
# it resolves the name itself from ksplashrc, falling back to the active
# look-and-feel's own splash. Keep the resolution here in one place so the
# writer and the checker cannot disagree again.

# KPackage data roots, highest priority first: a user's own theme must win over
# a system one, exactly as KPackage resolves them.
_splash_lnf_roots() {
  # XDG_DATA_DIRS is a colon-separated LIST (here it also carries two flatpak
  # export dirs), so it has to be split before use. Iterating it unquoted as a
  # single word yields one bogus concatenated root and silently finds nothing.
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share} \
    | tr ':' '\n' | sed '/^$/d; s|$|/plasma/look-and-feel|'
}

# splash_theme_path <name> -> prints the resolved package dir on stdout.
splash_theme_path() {
  local name="${1:-}" root
  [ -n "$name" ] || return 1
  case "$name" in
    */*|*[!A-Za-z0-9._-]*) return 1 ;;   # a package id, never a path
  esac
  while IFS= read -r root; do
    [ -f "$root/$name/contents/splash/Splash.qml" ] || continue
    printf '%s\n' "$root/$name/contents/splash"
    return 0
  done < <(_splash_lnf_roots)
  # Pre-6.7 layout, kept so an older install (or a standalone splash package)
  # still resolves instead of silently losing its splash.
  while IFS= read -r root; do
    [ -d "$root/plasma/splash/themes/$name" ] || continue
    printf '%s\n' "$root/plasma/splash/themes/$name"
    return 0
  done < <(_splash_lnf_roots)
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  splash_theme_path "$@"
fi
