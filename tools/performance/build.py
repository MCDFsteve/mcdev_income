#!/usr/bin/env python3
"""Reproducibly build the two small Windows patch helpers. No game/Wine assets."""
from pathlib import Path
import hashlib
import os
import subprocess

root = Path(__file__).resolve().parents[2]
source = root / "tools/performance"
assets = root / "assets/development"
assets.mkdir(exist_ok=True)
cc = os.environ.get("MCDEV_MINGW_CC", "x86_64-w64-mingw32-gcc")
common = [cc, "-O2", "-s", "-static-libgcc", "-Wl,--no-insert-timestamp"]
subprocess.run(common + ["-municode", "-o", str(assets / "performance-inject.exe"),
                        str(source / "native/inject.c")], check=True)
subprocess.run(common + ["-shared", "-I" + str(source / "minhook/include"),
                        "-I" + str(source / "minhook/src"),
                        "-o", str(assets / "graphics-patch.dll"),
                        str(source / "native/graphics_patch.c")] +
               [str(source / "minhook/src" / name) for name in
                ["hook.c", "buffer.c", "trampoline.c", "hde/hde64.c"]], check=True)
for path in sorted(assets.iterdir()):
    if path.suffix in {".dll", ".exe"}:
        print(path.name, path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest())
