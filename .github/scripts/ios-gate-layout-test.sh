#!/usr/bin/env bash
# Blind-test bug: right after the sign-in in the in-app browser, the first onboarding screen had no
# safe area (its title was under the Dynamic Island). This runs the built Simulator app (a test build
# with PUBLIK_TEST_HOOKS) against a fake publik on this runner (fake-publik.py):
#   1. the gate presses "Sign in with publik" by itself (PUBLIK_TEST_PRESS=sign_in);
#   2. the in-app browser opens the fake claim page, and the gate sees the sign-in and passes;
#   3. the first onboarding screen prints its layout and the app exits (PUBLIK_LAYOUT_PROBE=1):
#      "noscroll-layout: onboarding view-safe-top=<pt> window-safe-top=<pt> title-y=<pt>".
# Pass: view-safe-top > 0, window-safe-top > 0, and title-y >= window-safe-top.
set -euo pipefail
APP="$1"
HERE=$(cd "$(dirname "$0")" && pwd)
PORT=8787

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if ".iOS-" not in runtime:
        continue
    for d in devices[runtime]:
        if d["name"].startswith("iPhone"):
            print(d["udid"], d["name"])
            sys.exit(0)
sys.exit(1)
')
NAME=${UDID#* }; UDID=${UDID%% *}
echo "Simulator: $NAME"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

OUT=$(mktemp)
LOG=$(mktemp)
SERVER=""
stop_server() { if [ -n "$SERVER" ]; then kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true; SERVER=""; fi; }
start_server() { # a fresh fake publik each time: nobody is signed in
  stop_server
  python3 "$HERE/fake-publik.py" "$PORT" > "$LOG" 2>&1 &
  SERVER=$!
  for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/health" && return 0; sleep 0.2; done
  echo "::error::The fake publik did not start."; cat "$LOG"; exit 1
}
trap stop_server EXIT

launch_once() { # a fresh install each time; prints only the layout line
  {
    xcrun simctl terminate "$UDID" app.noscroll || true
    xcrun simctl uninstall "$UDID" app.noscroll || true
    xcrun simctl install "$UDID" "$APP"
  } > /dev/null 2>&1
  echo "Installed after $(( $(date +%s) - START )) s." >&2
  : > "$OUT"
  SIMCTL_CHILD_PUBLIK_API_BASE_URL="http://127.0.0.1:$PORT/api/v1" \
  SIMCTL_CHILD_PUBLIK_APP_TOKEN="pat_ci_fake" \
  SIMCTL_CHILD_PUBLIK_TEST_PRESS=sign_in \
  SIMCTL_CHILD_PUBLIK_LAYOUT_PROBE=1 \
  SIMCTL_CHILD_DO_NOT_TRACK=1 \
    perl -e 'alarm 300; exec @ARGV' script -q -t 0 "$OUT" xcrun simctl launch --console-pty "$UDID" app.noscroll < /dev/null > /dev/null 2>&1 &
  local pid=$! line="" i
  # Stop as soon as the line is there: the console of a finished app does not always close at once.
  for i in $(seq 1 300); do
    line=$(grep -a -o 'noscroll-layout: [^[:cntrl:]]*' "$OUT" | head -n 1 || true)
    [ -n "$line" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  xcrun simctl terminate "$UDID" app.noscroll > /dev/null 2>&1 || true
  [ -n "$line" ] || line=$(grep -a -o 'noscroll-layout: [^[:cntrl:]]*' "$OUT" | head -n 1 || true)
  printf '%s\n' "$line"
}

START=$(date +%s)
start_server
LINE=$(launch_once)
if [ -z "$LINE" ]; then
  echo "No layout line after $(( $(date +%s) - START )) s. App output:"; cat -v "$OUT" | tail -n 20
  echo "Fake publik:"; tail -n 20 "$LOG"
  echo "Launching again."
  start_server
  LINE=$(launch_once)
fi
stop_server
echo "${LINE:-no layout line from the app} ($(( $(date +%s) - START )) s)"
echo "--- fake publik (requests) ---"
grep -a -E 'claim page|signed in anyway|"(GET|POST) ' "$LOG" | sed -E 's/pk_[A-Za-z0-9]+/pk_.../g' | tail -n 20 || true
xcrun simctl shutdown "$UDID" || true

num() { printf '%s' "$LINE" | sed -n "s/.*$1=\(-\{0,1\}[0-9][0-9]*\).*/\1/p"; }
VIEW=$(num view-safe-top); WINDOW=$(num window-safe-top); TITLE=$(num title-y)
if [ -z "$VIEW" ] || [ -z "$WINDOW" ] || [ -z "$TITLE" ]; then
  echo "::error::The app printed no layout line."; cat -v "$OUT" | tail -n 40; exit 1
fi
grep -q 'claim page' "$LOG" || echo "Note: the in-app browser did not load the claim page; the sheet was still open at sign-in."
if [ "$VIEW" -gt 0 ] && [ "$WINDOW" -gt 0 ] && [ "$TITLE" -ge "$WINDOW" ]; then
  echo "OK: after the sign-in, the first onboarding screen has its safe area (top $VIEW pt; title at $TITLE pt, window safe area $WINDOW pt)."
  exit 0
fi
echo "::error::After the sign-in, the first onboarding screen has no safe area: view-safe-top=$VIEW window-safe-top=$WINDOW title-y=$TITLE."
exit 1
