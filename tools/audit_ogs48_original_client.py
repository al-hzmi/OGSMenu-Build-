#!/usr/bin/env python3
"""Read-only native ABI/call-graph evidence for the OGS48 original-client test.

This proves the local call path exists in the exact OGS46 binary. It cannot
prove that Photon accepts SetCustomProperties targeting a different actor, or
that the unmodified recipient adopts the requested team after a round change.
"""
import argparse
import hashlib
import json
import struct
import zipfile
from pathlib import Path

GAME = 'Payload/fps.app/fps'
META = 'Payload/fps.app/Data/Managed/Metadata/global-metadata.dat'
GAME_SHA = '766b1cfe693304faab1160b7696ce803780f0087ca50a17c9d94fc3e73ed10dc'
META_SHA = '80f36c11ca253385d693a505b2693c442c4e0c981f665e285587c6cfdd403faf'
METHOD_TABLE = 0x2358400
BASE = 0x100000000
CHECKS = {
    31982: ('TeamExtensions', 'GetTeam', 0x14232D8),
    31983: ('TeamExtensions', 'SetTeam', 0x1423388),
    31613: ('PhotonPlayer', 'SetCustomProperties', 0x13D0CC0),
    31977: ('PunTeams', 'OnPhotonPlayerPropertiesChanged', 0x13ECFC0),
    31980: ('PunTeams', 'UpdateTeams', 0x13ECCC0),
}


def read_name(m, h, ix):
    start = h[6] + ix
    return m[start:m.index(b'\0', start)].decode()


def method(g, m, h, index):
    row = struct.unpack_from('<11I4H', m, h[12] + index*52)
    typ = struct.unpack_from('<I', m, h[40] + row[1]*100)[0]
    address = struct.unpack_from('<Q', g, METHOD_TABLE + 8*row[5])[0]
    return read_name(m, h, typ), read_name(m, h, row[0]), address-BASE


def branches(g, start, stop):
    result = set()
    for pc in range(start, stop, 4):
        w = struct.unpack_from('<I', g, pc)[0]
        op = w & 0xFC000000
        if op not in (0x14000000, 0x94000000):
            continue
        d = w & 0x3FFFFFF
        if d & (1 << 25):
            d -= 1 << 26
        result.add((pc, pc + d*4, 'BL' if op == 0x94000000 else 'B'))
    return result


def audit(ipa):
    with zipfile.ZipFile(ipa) as z:
        assert len(z.namelist()) == len(set(z.namelist()))
        assert z.testzip() is None
        g, m = z.read(GAME), z.read(META)
    assert hashlib.sha256(g).hexdigest() == GAME_SHA, 'unsupported native executable'
    assert hashlib.sha256(m).hexdigest() == META_SHA, 'unsupported IL2CPP metadata'
    h = struct.unpack_from('<68I', m)
    assert h[:2] == (0xFAB11BAF, 24), 'unsupported metadata layout'
    for index, expected in CHECKS.items():
        assert method(g, m, h, index) == expected, f'method identity/ABI {index}'
    setter_calls = branches(g, 0x1423388, 0x1423534)
    assert any(dest == 0x14232D8 and kind == 'BL' for _, dest, kind in setter_calls)
    assert any(dest == 0x13D0CC0 and kind == 'BL' for _, dest, kind in setter_calls)
    update_calls = branches(g, 0x13ECFC0, 0x13ECFC4)
    assert any(dest == 0x13ECCC0 for _, dest, _ in update_calls)
    # There is no direct MasterClient getter call in the SetTeam method body.
    # This is NOT a claim that the Photon server accepts another-actor writes.
    return {'source_sha256': GAME_SHA, 'metadata_sha256': META_SHA,
            'verified_methods': {str(i): f'{t}.{n}@{rva:#x}'
                                 for i, (t, n, rva) in CHECKS.items()},
            'setteam_calls_getteam': True,
            'setteam_calls_photonplayer_setcustomproperties': True,
            'punteams_property_callback_calls_updateteams': True,
            'server_acceptance_verified': False,
            'unmodified_recipient_verified': False}


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('input_ipa', type=Path)
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    result = audit(a.input_ipa)
    if a.output:
        a.output.write_text(json.dumps(result, indent=2) + '\n')
    print('PASS exact native TeamExtensions/PhotonPlayer/PunTeams identities and calls')
