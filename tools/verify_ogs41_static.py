#!/usr/bin/env python3
"""Exact-input ARM64 proof of the direct-damage entry path used by OGS41."""

import hashlib
from pathlib import Path
import struct
import sys

from trace_il2cpp_callers import GAME_SHA256, branch_target


if len(sys.argv) != 2:
    raise SystemExit("Usage: verify_ogs41_static.py /path/to/original/fps")
binary = Path(sys.argv[1]).read_bytes()
if hashlib.sha256(binary).hexdigest() != GAME_SHA256:
    raise SystemExit("FAIL: executable hash mismatch")

# Method table identities checked independently from the metadata parser.
method_table = 0x2358400
for label, index, entry in (
    ("PlayerNetwork.ApplyDamage", 29156, 0x13E7360),
    ("PlayerNetwork.DamageRemote", 29157, 0x13E7588),
    ("PlayerNetwork.KillPlayer", 29168, 0x13E8FBC),
    ("RoomController.PrepareRespawn", 29342, 0x13F65C0),
    ("RoomController.JoinedTeam", 29354, 0x13F6E30),
):
    resolved = struct.unpack_from("<Q", binary, method_table + index * 8)[0]
    assert resolved == 0x100000000 + entry, f"{label}: unexpected method address"
    print("PASS method identity", label)

for label, callsite, expected, kind in (
    ("HitBox.Damage -> ApplyDamage", 0x138A8A0, 0x13E7360, "B"),
    ("FallingDamageAlert -> ApplyDamage", 0x137CF70, 0x13E7360, "BL"),
    ("KillPlayer -> PrepareRespawn", 0x13E9130, 0x13F65C0, "BL"),
):
    word = struct.unpack_from("<I", binary, callsite)[0]
    assert branch_target(word, callsite) == (expected, kind), label
    print("PASS native branch", label)

print("PASS: native ARM64 call graph verified; not a live game test")
