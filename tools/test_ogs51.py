#!/usr/bin/env python3
"""Native bridge execution and source regression checks; NO live gameplay tests."""
import argparse,struct,subprocess,re
from pathlib import Path
from audit_ogs51 import BRIDGES,load,require
from package_ogs51 import patch
def body(text,name):
 match=re.search(r'\b'+re.escape(name)+r'\([^;{}]*\)\s*\{',text)
 require(match is not None,'function missing '+name)
 start=match.end()-1;depth=1;i=start+1
 while depth:
  depth+=(text[i]=='{')-(text[i]=='}');i+=1
 return text[start:i]
BASELINE='a4f108446190894791845fd5a48921611e851631'

def regression():
 for file,names in {
  'OGSMenu/ModMenu.mm':('OGSProcessSelfNicknameOnPhotonThread','OGSProcessRoomCapacityOnPhotonThread','OGSHasForbiddenNicknameControls','OGSBridgeKillPlayer','OGSBridgeOutgoingDamage','OGS46ShouldBlockSelfDamage'),
  'OGSMenu/OGSGameplayRuntime.h':('fpsUpdate','move','toggleFlight','stopFlight','processSelfRequest'),
 }.items():
  current=Path(file).read_text();old=subprocess.check_output(['git','show',BASELINE+':'+file],text=True)
  for name in names:require(body(current,name)==body(old,name),'changed stable source '+name)
 print('PASS nickname/unicode/capacity, KillPlayer/ApplyDamage, flight/move/toggle and self-transition source unchanged')

def emulate(g):
 from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM
 from unicorn.arm64_const import UC_ARM64_REG_PC,UC_ARM64_REG_SP,UC_ARM64_REG_LR,UC_ARM64_REG_X0,UC_ARM64_REG_Q0
 for name,md,entry,stub,slot,prolog in BRIDGES:
  for installed in (False,True):
   u=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
   for page in {entry&~4095,stub&~4095,slot&~4095,0x5000000,0x6000000}:u.mem_map(page,4096)
   u.mem_write(entry,g[entry:entry+4]);u.mem_write(stub,g[stub:stub+28]);u.mem_write(slot,struct.pack('<Q',0x5000000 if installed else 0))
   u.reg_write(UC_ARM64_REG_SP,0x6000800);u.reg_write(UC_ARM64_REG_LR,0x12345678)
   args=[(UC_ARM64_REG_X0+i,0xabc+i) for i in range(6)]+[(UC_ARM64_REG_Q0+i,0x3f800000+i) for i in range(3)]
   for reg,value in args:u.reg_write(reg,value)
   stop=0x5000000 if installed else entry+4;u.emu_start(entry,stop,count=12)
   require(u.reg_read(UC_ARM64_REG_PC)==stop,name+' destination');require(u.reg_read(UC_ARM64_REG_LR)==0x12345678,name+' LR')
   for reg,value in args:require(u.reg_read(reg)==value,name+' ABI arguments')
   displaced=0x70 if name=='FPSWeapon.GrenadeShootm' else (prolog>>10)&4095
   require(u.reg_read(UC_ARM64_REG_SP)==0x6000800-(0 if installed else displaced),name+' SP')
 print('PASS 8 ARM64 bridge paths: original fallthrough/callback, X0-X5/Q0-Q2/LR/SP preserved')

def cas_branch(g):
 from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM,UC_HOOK_CODE
 from unicorn.arm64_const import UC_ARM64_REG_X0,UC_ARM64_REG_X20,UC_ARM64_REG_X22,UC_ARM64_REG_X24,UC_ARM64_REG_PC
 for count in (0,1):
  u=Uc(UC_ARCH_ARM64,UC_MODE_ARM);u.mem_map(0,((max(len(g),0x2821000)+4095)//4096)*4096);u.mem_write(0,g)
  u.mem_map(0x6000000,4096);u.mem_write(0x281b1c8,struct.pack('<Q',0x6000100))
  u.mem_write(0x6000300,struct.pack('<Q',0x6000100));u.mem_write(0x6000810,struct.pack('<i',2))
  u.reg_write(UC_ARM64_REG_X20,0x6000800);u.reg_write(UC_ARM64_REG_X22,0x6000500)
  u.reg_write(UC_ARM64_REG_X0,0x6000500);u.reg_write(UC_ARM64_REG_X24,0x6000300)
  seen=[]
  def hook(emu,address,size,user):
   if address in (0x13d0d68,0x13d0da8,0x13d0de8,0x13d0df4):
    seen.append(address);emu.reg_write(UC_ARM64_REG_X0,count if address==0x13d0d68 else 0);emu.reg_write(UC_ARM64_REG_PC,address+4)
  u.hook_add(UC_HOOK_CODE,hook);u.emu_start(0x13d0d54,0x13d0df8,count=150)
  require(u.reg_read(UC_ARM64_REG_PC)==0x13d0df8,'CAS native guard completed')
  require((0x13d0de8 in seen)==(count==0),'nonempty expected skips optimistic Merge')
 print('PASS native CAS guard: expected count 1 skips Merge; count 0 enters Merge (external calls stubbed, not networking)')

def main():
 p=argparse.ArgumentParser();p.add_argument('ipa',type=Path);a=p.parse_args();g,m=load(a.ipa);out=patch(g,m)
 intervals=sorted([(b[2],b[2]+4) for b in BRIDGES]+[(b[3],b[3]+28) for b in BRIDGES]);cursor=0
 for lo,hi in intervals:require(g[cursor:lo]==out[cursor:lo],'undeclared bytes');cursor=hi
 require(g[cursor:]==out[cursor:] and len(g)==len(out),'tail/size')
 for changedG,changedM in [(g[:42]+bytes([g[42]^1])+g[43:],m),(g,m[:300]+bytes([m[300]^1])+m[301:])]:
  try:patch(changedG,changedM)
  except ValueError:pass
  else:raise AssertionError('mismatched input accepted')
 print('PASS only four entry/stub spans changed; all old bridges and other native code preserved; tampered input refused')
 emulate(out);cas_branch(g);regression()
if __name__=='__main__':main()
