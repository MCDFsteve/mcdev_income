#!/usr/bin/env python3
"""Build the injected, per-game FMOD silent-output adapter and pin its hash."""
from pathlib import Path
import hashlib
import os
import re
import subprocess

root = Path(__file__).resolve().parents[2]
hooks = root / "tools/performance/minhook"
target = root / "assets/development/sound-patch.dll"
subprocess.run([
    os.environ.get("MCDEV_MINGW_CC", "x86_64-w64-mingw32-gcc"),
    "-shared", "-O2", "-s", "-static-libgcc", "-Wl,--no-insert-timestamp",
    "-Wall", "-Wextra", "-Werror", "-I", str(hooks / "include"),
    "-o", str(target), str(root / "tools/sound/sound_patch.c"),
    *[str(hooks / "src" / name) for name in ["buffer.c", "hook.c", "trampoline.c", "hde/hde64.c"]],
], check=True)
digest = hashlib.sha256(target.read_bytes()).hexdigest()
pin = root / "lib/development/sound_patch_io.dart"
pin.write_text(re.sub(r"(const soundPatchHash\s*=\s*)'[a-f0-9]{64}'", lambda m: m.group(1) + repr(digest), pin.read_text()))
print(target.name, target.stat().st_size, digest)
