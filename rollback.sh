#!/usr/bin/env bash
# kde-macos-config -- rollback.sh
# Restores the most recent timestamped backup and reloads the desktop shell.
# No manual bookkeeping needed: backups are chronological directories under
# ~/.config/kde-backups/YYYYmmdd-HHMMSS/.
#
# The restore itself lives in scripts/restore-backup.sh, which is the single
# implementation shared with apply.sh's automatic fail-safe. This script only
# picks the backup.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

BK="$(ls -1dt "$HOME"/.config/kde-backups/*/ 2>/dev/null | head -1)"
if [ -z "$BK" ]; then
  echo "No backups found under ~/.config/kde-backups/ — nothing to restore." >&2
  exit 1
fi

# shellcheck source=scripts/restore-backup.sh
. "$ROOT/scripts/restore-backup.sh"
restore_backup "$BK"
echo "Rollback complete — desktop reloaded with the previous configuration."
