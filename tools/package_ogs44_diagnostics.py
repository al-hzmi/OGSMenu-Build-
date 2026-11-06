#!/usr/bin/env python3
"""Build an unsigned, observation-only OGS44 test IPA from exact OGS34 input.

The four new native bridges preserve the original first ARM64 instruction and
fall through to the unmodified function if no callback is installed. Device,
signature, authority, and gameplay behavior are not established by packaging.
"""
import argparse
import copy
import hashlib
import os
from pathlib import Path
import struct
import tempfile
import zipfile

from package_ogs40_ipa import (GAME, LIB, GAME_SHA256, ORIGINAL_LIB_SHA256,
    KILL_SLOT, b_imm, adrp_x16, patch_kill_bridge, verify_dylib)
from trace_il2cpp_callers import method_map

META = 'Payload/fps.app/Data/Managed/Metadata/global-metadata.dat'
SPECS = (
    ('PlayerNetwork.BombDmg',     30370, 0x13e7db0, 0x30c0, 0x2a98dd8, 0xd10183ff),
    ('PlayerNetwork.BombDmgLong', 30371, 0x13e815c, 0x3100, 0x2a98de0, 0xd10183ff),
    ('PlayerNetwork.C4Dmg',       30372, 0x13e8508, 0x3140, 0x2a98de8, 0xd10143ff),
    ('PlayerNetwork.C4DmgLong',   30373, 0x13e88a4, 0x3180, 0x2a98df0, 0xd10143ff),
)


def digest(data): return hashlib.sha256(data).hexdigest()


def ensure_slot_range(game):
    # Require the five total slots to lie after __DATA,__common, within writable
    # zero-fill region, and outside EVERY declared section, not merely __common.
    ncmds = struct.unpack_from('<I', game, 16)[0]
    c = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', game, c)
        if size < 8 or c + size > len(game): raise ValueError('bad Mach-O command')
        if cmd == 0x19:
            name, vm, vmsize, fo, fs, maxprot, prot, nsects, _ = struct.unpack_from('<16sQQQQiiII', game, c + 8)
            if name.rstrip(b'\0') == b'__DATA':
                start, end = 0x100000000 + KILL_SLOT, 0x100000000 + SPECS[-1][4] + 8
                if prot & 3 != 3 or not(vm <= start < end <= vm + vmsize): raise ValueError('slots not in writable __DATA')
                if start < vm + fs: raise ValueError('slots are not zero-fill memory')
                common_end = None
                for i in range(nsects):
                    section, _, addr, length = struct.unpack_from('<16s16sQQ', game, c + 72 + i * 80)
                    if section.rstrip(b'\0') == b'__common': common_end = addr + length
                    if length and start < addr + length and addr < end: raise ValueError('slot overlaps a declared section')
                if common_end != start: raise ValueError('unexpected common-section boundary')
                return
        c += size
    raise ValueError('missing __DATA')


def patch_diagnostics(original, metadata):
    if digest(original) != GAME_SHA256: raise ValueError('wrong source game SHA-256')
    methods = method_map(original, metadata)
    ensure_slot_range(original)
    prepared = bytearray(patch_kill_bridge(original))
    for name, md, entry, stub, slot, prolog in SPECS:
        if not any(row[0] == md and row[1] == name for row in methods.get(entry, [])):
            raise ValueError(f'method identity mismatch: {name}')
        if struct.unpack_from('<I', original, entry)[0] != prolog: raise ValueError(f'wrong prolog: {name}')
        if any(prepared[stub:stub + 64]): raise ValueError(f'stub space not empty: {name}')
        words = (adrp_x16(stub, slot), 0x91000210 | ((slot & 0xfff) << 10),
                 0xf9400210, 0xb4000050, 0xd61f0200, prolog,
                 b_imm(stub + 24, entry + 4))
        struct.pack_into('<7I', prepared, stub, *words)
        struct.pack_into('<I', prepared, entry, b_imm(entry, stub))
    return bytes(prepared)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('source',type=Path); ap.add_argument('dylib',type=Path); ap.add_argument('output',type=Path)
    a=ap.parse_args()
    if a.output.resolve() == a.source.resolve(): raise ValueError('refusing to overwrite source')
    dylib=a.dylib.read_bytes(); verify_dylib(dylib)
    with zipfile.ZipFile(a.source) as src:
        names=src.namelist()
        if len(names)!=len(set(names)) or any(names.count(n)!=1 for n in (GAME,LIB,META)): raise ValueError('unexpected ZIP manifest')
        if src.testzip() is not None: raise ValueError('source ZIP failed integrity')
        if digest(src.read(LIB)) != ORIGINAL_LIB_SHA256: raise ValueError('wrong source library')
        game=patch_diagnostics(src.read(GAME),src.read(META))
        fd,tmp=tempfile.mkstemp(prefix='ogs44-',suffix='.ipa',dir=a.output.parent); os.close(fd)
        try:
            with zipfile.ZipFile(tmp,'w') as out:
                for info in src.infolist():
                    data=game if info.filename==GAME else dylib if info.filename==LIB else src.read(info.filename)
                    out.writestr(copy.copy(info),data)
            with zipfile.ZipFile(tmp) as out:
                if out.testzip() is not None or out.namelist()!=names: raise ValueError('output ZIP integrity/manifest failure')
                for name in names:
                    expected=game if name==GAME else dylib if name==LIB else src.read(name)
                    if digest(out.read(name))!=digest(expected): raise ValueError('output mismatch: '+name)
            os.replace(tmp,a.output)
        finally:
            if os.path.exists(tmp): os.unlink(tmp)
    print('PASS unsigned diagnostic IPA',a.output)
    print('game SHA256',digest(game),'dylib SHA256',digest(dylib))
    print('NOT VERIFIED: Apple signature, installation, iOS runtime, network behavior')

if __name__=='__main__': main()
