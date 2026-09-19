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

# NOSCROLL_SKIP_A11Y_GRANT=1 reproduces the GUIDE-INSTALLER path: the rendered
# Android guide (publik lib/guides/noscroll.ts version 8) has 14 steps and not
# one of them asks the reader to enable NoScroll in Android's Accessibility
# settings, so a reader who follows it to the end never grants this.
if [ "${NOSCROLL_SKIP_A11Y_GRANT:-0}" = "1" ]; then
  echo "=== step 2: SKIPPED -- the Android guide never tells the reader to grant it ==="
  echo "enabled_accessibility_services = $(adb shell settings get secure enabled_accessibility_services | tr -d '\r')"
else
  echo "=== step 2: pairing -- grant the accessibility permission ==="
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
fi

echo "=== is the service actually bound? (dumpsys accessibility) ==="
adb shell dumpsys accessibility 2>&1 | grep -iE "noscroll|ForegroundAppMonitor|Service\[" | head -20

# NOSCROLL_SKIP_RESTART=1 isolates the region this cluster's REGION.json
# actually scoped: MINIMIZE proved (run 35447520354, mode=guide-nostop, and
# REPRODUCE's mode=behavior-nostop run 35447028416) that the force-stop +
# relaunch below is NOT load-bearing for THIS cluster's bug -- the missing
# accessibility-permission step alone is necessary and sufficient. The
# force-stop step models a real but explicitly out-of-region, still-open
# lead (an AccessibilityService rebind gap on this emulator) that FIX round 1
# re-confirmed (run 35448517323 / 35448792058) and declined to fold into this
# guide-text region; see fix-log.md. Same gate already proven on the
# diagnostic branch fix/noscroll-android-blocking-not-active-ctl (9080c16).
if [ "${NOSCROLL_SKIP_RESTART:-0}" = "1" ]; then
  echo "=== step 3: SKIPPED (no force-stop) -- isolating the restart as a confound ==="
else
  echo "=== step 3: 'restarting phone / pairing again' -- force-stop + relaunch ==="
  adb shell am force-stop "$PKG"
  sleep 2
  adb shell am start -W -n "${PKG}/.MainActivity"
  sleep 5
fi

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
