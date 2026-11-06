#!/usr/bin/env python3
"""Package an UNSIGNED OGS46 candidate from exact OGS41; never changes metadata.
The seven additions preserve native prologues and fall through when uninstalled.
Existing damage/KillPlayer bridges remain byte-identical. Re-sign externally.
"""
import argparse, copy, os, struct, tempfile, zipfile
from pathlib import Path
from audit_ogs46 import BRIDGES, GAME, META, LIB, LIB_SHA, sha, require, verify
from package_ogs40_ipa import b_imm, adrp_x16, verify_dylib

def verify_padding(g):
    c=32; found=False;stubStart=min(x[3] for x in BRIDGES);stubEnd=max(x[3] for x in BRIDGES)+64
    slotStart=min(x[4] for x in BRIDGES);slotEnd=max(x[4] for x in BRIDGES)+8
    for _ in range(struct.unpack_from('<I',g,16)[0]):
        cmd,size=struct.unpack_from('<II',g,c);require(size>=8 and c+size<=len(g),'load command')
        if cmd==0x19:
            name,vm,vs,fo,fs,mp,prot,ns,flags=struct.unpack_from('<16sQQQQiiII',g,c+8)
            if name.rstrip(b'\0')==b'__DATA':
                require(prot&3==3 and vm+fs<=0x100000000+slotStart<0x100000000+slotEnd<=vm+vs,'writable zero-fill slots')
                found=True
            for j in range(ns):
                sn,seg,va,n,off=struct.unpack_from('<16s16sQQI',g,c+72+j*80)
                require(not(n and 0x100000000+slotStart<va+n and va<0x100000000+slotEnd),'slot overlaps section')
                require(not(n and 0x100000000+stubStart<va+n and va<0x100000000+stubEnd),'stub overlaps section')
        c+=size
    require(found and c<=stubStart,'padding boundaries')

def patch(g,m):
    verify(g,m);verify_padding(g);out=bytearray(g)
    for name,md,entry,stub,slot,prolog in BRIDGES:
        words=[adrp_x16(stub,slot),0x91000210|((slot&0xfff)<<10),0xf9400210,0xb4000050,0xd61f0200,prolog,b_imm(stub+24,entry+4)]
        struct.pack_into('<7I',out,stub,*words);struct.pack_into('<I',out,entry,b_imm(entry,stub))
    return bytes(out)

def package(source,lib,output):
    require(source.resolve()!=output.resolve(),'cannot overwrite source')
    replacement=lib.read_bytes();verify_dylib(replacement)
    with zipfile.ZipFile(source) as z:
        names=z.namelist();require(len(names)==len(set(names)) and z.testzip() is None,'ZIP integrity')
        require(sha(z.read(LIB))==LIB_SHA,'source dylib fingerprint')
        prepared=patch(z.read(GAME),z.read(META))
        fd,tmp=tempfile.mkstemp(prefix='ogs46-',suffix='.ipa',dir=output.parent);os.close(fd)
        try:
            with zipfile.ZipFile(tmp,'w') as out:
                for info in z.infolist():
                    data=prepared if info.filename==GAME else replacement if info.filename==LIB else z.read(info.filename)
                    out.writestr(copy.copy(info),data)
            with zipfile.ZipFile(tmp) as out:
                require(out.namelist()==names and out.testzip() is None,'output integrity')
                for n in names:
                    expected=prepared if n==GAME else replacement if n==LIB else z.read(n)
                    require(out.read(n)==expected,'unexpected output bytes: '+n)
            os.replace(tmp,output)
        finally:
            if os.path.exists(tmp):os.unlink(tmp)
    print('PASS package: seven bridges; all other game bytes preserved; 170 other ZIP entries unchanged')
    print('game',sha(prepared),'dylib',sha(replacement),'IPA',sha(output.read_bytes()))
    print('UNSIGNED candidate. Not verified on iOS or two devices; old embedded signatures are invalid after modification.')
def main():
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('dylib',type=Path);p.add_argument('output',type=Path);a=p.parse_args();package(a.source,a.dylib,a.output)
if __name__=='__main__':main()
