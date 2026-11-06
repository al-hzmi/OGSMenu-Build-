#!/usr/bin/env python3
"""Exact OGS50 IL2CPP/ARM64 root-cause audit. Static evidence, never gameplay."""
import argparse,bisect,hashlib,json,struct,zipfile
from pathlib import Path
from trace_il2cpp_callers import method_map,branch_target
from audit_ogs46 import GAME,META,LIB,BASE,require
GAME_SHA='766b1cfe693304faab1160b7696ce803780f0087ca50a17c9d94fc3e73ed10dc'
META_SHA='80f36c11ca253385d693a505b2693c442c4e0c981f665e285587c6cfdd403faf'
LIB_SHA='f4484148e1fbe7a5b5831e2c7ec0a6f0bf2d3130404445b66283fb15379a1b0a'
BRIDGES=(
 ('LoadBalancingPeer.OpSetPropertiesOfActor',31133,0x139231c,0x3280,0x2a98e10,0xd10183ff),
 ('FPSWeapon.FireOneShot',30438,0x137f584,0x32c0,0x2a98e18,0xd102c3ff),
 ('FPSWeapon.GrenadeShootm',30435,0x1381160,0x3300,0x2a98e20,0x6db93bef),
 ('PlayerNetwork.Update',30358,0x13e6060,0x3340,0x2a98e28,0xd10203ff),
)
def sha(b):return hashlib.sha256(b).hexdigest()
def load(path):
 with zipfile.ZipFile(path) as z:
  require(len(z.namelist())==len(set(z.namelist()))==172 and z.testzip() is None,'ZIP integrity')
  g,m,l=(z.read(n) for n in (GAME,META,LIB))
 require((sha(g),sha(m),sha(l))==(GAME_SHA,META_SHA,LIB_SHA),'not exact OGS50 input')
 return g,m

def verify(g,m,out=None):
 from capstone import Cs,CS_ARCH_ARM64,CS_MODE_ARM
 require(sha(g)==GAME_SHA and sha(m)==META_SHA,'unknown native/metadata input')
 require(struct.unpack_from('<II',g)==(0xfeedfacf,0x100000c),'ARM64 Mach-O')
 mm=method_map(g,m);h=struct.unpack_from('<68I',m);cs=Cs(CS_ARCH_ARM64,CS_MODE_ARM)
 pairs=dict(struct.iter_unpack('<II',m[h[50]:h[50]+h[51]]));usage=struct.unpack_from('<Q',g,0x232dda8)[0]-BASE
 def usage_value(slot):
  at=g.find(struct.pack('<Q',BASE+slot));require(at>=usage and (at-usage)%8==0,'usage registration')
  return pairs[(at-usage)//8]
 def literal(slot):
  v=usage_value(slot);require(v>>29==5,'literal usage kind')
  n,o=struct.unpack_from('<II',m,h[2]+8*(v&0x1fffffff));return m[h[4]+o:h[4]+o+n].decode()
 def type_name(slot):
  v=usage_value(slot);require(v>>29==1,'type info usage kind')
  types=struct.unpack_from('<Q',g,0x232dd68)[0]-BASE
  ptr=struct.unpack_from('<Q',g,types+8*(v&0x1fffffff))[0]-BASE
  ti=struct.unpack_from('<Q',g,ptr)[0];ni=struct.unpack_from('<I',m,h[40]+ti*100)[0];p=h[6]+ni
  return m[p:m.index(0,p)].decode()
 require(literal(0x283d770)=='Team' and literal(0x283de90)=='team','case-sensitive keys')
 require(type_name(0x2815340)=='Int32' and type_name(0x2815438)=='Byte','boxed types')
 require(type_name(0x281a3f8)=='Hashtable' and type_name(0x281b898)=='Team','table/enum classes')
 for name,md,entry,stub,slot,prolog in BRIDGES:
  require((md,name,4 if md==31133 else 0) in mm[entry],name+' identity/ABI')
  require(struct.unpack_from('<I',g,entry)[0]==prolog,name+' prologue')
  require(not any(g[stub:stub+64]),name+' stub padding')
 identities={0x1964f6c:(20738,'Camera.WorldToViewportPoint',1),0x173ace4:(27090,'EventData.get_Item',1),0x13d0cc0:(31613,'PhotonPlayer.SetCustomProperties',3),0x13d756c:(31633,'PhotonPlayer.get_customProperties',0),0x173af94:(26804,'Hashtable.get_Item',1),0x173b00c:(26805,'Hashtable.set_Item',2)}
 for a,v in identities.items():require(v in mm[a],'method '+hex(a))
 # These native instructions distinguish value width, dispatch, event identity,
 # List storage, ammo consumption, and the non-optimistic CAS branch.
 checks={
  0x1423374:('ldrb','w0, [x0]'),
  0x1423420:('strb','w20, [sp, #0xb]'),
  0x13f6ad8:('str','w21, [sp, #0xc]'),
  0x13f6aec:('bl','#0x1294484'),
  0x13f6b08:('ldr','x1, [x8, #0x770]'),
  0x13f6b64:('bl','#0x13d0cc0'),
  0x13d0db0:('cbnz','w25, #0x13d0dc0'),
  0x13d0db4:('b','#0x13d0df8'),
  0x13d0de8:('bl','#0x137ab70'),
  0x13d0e48:('bl','#0x139231c'),
  0x13d0e54:('cbz','w8, #0x13d0f54'),
  0x13b6b74:('mov','w1, #0xfd'),0x13b6b98:('mov','w1, #0xfb'),
  0x14877f0:('ldr','w8, [x0, #0x18]'),0x1487804:('ldr','x8, [x20, #0x10]'),
  0x13809f8:('ldr','w8, [x19, #0x12c]'),0x1380a00:('str','w21, [x19, #0x12c]'),
  0x13e6138:('ldr','x1, [x8, #0x770]'),0x13e615c:('str','w8, [x19, #0x154]'),
  0x13b0cbc:('mov','w26, #0xf8'),0x13b0d4c:('bl','#0x13ab2a4'),
 }
 verified={}
 for a,(mn,op) in checks.items():
  i=next(cs.disasm(g[a:a+4],a));require((i.mnemonic,i.op_str)==(mn,op),f'instruction {a:#x}: {i.mnemonic} {i.op_str}')
  verified[hex(a)]=mn+' '+op
 result={'input_game_sha256':GAME_SHA,'metadata_sha256':META_SHA,'input_library_sha256':LIB_SHA,
  'keys':{'0x283d770':'Team (game Int32)','0x283de90':'team (PUN Byte enum)'},
  'checked_instructions':verified,'server_authorization':'NOT VERIFIED','stock_client_gameplay':'NOT RUN'}
 if out:
  out.mkdir(parents=True,exist_ok=True);starts=sorted(mm);graph={}
  wanted=('TeamExtensions.','PhotonPlayer.SetCustomProperties','PhotonPlayer.InternalCacheProperties','LoadBalancingPeer.OpSetPropertiesOfActor','NetworkingPeer.SetMasterClient','PhotonNetwork.SetMasterClient','NetworkingPeer.OnEvent','RoomController.RefreshPlayerList','RoomController.PrepareRespawn','RoomController.OnPhoton','RoomController.SpawnPlayer','RoomController.JoinedTeam','<PrepareRespawnCoroutine>','<Restart','PlayerNetwork.Update','PlayerNetwork.ApplyDamage','PlayerNetwork.DamageRemote','PlayerNetwork.BombDmg','PlayerNetwork.C4Dmg','PlayerNetwork.KillPlayer','FPSWeapon.FireOneShot','FPSWeapon.Fire2','FPSWeapon.GrenadeShootm','PlayerWeapons.SwitchWeaponGrenade','Grenade.','C4.','Camera.WorldToViewportPoint','EventData.get_Item')
  for a in starts:
   rows=mm[a];name=rows[0][1]
   if not any(name.startswith(x) for x in wanted):continue
   end=starts[bisect.bisect_right(starts,a)];lines=[];calls=[]
   for i in cs.disasm(g[a:end],a):
    dest=branch_target(struct.unpack_from('<I',g,i.address)[0],i.address)
    annotation=''
    if dest:
     to,kind=dest;annotation=' '+str(mm.get(to,''));calls.append({'at':hex(i.address),'to':hex(to),'kind':kind,'method':mm.get(to,[])})
    lines.append(f'{i.address:08x} {i.mnemonic:8s} {i.op_str}{annotation}')
   (out/f'{a:x}-{name.replace("/","_")}.asm').write_text('\n'.join(lines)+'\n')
   graph[f'{name}@{a:x}']=calls
  (out/'callgraph.json').write_text(json.dumps(graph,indent=2)+'\n');(out/'evidence.json').write_text(json.dumps(result,indent=2)+'\n')
 return result
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('ipa',type=Path);p.add_argument('--output',type=Path);a=p.parse_args();verify(*load(a.ipa),a.output);print('PASS exact binary identity, case/type root cause, CAS dispatch, List and ammo paths (STATIC ONLY)')
