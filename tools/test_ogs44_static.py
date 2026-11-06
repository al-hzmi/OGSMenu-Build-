#!/usr/bin/env python3
"""Evidence and bridge regression checks; no execution of the iOS application."""
import hashlib
from pathlib import Path
import re
import struct
import sys
import zipfile
from package_ogs44_diagnostics import GAME, LIB, META, SPECS, digest, patch_diagnostics
from trace_il2cpp_callers import branch_target, method_map


def literal(metadata, index):
    if struct.unpack_from('<II', metadata, 0) != (0xfab11baf, 24): raise ValueError('unexpected metadata')
    table, _, data, size = struct.unpack_from('<4I', metadata, 8)
    length, off = struct.unpack_from('<II', metadata, table + 8 * index)
    if off + length > size: raise ValueError('literal out of bounds')
    return metadata[data+off:data+off+length].decode('utf8')


def main():
    if len(sys.argv)!=3: raise SystemExit('usage: test_ogs44_static.py OGS34.ipa OGS44.ipa')
    with zipfile.ZipFile(sys.argv[1]) as a,zipfile.ZipFile(sys.argv[2]) as b:
        orig=a.read(GAME);meta=a.read(META);patched=b.read(GAME)
        assert b.testzip() is None and patched==patch_diagnostics(orig,meta)
        assert a.namelist()==b.namelist()
        for name in a.namelist():
            if name not in (GAME,LIB): assert hashlib.sha256(a.read(name)).digest()==hashlib.sha256(b.read(name)).digest(),name
        print('PASS complete ZIP comparison and independently rebuilt prepared executable')
        expected={
            0x13e7e14:0x97ffca98, 0x13e7ea4:0x3944b268,
            0x13e7f18:0x97ff90e9, 0x13e7f1c:0x34001120,
            0x13e7fd8:0x51019519, 0x13e8078:0x97ffa312,
            0x13e807c:0x7100033f, 0x13e8080:0x5400060c,
            0x13e812c:0x52800002, 0x13e8134:0x97ffd79c,
            0x13e813c:0x3904b268, 0x13e8564:0x97ffc8c4,
            0x13e8634:0x97ff8f22, 0x13e8638:0x340012a0,
            0x13e86f4:0x51019518, 0x13e8794:0x97ffa14b,
            0x13e8798:0x7100031f, 0x13e8880:0x97ffd5c9,
            0x13e8888:0x3904b268, 0x13e8384:0x51008519,
            0x13e8a90:0x51008518, 0x13f6e78:0x7100067f,
            0x13f6e80:0x71000a7f, 0x13f6ef0:0x52800017,
        }
        for pc, val in expected.items(): assert struct.unpack_from('<I',orig,pc)[0]==val,hex(pc)
        # In this IL2CPP v24 binary, the metadata-usage table entries point to
        # zero-fill globals initialized from the literal usage pairs. Verify
        # both the pointer and mapping, not just the existence of the strings.
        usage_base=0x2357588-21243*8
        pair_off,pair_size=struct.unpack_from('<II',meta,50*4)
        mappings={}
        for j in range(pair_off,pair_off+pair_size,8):
            dest,encoded=struct.unpack_from('<II',meta,j)
            if encoded>>29==5 and dest in (21235,21243,21309,21310):
                mappings[dest]=encoded&0x1fffffff
        for dest,slot,index,text in ((21235,0x283d768,5819,'PlayerHP'),
                                    (21243,0x283d7a8,5820,'KillPlayer'),
                                    (21309,0x283d9b8,6616,'ﺪﻫﺎﺸﻣ:'),
                                    (21310,0x283d9c0,6617,'PostActivityRemote')):
            assert struct.unpack_from('<Q',orig,usage_base+dest*8)[0]==0x100000000+slot
            assert mappings[dest]==index and literal(meta,index)==text
        assert struct.unpack_from('<II',orig,0x13e7f5c)==(0xd000a2b8,0x911da318)
        assert struct.unpack_from('<III',orig,0x13e811c)==(0xb000a2a8,0xd503201f,0xf943d501)
        assert literal(meta,6617)=='PostActivityRemote'
        assert 'ﺪﻫﺎﺸﻣ' in literal(meta,6616)
        methods=method_map(orig,meta)
        for pc, expected_name in ((0x13e7f18,'PhotonNetwork.get_isMasterClient'),
                                  (0x13e8078,'PhotonPlayer.SetCustomProperties'),
                                  (0x13e8134,'PhotonView.RPC'),
                                  (0x13e8634,'PhotonNetwork.get_isMasterClient'),
                                  (0x13e8794,'PhotonPlayer.SetCustomProperties'),
                                  (0x13e8880,'PhotonView.RPC'),
                                  (0x13f7164,'PhotonView.RPC'),
                                  (0x137cd2c,'CharacterController.Move')):
            dest=branch_target(struct.unpack_from('<I',orig,pc)[0],pc)[0]
            assert any(x[1]==expected_name for x in methods.get(dest,[])),(hex(pc),expected_name)
        print('PASS damage flow ARM64 anchors, metadata literals and called method identities')
        for name,_,entry,stub,slot,pro in SPECS:
            words=struct.unpack_from('<7I',patched,stub)
            assert branch_target(struct.unpack_from('<I',patched,entry)[0],entry)==(stub,'B')
            assert words[2:6]==(0xf9400210,0xb4000050,0xd61f0200,pro)
            assert branch_target(words[6],stub+24)==(entry+4,'B')
            print('PASS passive bridge/fallback',name)
        for address in (SPECS[0][2],SPECS[0][3]):
            damaged=bytearray(orig);damaged[address]^=1
            try:patch_diagnostics(damaged,meta)
            except ValueError:pass
            else:raise AssertionError('modified game not rejected')
        print('PASS tampered source executable and stub area rejected')
    source=(Path(__file__).resolve().parents[1]/'OGSMenu/ModMenu.mm').read_text()
    for i,f in enumerate(('OGS44BombNear','OGS44BombFar','OGS44C4Near','OGS44C4Far')):
        match=re.search(r'static void '+f+r'\([^)]*\)\s*\{(.*?)\}',source,re.S)
        assert match and f'if (OGS44ObserveExplosion({i}, self)) return;' in match.group(1) and 'if (original) original(' in match.group(1),f
    print('PASS four explosion callbacks gate suppression and otherwise call original in source')
    print('NOT TESTED: valid signature, runtime hooks, authority, two-client gameplay')

if __name__=='__main__':main()
