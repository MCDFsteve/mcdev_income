#!/usr/bin/env python3
"""Reproducibly build only the RenderDragon adapter; retain the verified GL patch."""
from pathlib import Path
import hashlib
import os
import subprocess

root = Path(__file__).resolve().parents[2]
minhook = root / "tools/performance/minhook"
target = root / "assets/development/renderer-patch.dll"
cc = os.environ.get("MCDEV_MINGW_CC", "x86_64-w64-mingw32-gcc")
injector = target.with_name("renderer-inject.exe")
subprocess.run([cc, "-municode", "-O2", "-s", "-static-libgcc", "-Wl,--no-insert-timestamp",
                "-o", str(injector), str(root / "tools/renderer/native/inject.c")], check=True)
subprocess.run([
    cc, "-shared", "-O2", "-s", "-static-libgcc", "-Wl,--no-insert-timestamp",
    "-Wall", "-Wextra", "-Wno-unused-parameter", "-I" + str(minhook / "include"),
    "-o", str(target), str(root / "tools/renderer/native/renderer_patch.c"),
] + [str(minhook / "src" / name) for name in
     ["hook.c", "buffer.c", "trampoline.c", "hde/hde64.c"]], check=True)
print(target.name, target.stat().st_size, hashlib.sha256(target.read_bytes()).hexdigest())
print(injector.name, injector.stat().st_size, hashlib.sha256(injector.read_bytes()).hexdigest())
