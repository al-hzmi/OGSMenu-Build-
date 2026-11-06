#!/usr/bin/env python3
"""Exact OGS41 metadata evidence for the OGS47 cooperative team protocol."""
import argparse, json, struct
from pathlib import Path
from audit_ogs46 import load_ipa, verify, require, BASE

def audit(ipa):
    g,m=load_ipa(ipa);mm,_,_=verify(g,m);h=struct.unpack_from('<68I',m)
    expected={0x13d6d08:(31614,'PhotonPlayer.Find',1),
              0x13d694c:(31602,'PhotonPlayer.get_IsInactive',0),
              0x13d756c:(31633,'PhotonPlayer.get_customProperties',0),
              0x173af94:(26804,'Hashtable.get_Item',1),
              0x173b00c:(26805,'Hashtable.set_Item',2),
              0x173aee4:(26802,'Hashtable..ctor',0),
              0x13d0cc0:(31613,'PhotonPlayer.SetCustomProperties',3),
              0x13f65c0:(30044,'RoomController.PrepareRespawn',3)}
    for r,v in expected.items():require(v in mm[r],f'method/ABI {v}')
    def name(i):p=h[6]+i;return m[p:m.index(0,p)].decode()
    image=None
    for off in range(h[44],h[44]+h[45],40):
        row=struct.unpack_from('<10I',m,off)
        if name(row[0])=='Assembly-CSharp.dll':image=row
    require(image is not None,'image')
    attrs={token:struct.unpack_from('<'+'I'*n,m,h[58]+start*4)
           for token,start,n in struct.iter_unpack('<III',m[h[56]+image[8]*12:h[56]+(image[8]+image[9])*12])}
    count,table=struct.unpack_from('<QQ',g,0x232dd60)
    require(count==26433,'type registration')
    def typeName(t):
        ptr=struct.unpack_from('<Q',g,table-BASE+t*8)[0]
        index=struct.unpack_from('<Q',g,ptr-BASE)[0]
        return name(struct.unpack_from('<I',m,h[40]+index*100)[0])
    require(typeName(11170)=='PunRPC','RPC attribute identity')
    result={}
    for md in [30044,30056,30058,30369,30380]:
        row=struct.unpack_from('<11I4H',m,h[12]+md*52)
        result[name(row[0])]=[typeName(a) for a in attrs.get(row[10],())]
    require('PunRPC' not in result['PrepareRespawn'],'unexpected remote respawn')
    require('PunRPC' not in result['JoinedTeam'],'unexpected remote join')
    require('PunRPC' in result['PostActivityRemote'] and 'PunRPC' in result['KillPlayer'],'positive RPC controls')
    # Hashtable type slot and constructor are used by the native SetTeam path.
    require(struct.unpack_from('<I',g,0x142340c)[0]==0xf941fd00,'Hashtable type load')
    return {'methods':{hex(k):v for k,v in expected.items()},'attributes':result,
            'finding':'PrepareRespawn and JoinedTeam are not registered PunRPC methods. OGS47 therefore executes the native transition on the consenting target device.',
            'runtime_verified':False}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('ipa',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
    result=audit(a.ipa);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2));print('PASS metadata identities, RPC positive/negative controls and native Hashtable path')
