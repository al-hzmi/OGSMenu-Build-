#!/usr/bin/env python3
"""Exact OGS54 -> OGS55 TEST; read-only probes, no gameplay claims. Re-sign required."""
import argparse,copy,hashlib,json,struct,zipfile
from pathlib import Path
from keystone import Ks,KS_ARCH_ARM64,KS_MODE_LITTLE_ENDIAN
from capstone import Cs,CS_ARCH_ARM64,CS_MODE_ARM
from audit_ogs55_defensive import SHA
from package_ogs40_ipa import b_imm,adrp_x16,verify_dylib
BASE=0x100000000
# name, entry, stub, writable callback slot, original instruction text
ENTRIES=[('ExecuteRpc',0x13b8520,0x3380,0x2a98e30,'sub sp, sp, #0xe0'),
 ('PrepareRespawn',0x13f65c0,0x33c0,0x2a98e38,'sub sp, sp, #0x90'),
 ('InternalCacheProperties',0x13d0f70,0x3400,0x2a98e40,'sub sp, sp, #0x60'),
 ('SetCustomProperties',0x13d0cc0,0x3440,0x2a98e48,'stp x28, x27, [sp, #-0x60]!'),
 ('ReceivedRpcDispatch',0x13b77a0,0x3d80,0x2a98e80,'b #0x13b8520')]
# site, object register, value register, offset, width. Captures old value, performs
# ORIGINAL store, then observes. All GPRs/vector registers/NZCV/FPCR/FPSR preserved.
STORES=[(0x141afd4,20,8,0xfd,1),(0x141afec,20,8,0xfd,1),
 (0x13e615c,19,8,0x154,4),(0x13f3b0c,19,20,0x1b0,4),
 (0x13f3b38,8,20,0x14c,4),(0x13f41d8,8,20,0x158,1)]
KS=Ks(KS_ARCH_ARM64,KS_MODE_LITTLE_ENDIAN);CS=Cs(CS_ARCH_ARM64,CS_MODE_ARM)
def asm(s,a):return bytes(KS.asm(s,a)[0])
def sha(b):return hashlib.sha256(b).hexdigest()
def probes(g):
 patches=[]
 for name,entry,stub,slot,ins in ENTRIES:
  original=g[entry:entry+4];decoded=next(CS.disasm(original,entry))
  assert decoded.mnemonic+' '+decoded.op_str==ins,(name,decoded.mnemonic,decoded.op_str)
  relocated=b_imm(stub+20,0x13b8520) if name=='ReceivedRpcDispatch' else struct.unpack('<I',original)[0]
  words=[adrp_x16(stub,slot),0x91000210|((slot&4095)<<10),0xf9400210,0xb4000050,0xd61f0200,relocated,b_imm(stub+24,entry+4)]
  patches.append(dict(name=name,site=entry,stub=stub,slot=slot,original=original.hex(),code=struct.pack('<7I',*words)))
 for idx,(site,obj,val,off,width) in enumerate(STORES):
  stub=0x3480+idx*0x180;slot=0x2a98e50+idx*8
  ins=f'{"strb" if width==1 else "str"} w{val}, [x{obj}, #{off:#x}]'
  original=g[site:site+4];decoded=next(CS.disasm(original,site));assert decoded.mnemonic+' '+decoded.op_str==ins
  s=['sub sp, sp, #0x320']
  s += [f'stp x{i}, x{i+1}, [sp, #{i*8}]' for i in range(0,30,2)]
  s += ['str x30, [sp, #240]','mrs x16, nzcv','str x16, [sp, #248]', 'mrs x16, fpcr','str x16, [sp, #768]','mrs x16, fpsr','str x16, [sp, #776]']
  s += [f'stp q{i}, q{i+1}, [sp, #{256+i*16}]' for i in range(0,32,2)]
  s += [f'{"ldrb" if width==1 else "ldr"} w3, [x{obj}, #{off}]',ins,
        f'mov x0, x{obj}',f'mov w1, w{val}',f'movz w2, #{site&65535}',f'movk w2, #{site>>16}, lsl #16',
        f'adrp x16, #{slot&~4095}',f'ldr x16, [x16, #{slot&4095}]','cbz x16, restore','blr x16','restore:']
  s += [f'ldp q{i}, q{i+1}, [sp, #{256+i*16}]' for i in range(0,32,2)]
  s += ['ldr x16, [sp, #768]','msr fpcr, x16','ldr x16, [sp, #776]','msr fpsr, x16','ldr x16, [sp, #248]','msr nzcv, x16']
  s += [f'ldp x{i}, x{i+1}, [sp, #{i*8}]' for i in range(0,30,2)]
  s += ['ldr x30, [sp, #240]','add sp, sp, #0x320',f'b #{site+4}']
  code=asm(';'.join(s),stub);assert len(code)<=0x180
  patches.append(dict(name='store_'+hex(site),site=site,stub=stub,slot=slot,original=original.hex(),code=code))
 # Prove padding and slots don't overlap mapped sections or commands; unbacked RW DATA.
 c=32;sections=[];rw=None
 for _ in range(struct.unpack_from('<I',g,16)[0]):
  cmd,n=struct.unpack_from('<II',g,c)
  if cmd==25:
   name,vm,vs,fo,fs,mp,prot,ns,flags=struct.unpack_from('<16sQQQQiiII',g,c+8)
   if name.rstrip(b'\0')==b'__DATA':rw=(vm+fs,vm+vs,prot)
   for j in range(ns):
    sn,sg,va,size,off=struct.unpack_from('<16s16sQQI',g,c+72+j*80);sections.append((va,va+size))
  c+=n
 for p in patches:
  s=p['stub'];e=s+len(p['code']);slot=BASE+p['slot']
  assert c<=s and not any(g[s:e]);assert rw and rw[2]&3==3 and rw[0]<=slot<slot+8<=rw[1]
  assert not any(BASE+s<b and a<BASE+e for a,b in sections)
  assert not any(slot<b and a<slot+8 for a,b in sections)
 return patches

def load(source):
 with zipfile.ZipFile(source) as z:
  assert len(set(z.namelist()))==len(z.namelist()) and z.testzip() is None
  for n,h in SHA.items():assert sha(z.read(n))==h,n
  return z.read('Payload/fps.app/fps')
def generate(source,header,evidence):
 g=load(source);ps=probes(g)
 out=['#pragma once','// Generated from exact OGS54 by tools/package_ogs55_test.py.','struct OGS55ProbeBytes { uint32_t site,stub,slot; const uint32_t *words; size_t count; };']
 for i,p in enumerate(ps):
  words=struct.unpack('<'+'I'*(len(p['code'])//4),p['code']);out.append('static const uint32_t ogs55Words%d[]={%s};'%(i,','.join(hex(v)+'u' for v in words)))
 out.append('static const OGS55ProbeBytes ogs55Probes[]={')
 for i,p in enumerate(ps):out.append('{%su,%su,%su,ogs55Words%d,sizeof(ogs55Words%d)/4},'%(hex(p['site']),hex(p['stub']),hex(p['slot']),i,i))
 out.append('};');header.write_text('\n'.join(out)+'\n')
 evidence.write_text(json.dumps([{**p,'code':p['code'].hex()} for p in ps],indent=2))
 return ps

def package(source,lib,output):
 g=load(source);ps=probes(g);patched=bytearray(g)
 for p in ps:
  struct.pack_into('<I',patched,p['site'],b_imm(p['site'],p['stub']));patched[p['stub']:p['stub']+len(p['code'])]=p['code']
 replacement=lib.read_bytes();verify_dylib(replacement);assert source.resolve()!=output.resolve()
 with zipfile.ZipFile(source) as src,zipfile.ZipFile(output,'w') as dst:
  for info in src.infolist():dst.writestr(copy.copy(info),patched if info.filename=='Payload/fps.app/fps' else replacement if info.filename=='Payload/fps.app/Frameworks/OGSMenu.dylib' else src.read(info.filename))
 with zipfile.ZipFile(source) as src,zipfile.ZipFile(output) as dst:
  assert src.namelist()==dst.namelist() and dst.testzip() is None
  for n in src.namelist():
   if n not in ['Payload/fps.app/fps','Payload/fps.app/Frameworks/OGSMenu.dylib']:assert src.read(n)==dst.read(n),n
 print(json.dumps({'test_only':True,'device_tests':'NOT RUN','resign_required':True,'changed_entries':2,'ipa_sha256':sha(output.read_bytes()),'game_sha256':sha(patched),'dylib_sha256':sha(replacement)},indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--generate',type=Path);p.add_argument('--evidence',type=Path);p.add_argument('--dylib',type=Path);p.add_argument('--output',type=Path);a=p.parse_args()
 if a.generate:generate(a.source,a.generate,a.evidence)
 if a.dylib:package(a.source,a.dylib,a.output)
