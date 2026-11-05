#!/usr/bin/env python3
"""Package a verified OGS40 native KillPlayer bridge and matching dylib.

Input is the exact user-provided OGS34 IPA (already prepared for the earlier
DamageRemote and ApplyDamage bridges). This script does not sign the result.
No unrelated files are modified, and no speculative offsets are patched.
"""

import argparse
import hashlib
import os
from pathlib import Path
import struct
import tempfile
import zipfile


GAME = "Payload/fps.app/fps"
LIB = "Payload/fps.app/Frameworks/OGSMenu.dylib"
GAME_SHA256 = "ad1794ad50d976e042bbbe0c604a4e8bbb3fe8092787ee9ce24d07e7a530ac2f"
ORIGINAL_LIB_SHA256 = "bd743cd4597d145dca0f8f4920bf11f47fff6a638573268fbf4e197e26aa421b"

KILL_ENTRY = 0x13E8FBC
KILL_STUB = 0x3080
KILL_SLOT = 0x2A98DD0
KILL_PROLOG = 0xD101C3FF


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def b_imm(pc: int, target: int) -> int:
    delta = target - pc
    if delta % 4 or not (-2**27 <= delta < 2**27):
        raise ValueError("ARM64 B target out of range")
    return 0x14000000 | ((delta // 4) & 0x03FFFFFF)


def adrp_x16(pc: int, target: int) -> int:
    delta = ((target & ~0xFFF) - (pc & ~0xFFF)) // 4096
    if not (-2**20 <= delta < 2**20):
        raise ValueError("ARM64 ADRP target out of range")
    return 0x90000010 | ((delta & 3) << 29) | (((delta >> 2) & 0x7FFFF) << 5)


def verify_unused_callback_slot(binary: bytes) -> None:
    """Require an 8-byte writable gap beyond __DATA,__common, not within it."""
    ncmds = struct.unpack_from("<I", binary, 16)[0]
    cursor = 32
    found = False
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", binary, cursor)
        if size < 8 or cursor + size > len(binary):
            raise ValueError("Invalid Mach-O load command")
        if cmd == 0x19:
            name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, sections, _ = (
                struct.unpack_from("<16sQQQQiiII", binary, cursor + 8))
            if name.rstrip(b"\x00") == b"__DATA":
                if not (initprot & 0x3) == 0x3 or not (
                    vmaddr <= 0x100000000 + KILL_SLOT and
                    0x100000000 + KILL_SLOT + 8 <= vmaddr + vmsize
                ):
                    raise ValueError("Kill callback slot is not in writable __DATA")
                for index in range(sections):
                    offset = cursor + 72 + index * 80
                    section, _, address, length = struct.unpack_from(
                        "<16s16sQQ", binary, offset)
                    if section.rstrip(b"\x00") == b"__common":
                        if address + length != 0x100000000 + KILL_SLOT:
                            raise ValueError("No verified padding after __common")
                        if vmaddr + vmsize - (address + length) < 8:
                            raise ValueError("Insufficient callback padding")
                        found = True
        cursor += size
    if not found:
        raise ValueError("Writable callback gap layout not verified")


def patch_kill_bridge(original: bytes) -> bytes:
    if digest(original) != GAME_SHA256:
        raise ValueError("Unknown fps binary SHA-256; refusing patch")
    if original[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Not a Mach-O 64-bit executable")
    if struct.unpack_from("<I", original, KILL_ENTRY)[0] != KILL_PROLOG:
        raise ValueError("KillPlayer entrypoint changed")
    if original[KILL_STUB:KILL_STUB + 64] != bytes(64):
        raise ValueError("Kill bridge stub region is not free")
    verify_unused_callback_slot(original)

    patched = bytearray(original)
    stub_words = [
        adrp_x16(KILL_STUB, KILL_SLOT),
        0x91000210 | ((KILL_SLOT & 0xFFF) << 10),
        0xF9400210,  # ldr x16, [x16]
        0xB4000050,  # cbz x16, +8
        0xD61F0200,  # br x16 (preserve LR)
        KILL_PROLOG,
        b_imm(KILL_STUB + 24, KILL_ENTRY + 4),
    ]
    struct.pack_into("<7I", patched, KILL_STUB, *stub_words)
    struct.pack_into("<I", patched, KILL_ENTRY, b_imm(KILL_ENTRY, KILL_STUB))
    return bytes(patched)


def verify_dylib(data: bytes) -> None:
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Dylib is not Mach-O 64-bit")
    if struct.unpack_from("<I", data, 4)[0] != 0x0100000C:
        raise ValueError("Dylib is not ARM64")
    cursor = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        cmd, size = struct.unpack_from("<II", data, cursor)
        if size < 8 or cursor + size > len(data):
            raise ValueError("Corrupt dylib load command")
        if cmd == 0xD:  # LC_ID_DYLIB
            name_offset = struct.unpack_from("<I", data, cursor + 8)[0]
            name = data[cursor + name_offset:cursor + size].split(b"\x00")[0]
            if name != b"@rpath/OGSMenu.dylib":
                raise ValueError("Dylib install name mismatch")
            return
        cursor += size
    raise ValueError("Dylib install name not found")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("dylib", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.resolve() == args.source.resolve():
        raise ValueError("Refusing to overwrite source IPA")
    replacement = args.dylib.read_bytes()
    verify_dylib(replacement)
    with zipfile.ZipFile(args.source) as source:
        names = source.namelist()
        if names.count(GAME) != 1 or names.count(LIB) != 1:
            raise ValueError("Unexpected IPA manifest")
        old_game = source.read(GAME)
        if digest(source.read(LIB)) != ORIGINAL_LIB_SHA256:
            raise ValueError("Unexpected source OGS library")
        patched_game = patch_kill_bridge(old_game)
        fd, temp = tempfile.mkstemp(prefix="ogs40-", suffix=".ipa",
                                    dir=args.output.parent)
        os.close(fd)
        try:
            with zipfile.ZipFile(temp, "w") as output:
                for info in source.infolist():
                    data = patched_game if info.filename == GAME else (
                        replacement if info.filename == LIB else source.read(info.filename))
                    output.writestr(info, data)
            with zipfile.ZipFile(temp) as output:
                if output.testzip() is not None or output.namelist() != names:
                    raise ValueError("Repacked IPA integrity or manifest mismatch")
                if digest(output.read(GAME)) != digest(patched_game) or (
                    digest(output.read(LIB)) != digest(replacement)):
                    raise ValueError("Game or library does not match the output")
                for name in names:
                    if name in (GAME, LIB):
                        continue
                    if digest(output.read(name)) != digest(source.read(name)):
                        raise ValueError("Unintended modification: " + name)
            os.replace(temp, args.output)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
    print("Created", args.output)
    print("OGS40 game SHA-256", digest(patched_game))
    print("OGS40 ARM64 dylib SHA-256", digest(replacement))
    print("Other entries unchanged", len(names) - 2)
    print("IPA is UNSIGNED and must be signed with the usual authorized workflow")


if __name__ == "__main__":
    main()
