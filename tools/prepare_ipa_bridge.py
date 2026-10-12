#!/usr/bin/env python3
"""Prepare the *exact* fps 3.4.0 binary for a pre-sign OGSMenu damage bridge.
This output INVALIDATES the original app signature: inject the matching dylib,
then re-sign the complete IPA with your own permitted signing workflow.
It is NOT installable until re-signed. No iPhone runtime code-page patches.
"""
import argparse
import hashlib
import struct
import zipfile
from pathlib import Path

SOURCE_SHA256 = "ac5155a93ae40201210f3e9496ee95d98cfa5de8c70c43098c43127659f9a390"
EXECUTABLE_PATH = "Payload/fps.app/fps"
POINTS = {
    "magic": (0x13E7360, 0x3000, 0x2813EF0, bytes.fromhex("ff0301d1")),
    "god":   (0x13E7588, 0x3040, 0x2813EF8, bytes.fromhex("ff8301d1")),
}

def b_imm(pc, to):
    delta = to - pc
    if delta % 4 or not (-2**27 <= delta < 2**27):
        raise ValueError("ARM64 B target is out of range")
    return 0x14000000 | ((delta // 4) & 0x03ffffff)

def adrp_x16(pc, target):
    delta = ((target & ~0xfff) - (pc & ~0xfff)) // 4096
    if not (-2**20 <= delta < 2**20):
        raise ValueError("ADRP target out of range")
    return 0x90000010 | ((delta & 3) << 29) | (((delta >> 2) & 0x7ffff) << 5)

def patch_executable(original):
    digest = hashlib.sha256(original).hexdigest()
    if digest != SOURCE_SHA256:
        raise ValueError("Wrong fps build; exact SHA-256 required: " + digest)
    result = bytearray(original)
    if result[:4] != bytes.fromhex("cffaedfe"):
        raise ValueError("Not arm64 Mach-O")
    header_end = 32 + struct.unpack_from("<I", result, 20)[0]
    if header_end > 0x3000:
        raise ValueError("Executable header pad not free")
    for name, (entry, stub, slot, prolog) in POINTS.items():
        if result[entry:entry+4] != prolog:
            raise ValueError(name + " entrypoint prologue mismatch")
        if result[stub:stub+64] != bytes(64):
            raise ValueError(name + " stub region occupied")
        words = [
            adrp_x16(stub, slot),
            0x91000210 | ((slot & 0xfff) << 10),  # add x16, x16, #off
            0xF9400210,  # ldr x16, [x16]
            0xB4000050,  # cbz x16, +8
            0xD61F0200,  # br x16, preserves caller LR
            struct.unpack("<I", prolog)[0],
            b_imm(stub+24, entry+4),
        ]
        struct.pack_into("<7I", result, stub, *words)
        struct.pack_into("<I", result, entry, b_imm(entry, stub))
    return bytes(result)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_ipa", type=Path)
    parser.add_argument("output_ipa", type=Path)
    a = parser.parse_args()
    with zipfile.ZipFile(a.input_ipa) as source:
        target = patch_executable(source.read(EXECUTABLE_PATH))
        with zipfile.ZipFile(a.output_ipa, "w") as output:
            for info in source.infolist():
                output.writestr(info, target if info.filename == EXECUTABLE_PATH
                                else source.read(info.filename))
    print("Prepared:", a.output_ipa)
    print("Original code signature INVALID. Inject current OGSMenu.dylib and RE-SIGN IPA.")

if __name__ == "__main__":
    main()
