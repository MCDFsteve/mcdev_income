#!/usr/bin/env python3
"""Read-only survey of a 3.10 PE and previously captured runtime sections.

This does not inject, patch, import game modules, or execute discovered functions.
String references and registration patterns are not a callable ABI guarantee.
Optional disassembly requires capstone; the JSON survey uses only the stdlib.
"""
import argparse
import bisect
import hashlib
import json
from pathlib import Path
import re
import struct


EXPECTED_SHA256 = "9be281dbe08bc591336680d5a50f94d87f3c57ee75b3afcb3cabdf03347e0269"
SIGNATURES = {
    "PyEval_EvalFrameEx": (0x0F7C0090, "4055564157488d6c24b94881ec000100"),
    "PyRun_StringFlags": (0x0F7DBC90, "48896c2410488974241848897c2420"),
    "PyErr_PrintEx": (0x0F7DA6E0, "48895c241855488bec4883ec60"),
}
TARGETS = (
    "get_input_vector", "get_move_input", "lock_move_vector", "unlock_move_vector", "change_jump_state",
    "getLocalPlayerPos", "getLocalPlayerRot", "setLocalPlayerRot",
    "_gui::change_jump_state", "_sunshine_interface::getLocalPlayerPos",
    "_sunshine_interface::setLocalPlayerRot", "_sunshine_interface::getLocalPlayerRot",
    "setLocalPlayerJump", "local_player_attack_entity", "player_destory_block",
    "local_player_start_destroy_block", "local_player_continue_destroy_block",
    "local_player_stop_destroy_block", "local_player_build_block",
    "local_player_select_slot", "local_player_use_item",
    "local_player_release_using_item", "local_player_is_using_item",
    "player_use_item_to_pos", "player_attack_entity", "_camera::Pick",
    "_entitymodule::get_player_destroy_total_time", "_camera::SetRot",
)


def digest(path):
    with path.open("rb") as handle:
        h = hashlib.sha256()
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
        return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True, type=Path)
    parser.add_argument("--sections", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--disassemble", action="store_true")
    args = parser.parse_args()
    header = (args.sections / "headers.bin").read_bytes()
    pe = struct.unpack_from("<I", header, 0x3C)[0]
    if header[:2] != b"MZ" or header[pe:pe + 4] != b"PE\0\0":
        parser.error("not a captured PE header")
    machine = struct.unpack_from("<H", header, pe + 4)[0]
    base = struct.unpack_from("<Q", header, pe + 24 + 24)[0]
    size = struct.unpack_from("<I", header, pe + 24 + 56)[0]
    exe_hash = digest(args.exe)
    if machine != 0x8664 or size != 0x1D28E000 or exe_hash != EXPECTED_SHA256:
        parser.error("unsupported image: expected the pinned 3.10.0.420447 x64 build")
    sections = {int(p.stem.split("-")[1], 16): p.read_bytes()
                for p in sorted(args.sections.glob("section-*.bin"))}

    def read(rva, length):
        for start, data in sections.items():
            if start <= rva and rva + length <= start + len(data):
                return data[rva - start:rva - start + length]
        return b""

    def cstring(va):
        for start, data in sections.items():
            offset = va - base - start
            if 0 <= offset < len(data):
                value = data[offset:offset + 240].split(b"\0", 1)[0]
                if value and all(32 <= c < 127 for c in value):
                    return value.decode("ascii")
        return ""

    signatures = {name: {"rva": hex(rva), "matches": read(rva, len(bytes.fromhex(sig))) == bytes.fromhex(sig)}
                  for name, (rva, sig) in SIGNATURES.items()}
    if not all(v["matches"] for v in signatures.values()):
        parser.error("captured runtime does not match the existing Python hook signatures")

    # Captures intentionally omit writable sections. Method tables may live
    # there; independently follow RIP-relative references to diagnostic strings.
    # The packed header's exception directory points into its boot section.
    # Use the original unwind section recovered for this exact pinned image.
    pdata = sections[0x19A84000]
    functions = sorted((a, b) for a, b, _ in struct.iter_unpack("<III", pdata)
                       if 0x1000 <= a < b <= 0x1000 + len(sections[0x1000]))
    starts = [a for a, _ in functions]
    targets = {}
    for name in TARGETS:
        needle = name.encode("ascii") + b"\0"
        for start, data in sections.items():
            if start == 0x1000:
                continue
            offset = data.find(needle)
            while offset >= 0:
                if offset == 0 or data[offset - 1] == 0:
                    targets[start + offset] = {"text": name, "string_rva": hex(start + offset), "xrefs": []}
                offset = data.find(needle, offset + 1)
    for match in re.finditer(rb"[\x48-\x4f][\x8d\x8b][\x05\x0d\x15\x1d\x25\x2d\x35\x3d][\s\S]{4}", sections[0x1000]):
        rva = 0x1000 + match.start()
        dest = rva + 7 + struct.unpack_from("<i", match.group(), 3)[0]
        if dest not in targets:
            continue
        index = bisect.bisect_right(starts, rva) - 1
        bounds = functions[index] if index >= 0 and rva < functions[index][1] else None
        xref = {"instruction_rva": hex(rva),
                "unwind_range": [hex(x) for x in bounds] if bounds else None}
        # Observed dynamic binding pattern: lea r8, function; mov rcx, rbx;
        # lea rdx, name; call registration helper. This is not a Python ABI.
        before = read(rva - 10, 10)
        after = read(rva + 7, 5)
        if (match.group()[:3] == b"\x48\x8d\x15" and
                before[:3] == b"\x4c\x8d\x05" and before[7:] == b"\x48\x8b\xcb" and
                after[:1] == b"\xe8"):
            function = rva - 3 + struct.unpack_from("<i", before, 3)[0]
            helper = rva + 12 + struct.unpack_from("<i", after, 1)[0]
            xref["binding_candidate"] = {"function_rva": hex(function), "helper_rva": hex(helper)}
        targets[dest]["xrefs"].append(xref)

    report = {
        "evidence_level": "static_candidates_not_live_execution",
        "version": "3.10.0.420447", "exe_sha256": exe_hash,
        "image_base": hex(base), "image_size": hex(size),
        "dump_provenance": "pre-existing capture; signatures/layout match, original capture not repeated",
        "sections": [{"name": p.name, "sha256": digest(p)}
                     for p in sorted(args.sections.glob("*.bin"))],
        "python_signatures": signatures,
        "string_xrefs": list(targets.values()),
        "capture_boundary": "writable sections omitted; signatures and runtime module accessibility need live verification",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if args.disassemble:
        import capstone
        cs = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
        cs.detail = True
        lines = []
        ranges = {}
        for target in targets.values():
            for xref in target["xrefs"]:
                if xref["unwind_range"]:
                    key = tuple(int(x, 16) for x in xref["unwind_range"])
                    ranges.setdefault(key, set()).add(target["text"])
                binding = xref.get("binding_candidate")
                if binding:
                    rva = int(binding["function_rva"], 16)
                    index = bisect.bisect_right(starts, rva) - 1
                    if index >= 0 and rva < functions[index][1]:
                        ranges.setdefault(functions[index], set()).add("binding:" + target["text"])
                    else:
                        ranges.setdefault((rva, rva + 32), set()).add("leaf excerpt, binding:" + target["text"])
        for (rva, end), names in sorted(ranges.items()):
            length = min(end - rva, 2048)
            lines.append("\nXREF UNWIND REGION %s RVA %s..%s (showing %d bytes; a function may span regions)" % (", ".join(sorted(names)), hex(rva), hex(end), length))
            for ins in cs.disasm(read(rva, length), base + rva):
                notes = []
                for op in ins.operands:
                    if op.type == capstone.x86.X86_OP_MEM and op.mem.base == capstone.x86.X86_REG_RIP:
                        text = cstring(ins.address + ins.size + op.mem.disp)
                        if text:
                            notes.append(text)
                lines.append("%08x %-8s %-44s %s" % (ins.address - base, ins.mnemonic, ins.op_str, " | ".join(notes)))
        args.output.with_suffix(".asm.txt").write_text("\n".join(lines) + "\n")
    print(json.dumps({"output": str(args.output), "binding_candidates": sum("binding_candidate" in x for t in targets.values() for x in t["xrefs"]),
                      "strings_with_xrefs": sum(bool(t["xrefs"]) for t in targets.values()), "signatures_match": True}))


if __name__ == "__main__":
    main()
