#!/usr/bin/env bash
# Starts SurfTV in an Android emulator and prints what happens (used by CI).
set -x
APK=build/app/outputs/flutter-apk/app-release.apk
PKG=de.itdummkopfen.surftv

adb install -r "$APK"
adb logcat -c
adb shell am start -W -n $PKG/.MainActivity
sleep 45

echo "===== FOCUS ====="
adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp"
echo "===== PROCESS ====="
adb shell pidof $PKG || echo "PROCESS NOT RUNNING"
echo "===== ANR ====="
adb shell dumpsys activity processes | grep -iE "notResponding|crashing" || echo "no ANR flag"
echo "===== LOGCAT (app + errors) ====="
adb logcat -d -v brief | grep -iE "flutter|surftv|media_kit|mpv|AndroidRuntime|FATAL|ANR|libc|DEBUG" | tail -n 300

# Tap the middle of the screen to see whether the UI still reacts.
adb shell input tap 540 1200
sleep 5
echo "===== AFTER TAP ====="
adb shell dumpsys window | grep -E "mCurrentFocus"
adb logcat -d -v brief | grep -iE "ANR|not responding" | tail -n 20
exit 0
