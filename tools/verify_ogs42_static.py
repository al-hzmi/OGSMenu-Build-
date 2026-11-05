#!/usr/bin/env python3
"""Static regression checks for the OGS42 dead-but-moving recovery mitigation.

These checks intentionally do not claim live network or server confirmation.
"""

import hashlib
from pathlib import Path
import re
import struct
import sys

from trace_il2cpp_callers import GAME_SHA256, branch_target


def check_original_game(game: bytes) -> None:
    assert hashlib.sha256(game).hexdigest() == GAME_SHA256, "wrong executable"
    # KillPlayer's original writes playerKilled at self+0x12C, and directly
    # schedules PrepareRespawn. Its entire call must NOT be suppressed.
    assert struct.unpack_from("<I", game, 0x13E9008)[0] == 0x52800028, (
        "KillPlayer's mov w8,#1 changed"
    )
    assert struct.unpack_from("<I", game, 0x13E900C)[0] == 0x3904B268, (
        "KillPlayer's playerKilled store changed"
    )
    assert branch_target(struct.unpack_from("<I", game, 0x13E9130)[0],
                         0x13E9130) == (0x13F65C0, "BL"), (
        "KillPlayer -> PrepareRespawn branch changed"
    )


def check_bridge_source(source: str) -> None:
    bridge = re.search(r"static void OGSBridgeKillPlayer\([^)]*\)\s*\{",
                       source)
    assert bridge, "KillPlayer bridge absent"
    until = source.index("static void OGSBridgeOutgoingDamage", bridge.end())
    body = source[bridge.start():until]
    assert "if (original) original(self, argument, method);" in body, (
        "original KillPlayer is not forwarded"
    )
    assert not re.search(r"\breturn\s*;", body), (
        "KillPlayer bridge must not return before PrepareRespawn"
    )
    assert "gOGS42KillLocalOriginalForwarded" in body
    assert "gOGS42KillPreDeadFlagZero" in body
    assert "gOGS42KillPreDeadFlagOne" in body
    assert "gOGS42KillPreDeadFlagUnknown" in body


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify_ogs42_static.py /path/to/original/fps")
    game = Path(sys.argv[1]).read_bytes()
    check_original_game(game)
    print("PASS original KillPlayer state store and PrepareRespawn branch")
    source = Path(__file__).resolve().parents[1] / "OGSMenu" / "ModMenu.mm"
    check_bridge_source(source.read_text(encoding="utf-8"))
    print("PASS OGS42 bridge always forwards original KillPlayer")
    print("PASS static mitigation regression; live respawn still unverified")


if __name__ == "__main__":
    main()
