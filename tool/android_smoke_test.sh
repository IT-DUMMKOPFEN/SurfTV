#!/usr/bin/env bash
# Starts SurfTV in an Android emulator, takes screenshots and prints them
# as base64 (between SHOT markers) plus the app log. Used by CI.
# Note: the CI emulator does not pass key events (F1 etc.) to the app
# reliably, so everything is done with taps.
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

# Landscape "TV" screen: 1280x720
adb shell wm size 1280x720
adb shell wm density 160
adb shell am start -W -n $PKG/.MainActivity
sleep 30
adb shell input keyevent 4      # close info window
sleep 3
shot classic_wide
adb shell input tap 1226 40     # "TV like" switch on the remote
sleep 5
shot tv_wide
adb shell input tap 408 54      # Discover
sleep 5
shot tv_discover
adb shell input tap 130 430     # first channel tile
sleep 15
shot tv_discover_play
adb shell input tap 518 54      # Live TV
sleep 5
shot tv_live
adb shell input swipe 640 650 640 150 600   # scroll down to the categories
sleep 4
shot tv_rows
adb shell input tap 800 54      # Categories
sleep 5
shot tv_categories

# Phone (portrait) - TV like is remembered
adb shell wm size reset
adb shell wm density reset
adb shell am force-stop $PKG
sleep 2
adb shell am start -W -n $PKG/.MainActivity
sleep 30
adb shell input keyevent 4
sleep 3
shot tv_phone

echo "===== PROCESS ====="
adb shell pidof $PKG || echo "PROCESS NOT RUNNING"
echo "===== APP LOG ====="
adb logcat -d -v time | grep -iE "flutter|AndroidRuntime|FATAL" | tail -n 60
echo "===== SYSTEM LOG ====="
adb logcat -d -v time | grep -iE "surftv|lowmemory|lmkd|has died|Fatal signal|DEBUG|ANR in|crash|backtrace|libmpv|SIGSEGV|SIGABRT" | tail -n 120
exit 0
