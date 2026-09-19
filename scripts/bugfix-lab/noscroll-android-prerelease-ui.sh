#!/usr/bin/env bash
# bugfix-lab oracle body — cluster
# noscroll-android-prerelease-ui-missing-not-documented
#
# Runs on a CI host with a BOOTED Android emulator (adb on PATH).
# It does what the reporter did: build the app from the ref the install
# guide pins, install it on an Android device, OPEN IT, and look at what is
# on the first screen. No source is inspected.
#
# Prints BUGFIX_LAB_PRESENT (exit 1) or BUGFIX_LAB_ABSENT (exit 0).
set -uo pipefail

SRC="${1:?usage: $0 <src-checkout-dir>}"
OUT="${2:-$PWD/bugfix-lab-out}"
mkdir -p "$OUT"

echo "== src: $SRC"
( cd "$SRC" && git log -1 --format='HEAD %H %ci %s' ) || true

# ---------------------------------------------------------------- build ----
# Mirrors the install guide's build steps (engine deps -> sync engine into
# the Android project -> Android build), which is what a guide reader runs.
set -e
( cd "$SRC" && pnpm install --dir engine )
if [ -f "$SRC/tools/sync-engine.mjs" ]; then
  ( cd "$SRC" && node tools/sync-engine.mjs )
elif [ -f "$SRC/tools/sync-engine.sh" ]; then
  ( cd "$SRC" && bash tools/sync-engine.sh )
fi
( cd "$SRC/android" && ./gradlew --no-daemon :app:assembleDebug )
set +e

APK="$(find "$SRC/android/app/build/outputs/apk" -name '*.apk' | head -1)"
echo "== apk: $APK"
[ -n "$APK" ] || { echo "ORACLE COULD NOT RUN: no apk built"; exit 2; }

# -------------------------------------------------------------- install ----
adb wait-for-device
adb shell input keyevent 82 >/dev/null 2>&1
adb uninstall app.noscroll >/dev/null 2>&1
adb install -r "$APK" || { echo "ORACLE COULD NOT RUN: adb install failed"; exit 2; }

# ----------------------------------------------------------------- open ----
adb shell am start -W -n app.noscroll/.MainActivity
sleep 20

DUMP="$OUT/ui.xml"
for i in 1 2 3 4 5 6; do
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml "$DUMP" >/dev/null 2>&1
  if [ -s "$DUMP" ] && grep -q 'app.noscroll' "$DUMP"; then break; fi
  echo "   (ui dump attempt $i not ready, retrying)"
  sleep 8
done

adb exec-out screencap -p > "$OUT/first-screen.png" 2>/dev/null
echo "== window focus:"
adb shell dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -4
echo "== logcat (app tag lines, tail):"
adb logcat -d -t 200 2>/dev/null | grep -iE 'noscroll|chromium.*instagram' | tail -15

[ -s "$DUMP" ] || { echo "ORACLE COULD NOT RUN: empty uiautomator dump"; exit 2; }
echo "== ui dump bytes: $(wc -c < "$DUMP")"

# -------------------------------------------------------------- observe ----
python3 - "$DUMP" > "$OUT/ui-report.txt" <<'PY'
import sys, xml.etree.ElementTree as ET
tree = ET.parse(sys.argv[1]); root = tree.getroot()
buttons, blank, webviews, texts = [], [], 0, []
for n in root.iter('node'):
    pkg = n.get('package','' ); cls = n.get('class','')
    if pkg != 'app.noscroll':
        continue
    if 'WebView' in cls:
        webviews += 1
    t = (n.get('text') or '').strip()
    d = (n.get('content-desc') or '').strip()
    label = t or d
    if cls.endswith('Button') or (n.get('clickable') == 'true' and 'WebView' not in cls and 'View' != cls.split('.')[-1]):
        (buttons if label else blank).append((cls, label, n.get('bounds')))
    if label:
        texts.append((cls, label))
print("app_webviews=%d" % webviews)
print("app_labelled_controls=%d" % len(buttons))
print("app_blank_controls=%d" % len(blank))
for c,l,b in buttons: print("  CONTROL", c, repr(l), b)
for c,l,b in blank:   print("  BLANK-CONTROL", c, b)
for c,l in texts[:40]: print("  TEXT", c, repr(l))
PY
cat "$OUT/ui-report.txt"
CONTROLS="$(grep -m1 '^app_labelled_controls=' "$OUT/ui-report.txt" | cut -d= -f2)"
CONTROLS="${CONTROLS:-0}"

# ------------------------------------------------------ served guide text --
# The other half of the report: nothing the reader is SERVED said this was
# expected. Read what publikhq.com serves today (the live guide a reader
# follows, and the live app page), not a local file.
DOCS=0
GUIDE_JSON="$OUT/live-guide.json"
if curl -fsS 'https://publikhq.com/api/iris/guides/noscroll' -o "$GUIDE_JSON"; then
  DOCS="$(python3 - "$GUIDE_JSON" <<'PY'
import json,sys,re
d=json.load(open(sys.argv[1]))
ok=0
for b in d.get('branches',[]):
    if b.get('target')=='android':
        for s in (b.get('steps') or []):
            body=((s.get('title') or '')+' '+(s.get('body') or '')).lower()
            if re.search(r'simple wrapper|no five-tab|does not have (this |the )?(five-tab|ui)|wrapper is correct', body):
                ok=1
print(ok)
PY
)"
  echo "== live guide version: $(python3 -c "import json,sys;print(json.load(open('$GUIDE_JSON'))['version'], json.load(open('$GUIDE_JSON'))['sourceCommit'])")"
else
  echo "   (could not fetch live guide; docs signal unavailable)"
fi
echo "served_guide_sets_expectation=$DOCS"

echo
if [ "$CONTROLS" -eq 0 ] || [ "$DOCS" -eq 0 ]; then
  echo "BUGFIX_LAB_PRESENT — first screen after opening NoScroll exposes $CONTROLS labelled control(s) besides the web view; served-guide-sets-expectation=$DOCS"
  exit 1
fi
echo "BUGFIX_LAB_ABSENT — first screen exposes $CONTROLS labelled control(s) (service switch / status) and the served guide states the wrapper is the expected result"
exit 0
