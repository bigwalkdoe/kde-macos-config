#!/usr/bin/env bash
# kde-macos-config -- sync.sh
# Snapshots the live KDE config into config/ so git tracks a portable,
# machine-independent copy. Machine-specific noise (fresh desktop UUIDs,
# per-desktop tiling sections) is stripped before writing, so commits don't
# churn on every machine the config is applied to.
#
# Usage:
#   ./sync.sh            # snapshot + show git status (does NOT commit)
#   ./sync.sh --commit   # snapshot + commit with a generated message
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; cd "$ROOT"
CFG="$HOME/.config"
C="$ROOT/config"

# live file -> repo snapshot (copied verbatim)
PAIRS=(
  "$CFG/plasma-org.kde.plasma.desktop-appletsrc $C/applied-appletsrc.conf"
  "$CFG/plasmashellrc $C/applied-plasmashellrc.conf"
  "$CFG/kdeglobals $C/applied-kdeglobals.conf"
  "$CFG/kwinrc $C/applied-kwinrc.conf"
  "$CFG/gtk-3.0/settings.ini $C/applied-gtk3.ini"
  "$CFG/gtk-3.0/settings.ini $C/gtk.settings.ini"
  "$CFG/kdeglobals $C/kdeglobals.reference"
  "$CFG/kwinrc $C/kwinrc.reference"
  "$CFG/kcminputrc $C/kcminputrc.reference"
  "$CFG/ksplashrc $C/ksplashrc.reference"
)

# Normalize a kwinrc stream on stdin -> stdout: drop per-desktop [Tiling][uuid]
# sections and the freshly regenerated desktop IDs 2-4 (Id_1 is preserved).
strip_machine_noise() {
  awk '
    /^\[/ {
      tiling = ($0 ~ /^\[Tiling\]\[/);
      print; next
    }
    tiling { next }
    /^Id_[0-9]+=/ && $0 !~ /^Id_1=/ { next }
    { print }
  '
}

ver="$(git rev-parse --short HEAD)"
echo "=== kde-macos-config: sync ($(date +%Y-%m-%d\ %H:%M:%S)) ==="
for pair in "${PAIRS[@]}"; do
  src="${pair%% *}"; dst="${pair#* }"
  if [ ! -f "$src" ]; then
    echo "skip: $src (not present)"
    continue
  fi
  if [[ "$dst" == *kwinrc* ]]; then
    strip_machine_noise < "$src" > "$dst.tmp" && mv "$dst.tmp" "$dst"
  else
    cp -a "$src" "$dst"
  fi
  echo "synced $(basename "$src") -> config/$(basename "$dst")"
done

echo "--- rebuild fontconfig cache (avoids stale/corrupt caches) ---"
if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f >/dev/null 2>&1 && echo "fc-cache: clean" \
    || echo "note: fc-cache failed"
else
  echo "note: fontconfig not present"
fi

echo "--- git status ---"
git add config/
git status --short

if [ "${1:-}" = "--commit" ]; then
  git commit -q -m "Sync live KDE config into snapshots (was $ver)" \
    && echo "committed: $(git rev-parse --short HEAD)" \
    || echo "nothing to commit"
fi
echo "=== sync complete ==="