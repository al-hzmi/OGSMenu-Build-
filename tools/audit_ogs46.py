#!/usr/bin/env python3
"""Reproducible exact-input IL2CPP/ARM64 evidence. No runtime claims.

Metadata layout reference: Perfare/Il2CppDumper MetadataClass.cs, v24.1.
Addresses are resolved from registration tables in this SHA-pinned executable.
"""
import argparse, bisect, hashlib, json, struct, zipfile
from pathlib import Path
from trace_il2cpp_callers import method_map, branch_target, executable_sections

GAME = 'Payload/fps.app/fps'
META = 'Payload/fps.app/Data/Managed/Metadata/global-metadata.dat'
LIB = 'Payload/fps.app/Frameworks/OGSMenu.dylib'
GAME_SHA = 'e46148304090f8de5a4fadb009883d0e7a2e0c5541e8628261164b6457b735b2'
META_SHA = '80f36c11ca253385d693a505b2693c442c4e0c981f665e285587c6cfdd403faf'
LIB_SHA = '37cfb06b9a08370acd3417efccc3fada787dd69359fe0e6ef9189aa94733233b'
BASE = 0x100000000
# Native fieldOffsets registration: type count=5061, pointer=0x1026bea10.
FIELD_TABLE = 0x26bea10
BRIDGES = (
 ('PlayerNetwork.BombDmg',30370,0x13e7db0,0x30c0,0x2a98dd8,0xd10183ff),
 ('PlayerNetwork.BombDmgLong',30371,0x13e815c,0x3100,0x2a98de0,0xd10183ff),
 ('PlayerNetwork.C4Dmg',30372,0x13e8508,0x3140,0x2a98de8,0xd10143ff),
 ('PlayerNetwork.C4DmgLong',30373,0x13e88a4,0x3180,0x2a98df0,0xd10143ff),
 ('RoomController.Update',30037,0x13f3f2c,0x31c0,0x2a98df8,0x6dbc23e9),
 ('FPSController.Update',30314,0x137be64,0x3200,0x2a98e00,0xd10303ff),
 ('CharacterController.Move',23735,0x19bb3b4,0x3240,0x2a98e08,0xd10083ff),
)

def sha(b): return hashlib.sha256(b).hexdigest()
def require(ok, msg):
    if not ok: raise ValueError(msg)
def load_ipa(path):
    with zipfile.ZipFile(path) as z:
        require(len(set(z.namelist())) == len(z.namelist()), 'duplicate ZIP members')
        require(z.testzip() is None, 'ZIP CRC failed')
        g,m,l = (z.read(n) for n in (GAME,META,LIB))
    require(sha(g)==GAME_SHA and sha(m)==META_SHA and sha(l)==LIB_SHA,'input fingerprint differs')
    return g,m

def metadata(g,m):
    h=struct.unpack_from('<68I',m)
    require(h[:2]==(0xfab11baf,24),'metadata version')
    require(struct.unpack_from('<QQ',g,0x232dd80)==(5061,BASE+FIELD_TABLE),'field registration')
    def name(i):
        require(0<=i<h[7],'string index');start=h[6]+i
        return m[start:m.index(0,start)].decode()
    types={}
    for t in range(h[41]//100):
        row=struct.unpack_from('<19I8H2I',m,h[40]+t*100)
        label=name(row[0]);fields={}
        if label not in ('RoomController','FPSController','PlayerNetwork','GameSettings','Scoreboard','PunTeams','Object'):continue
        p=struct.unpack_from('<Q',g,FIELD_TABLE+t*8)[0]-BASE
        for j in range(row[21]):
            fi=struct.unpack_from('<3I',m,h[24]+12*(row[11]+j))
            fields[name(fi[0])]=struct.unpack_from('<i',g,p+j*4)[0]
        types[label]={'type_index':t,'fields':fields}
    pairs=dict(struct.iter_unpack('<II',m[h[50]:h[50]+h[51]]))
    usage=struct.unpack_from('<Q',g,0x232dda8)[0]-BASE
    literals={}
    for slot in (0x283d768,0x283d770,0x283be98,0x283c3f8,0x283bdd0,0x283d778,0x283d7a8,0x283d9c0):
        at=g.find(struct.pack('<Q',BASE+slot));require(at>=usage,'usage pointer')
        v=pairs[(at-usage)//8];require(v>>29==5,'literal kind')
        length,start=struct.unpack_from('<II',m,h[2]+8*(v&0x1fffffff))
        literals[hex(slot)]=m[h[4]+start:h[4]+start+length].decode()
    return types,literals

def verify(g,m):
    require(sha(g)==GAME_SHA and sha(m)==META_SHA,'unknown executable/metadata')
    require(struct.unpack_from('<II',g)==(0xfeedfacf,0x100000c),'Mach-O ARM64')
    mm=method_map(g,m);types,literals=metadata(g,m)
    for name,md,entry,stub,slot,prolog in BRIDGES:
        require((md,name,1 if name.endswith(('BombDmg','BombDmgLong','.Move')) else 0) in mm[entry],name+' identity/ABI')
        require(struct.unpack_from('<I',g,entry)[0]==prolog,name+' prolog')
        require(not any(g[stub:stub+64]),name+' occupied stub')
    expected={'FPSController':{'gravity':0x3c,'airControl':0x4c,'pn':0x60,'moveDirection':0x7c,'controller':0x90,'myTransform':0x98,'fallStartLevel':0xcc,'falling':0xd0,'currentLadder':0x108},
      'RoomController':{'ourTeam':0x1b0,'meTeam':0x1b4,'ourPlayer':0x108,'currentRespawnTime':0x1c0,'currentGameMode':0x1b8},
      'PlayerNetwork':{'fpsController':0xf8,'playerKilled':0x12c,'Counter':0x28,'Teror':0x30},
      'GameSettings':{'rc':0x30,'menuOpened':0x158}}
    for typ,fields in expected.items():
        for name,off in fields.items():require(types[typ]['fields'][name]==off,f'{typ}.{name}')
    # Both the displaced instruction and mandatory lifecycle call must survive.
    require(branch_target(struct.unpack_from('<I',g,0x13e9130)[0],0x13e9130)==(0x13f65c0,'BL'),'KillPlayer respawn call')
    require(struct.unpack_from('<II',g,0x13e9008)==(0x52800028,0x3904b268),'death state writes')
    return mm,types,literals

def main():
    ap=argparse.ArgumentParser();ap.add_argument('ipa',type=Path);ap.add_argument('output',type=Path);a=ap.parse_args()
    g,m=load_ipa(a.ipa);mm,types,literals=verify(g,m);a.output.mkdir(parents=True,exist_ok=True)
    import capstone
    cs=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM)
    # LC_FUNCTION_STARTS supplies native boundaries; never attribute a call to
    # the nearest method across unmapped helper functions.
    cursor=32;boundaries=[]
    for _ in range(struct.unpack_from('<I',g,16)[0]):
        cmd,size=struct.unpack_from('<II',g,cursor)
        if cmd==0x26:
            off,n=struct.unpack_from('<II',g,cursor+8);total=0;value=shift=0
            for byte in g[off:off+n]:
                value|=(byte&127)<<shift
                if byte&128:shift+=7;continue
                if not value:break
                total+=value;boundaries.append(total);value=shift=0
        cursor+=size
    require(boundaries,'function starts missing')
    selected={r for r,rows in mm.items() if any(n.startswith(('PlayerNetwork.','RoomController.','FPSController.','Scoreboard.','Grenade.','C4.','HitBox.','PunTeams.','TeamExtensions.','<PrepareRespawnCoroutine>')) or n in ('CharacterController.Move','PhotonView.RPC','PhotonView.get_isMine','PhotonPlayer.SetCustomProperties','PhotonNetwork.get_isMasterClient') for _,n,_ in rows)}
    # Direct inbound edges from ALL executable sections, including callers
    # outside the selected gameplay classes. Native helpers stay unidentified.
    inbound=[]; hp_refs=[]
    for lo,hi in executable_sections(g):
        for pc in range(lo,hi,4):
            w=struct.unpack_from('<I',g,pc)[0];target=branch_target(w,pc)
            i=bisect.bisect_right(boundaries,pc)-1
            caller=boundaries[i] if i>=0 else None
            if target and target[0] in selected:
                inbound.append({'site':hex(pc),'target':hex(target[0]),'kind':target[1],
                                'caller_rva':hex(caller) if caller else None,'caller':mm.get(caller,[])})
            # ADRP + short LDR/ADD references are candidates, not proof that
            # every alias/indirect/computed access to PlayerHP was found.
            if w&0x9f000000!=0x90000000:continue
            rd=w&31;imm=((w>>29)&3)|(((w>>5)&0x7ffff)<<2)
            if imm&(1<<20):imm-=1<<21
            page=(pc&~4095)+(imm<<12)
            if page!=0x283d000:continue
            for q in range(pc+4,min(pc+24,hi),4):
                ins=struct.unpack_from('<I',g,q)[0]
                is_ldr=ins&0xffc00000==0xf9400000 and ((ins>>5)&31)==rd
                is_add=ins&0xffc00000==0x91000000 and ((ins>>5)&31)==rd and (ins&31)==rd
                if (is_ldr and page+((ins>>10)&4095)*8==0x283d768) or (is_add and page+((ins>>10)&4095)==0x283d768):
                    hp_refs.append({'site':hex(q),'caller':mm.get(caller,[])})
    records=[]
    for start in sorted(selected):
        i=bisect.bisect_left(boundaries,start)
        require(i<len(boundaries) and boundaries[i]==start,'method is not a native function boundary')
        end=boundaries[i+1];lines=[];calls=[];branches=[];indirect=[]
        for ins in cs.disasm(g[start:end],start):
            annotation=''
            if ins.mnemonic in ('b','bl'):
                target=int(ins.op_str.removeprefix('#'),16);annotation=str(mm.get(target,''))
                calls.append({'site':hex(ins.address),'kind':ins.mnemonic,'target':hex(target),'identities':mm.get(target,[])})
            if ins.mnemonic in ('blr','br'):indirect.append(hex(ins.address))
            if ins.mnemonic.startswith('b.') or ins.mnemonic in ('cbz','cbnz','tbz','tbnz'):
                branches.append({'site':hex(ins.address),'op':ins.mnemonic,'operands':ins.op_str})
            lines.append(f'{ins.address:08x} {ins.mnemonic:8s} {ins.op_str} '+annotation)
        label=mm[start][0][1].replace('/','_')
        (a.output/(label+'.asm')).write_text('\n'.join(lines)+'\n')
        records.append({'rva':hex(start),'end':hex(end),'identities':mm[start],'direct_edges':calls,'conditional_edges':branches,'indirect_sites':indirect})
    report={'input_sha256':GAME_SHA,'metadata_sha256':META_SHA,'metadata_layout':'24.1 (header reports 24)', 'fields':types,'literals':literals,'methods':records,'all_direct_inbound_edges':inbound,'PlayerHP_reference_candidates':hp_refs,'runtime_verified':False,
      'limits':'Static control-flow and table identities; runtime virtual targets, Photon acceptance, installation and two-device behavior require device testing.'}
    (a.output/'evidence.json').write_text(json.dumps(report,indent=2))
    print(f'PASS: {len(records)} native method bodies, registration fields, literals, seven bridge identities and existing death lifecycle')
if __name__=='__main__':main()
