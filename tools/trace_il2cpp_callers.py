#!/usr/bin/env python3
"""Read-only ARM64 callsite audit for the exact fps 3.4.0 IL2CPP binary.

Maps direct `bl`/unconditional `b` instructions in Mach-O executable sections
to a small set of genuine metadata method identities. Does not hook, mutate,
or imply that a network request is authorized by the server.
"""

import argparse
import bisect
import hashlib
from pathlib import Path
import struct


GAME_SHA256 = "ad1794ad50d976e042bbbe0c604a4e8bbb3fe8092787ee9ce24d07e7a530ac2f"
METHOD_TABLE_RVA = 0x2358400
IMAGE_BASE = 0x100000000
TARGETS = {
    30044, 30045, 30046, 30056, 30318, 30353, 30358, 30368, 30369,
    30370, 30371, 30372, 30373, 30380, 30381, 30314, 30315, 30868,
    30869, 30957, 30999, 31002, 31983,
}


def unpack(fmt, blob, offset):
    if offset < 0 or offset + struct.calcsize(fmt) > len(blob):
        raise ValueError(f"Outside file bounds: {offset:#x} {fmt}")
    return struct.unpack_from(fmt, blob, offset)


def name_at(metadata, base, index):
    start = base + index
    if not 0 <= start < len(metadata):
        raise ValueError("Invalid metadata string index")
    end = metadata.find(b"\x00", start)
    if end == -1:
        raise ValueError("Unterminated metadata string")
    return metadata[start:end].decode("utf-8", "replace")


def executable_sections(game):
    commands = unpack("<I", game, 16)[0]
    cursor = 32
    for _ in range(commands):
        cmd, size = unpack("<II", game, cursor)
        if size < 8 or cursor + size > len(game):
            raise ValueError("Malformed Mach-O commands")
        if cmd == 0x19:
            seg = unpack("<16sQQQQiiII", game, cursor + 8)
            if seg[0].rstrip(b"\x00") == b"__TEXT":
                for index in range(seg[7]):
                    section = unpack("<16s16sQQ", game, cursor + 72 + 80 * index)
                    if section[0].rstrip(b"\x00") in (b"__text", b"il2cpp"):
                        start, length = section[2] - IMAGE_BASE, section[3]
                        yield start, start + length
        cursor += size


def method_map(game, metadata):
    header = unpack("<60I", metadata, 0)
    if header[0] != 0xFAB11BAF or header[1] != 24:
        raise ValueError("Unknown IL2CPP metadata version")
    string_base, methods_offset, method_bytes = header[6], header[12], header[13]
    typedef_offset, typedef_bytes = header[40], header[41]
    if method_bytes % 52 or typedef_bytes % 100:
        raise ValueError("Unexpected method/type definition stride")
    type_count = typedef_bytes // 100
    methods = {}
    for md in range(method_bytes // 52):
        row = unpack("<11I4H", metadata, methods_offset + 52 * md)
        index, type_index = row[5], row[1]
        if type_index >= type_count or index >= 30000:
            continue
        absolute = unpack("<Q", game, METHOD_TABLE_RVA + 8 * index)[0]
        if not IMAGE_BASE <= absolute < IMAGE_BASE + len(game):
            continue
        type_row = unpack("<2I", metadata, typedef_offset + type_index * 100)
        name = name_at(metadata, string_base, row[0])
        type_name = name_at(metadata, string_base, type_row[0])
        rva = absolute - IMAGE_BASE
        methods.setdefault(rva, []).append((md, f"{type_name}.{name}", row[-1]))
    return methods


def branch_target(word, pc):
    op = word & 0xFC000000
    if op not in (0x94000000, 0x14000000):
        return None
    displacement = word & 0x03FFFFFF
    if displacement & (1 << 25):
        displacement -= 1 << 26
    return pc + displacement * 4, "BL" if op == 0x94000000 else "B"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("game", type=Path)
    parser.add_argument("metadata", type=Path)
    options = parser.parse_args()
    game, metadata = options.game.read_bytes(), options.metadata.read_bytes()
    if hashlib.sha256(game).hexdigest() != GAME_SHA256:
        raise ValueError("Unknown game binary; refusing to infer offsets")
    methods = method_map(game, metadata)
    starts = sorted(methods)
    targets = {rva: rows for rva, rows in methods.items()
               if any(md in TARGETS for md, _name, _argc in rows)}
    findings = {rva: [] for rva in targets}
    for section_start, section_end in executable_sections(game):
        for pc in range(section_start, section_end, 4):
            word = unpack("<I", game, pc)[0]
            result = branch_target(word, pc)
            if not result or result[0] not in targets:
                continue
            target, branch_type = result
            caller_i = bisect.bisect_right(starts, pc) - 1
            if caller_i < 0:
                continue
            caller_start = starts[caller_i]
            # Nearest-lower method is a heuristic: native helper code may not
            # have an IL2CPP method identity, and aliases are possible.
            caller_names = "|".join(x[1] for x in methods[caller_start][:3])
            findings[target].append((pc, branch_type, caller_names))

    for target in sorted(targets):
        names = " | ".join(f"{n}(MD{md}, argc={argc})"
                           for md, n, argc in targets[target])
        print(f"TARGET {target:#x} {names}")
        if not findings[target]:
            print("  No direct ARM64 BL/B callers found; not proof of disuse")
        for pc, branch_type, caller in sorted(findings[target])[:35]:
            print(f"  {branch_type} at {pc:#x}  nearest method: {caller}")
        if len(findings[target]) > 35:
            print(f"  ... {len(findings[target]) - 35} more callsites")
    print("Read-only audit only. Indirect calls and network-authoritative state unmeasured.")


if __name__ == "__main__":
    main()
