#!/usr/bin/env python3
"""
SlaxxTV - one-time platform setup.

Creates the Windows / Linux / macOS / Android project folders with
`flutter create` and patches them for streaming:
  * Android: internet permission + plain-HTTP streams allowed, name "SlaxxTV"
  * macOS:   network client entitlement, name "SlaxxTV"
  * Windows / Linux: window title "SlaxxTV"

Run from the project folder:   python3 tool/setup_platforms.py
(On Windows: py tool\\setup_platforms.py)
"""
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def run_flutter_create():
    flutter = shutil.which("flutter")
    if not flutter:
        sys.exit("Flutter not found. Install it first: https://docs.flutter.dev/get-started/install")
    subprocess.run(
        [flutter, "create", "--project-name", "surftv", "--org", "de.itdummkopfen",
         "--platforms", "windows,linux,macos,android", "."],
        cwd=ROOT, check=True, shell=(sys.platform == "win32"))
    # flutter create adds a demo test that does not fit SlaxxTV.
    demo_test = ROOT / "test" / "widget_test.dart"
    if demo_test.exists():
        demo_test.unlink()


def patch(path, func):
    p = ROOT / path
    if not p.exists():
        print(f"  skip (missing): {path}")
        return
    old = p.read_text(encoding="utf-8")
    new = func(old)
    if new != old:
        p.write_text(new, encoding="utf-8")
        print(f"  patched: {path}")
    else:
        print(f"  ok:      {path}")


def android_manifest(t):
    if "android.permission.INTERNET" not in t:
        t = t.replace("<application",
                      '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
    if "usesCleartextTraffic" not in t:
        t = t.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
    t = re.sub(r'android:label="[^"]*"', 'android:label="SlaxxTV"', t, count=1)
    return t


def mac_entitlements(t):
    if "com.apple.security.network.client" not in t:
        t = t.replace("</dict>",
                      "\t<key>com.apple.security.network.client</key>\n\t<true/>\n</dict>", 1)
    # Export / import of favorites (file dialogs).
    if "com.apple.security.files.user-selected.read-write" not in t:
        t = t.replace("</dict>",
                      "\t<key>com.apple.security.files.user-selected.read-write</key>\n\t<true/>\n</dict>", 1)
    return t


def title(t):
    # Windows uses L"surftv", Linux uses "surftv" - both end with "surftv".
    return t.replace('"surftv"', '"SlaxxTV"').replace('"SurfTV"', '"SlaxxTV"')


def binary_name(t):
    # surftv.exe -> slaxxtv.exe
    return t.replace('set(BINARY_NAME "surftv")', 'set(BINARY_NAME "slaxxtv")')


def mac_name(t):
    return re.sub(r"PRODUCT_NAME = .*", "PRODUCT_NAME = SlaxxTV", t)


def main():
    print("Running flutter create ...")
    run_flutter_create()
    print("Patching platform files ...")
    patch("android/app/src/main/AndroidManifest.xml", android_manifest)
    patch("macos/Runner/DebugProfile.entitlements", mac_entitlements)
    patch("macos/Runner/Release.entitlements", mac_entitlements)
    patch("macos/Runner/Configs/AppInfo.xcconfig", mac_name)
    patch("windows/runner/main.cpp", title)
    patch("windows/CMakeLists.txt", binary_name)
    patch("linux/CMakeLists.txt", binary_name)
    patch("linux/runner/my_application.cc", title)
    patch("linux/my_application.cc", title)
    print("\nDone. Now run:  flutter pub get   and then   flutter run")


if __name__ == "__main__":
    main()
