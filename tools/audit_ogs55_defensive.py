#!/usr/bin/env python3
"""Read-only OGS54 evidence extractor; no network messages or IPA mutation."""
import sys,struct,hashlib,json,re,bisect,csv,zipfile,argparse
from pathlib import Path
from trace_il2cpp_callers import method_map,branch_target,executable_sections
BASE=0x100000000
SHA={'Payload/fps.app/fps':'dbd88b6d645fb31914a7d8445d6370516a3f9db447c44abce826491f1d85712e','Payload/fps.app/Data/Managed/Metadata/global-metadata.dat':'80f36c11ca253385d693a505b2693c442c4e0c981f665e285587c6cfdd403faf','Payload/fps.app/Frameworks/OGSMenu.dylib':'6aaf4743a040a79e21ee848f0d7423fc9cd3c2c64f9d5b40b55b6abb569a6d32'}
def main():
 import capstone
 p=argparse.ArgumentParser();p.add_argument('ipa',type=Path);p.add_argument('output',type=Path);a=p.parse_args();out=a.output;out.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(a.ipa) as z:
  assert len(z.namelist())==len(set(z.namelist())) and z.testzip() is None
  blobs={k:z.read(k) for k in SHA}
 for k,v in blobs.items():assert hashlib.sha256(v).hexdigest()==SHA[k],k
 g,m,d=blobs.values();h=struct.unpack_from('<68I',m);assert h[:2]==(0xfab11baf,24)
 def u(fmt,o,b=g):return struct.unpack_from(fmt,b,o)
 commands=[];sections=[];cursor=32;bounds=[];syms=[]
 for _ in range(u('<I',16)[0]):
  cmd,size=u('<II',cursor);assert size>=8
  commands.append({'command':hex(cmd),'offset':hex(cursor),'size':size})
  if cmd==0x19:
   seg=u('<16sQQQQiiII',cursor+8)
   for j in range(seg[7]):
    sn,sg,va,n,fo=u('<16s16sQQI',cursor+72+j*80)
    sections.append({'segment':sg.rstrip(b'\0').decode(),'section':sn.rstrip(b'\0').decode(),'rva':hex(va-BASE),'size':n,'file_offset':fo})
  if cmd==0x26:
   off,n=u('<II',cursor+8);total=value=shift=0
   for byte in g[off:off+n]:
    value|=(byte&127)<<shift
    if byte&128:shift+=7;continue
    if not value:break
    total+=value;bounds.append(total);value=shift=0
  if cmd==0x2c:assert u('<I',cursor+16)[0]==0,'encrypted executable'
  cursor+=size
 assert bounds and all(x<y for x,y in zip(bounds,bounds[1:]))
 # Checked exact binary plus registration and LC_FUNCTION_STARTS, not old RVA reuse.
 assert u('<QQ',0x232dd80)==(5061,BASE+0x26bea10)
 mm=method_map(g,m);boundset=set(bounds)
 def name(i):
  assert 0<=i<h[7];s=h[6]+i;return m[s:m.index(0,s)].decode()
 typesptr=u('<Q',0x232dd68)[0]-BASE
 primitive={1:'void',2:'bool',3:'char',4:'int8',5:'uint8',6:'int16',7:'uint16',8:'int32',9:'uint32',10:'int64',11:'uint64',12:'float',13:'double',14:'string',24:'intptr',25:'uintptr',28:'object'}
 def typename(idx):
  try:
   ptr=u('<Q',typesptr+idx*8)[0]-BASE;data,bits=u('<QI',ptr);kind=(bits>>16)&255
   if kind in primitive:return primitive[kind]
   if kind in (0x11,0x12):return name(u('<I',h[40]+data*100,m)[0])
   if kind==0x1d:
    dd,bb=u('<QI',data-BASE);kk=(bb>>16)&255
    if kk in primitive:return primitive[kk]+'[]'
    if kk in (0x11,0x12):return name(u('<I',h[40]+dd*100,m)[0])+'[]'
   return f'IL2CPPType(kind=0x{kind:x},index={idx})'
  except (ValueError,struct.error,AssertionError):return f'UNRESOLVED_TYPE_{idx}'
 methods=[]
 for r,rows in sorted(mm.items()):
  for md,label,argc in rows:
   row=u('<11I4H',h[12]+md*52,m);params=[]
   for j in range(argc):
    pn,token,pt=u('<III',h[22]+(row[3]+j)*12,m);params.append({'name':name(pn),'type':typename(pt)})
   methods.append({'rva':hex(r),'metadata_index':md,'name':label,'return':typename(row[2]),'parameters':params,'flags':hex(row[11]),'native_boundary':r in boundset,'confidence':'SOURCE-CONFIRMED metadata/registration; execution untested'})
 fields={}
 for t in range(h[41]//100):
  row=u('<19I8H2I',h[40]+t*100,m);label=name(row[0]);fs={}
  if not re.search(r'PlayerNetwork|RoomController|FPSWeapon|PlayerWeapons|Grenade|C4$|HitBox|GameSettings|Settings|Menu|Pause|PhotonView|PhotonMessageInfo',label):continue
  ptr=u('<Q',0x26bea10+t*8)[0]-BASE
  for j in range(row[21]):
   fn,ft,token=u('<3I',h[24]+12*(row[11]+j),m);fs[name(fn)]={'offset':hex(u('<i',ptr+j*4)[0]),'type':typename(ft)}
  fields[label]={'type_index':t,'fields':fs}
 wanted=re.compile(r'^(RoomUI|PlayerNetwork|RoomController|FPSWeapon|PlayerWeapons|Grenade|C4|HitBox|GameSettings|Scoreboard|TeamExtensions|PunTeams|GameLogic|Weapon|FPSController|NetworkingPeer|PhotonNetwork|PhotonView|PhotonPlayer|LoadBalancingPeer|PhotonHandler|PhotonMessageInfo|WorkerInGame|<PrepareRespawn|<Restart)|Settings|Menu|Pause|Spectat')
 selected={int(x['rva'],16) for x in methods if wanted.search(x['name'])}
 cs=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM);records=[];inbound=[]
 for lo,hi in executable_sections(g):
  for pc in range(lo,hi,4):
   target=branch_target(u('<I',pc)[0],pc)
   if not target or target[0] not in selected:continue
   i=bisect.bisect_right(bounds,pc)-1;caller=bounds[i] if i>=0 else None
   inbound.append({'site':hex(pc),'target':hex(target[0]),'kind':target[1],'caller_rva':hex(caller) if caller else None,'caller':mm.get(caller,[])})
 asm=out/'asm';asm.mkdir(exist_ok=True)
 for start in sorted(selected):
  bi=bisect.bisect_left(bounds,start)
  if bi>=len(bounds)-1 or bounds[bi]!=start:continue
  end=bounds[bi+1];lines=[];calls=[];indirect=[]
  for ins in cs.disasm(g[start:end],start):
   annotation='';target=branch_target(u('<I',ins.address)[0],ins.address)
   if target:
    to,kind=target;annotation=str(mm.get(to,''));calls.append({'site':hex(ins.address),'target':hex(to),'kind':kind,'identities':mm.get(to,[])})
   if ins.mnemonic in ('br','blr'):indirect.append(hex(ins.address))
   lines.append(f'{ins.address:08x} {ins.mnemonic:8s} {ins.op_str} {annotation}')
  filename=f'{start:x}-'+re.sub(r'[^a-zA-Z0-9_.-]','_',mm[start][0][1])+'.asm'
  (asm/filename).write_text('\n'.join(lines)+'\n')
  records.append({'rva':hex(start),'end':hex(end),'identities':mm[start],'calls':calls,'indirect_sites':indirect,'file':'asm/'+filename})
 # Preserve bridge instructions separately; function entry B to padding is not original prologue.
 bridges=[]
 for rec in records:
  r=int(rec['rva'],16);bt=branch_target(u('<I',r)[0],r)
  if bt and bt[1]=='B' and bt[0]<0x43f0:
   s=bt[0];lines=[f'{i.address:08x} {i.mnemonic} {i.op_str}' for i in cs.disasm(g[s:s+32],s)];bridges.append({'method':rec['identities'],'entry':hex(r),'stub':hex(s),'instructions':lines})
 # Dylib symbols allow provenance checks for hooked source without claiming reproducible compilation.
 cursor=32
 for _ in range(u('<I',16,d)[0]):
  cmd,size=u('<II',cursor,d)
  if cmd==2:
   so,n,st,sz=u('<4I',cursor+8,d)
   for j in range(n):
    ni,typ,sect,desc,val=u('<IBBHQ',so+j*16,d)
    if ni and val:
     ns=st+ni;nm=d[ns:d.index(0,ns)].decode(errors='replace');syms.append({'name':nm,'address':hex(val),'type':typ})
  cursor+=size
 data={'input':SHA,'metadata_layout':'24.1/header24','sections':sections,'methods':methods,'fields':fields,'selected_bodies':records,'inbound':inbound,'bridges':bridges,'dylib_symbols':syms,'runtime_verified':False,'limits':['Indirect virtual/reflection targets not resolved','Native function boundaries from LC_FUNCTION_STARTS','No server source or device session','Source candidate commit 277a62d; source-to-binary build provenance not independently attested']}
 (out/'evidence.json').write_text(json.dumps(data,indent=2))
 with (out/'function_map.csv').open('w') as f:
  w=csv.writer(f);w.writerow(['Name','RVA','MetadataIndex','Return','Parameters','NativeBoundary','Evidence','Calls','Callers','IndirectSites'])
  for x in methods:
   r=x['rva']
   if int(r,16) not in selected:continue
   rec=next((y for y in records if y['rva']==r),{})
   w.writerow([x['name'],r,x['metadata_index'],x['return'],'; '.join(p['type']+' '+p['name'] for p in x['parameters']),x['native_boundary'],x['confidence'],'; '.join(c['target'] for c in rec.get('calls',[])),'; '.join(c['site'] for c in inbound if c['target']==r),'; '.join(rec.get('indirect_sites',[]))])
 print(json.dumps({'methods':len(methods),'selected':len(selected),'bodies':len(records),'inbound_edges':len(inbound),'bridges':len(bridges),'dylib_symbols':len(syms),'runtime_verified':False}))
if __name__=='__main__':main()
