#!/usr/bin/env bash
# Runs the built APK once with the launch argument PUBLIK_SELF_TEST=1 and checks the one line it
# writes to logcat (tag "publik"): "publik self-test: ok noscroll <version>" (publikhq.com/skills/setup.md, step 6).
set -euo pipefail
APK="$1"

adb install -r "$APK"
adb logcat -c
adb shell am start -n app.noscroll/.MainActivity --es PUBLIK_SELF_TEST 1
for _ in $(seq 1 60); do
  LINE=$(adb logcat -d -s publik:I | grep -o 'publik self-test: [^[:cntrl:]]*' | head -n 1 || true)
  if [ -n "$LINE" ]; then
    echo "$LINE"
    case "$LINE" in
      "publik self-test: ok noscroll "*) exit 0 ;;
      *) exit 1 ;;
    esac
  fi
  sleep 2
done
echo "No self-test line in 120 seconds."
adb logcat -d | tail -n 80
exit 1
