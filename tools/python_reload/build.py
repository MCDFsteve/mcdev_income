#!/usr/bin/env python3
"""Build the exact-version CPython safe-point DLL and pin its packaged hash."""
from pathlib import Path
import hashlib
import os
import re
import subprocess

root = Path(__file__).resolve().parents[2]
source = root / "tools/python_reload"
hooks = root / "tools/performance/minhook"
target = root / "assets/development/python-reload.dll"
subprocess.run([
    os.environ.get("MCDEV_MINGW_CC", "x86_64-w64-mingw32-gcc"),
    "-shared", "-O2", "-s", "-static-libgcc", "-Wl,--no-insert-timestamp",
    "-Wall", "-Wextra", "-Werror", "-I", str(hooks / "include"),
    "-o", str(target), str(source / "python_reload.c"),
    *[str(hooks / "src" / name) for name in ["buffer.c", "hook.c", "trampoline.c", "hde/hde64.c"]],
], check=True)
digest = hashlib.sha256(target.read_bytes()).hexdigest()
pin = root / "lib/development/python_reload_io.dart"
pin.write_text(re.sub(r"(const pythonReloadDllHash\s*=\s*)'[a-f0-9]{64}'", lambda m: m.group(1) + repr(digest), pin.read_text()))
print(target.name, target.stat().st_size, digest)
