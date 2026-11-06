#!/usr/bin/env python3
"""Read-only, exact-build verification for the OGS34/41/42 investigation.

This checks package integrity and a small number of static invariants. Passing
cannot verify signatures, iOS installation, runtime calls, or Photon behavior.
"""
import argparse
import hashlib
import struct
import zipfile
from pathlib import Path

from trace_il2cpp_callers import GAME_SHA256, branch_target, method_map

GAME = 'Payload/fps.app/fps'
META = 'Payload/fps.app/Data/Managed/Metadata/global-metadata.dat'
LIB = 'Payload/fps.app/Frameworks/OGSMenu.dylib'
PATCHED_GAME_SHA256 = 'e46148304090f8de5a4fadb009883d0e7a2e0c5541e8628261164b6457b735b2'
TARGETS = {
    30368: ('PlayerNetwork.ApplyDamage', 0x13e7360),
    30369: ('PlayerNetwork.DamageRemote', 0x13e7588),
    30370: ('PlayerNetwork.BombDmg', 0x13e7db0),
    30372: ('PlayerNetwork.C4Dmg', 0x13e8508),
    30380: ('PlayerNetwork.KillPlayer', 0x13e8fbc),
    30318: ('FPSController.FallingDamageAlert', 0x137ce08),
    30044: ('RoomController.PrepareRespawn', 0x13f65c0),
    30056: ('RoomController.JoinedTeam', 0x13f6e30),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def word(data, offset):
    return struct.unpack_from('<I', data, offset)[0]


def inspect(original, candidate):
    with zipfile.ZipFile(original) as a, zipfile.ZipFile(candidate) as b:
        for path, archive in ((original, a), (candidate, b)):
            names = archive.namelist()
            require(len(names) == len(set(names)), f'{path}: duplicate ZIP entries')
            bad = archive.testzip()
            require(bad is None, f'{path}: corrupt ZIP member {bad}')
        game, patched, metadata = a.read(GAME), b.read(GAME), b.read(META)
        require(sha(game) == GAME_SHA256, 'unexpected OGS34 game executable')
        require(sha(patched) == PATCHED_GAME_SHA256, 'unexpected prepared game executable')
        require(a.read(META) == metadata, 'metadata differs between packages')
        require(word(metadata, 0) == 0xfab11baf and word(metadata, 4) == 24,
                'unexpected IL2CPP metadata signature/version')
        require(word(game, 0) == 0xfeedfacf and word(game, 4) == 0x0100000c,
                'expected Mach-O 64 ARM64')
        methods = method_map(game, metadata)
        for md, (name, rva) in TARGETS.items():
            require(any(row[0] == md and row[1] == name for row in methods.get(rva, [])),
                    f'method identity mismatch: {name}')
        require(word(game, 0x13e9008) == 0x52800028 and
                word(game, 0x13e900c) == 0x3904b268,
                'expected KillPlayer state store missing')
        for pc, target, kind in ((0x13e9130, 0x13f65c0, 'BL'),
                                 (0x137cf70, 0x13e7360, 'BL'),
                                 (0x138a8a0, 0x13e7360, 'B'),
                                 (0x138987c, 0x13e7db0, 'B'),
                                 (0x13548f8, 0x13e8508, 'B')):
            require(branch_target(word(game, pc), pc) == (target, kind),
                    f'callsite mismatch at {pc:#x}')
        require(branch_target(word(patched, 0x13e8fbc), 0x13e8fbc) == (0x3080, 'B'),
                'KillPlayer entry does not branch to expected stub')
        require(word(patched, 0x3094) == word(game, 0x13e8fbc),
                'KillPlayer trampoline lacks displaced instruction')
        require(branch_target(word(patched, 0x3098), 0x3098) == (0x13e8fc0, 'B'),
                'KillPlayer trampoline continuation mismatch')
        require(len(game) == len(patched), 'game length changed')
        changes = [i for i, (x, y) in enumerate(zip(game, patched)) if x != y]
        require(all(0x3080 <= i < 0x309c or 0x13e8fbc <= i < 0x13e8fc0 for i in changes),
                'unexpected game modification outside KillPlayer bridge')
        print(f'PASS ZIP integrity and unique members: {original} / {candidate}')
        print(f'PASS SHA-256 original={sha(game)} prepared={sha(patched)}')
        print('PASS ARM64 Mach-O and IL2CPP metadata version 24')
        print(f'PASS {len(TARGETS)} IL2CPP method identities and five ARM64 direct callsites')
        print(f'PASS KillPlayer bridge entry, displaced instruction and continuation; {len(changes)} changed bytes')
        print(f'INFO candidate library sha256={sha(b.read(LIB))}')
        print('NOT CHECKED: Apple signature, runtime hooks, gameplay, multiplayer authority')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('original', type=Path, help='OGS34 IPA')
    parser.add_argument('candidate', type=Path, help='OGS41 or OGS42 IPA')
    args = parser.parse_args()
    inspect(args.original, args.candidate)


if __name__ == '__main__':
    main()
