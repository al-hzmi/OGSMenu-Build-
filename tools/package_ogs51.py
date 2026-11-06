#!/usr/bin/env python3
"""Four verified native bridges on exact OGS50. Never overwrite input. Re-sign output."""
import argparse,copy,os,struct,tempfile,zipfile
from pathlib import Path
from audit_ogs51 import BRIDGES,load,verify,sha,GAME,META,LIB,require
from package_ogs40_ipa import b_imm,adrp_x16,verify_dylib

def padding(g):
 c=32;found=False;ss=min(b[3] for b in BRIDGES);se=max(b[3] for b in BRIDGES)+64
 ds=min(b[4] for b in BRIDGES);de=max(b[4] for b in BRIDGES)+8
 for _ in range(struct.unpack_from('<I',g,16)[0]):
  cmd,size=struct.unpack_from('<II',g,c);require(size>=8 and c+size<=len(g),'load command')
  if cmd==0x19:
   name,vm,vs,fo,fs,mp,prot,ns,flags=struct.unpack_from('<16sQQQQiiII',g,c+8)
   if name.rstrip(b'\0')==b'__DATA':
    require(prot&3==3 and vm+fs<=0x100000000+ds<0x100000000+de<=vm+vs,'writable unbacked slots');found=True
   for j in range(ns):
    sn,seg,va,n,off=struct.unpack_from('<16s16sQQI',g,c+72+j*80)
    require(not(n and 0x100000000+ds<va+n and va<0x100000000+de),'slot overlaps section')
    require(not(n and 0x100000000+ss<va+n and va<0x100000000+se),'stub overlaps section')
  c+=size
 require(found and c<=ss,'padding boundaries')

def patch(g,m):
 verify(g,m);padding(g);out=bytearray(g)
 for name,md,entry,stub,slot,prolog in BRIDGES:
  words=[adrp_x16(stub,slot),0x91000210|((slot&4095)<<10),0xf9400210,0xb4000050,0xd61f0200,prolog,b_imm(stub+24,entry+4)]
  struct.pack_into('<7I',out,stub,*words);struct.pack_into('<I',out,entry,b_imm(entry,stub))
 return bytes(out)

def package(source,lib,output):
 require(source.resolve()!=output.resolve(),'cannot overwrite source')
 g,m=load(source);prepared=patch(g,m);replacement=lib.read_bytes();verify_dylib(replacement)
 output.parent.mkdir(parents=True,exist_ok=True)
 fd,tmp=tempfile.mkstemp(prefix='ogs51-',suffix='.ipa',dir=output.parent);os.close(fd)
 try:
  with zipfile.ZipFile(source) as src:
   with zipfile.ZipFile(tmp,'w') as dest:
    for info in src.infolist():dest.writestr(copy.copy(info),prepared if info.filename==GAME else replacement if info.filename==LIB else src.read(info.filename))
   with zipfile.ZipFile(tmp) as dest:
    require(dest.namelist()==src.namelist() and dest.testzip() is None,'output ZIP integrity')
    for n in src.namelist():require(dest.read(n)==(prepared if n==GAME else replacement if n==LIB else src.read(n)),'unexpected bytes '+n)
  os.replace(tmp,output)
 finally:
  if os.path.exists(tmp):os.unlink(tmp)
 print('PASS OGS51: four native entries/bridges, dylib replaced, 170 other entries byte-identical')
 print('game',sha(prepared),'dylib',sha(replacement),'IPA',sha(output.read_bytes()))
 print('UNSIGNED CANDIDATE; retained old embedded signatures INVALID. Full app and nested library re-sign required. No device tests.')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('dylib',type=Path);p.add_argument('output',type=Path);a=p.parse_args();package(a.source,a.dylib,a.output)
