#!/usr/bin/env python3
"""Exact-binary tests + ARM64 bridge execution under Unicorn; not gameplay."""
import argparse, struct, subprocess, sys
from pathlib import Path
from audit_ogs46 import load_ipa, BRIDGES, require
from package_ogs46 import patch

def native_bridge_test(g):
    from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM
    from unicorn.arm64_const import UC_ARM64_REG_PC, UC_ARM64_REG_SP, UC_ARM64_REG_LR, UC_ARM64_REG_X0, UC_ARM64_REG_X1, UC_ARM64_REG_X2, UC_ARM64_REG_Q0, UC_ARM64_REG_Q1, UC_ARM64_REG_Q2
    for name,md,entry,stub,slot,prolog in BRIDGES:
        for installed in (False,True):
            u=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
            for page in {entry&~4095,stub&~4095,slot&~4095,0x5000000,0x6000000}:
                u.mem_map(page,4096)
            u.mem_write(entry,g[entry:entry+4]);u.mem_write(stub,g[stub:stub+28])
            u.mem_write(slot,struct.pack('<Q',0x5000000 if installed else 0))
            u.reg_write(UC_ARM64_REG_SP,0x6000800);u.reg_write(UC_ARM64_REG_LR,0x12345678)
            for reg,v in [(UC_ARM64_REG_X0,0xabc),(UC_ARM64_REG_X1,0xdef),(UC_ARM64_REG_X2,0x123),(UC_ARM64_REG_Q0,0x3f800000),(UC_ARM64_REG_Q1,0x40000000),(UC_ARM64_REG_Q2,0x40400000)]:u.reg_write(reg,v)
            stop=0x5000000 if installed else entry+4
            u.emu_start(entry,stop,count=12)
            require(u.reg_read(UC_ARM64_REG_PC)==stop,name+' branch destination')
            require(u.reg_read(UC_ARM64_REG_LR)==0x12345678,name+' LR preserved')
            for reg,v in [(UC_ARM64_REG_X0,0xabc),(UC_ARM64_REG_X1,0xdef),(UC_ARM64_REG_X2,0x123),(UC_ARM64_REG_Q0,0x3f800000),(UC_ARM64_REG_Q1,0x40000000),(UC_ARM64_REG_Q2,0x40400000)]:require(u.reg_read(reg)==v,name+' ABI arguments')
            if installed:require(u.reg_read(UC_ARM64_REG_SP)==0x6000800,name+' callback stack')
            else:
                expected=0x40 if name=='RoomController.Update' else (prolog>>10)&0xfff
                require(u.reg_read(UC_ARM64_REG_SP)==0x6000800-expected,name+' displaced stack prologue')
    print('PASS 14 ARM64 bridge paths: empty-slot fallback + callback, LR/stack/integer/vector ABI preserved')

def body(text,name):
    # Exact source body comparison for unchanged stable entry points.
    start=text.index(name+'(');start=text.index('{',start);depth=1;i=start+1
    while depth:
        depth+=(text[i]=='{')-(text[i]=='}');i+=1
    return text[start:i]

def regression():
    source=Path('OGSMenu/ModMenu.mm').read_text()
    baseline=subprocess.check_output(['git','show','db904e127c3232211e7946a81f9d226acc492a36:OGSMenu/ModMenu.mm'],text=True)
    for n in ('OGSProcessSelfNicknameOnPhotonThread','OGSProcessRoomCapacityOnPhotonThread','OGSHasForbiddenNicknameControls','OGSBridgeKillPlayer'):
        require(body(source,n)==body(baseline,n),'regression source changed: '+n)
    print('PASS nickname/unicode/capacity and KillPlayer original forwarding unchanged (source comparison, not runtime)')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('ipa',type=Path);a=ap.parse_args();g,m=load_ipa(a.ipa);out=patch(g,m)
    intervals=[(entry,entry+4) for _,_,entry,_,_,_ in BRIDGES]+[(stub,stub+28) for _,_,_,stub,_,_ in BRIDGES]
    require(len(g)==len(out),'length')
    require(all(x==y or any(lo<=i<hi for lo,hi in intervals) for i,(x,y) in enumerate(zip(g,out))),'unrelated executable mutation')
    for off in (0x13e8fbc,0x13e9008,0x13e9130,0x13f65c0,0x3000,0x3040,0x3080):require(g[off:off+28]==out[off:off+28],'existing path modified')
    for badg,badm in ((g[:42]+bytes([g[42]^1])+g[43:],m),(g,m[:300]+bytes([m[300]^1])+m[301:])):
        try:patch(badg,badm)
        except ValueError:pass
        else:raise AssertionError('mutated fingerprint accepted')
    print('PASS exact-input refusal + only declared patch spans + unchanged old bridges/death/respawn')
    native_bridge_test(out);regression()
if __name__=='__main__':main()
