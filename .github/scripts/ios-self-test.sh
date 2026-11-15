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
# The first launch on a freshly booted CI Simulator can take minutes, so allow 5 minutes and one
# more launch. `script` gives simctl a terminal, so its output reaches the file line by line.
launch_once() {
  : > "$OUT"
  SIMCTL_CHILD_PUBLIK_SELF_TEST=1 SIMCTL_CHILD_DO_NOT_TRACK=1 \
    perl -e 'alarm 300; exec @ARGV' script -q -t 0 "$OUT" xcrun simctl launch --console-pty "$UDID" app.noscroll > /dev/null 2>&1 || true
  grep -a -o 'publik self-test: [^[:cntrl:]]*' "$OUT" | head -n 1 || true
}
START=$(date +%s)
LINE=$(launch_once)
if [ -z "$LINE" ]; then
  echo "No self-test line after $(( $(date +%s) - START )) s. Output of the first launch:"
  cat -v "$OUT" | tail -n 20
  echo "Is the app still running?"
  xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -i noscroll || echo "no app.noscroll process"
  xcrun simctl terminate "$UDID" app.noscroll 2>/dev/null || true
  echo "Launching again."
  LINE=$(launch_once)
fi
echo "${LINE:-no self-test line from the app} ($(( $(date +%s) - START )) s)"
case "$LINE" in
  "publik self-test: ok noscroll "*) xcrun simctl shutdown "$UDID" || true; exit 0 ;;
esac
echo "--- app output ---"; cat -v "$OUT" | tail -n 40
echo "--- crash reports ---"
ls -t "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -i noscroll | head -n 2 | while read -r f; do
  head -n 80 "$HOME/Library/Logs/DiagnosticReports/$f"
done
xcrun simctl shutdown "$UDID" || true
exit 1
