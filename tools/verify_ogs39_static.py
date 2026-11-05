#!/usr/bin/env python3
"""Read-only evidence checks for exact fps 3.4.0 ARM64 binary (not gameplay tests).

Usage: python3 tools/verify_ogs39_static.py /path/to/fps
The binary is the Mach-O executable, not the IPA or the injected dylib.
"""

import argparse
import struct
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("binary", type=Path)
args = parser.parse_args()
blob = args.binary.read_bytes()


def ptr_at(file_offset: int) -> int:
    return struct.unpack_from("<Q", blob, file_offset)[0]


def instruction_at(file_offset: int) -> int:
    return struct.unpack_from("<I", blob, file_offset)[0]


def expect(label: str, actual: int, expected: int) -> None:
    if actual != expected:
        raise SystemExit(f"FAIL {label}: got {actual:#x}, expected {expected:#x}")
    print(f"PASS {label}: {actual:#x}")


IMAGE_BASE = 0x100000000
METHOD_TABLE = 0x2358400

# MethodInfo mapping is from the supplied IL2CPP v24 global-metadata.dat.
for label, index, entry in (
    ("Room.set_MaxPlayers MI29298", 29298, 0x13F1AF0),
    ("Room.get_PlayerCount MI29299", 29299, 0x13ED320),
    ("PlayerNetwork.KillPlayer MI29168", 29168, 0x13E8FBC),
    ("FPSWeapon.GrenadeShootm MI27848", 27848, 0x1381160),
    ("PlayerWeapons.SwitchWeaponGrenade MI29196", 29196, 0x13EC238),
):
    expect(label, ptr_at(METHOD_TABLE + 8 * index), IMAGE_BASE + entry)

# Actual observed native instructions, independent of declared field names.
expect("Room.setter writes local MaxPlayers byte +0x20",
       instruction_at(0x13F1D08), 0x39008274)
expect("Room.get_PlayerCount returns player-list length +0x18",
       instruction_at(0x13ED3A8), 0xB9401A60)
expect("Grenade array field +0x60 in SwitchWeaponGrenade",
       instruction_at(0x13EC270), 0xF9403274)
expect("selectedGrenade +0x8C in SwitchWeaponGrenade",
       instruction_at(0x13EC274), 0xB9408E75)
expect("KillPlayer marks internal death flag +0x12C",
       instruction_at(0x13E900C), 0x3904B268)
print("STATIC AUDIT PASS — ARM64 method identities verified; no iOS runtime was tested")
