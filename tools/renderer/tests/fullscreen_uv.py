#!/usr/bin/env python3
"""Numeric GPU regression using official SM5 shaders from a verified local game.

No proprietary bytecode is distributed. The Wine prefix is a fresh private
directory, with no accounts, worlds or desktop windows. Outputs contain only
shader fixtures and numeric test results.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import tempfile

GAME_HASH = "9be281dbe08bc591336680d5a50f94d87f3c57ee75b3afcb3cabdf03347e0269"
SHADERS = {
    "vs": "1f3b37a932f75b8a0707387c7d57f48e98093622",
    "ps": "3b2f1a263f48d8d5b1ff3361e4a927e9a466f148",
}


def windows(path):
    return "Z:" + str(path).replace("/", "\\")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--wine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cc", default=os.environ.get("MCDEV_MINGW_CC", "x86_64-w64-mingw32-gcc"))
    args = parser.parse_args()
    game = args.game.resolve()
    wine = args.wine.resolve()
    with (game / "Minecraft.Windows.exe").open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    if digest != GAME_HASH:
        raise ValueError("Only the verified 3.10.0.420447 game is supported")
    args.output.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="fullscreen-uv-", dir=args.output.resolve()))
    remaining = set(SHADERS)
    for material in sorted((game / "data/renderer/materials").glob("*.bin")):
        data = material.read_bytes()
        for match in re.finditer(b"DXBC", data):
            offset = match.start()
            if offset + 32 > len(data):
                continue
            size = struct.unpack_from("<I", data, offset + 24)[0]
            if size < 32 or size > 1000000 or offset + size > len(data):
                continue
            code = data[offset:offset + size]
            sha1 = hashlib.sha1(code).hexdigest()
            for stage in tuple(remaining):
                if sha1 == SHADERS[stage]:
                    (work / f"{stage}.dxbc").write_bytes(code)
                    remaining.remove(stage)
        if not remaining:
            break
    if remaining:
        raise ValueError("Official fullscreen shader fixture is missing")
    broken = [0,0,0,0,0,0,0, 1,0,0,1,1,1,1, 1,1,0,1,1,0,2, 0,1,0,1,0,0,3]
    (work / "quad.bin").write_bytes(struct.pack("<28f", *broken))
    subprocess.run([
        args.cc, "-municode", "-O2", "-s", "-static-libgcc", "-o", str(work / "test.exe"),
        str(Path(__file__).with_suffix(".c")), "-ld3d11",
    ], check=True)
    prefix = work / "prefix"
    temp = work / "tmp"
    temp.mkdir()
    environment = dict(os.environ, WINEPREFIX=str(prefix), WINELOADER=str(wine),
                       WINEDEBUG="-all", TMPDIR=str(temp), MVK_CONFIG_LOG_LEVEL="1",
                       WINEDLLOVERRIDES="kerberos=;d3d11,dxgi,winemetal=b", DXMT_LOG_LEVEL="warn")
    process = None
    try:
        with (work / "test.log").open("wb") as log:
            process = subprocess.Popen([
                str(wine), windows(work / "test.exe"), windows(work), "vs.dxbc", "ps.dxbc", "quad.bin",
            ], env=environment, stdout=log, stderr=log)
            result = process.wait(timeout=90)
        if result != 0:
            raise RuntimeError(f"GPU fixture failed ({result}); inspect {work / 'test.log'}")
        rows = re.findall(r"pass=(\d+) pixels=1024 mismatches=(\d+) max_error=([\d.]+)",
                          (work / "test.log").read_text(errors="replace"))
        assert len(rows) == 4, "GPU results are incomplete"
        values = {int(index): (int(count), float(error)) for index, count, error in rows}
        assert values[0][0] > 0 and values[1] == values[0], "The original UV error was not reproduced"
        assert values[2] == (0, 0) and values[3] == (0, 0), "The corrected UV must copy every pixel exactly"
        report = {"version": "3.10.0.420447", "pixels": 1024,
                  "original_mismatches": values[0][0], "fixed_mismatches": 0,
                  "fixed_max_error": 0, "world_visual_validation": "separate_required"}
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report))
        print("Evidence:", work)
    finally:
        # Only this newly created, account-free prefix is stopped.
        if process is not None and process.poll() is None:
            process.terminate()
        subprocess.run([str(wine.parent / "wineserver"), "-k"], env=environment,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)


if __name__ == "__main__":
    main()
