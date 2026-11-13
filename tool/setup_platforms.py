#!/usr/bin/env python3
"""
SurfTV - one-time platform setup.

Creates the Windows / Linux / macOS / Android project folders with
`flutter create` and patches them for streaming:
  * Android: internet permission + plain-HTTP streams allowed, name "SurfTV"
  * macOS:   network client entitlement, name "SurfTV"
  * Windows / Linux: window title "SurfTV"

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
    # flutter create adds a demo test that does not fit SurfTV.
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
    t = re.sub(r'android:label="[^"]*"', 'android:label="SurfTV"', t, count=1)
    return t


def mac_entitlements(t):
    if "com.apple.security.network.client" in t:
        return t
    return t.replace("</dict>",
                     "\t<key>com.apple.security.network.client</key>\n\t<true/>\n</dict>", 1)


def title(t):
    # Windows uses L"surftv", Linux uses "surftv" - both end with "surftv".
    return t.replace('"surftv"', '"SurfTV"')


def mac_name(t):
    return re.sub(r"PRODUCT_NAME = .*", "PRODUCT_NAME = SurfTV", t)


def main():
    print("Running flutter create ...")
    run_flutter_create()
    print("Patching platform files ...")
    patch("android/app/src/main/AndroidManifest.xml", android_manifest)
    patch("macos/Runner/DebugProfile.entitlements", mac_entitlements)
    patch("macos/Runner/Release.entitlements", mac_entitlements)
    patch("macos/Runner/Configs/AppInfo.xcconfig", mac_name)
    patch("windows/runner/main.cpp", title)
    patch("linux/runner/my_application.cc", title)
    patch("linux/my_application.cc", title)
    print("\nDone. Now run:  flutter pub get   and then   flutter run")


if __name__ == "__main__":
    main()
