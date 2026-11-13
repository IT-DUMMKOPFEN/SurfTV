#!/usr/bin/env bash
# Starts SurfTV in an Android emulator, takes screenshots and prints them
# as base64 (between SHOT markers) plus the app log. Used by CI.
APK=build/app/outputs/flutter-apk/app-release.apk
PKG=de.itdummkopfen.surftv

shot() {
  adb exec-out screencap -p > /tmp/shot.png
  echo "SHOT-BEGIN $1"
  base64 -w0 /tmp/shot.png; echo
  echo "SHOT-END $1"
}

adb install -r "$APK"
adb logcat -c
adb shell am start -W -n $PKG/.MainActivity
sleep 25
shot start
adb shell wm size

# Press CH up on the remote control -> first channel plays.
SIZE=$(adb shell wm size | grep -oE "[0-9]+x[0-9]+" | tail -n1)
W=${SIZE%x*}; H=${SIZE#*x}
adb shell input tap $((W * 110 / 320)) $((H * 525 / 640))
sleep 30
shot playing

# Open the channel list drawer (top-left button).
adb shell input tap $((W * 28 / 320)) $((H * 52 / 640))
sleep 4
shot drawer

echo "===== PROCESS ====="
adb shell pidof $PKG || echo "PROCESS NOT RUNNING"
adb shell dumpsys activity processes | grep -iE "notResponding|crashing" || echo "no ANR flag"
echo "===== APP LOG ====="
adb logcat -d -v brief | grep -iE "flutter|surftv|media_kit|AndroidRuntime|FATAL" | tail -n 120
exit 0
