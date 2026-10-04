#!/usr/bin/env python3
"""Reproducibly build the version-scoped local LAN adapter; reuse the injector."""
from pathlib import Path
import hashlib
import os
import subprocess

root = Path(__file__).resolve().parents[2]
target = root / "assets/development/lan-patch.dll"
target.parent.mkdir(parents=True, exist_ok=True)
cc = os.environ.get("MCDEV_MINGW_CC", "x86_64-w64-mingw32-gcc")
subprocess.run([
    cc, "-shared", "-O2", "-s", "-static-libgcc", "-Wl,--no-insert-timestamp",
    "-Wall", "-Wextra", "-Werror", "-o", str(target),
    str(root / "tools/lan/lan_patch.c"),
], check=True)
print(target.name, target.stat().st_size, hashlib.sha256(target.read_bytes()).hexdigest())
