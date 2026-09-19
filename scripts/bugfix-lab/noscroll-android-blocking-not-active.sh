#!/usr/bin/env bash
# Runs inside reactivecircus/android-emulator-runner once the emulator is
# booted and `adb` is already targeting it.
#
# Reproduces exactly what the reporter describes: complete a fresh install,
# pair (grant the accessibility permission), then check whether anything is
# actually marked as shielded. This is a behavioural check against the
# app's own persisted SharedPreferences store, not a source grep.
set -uo pipefail

PKG="app.noscroll"
APK="android/app/build/outputs/apk/debug/app-debug.apk"
PREFS_PATH="/data/data/${PKG}/shared_prefs/noscroll.shield.xml"
A11Y_SERVICE="${PKG}/app.noscroll.shield.ForegroundAppMonitor"

echo "=== adb devices ==="
adb devices -l

echo "=== installing ${APK} ==="
adb install -r "$APK"

echo "=== first launch (fresh install => this is what onCreate does on install #1) ==="
adb shell am start -W -n "${PKG}/.MainActivity"
sleep 6

echo "=== pairing: grant the accessibility permission the way onboarding does ==="
adb shell settings put secure enabled_accessibility_services "$A11Y_SERVICE"
adb shell settings put secure accessibility_enabled 1
sleep 2
echo "enabled_accessibility_services now: $(adb shell settings get secure enabled_accessibility_services)"

echo "=== restart-and-repair simulation: force-stop and relaunch, same as the report describes ==="
adb shell am force-stop "$PKG"
sleep 1
adb shell am start -W -n "${PKG}/.MainActivity"
sleep 4

echo "=== reading the app's persisted shield-list store ==="
PREFS_OUT="$(adb shell run-as "$PKG" cat "$PREFS_PATH" 2>&1)"
echo "$PREFS_OUT"

echo "=== StatusActivity reachability check (present on the fixed build only; informational) ==="
adb shell am start -W -n "${PKG}/.shield.StatusActivity" 2>&1 || echo "(StatusActivity not launchable on this build)"
sleep 1

HAS_IG=0
HAS_YT=0
echo "$PREFS_OUT" | grep -q "com.instagram.android" && HAS_IG=1
echo "$PREFS_OUT" | grep -q "com.google.android.youtube" && HAS_YT=1

echo "=== verdict ==="
echo "shield list contains com.instagram.android: $HAS_IG"
echo "shield list contains com.google.android.youtube: $HAS_YT"

if [ "$HAS_IG" = "1" ] && [ "$HAS_YT" = "1" ]; then
  echo "BUGFIX_LAB_ABSENT"
  exit 0
else
  echo "BUGFIX_LAB_PRESENT"
  exit 1
fi
