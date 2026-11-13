#!/usr/bin/env bash
# Runs the built Simulator app once with PUBLIK_SELF_TEST=1 and checks the one line it prints:
# "publik self-test: ok noscroll <version>" (publikhq.com/skills/setup.md, step 6).
set -euo pipefail
APP="$1"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if ".iOS-" not in runtime:
        continue
    for d in devices[runtime]:
        if d["name"].startswith("iPhone"):
            print(d["udid"])
            sys.exit(0)
sys.exit(1)
')
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

OUT=$(mktemp)
SIMCTL_CHILD_PUBLIK_SELF_TEST=1 SIMCTL_CHILD_DO_NOT_TRACK=1 \
  perl -e 'alarm 180; exec @ARGV' xcrun simctl launch --console-pty "$UDID" app.noscroll > "$OUT" 2>&1 || true
LINE=$(grep -o 'publik self-test: [^[:cntrl:]]*' "$OUT" | head -n 1 || true)
echo "${LINE:-no self-test line from the app}"
xcrun simctl shutdown "$UDID" || true
case "$LINE" in
  "publik self-test: ok noscroll "*) exit 0 ;;
  *) echo "--- app output ---"; cat "$OUT"; exit 1 ;;
esac
