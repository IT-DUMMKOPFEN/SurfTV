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
adb shell input keyevent 4      # close info window
sleep 3
shot classic_phone
adb shell input keyevent 131    # F1 -> TV like
sleep 4
shot tv_phone

# Landscape "TV" screen: 1280x720
adb shell wm size 1280x720
adb shell wm density 160
adb shell am force-stop $PKG
sleep 2
adb shell am start -W -n $PKG/.MainActivity
sleep 20
adb shell input keyevent 4      # close info window
sleep 3
shot tv_wide
adb shell input keyevent 19     # arrow up -> first channel plays
sleep 15
shot tv_playing
adb shell input swipe 640 650 640 150 600   # scroll down to the categories
sleep 3
shot tv_rows
adb shell input tap 407 54      # Discover
sleep 4
shot tv_discover
adb shell input tap 800 54      # Categories
sleep 4
shot tv_categories
adb shell input keyevent 131    # F1 -> Classic
sleep 4
shot classic_wide

echo "===== PROCESS ====="
adb shell pidof $PKG || echo "PROCESS NOT RUNNING"
echo "===== APP LOG ====="
adb logcat -d -v brief | grep -iE "flutter|surftv|AndroidRuntime|FATAL" | tail -n 80
exit 0
