#!/usr/bin/env bash
# BEHAVIOURAL oracle for noscroll-android-blocking-not-active.
#
# The reporter's words are "Tried changing settings, restarting phone, pairing
# the phone again, nothing is blocked." So this script does not look at the
# app's preferences file at all. It performs the user-visible act -- OPEN A
# SHIELDED APP -- and asks the only question the reporter asked: did anything
# get blocked?
#
# Fixture: a code-free stub APK whose package name is com.instagram.android
# (one of NoScroll's DEFAULT_TARGETS). The real Instagram is not installable on
# a CI emulator; the accessibility service only ever reads the foreground
# package NAME (see ForegroundAppMonitor.kt), so a stub with that package name
# is indistinguishable from the real thing at the layer under test.
#
# PRESENT (exit 1) = the shielded app stays in the foreground: nothing blocked.
# ABSENT  (exit 0) = NoScroll's ShieldActivity takes the foreground.
# exit 2          = the harness itself could not run (no emulator, stub install
#                   failed, could not grant the accessibility permission).
set -uo pipefail

PKG="app.noscroll"
APK="android/app/build/outputs/apk/debug/app-debug.apk"
STUB_APK="${GITHUB_WORKSPACE:-$PWD}/stub-ig.apk"
STUB_PKG="com.instagram.android"
A11Y_SERVICE="${PKG}/app.noscroll.shield.ForegroundAppMonitor"

# The rendered publik install guide this reader is following. Regenerate with
#   cd <publik worktree> && npx tsx ~/bugfix-lab/bin/render-guide.mts noscroll android --json
# and commit the output verbatim, so this file is always the guide's real
# user-visible content and never a hand-written paraphrase of it.
GUIDE_JSON="${NOSCROLL_GUIDE_JSON:-scripts/bugfix-lab/rendered-guide-android.json}"
A11Y_MODE="${NOSCROLL_A11Y:-grant}"
RESTART_MODE="${NOSCROLL_RESTART:-force-stop}"
# Round 1/2 flag names, still honoured so their runs stay reproducible.
[ "${NOSCROLL_SKIP_A11Y_GRANT:-0}" = "1" ] && A11Y_MODE="skip"
[ "${NOSCROLL_SKIP_RESTART:-0}" = "1" ] && RESTART_MODE="none"
echo "harness config: A11Y=$A11Y_MODE RESTART=$RESTART_MODE GUIDE_JSON=$GUIDE_JSON"

fail_harness() { echo "HARNESS_ERROR: $*"; echo "BUGFIX_LAB_UNRUNNABLE"; exit 2; }

echo "=== devices ==="
adb devices -l
adb wait-for-device || fail_harness "no device"
echo "sdk level: $(adb shell getprop ro.build.version.sdk | tr -d '\r')"

echo "=== install NoScroll (the build a guide-installer gets) ==="
adb install -r "$APK" || fail_harness "could not install $APK"

echo "=== install the shielded-app fixture ($STUB_PKG) ==="
adb install -r "$STUB_APK" || fail_harness "could not install stub $STUB_APK"

echo "=== step 1: first launch (what the install guide ends with) ==="
adb shell am start -W -n "${PKG}/.MainActivity"
sleep 6

# ---------------------------------------------------------------------------
# What the simulated reader does about the Accessibility permission.
#
#   NOSCROLL_A11Y=guide   read the rendered publik install guide committed at
#                         $GUIDE_JSON and do what IT says: if a step tells the
#                         reader to turn NoScroll's accessibility service on,
#                         the reader turns it on; if no step does, the reader
#                         never does, because nothing ever told them it
#                         existed. This is the guide-installer path and it is
#                         the only one whose behaviour depends on the guide.
#   NOSCROLL_A11Y=grant   grant it unconditionally (the generous control that
#                         isolates guide text from app code).
#   NOSCROLL_A11Y=skip    never grant it (frozen negative control).
#
# The reader's physical act -- flipping NoScroll's switch in Settings >
# Accessibility -- is modelled by writing the two secure settings that switch
# sets, because CI cannot reliably tap a toggle in the Settings UI. The screen
# the guide step actually sends them to is opened first, so the path is the
# one the step names, and everything after this point is ordinary emulator
# behaviour.
grant_the_permission() {
  adb shell settings put secure enabled_accessibility_services "$A11Y_SERVICE"
  adb shell settings put secure accessibility_enabled 1
  sleep 3
  ENABLED_RAW="$(adb shell settings get secure enabled_accessibility_services | tr -d '\r')"
  echo "enabled_accessibility_services = $ENABLED_RAW"
  echo "accessibility_enabled = $(adb shell settings get secure accessibility_enabled | tr -d '\r')"
  case "$ENABLED_RAW" in
    *ForegroundAppMonitor*) : ;;
    *) fail_harness "accessibility permission did not stick" ;;
  esac
}

case "$A11Y_MODE" in
  guide)
    [ -f "$GUIDE_JSON" ] || fail_harness "rendered guide $GUIDE_JSON is missing"
    echo "=== step 2: what does the guide this reader is following tell them to do? ==="
    GUIDE_OUT="$(python3 scripts/bugfix-lab/guide-reader.py "$GUIDE_JSON")" \
      || fail_harness "could not read $GUIDE_JSON"
    echo "$GUIDE_OUT"
    A11Y_STEP="$(printf '%s\n' "$GUIDE_OUT" | sed -n 's/^A11Y_STEP: //p')"
    if [ -n "$A11Y_STEP" ] && [ "$A11Y_STEP" != "NONE" ]; then
      echo "=== step 2: guide step $A11Y_STEP tells the reader to turn the service on -- the reader does ==="
      adb shell am start -a android.settings.ACCESSIBILITY_SETTINGS >/dev/null 2>&1 || true
      sleep 3
      grant_the_permission
      adb shell input keyevent KEYCODE_HOME
      sleep 2
    else
      echo "=== step 2: SKIPPED -- no step in this guide tells the reader to turn the service on ==="
      echo "enabled_accessibility_services = $(adb shell settings get secure enabled_accessibility_services | tr -d '\r')"
    fi
    ;;
  skip)
    echo "=== step 2: SKIPPED -- this mode never grants the permission ==="
    echo "enabled_accessibility_services = $(adb shell settings get secure enabled_accessibility_services | tr -d '\r')"
    ;;
  grant)
    echo "=== step 2: pairing -- grant the accessibility permission ==="
    grant_the_permission
    ;;
  *)
    fail_harness "unknown NOSCROLL_A11Y=$A11Y_MODE"
    ;;
esac

echo "=== is the service actually bound? (dumpsys accessibility) ==="
adb shell dumpsys accessibility 2>&1 | grep -iE "noscroll|ForegroundAppMonitor|Service\[" | head -20

# ---------------------------------------------------------------------------
# "Tried ... restarting phone ..." -- the reporter's own words.
#
#   NOSCROLL_RESTART=reboot      a REAL emulator reboot (adb reboot). This is
#                                what the reporter did and it is the default
#                                for the guide-installer path.
#   NOSCROLL_RESTART=force-stop  `am force-stop` + relaunch, which is what
#                                rounds 1-2 of this cluster used. Kept so their
#                                runs stay reproducible: force-stop is NOT a
#                                reboot -- it leaves the package in the stopped
#                                state and AccessibilityManagerService does not
#                                re-bind an enabled service until something
#                                pokes it, which is a separate, still-open lead
#                                (see fix-log.md), not this cluster's bug.
#   NOSCROLL_RESTART=none        no restart at all (REGION.json's minimal repro).
case "$RESTART_MODE" in
  reboot)
    echo "=== step 3: the report's 'restarting phone' -- a real reboot of the device ==="
    adb reboot
    sleep 10
    adb wait-for-device || fail_harness "device never came back after reboot"
    BOOTED=""
    for _ in $(seq 1 60); do
      BOOTED="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      [ "$BOOTED" = "1" ] && break
      sleep 5
    done
    [ "$BOOTED" = "1" ] || fail_harness "emulator never finished booting after the reboot"
    sleep 15
    adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
    sleep 3
    echo "post-reboot enabled_accessibility_services = $(adb shell settings get secure enabled_accessibility_services | tr -d '\r')"
    echo "post-reboot accessibility bind state:"
    adb shell dumpsys accessibility 2>&1 | grep -iE "noscroll|ForegroundAppMonitor|Service\[|Bound services|Enabled services" | head -20
    adb shell am start -W -n "${PKG}/.MainActivity"
    sleep 5
    ;;
  force-stop)
    echo "=== step 3: 'restarting phone / pairing again' -- force-stop + relaunch ==="
    adb shell am force-stop "$PKG"
    sleep 2
    adb shell am start -W -n "${PKG}/.MainActivity"
    sleep 5
    ;;
  none)
    echo "=== step 3: SKIPPED (no restart) -- isolating the restart as a confound ==="
    ;;
  *)
    fail_harness "unknown NOSCROLL_RESTART=$RESTART_MODE"
    ;;
esac

echo "=== the app's own view of things (StatusActivity + prefs), informational only ==="
adb shell run-as "$PKG" cat "/data/data/${PKG}/shared_prefs/noscroll.shield.xml" 2>&1 || true

echo "=== go home, settle ==="
adb shell input keyevent KEYCODE_HOME
sleep 3

echo "=== THE TEST: open the shielded app, exactly as the reporter would ==="
adb shell am start -W -n "${STUB_PKG}/android.app.Activity" 2>&1
sleep 6

FOCUS="$(adb shell dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | tr -d '\r')"
RESUMED="$(adb shell dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|ResumedActivity' | tr -d '\r' | head -3)"
echo "--- window focus ---"
echo "$FOCUS"
echo "--- resumed activity ---"
echo "$RESUMED"

echo "--- second attempt (debounce is 800ms; a real user taps the icon again) ---"
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am start -W -n "${STUB_PKG}/android.app.Activity" >/dev/null 2>&1
sleep 6
FOCUS2="$(adb shell dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | tr -d '\r')"
echo "$FOCUS2"

echo "--- logcat (noscroll / activity-start denials) ---"
adb logcat -d 2>/dev/null | grep -iE "noscroll|Background activity start|BAL|ActivityTaskManager: START" | tail -40

adb shell screencap -p /sdcard/shield-check.png 2>/dev/null && adb pull /sdcard/shield-check.png "${GITHUB_WORKSPACE:-$PWD}/shield-check.png" 2>/dev/null || true

BLOCKED=0
echo "$FOCUS $FOCUS2 $RESUMED" | grep -q "ShieldActivity" && BLOCKED=1

echo "=== verdict ==="
echo "shielded app launched: $STUB_PKG"
echo "NoScroll ShieldActivity took the foreground: $BLOCKED"

if [ "$BLOCKED" = "1" ]; then
  echo "BUGFIX_LAB_ABSENT"
  exit 0
else
  echo "the shielded app stayed in the foreground -- nothing was blocked"
  echo "BUGFIX_LAB_PRESENT"
  exit 1
fi
