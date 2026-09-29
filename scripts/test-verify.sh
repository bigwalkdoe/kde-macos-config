#!/usr/bin/env bash
# Tests for the health checks in verify.sh that count events in a log.
#
# These three read their data through a pipe, so they share one failure mode: a
# verdict derived from a counter cannot tell "nothing happened" from "nothing
# could be read", and both states used to print PASS. Replaying the log is the
# only way to test that, and it needs no Plasma session -- putting stub
# journalctl / fc-cache executables ahead of PATH decides what verify.sh sees.
# That is what lets this run in CI, which cannot run verify.sh itself.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
ok(){ printf 'ok   %s\n' "$1"; }
no(){ printf 'FAIL %s\n       %s\n' "$1" "$2"; fails=$((fails + 1)); }

# A stub set is a directory of fake executables, named so it can go on PATH.
set_new(){ mkdir -p "$WORK/$1"; }
stub(){ printf '#!/bin/sh\n%s\n' "$3" > "$WORK/$1/$2"; chmod +x "$WORK/$1/$2"; }

# Run verify.sh once under a stub set and keep the whole output. Once per set, not
# once per assertion: a run costs ~20s even with the log tools stubbed
# (plasmashell --version, the panel probe, one desktop-file lookup per pinned
# launcher), and a single run is a single coherent state, so every needle is
# asserted against that one capture.
OUT=''
run(){ OUT="$(PATH="$WORK/$1:$PATH" bash "$ROOT/verify.sh" 2>&1)" || true; }
# Only the health lines are asserted on: the rest of verify.sh legitimately fails
# without a live Plasma session, which is why its result line is ignored here.
has(){
  case "$OUT" in
    *"$1"*) ok "$2" ;;
    *) no "$2" "no line matching: $1" ;;
  esac
}
lacks(){
  case "$OUT" in
    *"$1"*) no "$2" "unexpected line: $1" ;;
    *) ok "$2" ;;
  esac
}

echo "=== test-verify: health checks that read a log ==="

# A journal that reads fine and has nothing wrong with it. The crash-line count
# has to be 0 for the PASS branch, and the 24h readability probe has to be
# non-empty, so the stub prints one ordinary line.
set_new quiet
stub quiet journalctl 'echo "systemd: Started Session 12 of user deon."'
stub quiet fc-cache 'exit 0'
run quiet
has "PASS  no plasmashell crash-loop in last 10 min" \
  "readable journal with no crash still reports PASS"
has "PASS  no fs-verity digest mismatch in last 24h" \
  "readable kernel log with no mismatch still reports PASS"
has "PASS  no invalid fontconfig caches" \
  "fc-cache that ran cleanly still reports PASS"

# A journal that reads fine and contains a real crash. This is the positive
# control: without it a test that only ever saw UNVERIFIED would pass while the
# detection it is protecting had silently stopped working.
set_new crash
stub crash journalctl 'echo "plasma-plasmashell.service: Main process exited, code=dumped, status=11/SEGV"'
stub crash fc-cache 'exit 0'
run crash
has "FAIL  no plasmashell crash-loop in last 10 min" \
  "a crash in a readable journal is still detected"
lacks "UNVERIFIED  no plasmashell crash-loop" \
  "a readable journal is never reported as unread"

# A journal that is readable over 24h but has nothing in the last 10 minutes --
# the ordinary state of a session that has not restarted plasmashell recently.
# The verdict has to be PASS, and it can only be if the readability probe asks
# for a wider window than the crash detection does. Probing readability over the
# same 10 minutes would report UNVERIFIED here, i.e. turn the check's blind spot
# into a false alarm on a healthy machine.
set_new quietwindow
stub quietwindow journalctl 'case "$*" in *"24 hours ago"*) echo "systemd: Started Session 12 of user deon." ;; esac'
stub quietwindow fc-cache 'exit 0'
run quietwindow
has "PASS  no plasmashell crash-loop in last 10 min" \
  "a quiet 10-minute window in a readable journal is PASS, not UNVERIFIED"
has "PASS  no fs-verity digest mismatch in last 24h" \
  "a readable kernel log is PASS even when it holds no fs-verity lines"

# The regression this exists for: journalctl prints nothing and exits 0 when it
# cannot open the journal, and fc-cache may not run at all. Every verdict that
# used to come out of these as PASS must now be UNVERIFIED.
set_new dead
stub dead journalctl 'exit 1'
stub dead fc-cache 'echo "fc-cache: cannot open cache" >&2; exit 1'
run dead
has "UNVERIFIED  no plasmashell crash-loop in last 10 min" \
  "an unreadable journal is UNVERIFIED, not PASS"
has "UNVERIFIED  no fs-verity digest mismatch in last 24h" \
  "an unreadable kernel log is UNVERIFIED, not PASS"
has "UNVERIFIED  no invalid fontconfig caches" \
  "an fc-cache that could not run is UNVERIFIED, not PASS"
lacks "PASS  no plasmashell crash-loop" \
  "an unreadable journal never prints PASS"
lacks "PASS  no fs-verity digest mismatch" \
  "an unreadable kernel log never prints PASS"

echo "--- result ---"
if [ "$fails" -eq 0 ]; then
  echo "test-verify: ALL PASS"
  exit 0
fi
echo "test-verify: $fails FAILURE(S)"
exit 1
