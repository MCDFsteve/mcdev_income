#!/usr/bin/env python3
"""Build the Wine x64 LAN discovery helper and run native regression checks."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = root / "tools/network/native"
target = root / "assets/development/ipv6-discovery.dylib"
flags = ["/usr/bin/clang", "-arch", "x86_64", "-mmacosx-version-min=10.15",
         "-O2", "-Wall", "-Wextra", "-Werror", "-framework", "SystemConfiguration",
         "-framework", "CoreFoundation"]
subprocess.run(flags + ["-dynamiclib", "-Wl,-install_name,@rpath/ipv6-discovery.dylib",
                       str(source / "ipv6_scope.c"),
                       "-o", str(target)], check=True)
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none",
                str(target)], check=True)
with tempfile.TemporaryDirectory(prefix="mcdev-network-test-") as temp:
    probe = Path(temp) / "probe"
    subprocess.run(flags + [str(source / "test_ipv6_scope.c"), "-o", str(probe)],
                   check=True)
    subprocess.run([str(probe)], check=True, timeout=10)
print("SHA-256:", hashlib.sha256(target.read_bytes()).hexdigest())
