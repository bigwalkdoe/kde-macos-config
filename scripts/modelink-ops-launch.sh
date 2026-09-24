#!/usr/bin/env bash
# kde-macos-config -- scripts/modelink-ops-launch.sh
# Dock launcher for arcaden-labs/modelink-ops (a vite dev app, not an installed
# binary). If the dev server is already up, just focus the browser; otherwise
# start `npm run dev` detached, wait for the port, then open the app.
#
# The .desktop entry referencing this script is written by apply.sh (user-level,
# ~/.local/share/applications/modelink-ops.desktop) so the dock icon stays in
# sync with wherever this repo lives on the current machine.
set -u
REPO="${MODELINK_OPS_DIR:-$HOME/dev/github/arcaden-labs/modelink-ops}"
PORT="${MODELINK_OPS_PORT:-3001}"
URL="http://localhost:$PORT"
LOG="$HOME/.local/share/modelink-ops.log"

mkdir -p "$(dirname "$LOG")"

up() { curl -sf -o /dev/null "http://localhost:$PORT" 2>/dev/null; }

start_server() {
  if [ ! -f "$REPO/package.json" ]; then
    echo "modelink-ops not found at $REPO" >&2
    exit 1
  fi
  echo "starting vite dev server ($REPO, :$PORT) -> $LOG"
  ( cd "$REPO" && setsid nohup npm run dev >"$LOG" 2>&1 & )
  for i in $(seq 1 40); do
    up && return 0
    sleep 1
  done
  echo "dev server did not come up within 40s; see $LOG" >&2
  exit 1
}

if ! up; then start_server; fi
xdg-open "$URL" >/dev/null 2>&1 || true