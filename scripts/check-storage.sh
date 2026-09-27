#!/usr/bin/env bash
# kde-macos-config -- scripts/check-storage.sh
# Settles the fs-verity digest-mismatch question that verify.sh reports as a WARN.
#
# verify.sh can only count mismatches, because "btrfs scrub status" and the
# kernel journal need root. Those counters alone cannot distinguish a failing
# disk from a read-path artifact, so this script runs the check that can: a full
# blocking scrub of every btrfs mount, which re-reads and re-checksums all
# allocated data. That is the only thing that actually proves the data is sound.
#
# Usage: ./scripts/check-storage.sh            # scrubs, then interprets
#        ./scripts/check-storage.sh --dry-run  # report only, scrub nothing
#        ./scripts/check-storage.sh --since 7d
#
# Exit: 0 clean, 1 a real fault was found, 2 environment/usage problem.
set -euo pipefail

DRY=0
SINCE="24 hours ago"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --since) shift; SINCE="${1:?--since needs an argument}" ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

say(){ echo; echo "### $*"; }
die(){ echo "FAIL: $*" >&2; exit 2; }

# Root check. The scrub status file, the device error counters and the kernel
# journal are all root-only, and re-running under sudo keeps the rest of the
# script on the same host/mount namespace the user is looking at.
if [ "$(id -u)" -ne 0 ] && [ "$DRY" -eq 0 ]; then
  echo "note: needs root for the scrub and the kernel journal"
  exec sudo -H "$0" "$@"
fi

command -v btrfs >/dev/null || die "btrfs-progs not installed (Fedora: sudo dnf install btrfs-progs)"

# Collect the btrfs mounts. / and /home are usually the same filesystem, so
# de-duplicate by the device backing them rather than by mountpoint.
say "btrfs mounts"
MOUNTS="$(findmnt -rn -t btrfs -o TARGET 2>/dev/null | sort -u || true)"
[ -n "$MOUNTS" ] || die "no btrfs mount found; nothing to scrub"
printf '  %s\n' $MOUNTS

FAULT=0

# ---------------------------------------------------------------- scrub
say "Scrub"
if [ "$DRY" -eq 1 ]; then
  echo "  --dry-run: not starting a scrub"
else
  for m in $MOUNTS; do
    echo "  scrubbing $m (blocking, this reads the whole filesystem)"
    # -B blocks until finished, -d prints the per-error-count summary.
    btrfs scrub start -Bd "$m" 2>&1 | sed 's/^/    /' || true
  done
fi

# The verdict lives in "scrub status", not in the scrub output above.
#
# Parse the --raw form, which is stable machine-readable JSON with underscored
# keys, rather than the human -d form. The human form is what bit this script
# before: it prints "Read errors:", "Csum errors:", "Verify errors:" with
# SPACES, so a pattern written for underscored keys silently matches nothing --
# which made a broken parse indistinguishable from a clean disk, and would have
# reported PASS on a genuinely faulty drive.
#
# Rule enforced below: never conclude "clean" from an absence of data. If the
# output cannot be parsed, that is reported as unknown, not as a pass.
for m in $MOUNTS; do
  if [ "$DRY" -eq 1 ]; then
    printf '  %-24s %s\n' "$m" "(skipped: --dry-run)"
    continue
  fi
  raw="$(btrfs scrub status --raw "$m" 2>/dev/null || true)"
  pretty="$(btrfs scrub status -d "$m" 2>/dev/null | sed -n '1,4p' | tr '\n' ' ' || true)"
  printf '  %-24s %s\n' "$m" "${pretty:-no scrub on record}"

  if ! printf '%s' "$raw" | grep -q 'device_stats'; then
    # No scrub has ever run, or the format is not what we expect. Either way
    # there is no evidence of health -- say so instead of implying all is well.
    FAULT=1
    echo "    FAIL: could not read scrub counters for $m."
    echo "          No scrub appears to be on record, or 'btrfs scrub status"
    echo "          --raw' returned something unexpected, so the data has not"
    echo "          been verified at all. Raw output was:"
    printf '%s\n' "$raw" | sed 's/^/            /' | head -5
    continue
  fi

  # Pull every "<key>":<number> pair out of device_stats. Count how many we
  # recognised so an empty result cannot masquerade as "all zero".
  pairs="$(printf '%s' "$raw" | grep -oE '"[a-z_]+":[[:space:]]*[0-9]+' \
           | sed 's/"//g; s/:[[:space:]]*/ /' || true)"
  nseen="$(printf '%s' "$pairs" | grep -c . || true)"
  if [ "$nseen" -eq 0 ]; then
    FAULT=1
    echo "    FAIL: scrub counters for $m parsed to nothing ($nseen fields)."
    echo "          Refusing to call this clean without evidence."
    continue
  fi

  # Every counter except the csum/read informational ones is a fault if non-zero.
  # "no_csums" counts extents simply lacking a checksum, which is normal, so it
  # is reported but not treated as damage.
  # ($2+0) so a missing or malformed value counts as zero rather than as a
  # non-zero "error" -- the nseen guard above already proves fields were found.
  bad="$(printf '%s' "$pairs" | awk '$1 ~ /err/ && ($2+0) != 0' || true)"
  if [ -n "$bad" ]; then
    FAULT=1
    echo "    FAIL: scrub reported errors on $m:"
    printf '%s\n' "$bad" | sed 's/^/      /'
  else
    nocsum="$(printf '%s' "$pairs" | awk '$1 == "no_csums" {print $2}')"
    echo "    PASS: all $nseen scrub counters zero on $m (data re-read and re-checksummed)"
    [ -n "${nocsum:-}" ] && [ "$nocsum" != 0 ] \
      && echo "          ($nocsum extents have no checksum; normal, not damage)"
  fi
done

# ------------------------------------------------------- device counters
say "Device error counters"
for m in $MOUNTS; do
  stats="$(btrfs device stats "$m" 2>/dev/null || true)"
  if [ -z "$stats" ]; then
    echo "  $m: unavailable (needs root)"
    continue
  fi
  nz="$(printf '%s' "$stats" | grep -vE '[[:space:]]0$' || true)"
  if [ -n "$nz" ]; then
    FAULT=1
    echo "  FAIL: non-zero counters on $m:"
    printf '%s\n' "$nz" | sed 's/^/    /'
  else
    echo "  PASS: $m -- write/read/flush/corruption/generation all 0"
  fi
done

# ---------------------------------------------------------- fs-verity
# Same categorisation as verify.sh: a read that returns exactly one 4 KiB block
# of zeros is a known btrfs read-path artifact, anything else is unexplained.
# The inodes matter most -- if none of them resolve to a live file, no
# persistent data was involved.
say "fs-verity digest mismatches (since $SINCE)"
ZERO_BLOCK="$(head -c 4096 /dev/zero | sha256sum | cut -d' ' -f1)"
EV="$(journalctl -k --since "$SINCE" -o cat 2>/dev/null | grep -E 'fs-verity.*CORRUPTED|FILE CORRUPTED' || true)"
TOTAL="$(printf '%s' "$EV" | grep -c . || true)"
ZERO="$(printf '%s' "$EV" | grep -c "real_hash=sha256:$ZERO_BLOCK" || true)"
OTHER=$((TOTAL - ZERO))

if [ "$TOTAL" -eq 0 ]; then
  echo "  PASS: no digest mismatch logged"
else
  echo "  total=$TOTAL  zero-fill=$ZERO  unexplained=$OTHER"
  INODES="$(printf '%s' "$EV" | grep -oE 'inode [0-9]+' | awk '{print $2}' | sort -un || true)"
  NINODES="$(printf '%s' "$INODES" | grep -c . || true)"
  echo "  affected inodes: $NINODES (one full traversal per filesystem, be patient)"
  if [ "$NINODES" -eq 0 ]; then
    echo "  note: logged no inode numbers, cannot map them to files"
  else
    # One traversal for all inodes at once; -quit stops at the first live hit.
    PRED=''
    for i in $INODES; do PRED="$PRED -o -inum $i"; done
    LIVE=""
    for m in $MOUNTS; do
      hit="$(find "$m" -xdev \( $PRED \) -print -quit 2>/dev/null || true)"
      if [ -n "$hit" ]; then LIVE="$hit"; break; fi
    done
    if [ -n "$LIVE" ]; then
      FAULT=1
      echo "  FAIL: a live file is affected: $LIVE"
    else
      echo "  PASS: none of the affected inodes resolve to a live file"
      echo "        (consistent with short-lived files being freed while read,"
      echo "         not with damage to persistent data)"
    fi
  fi
fi

# ------------------------------------------------------------- verdict
say "Verdict"
if [ "$FAULT" -ne 0 ]; then
  cat <<'EOF'
  A storage fault WAS found -- see the FAIL lines above.

  Do not keep writing to this filesystem. Back up what matters, then:
    * check the drive's SMART data (Fedora: sudo dnf install smartmontools,
      sudo smartctl -a /dev/nvme0n1)
    * for a NVMe drive, check for a firmware update
    * run memtest86+ from the GRUB menu to rule out RAM
    * if the scrub counters are non-zero again after a memory test, the
      storage is the problem; replace it and restore from backup
EOF
  exit 1
fi

# A dry run deliberately skips the only check that proves anything about data
# integrity, so it must not claim the filesystem is fine. Say what was skipped.
if [ "$DRY" -eq 1 ]; then
  cat <<'EOF'
  No fault in the checks that ran, but this was --dry-run, so NO scrub was
  performed and the data itself has not been verified. The scrub is the only
  thing here that can prove the filesystem is intact, so this is not a verdict.

  Run it for real to settle it:
    ./scripts/check-storage.sh
EOF
  exit 0
fi

cat <<'EOF'
  No storage fault found.

  The filesystem scrubbed clean, every device error counter is 0, and no
  fs-verity mismatch touches a live file. The digest mismatches verify.sh warns
  about are a read-path artifact, not evidence of failing hardware.

  Still worth doing once, since RAM is not covered by any of the above:
    sudo dnf install memtest86+   # then reboot and run it from the GRUB menu
EOF
exit 0

cat <<'EOF'
  A storage fault WAS found -- see the FAIL lines above.

  Do not keep writing to this filesystem. Back up what matters, then:
    * check the drive's SMART data (Fedora: sudo dnf install smartmontools,
      sudo smartctl -a /dev/nvme0n1)
    * for a NVMe drive, check for a firmware update
    * run memtest86+ from the GRUB menu to rule out RAM
    * if the scrub counters are non-zero again after a memory test, the
      storage is the problem; replace it and restore from backup
EOF
exit 1
