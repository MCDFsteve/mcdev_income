#!/usr/bin/env python3
"""Test native game menus without starting the game or drawing a window."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
flutter = Path(shutil.which("flutter")).resolve().parents[1]
framework = next((flutter / "bin/cache/artifacts/engine/darwin-x64-release").glob(
    "FlutterMacOS.xcframework/macos-arm64_x86_64/FlutterMacOS.framework"
))
with tempfile.TemporaryDirectory(prefix="mcdev-menu-test-") as directory:
    target = Path(directory) / "menu-test"
    subprocess.run([
        "/usr/bin/clang", "-arch", "x86_64", "-O2", "-fobjc-arc",
        "-Wall", "-Wextra", "-Werror", "-framework", "AppKit",
        "-F", str(framework.parent),
        str(root / "tools/windowing/native/menu_test.m"), "-o", str(target),
    ], check=True)
    subprocess.run([str(target)], check=True)
