#!/usr/bin/env python3
"""Build only the game window bridge; reuse the launcher's Flutter engine."""
from pathlib import Path
import hashlib
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
flutter = Path(shutil.which("flutter")).resolve().parents[1]
framework = next((flutter / "bin/cache/artifacts/engine/darwin-x64-release").glob(
    "FlutterMacOS.xcframework/macos-arm64_x86_64/FlutterMacOS.framework"
))
target = root / "assets/development/game-window-chrome.dylib"
subprocess.run([
    "/usr/bin/clang", "-arch", "x86_64", "-mmacosx-version-min=10.15", "-O2", "-fobjc-arc",
    "-Wall", "-Wextra", "-Werror", "-dynamiclib", "-framework", "AppKit",
    "-install_name", "@rpath/game-window-chrome.dylib",
    "-F", str(framework.parent), str(root / "tools/windowing/native/game_chrome.m"),
    "-o", str(target),
], check=True)
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(target)], check=True)
digest = hashlib.sha256(target.read_bytes()).hexdigest()
manifest = root / "lib/development/game_window_chrome_io.dart"
source, count = re.subn(
    r"(const gameWindowChromeHash =\s*')[a-f0-9]+(';)",
    lambda match: match[1] + digest + match[2], manifest.read_text(),
)
if count != 1:
    raise RuntimeError("Could not update the window component hash")
manifest.write_text(source)
print("SHA-256:", digest)
