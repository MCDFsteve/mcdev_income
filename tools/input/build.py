#!/usr/bin/env python3
"""Build and verify the separate x64 Wine input helper (does not rebuild graphics)."""
from pathlib import Path
import hashlib
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = root / "tools/input/native"
target = root / "assets/development/fullscreen-shortcut.dylib"
flags = ["/usr/bin/clang", "-arch", "x86_64", "-mmacosx-version-min=10.15", "-O2", "-Wall", "-Wextra", "-Werror", "-framework", "AppKit"]
subprocess.run(flags + ["-dynamiclib", str(source / "fullscreen_shortcut.m"), "-o", str(target)], check=True)
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(target)], check=True)
with tempfile.TemporaryDirectory(prefix="mcdev-input-test-") as temp:
    probe = Path(temp) / "probe"
    subprocess.run(flags + [str(source / "test_fullscreen_shortcut.m"), "-o", str(probe)], check=True)
    for enabled in ["0", "1"]:
        subprocess.run([str(probe)], check=True, env={**os.environ, "DYLD_INSERT_LIBRARIES": str(target), "MCDEV_FULLSCREEN_SHORTCUT": enabled})
print("SHA-256:", hashlib.sha256(target.read_bytes()).hexdigest())
