"""ARM64 emulation, NOT iOS gameplay: preserve all registers/flags and store once."""
import sys,json,random,struct
from pathlib import Path
from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM,UC_HOOK_CODE,UC_HOOK_MEM_WRITE
from unicorn.arm64_const import *
ps=json.loads(Path(sys.argv[1]).read_text())
reg=[getattr(__import__('unicorn.arm64_const',fromlist=['']),f'UC_ARM64_REG_X{i}') for i in range(31)]
qreg=[getattr(__import__('unicorn.arm64_const',fromlist=['']),f'UC_ARM64_REG_Q{i}') for i in range(32)]
for p in ps[4:]:
 for enabled in [False,True]:
  for seed in range(8):
   r=random.Random(seed);u=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
   for a,n in [(0,0x10000),(0x1300000,0x200000),(0x2a98000,0x2000),(0x4000000,0x10000),(0x5000000,0x10000),(0x6000000,0x1000)]:u.mem_map(a,n)
   u.mem_write(p['stub'],bytes.fromhex(p['code']));u.mem_write(0x6000000,bytes.fromhex('c0035fd6'))
   u.mem_write(p['slot'],struct.pack('<Q',0x6000000 if enabled else 0))
   original=struct.unpack('<I',bytes.fromhex(p['original']))[0];obj=(original>>5)&31;val=original&31;width=1 if original>>30==0 else 4;off=((original>>10)&4095)*width
   initial=[r.getrandbits(64) for _ in reg];initial[obj]=0x5001000;initial[val]=r.randrange(0,3)
   for rr,v in zip(reg,initial):u.reg_write(rr,v)
   qs=[r.getrandbits(128) for _ in qreg]
   for rr,v in zip(qreg,qs):u.reg_write(rr,v)
   sp=0x400f000;u.reg_write(UC_ARM64_REG_SP,sp);u.reg_write(UC_ARM64_REG_NZCV,0xa0000000);u.reg_write(UC_ARM64_REG_FPCR,0x400000);u.reg_write(UC_ARM64_REG_FPSR,0x10)
   old=2;u.mem_write(initial[obj]+off,old.to_bytes(width,'little'));calls=[];writes=[]
   def code(uc,addr,size,data):
    if addr==0x6000000:
     calls.append([uc.reg_read(rr) for rr in reg[:4]])
     # Deliberately clobber ALL registers except SP/LR to stress preservation.
     for rr in reg[:30]:uc.reg_write(rr,0xdead)
     for rr in qreg:uc.reg_write(rr,0xbeef)
     uc.reg_write(UC_ARM64_REG_NZCV,0);uc.reg_write(UC_ARM64_REG_FPCR,0);uc.reg_write(UC_ARM64_REG_FPSR,0)
   def write(uc,access,addr,size,value,data):
    if addr==initial[obj]+off:writes.append(value)
   u.hook_add(UC_HOOK_CODE,code);u.hook_add(UC_HOOK_MEM_WRITE,write)
   u.emu_start(p['stub'],p['site']+4,count=500)
   assert u.reg_read(UC_ARM64_REG_PC)==p['site']+4
   assert [u.reg_read(rr) for rr in reg]==initial
   assert [u.reg_read(rr) for rr in qreg]==qs
   assert u.reg_read(UC_ARM64_REG_SP)==sp
   assert u.reg_read(UC_ARM64_REG_NZCV)==0xa0000000 and u.reg_read(UC_ARM64_REG_FPCR)==0x400000 and u.reg_read(UC_ARM64_REG_FPSR)==0x10
   assert writes==[initial[val]]
   assert calls==([[initial[obj],initial[val],p['site'],old]] if enabled else [])
print('PASS 96 ARM64 store probe cases: callback on/off, exact one write, arguments, x0-x30/q0-q31/SP/NZCV/FPCR/FPSR preserved. NOT iOS runtime.')
