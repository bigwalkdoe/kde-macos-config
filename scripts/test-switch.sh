#!/usr/bin/env bash
# Tests for switch.sh's manual override of the scheduled dark/light switch.
#
# The override is the one piece of switch.sh that fights something: --auto runs
# from a systemd timer every 15 min, so a pin that is not honoured on the next
# tick is a pin that silently reverts within a quarter of an hour. That failure
# is invisible on a healthy desktop and only shows up as "it changed back on its
# own", which is exactly the bug a test has to be able to catch.
#
# switch.sh resolves its own ROOT from the script path and calls $ROOT/apply.sh,
# so running the real file in place would restart plasmashell on a real session.
# Instead it is symlinked into a scratch repo beside a stub apply.sh: bash reads
# the symlink's target, so the code under test is the real switch.sh, and the
# stub marks the process boundary. Nothing here needs Plasma, so it runs in CI.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
ok(){ printf 'ok   %s\n' "$1"; }
no(){ printf 'FAIL %s\n       %s\n' "$1" "$2"; fails=$((fails + 1)); }

REPO="$WORK/repo"; HOME_DIR="$WORK/home"; CONF="$HOME_DIR/.config/kde-macos/switch.conf"
mkdir -p "$REPO" "$HOME_DIR/.config/kde-macos"
ln -s "$ROOT/switch.sh" "$REPO/switch.sh"

# Stubs. kreadconfig6 reports the currently applied icon theme, which is how
# switch.sh reads the current mode. date is pinned to 12:00 so the schedule
# resolves deterministically regardless of when the test runs.
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/kreadconfig6" <<'EOF'
#!/bin/sh
case "$*" in
  *"--group Icons"*)        echo "${ICON_THEME:-FairyWren_Light}" ;;
  *LookAndFeelPackage*)    echo "com.github.vinceliuice.Orchis" ;;
esac
EOF
cat > "$BIN/date" <<'EOF'
#!/bin/sh
case "$1" in
  +%H%M) echo 1200 ;;
  *)     echo 2026-01-01T12:00:00 ;;
esac
EOF
cat > "$REPO/apply.sh" <<'EOF'
#!/bin/sh
echo "STUB-APPLY $1"
exit 0
EOF
chmod +x "$BIN/kreadconfig6" "$BIN/date" "$REPO/apply.sh"

# write_conf <lines...>: seed switch.conf. Passing nothing removes it, which is
# how "a machine that never ran --install" is set up.
write_conf(){
  if [ "$#" -eq 0 ]; then rm -f "$CONF"; else printf '%s\n' "$@" > "$CONF"; fi
}

OUT=''; RC=0
run(){ OUT="$(PATH="$BIN:$PATH" HOME="$HOME_DIR" bash "$REPO/switch.sh" "$@" 2>&1)"; RC=$?; }
has(){ case "$OUT" in *"$1"*) ok "$2" ;; *) no "$2" "no line matching: $1
--- got ---
$OUT" ;; esac; }
lacks(){ case "$OUT" in *"$1"*) no "$2" "unexpected line: $1" ;; *) ok "$2" ;; esac; }
rc_is(){ [ "$RC" -eq "$1" ] && ok "$2" || no "$2" "expected exit $1, got $RC
--- got ---
$OUT"; }
# conf_has/conf_lacks: assert on what the run left behind in switch.conf.
conf_has(){ grep -q "^$1" "$CONF" && ok "$2" || no "$2" "switch.conf lacks: $1"; }
conf_lacks(){ grep -q "^$1" "$CONF" && no "$2" "switch.conf still has: $1" || ok "$2"; }

echo "=== test-switch: manual override of the schedule ==="

# At 12:00 with a 13:00-23:00 window the schedule wants dark. The stub reports
# light as the current mode, so an unpinned --auto has a real change to make.
SCHEDULE=(SUNRISE=13:00 SUNSET=23:00)

# --- the override is reported, so "nothing is happening" is explainable ------

write_conf "${SCHEDULE[@]}" "OVERRIDE=dark"
run --check
has "override=dark" "--check reports a pinned override"

write_conf "${SCHEDULE[@]}" "OVERRIDE="
run --check
has "override=none" "--check reports no override as none"

# --- a pin actually stops the timer ------------------------------------------
#
# The positive control comes first: with the same stubbed clock and mode, an
# unpinned --auto must apply. Without it, the test below would also pass if
# --auto had simply stopped working.
write_conf "${SCHEDULE[@]}" "OVERRIDE="
run --auto
has "STUB-APPLY --dark" "unpinned --auto still applies the scheduled mode"

write_conf "${SCHEDULE[@]}" "OVERRIDE=dark"
run --auto
lacks "STUB-APPLY" "a pinned --auto does not apply over the pin"
has "override=dark" "a pinned --auto says which pin is holding it"
has "follow-schedule" "a pinned --auto says how to clear the pin"
rc_is 0 "a pinned --auto is a successful no-op, not a failure"

# --- setting and clearing the pin --------------------------------------------

write_conf "${SCHEDULE[@]}" "OVERRIDE="
run --dark
has "STUB-APPLY --dark" "--dark applies the mode"
conf_has "OVERRIDE=dark" "--dark pins the mode"
conf_has "SUNRISE=13:00" "--dark leaves the sunrise alone"
conf_has "SUNSET=23:00" "--dark leaves the sunset alone"

write_conf "${SCHEDULE[@]}" "OVERRIDE=dark"
run --follow-schedule
rc_is 0 "--follow-schedule succeeds"
conf_lacks "OVERRIDE=dark" "--follow-schedule clears the pin"
conf_has "SUNRISE=13:00" "--follow-schedule leaves the sunrise alone"

# Clearing a pin that is not set is not an error: it is how you get back to the
# default state without having to know which state you were in.
write_conf "${SCHEDULE[@]}" "OVERRIDE="
run --follow-schedule
rc_is 0 "--follow-schedule on an already-clear pin succeeds"

# --- the pin survives, and does not eat the rest of the file -----------------
#
# switch.conf is sourced, so a pin is worthless if it does not outlive the
# session, and unacceptable if setting it tramples the hand-edited values and
# comments next to it.
write_conf "# my times, keep them" "${SCHEDULE[@]}" "OVERRIDE=light"
run --dark
conf_has "# my times, keep them" "setting the pin preserves comments in switch.conf"
conf_has "SUNRISE=13:00" "setting the pin preserves hand-edited times"
[ "$(grep -c '^OVERRIDE=' "$CONF")" -eq 1 ] \
  && ok "setting the pin leaves exactly one OVERRIDE line" \
  || no "setting the pin leaves exactly one OVERRIDE line" "found $(grep -c '^OVERRIDE=' "$CONF")"

# A machine that never ran --install has no switch.conf at all. The pin still
# has to be recorded, or it would be forgotten at the next reboot.
rm -f "$CONF"
run --light
conf_has "OVERRIDE=light" "--light pins the mode when switch.conf does not exist yet"
conf_has "SUNRISE=" "--light creates switch.conf with a sunrise default"
conf_has "SUNSET=" "--light creates switch.conf with a sunset default"

# --- a typo is loud, not silent ----------------------------------------------
#
# A silent acceptance here is the worst outcome available: the switcher would
# stop switching forever with nothing in the log but an ordinary-looking run.
write_conf "${SCHEDULE[@]}" "OVERRIDE=blue"
run --auto
rc_is 1 "an invalid override fails the run"
has "OVERRIDE" "an invalid override names the offending key"
lacks "STUB-APPLY" "an invalid override applies nothing"

echo "--- result ---"
if [ "$fails" -eq 0 ]; then
  echo "test-switch: ALL PASS"
  exit 0
fi
echo "test-switch: $fails FAILURE(S)"
exit 1