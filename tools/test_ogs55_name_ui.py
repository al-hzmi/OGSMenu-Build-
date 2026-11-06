#!/usr/bin/env python3
"""Static bridge checks only; the live Photon recipient is not tested here."""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "OGSMenu" / "ModMenu.mm").read_text()

for required in (
    '#include "OGSNameIdentityPolicy.h"',
    'ogsname::HasUniquePublishedUserId',
    'ogsname::ShouldPreserveHistoryDuringMissingRoom',
    'ogsname::CanPromoteActorHistory',
    'roomEpoch - self.sessionNameRoomEnterEpoch',
    'self.sessionNameHistory[actorKey]',
    '[self.sessionNameHistory removeObjectForKey:actorKey]',
    'self.sessionNameMissingRoomSince = 0.0',
    'عند الخروج والدخول يتغير رقمه',
    'ولا يمكن إثبات أنه نفس الحساب',
    'if (samples < 2) continue;',
):
    assert required in source, f"missing name identity guard: {required}"

assert 'self.sessionNameHistory[key] = names' in source
assert 'gOGSNameNotifications' in source
print("OGS55 name tracking source-contract checks passed (not a live game test)")
