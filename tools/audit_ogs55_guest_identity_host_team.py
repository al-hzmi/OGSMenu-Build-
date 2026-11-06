#!/usr/bin/env python3
"""Reproducible, read-only iOS IL2CPP evidence for guest identity/Team writes.

Usage: python3 tools/audit_ogs55_guest_identity_host_team.py OGS54.ipa

This examines *direct* ARM64 branches, not every indirect/reflection call, and
does not infer which remote peer caused a network event or claim server proof.
"""

import argparse
import bisect
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path

import trace_il2cpp_callers as trace


KNOWN_GAME_HASHES = {
    "766b1cfe693304faab1160b7696ce803780f0087ca50a17c9d94fc3e73ed10dc",
    "dbd88b6d645fb31914a7d8445d6370516a3f9db447c44abce826491f1d85712e",
}

INDEX = {
    "join_coroutine": 30003,
    "room_options_ctor": 31178,
    "publish_id_setter": 31158,
    "publish_id_alias": 31177,
    "auth_user_id_setter": 31198,
    "photon_user_id_getter": 31599,
    "player_properties_setter": 31613,
    "team_setter": 31983,
    "prepare_respawn": 30044,
    "spawn_player": 30046,
    "properties_changed_callback": 30050,
}


def method_rva(game, metadata, index):
    header = trace.unpack("<60I", metadata, 0)
    if header[0] != 0xFAB11BAF or header[1] != 24:
        raise ValueError("Unsupported metadata header")
    offset = header[12] + 52 * index
    row = trace.unpack("<11I4H", metadata, offset)
    name = trace.name_at(metadata, header[6], row[0])
    ptr = trace.unpack("<Q", game, trace.METHOD_TABLE_RVA + 8 * row[5])[0]
    if not trace.IMAGE_BASE <= ptr < trace.IMAGE_BASE + len(game):
        raise ValueError(f"Invalid method table pointer for {index}")
    return ptr - trace.IMAGE_BASE, name


def direct_calls(game, methods, targets):
    labels = sorted(methods)
    output = []
    for start, end in trace.executable_sections(game):
        for pc in range(start, end, 4):
            word = struct.unpack_from("<I", game, pc)[0]
            branch = trace.branch_target(word, pc)
            if branch is None or branch[0] not in targets:
                continue
            nearest = bisect.bisect_right(labels, pc) - 1
            owner = methods[labels[nearest]][0][1] if nearest >= 0 else "unknown"
            output.append({"rva": f"0x{pc:x}", "method": owner,
                           "target": targets[branch[0]], "branch": branch[1]})
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path, help="An OGS49/OGS54 compatible iOS IPA")
    args = parser.parse_args()
    with zipfile.ZipFile(args.ipa) as ipa:
        game = ipa.read("Payload/fps.app/fps")
        metadata = ipa.read("Payload/fps.app/Data/Managed/Metadata/global-metadata.dat")
    digest = hashlib.sha256(game).hexdigest()
    if digest not in KNOWN_GAME_HASHES:
        raise ValueError(f"Unreviewed executable SHA256 {digest}; no offset assumptions")

    found = {name: method_rva(game, metadata, index)
             for name, index in INDEX.items()}
    if found["photon_user_id_getter"][1] != "get_UserId":
        raise ValueError("PhotonPlayer.get_UserId method identity changed")
    if (found["publish_id_setter"][1] != "set_PublishUserId" or
            found["publish_id_alias"][1] != "set_publishUserId" or
            found["auth_user_id_setter"][1] != "set_UserId" or
            found["player_properties_setter"][1] != "SetCustomProperties"):
        raise ValueError("One of the audited IL2CPP method identities changed")
    if struct.unpack_from("<I", game, found["photon_user_id_getter"][0])[0] != 0xF9401000:
        raise ValueError("PhotonPlayer.UserId field is no longer at +0x20")

    # A caller scan is limited to direct BL/B instructions. Dynamic dispatch
    # and arbitrary direct field writes are NOT excluded by an empty result.
    scanned = trace.method_map(game, metadata)
    targets = {rva: name for name, (rva, _) in found.items()
               if name in {"publish_id_setter", "publish_id_alias",
                           "auth_user_id_setter", "player_properties_setter",
                           "team_setter", "room_options_ctor"}}
    calls = direct_calls(game, scanned, targets)
    select = lambda name: [row for row in calls if row["target"] == name]
    publish = select("publish_id_setter") + select("publish_id_alias")
    auth = select("auth_user_id_setter")
    props = select("player_properties_setter")
    ctor_callers = select("room_options_ctor")
    game_auth_callers = [row for row in auth if row["method"].startswith(
        ("ConnectMenu.", "RoomController.", "PlayerNetwork."))]
    game_room_construction = [row for row in ctor_callers if
                              row["method"] == "<JoinCreateRoom>d__75.MoveNext"]
    if not game_room_construction:
        raise ValueError("Could not confirm the game's room construction path")

    result = {
        "executable_sha256": digest,
        "metadata_version": 24,
        "photon_user_id_field_offset": "0x20",
        "room_creation_coroutine_rva": f"0x{found['join_coroutine'][0]:x}",
        "game_room_options_constructor_calls": game_room_construction,
        "publish_user_id_setter_direct_call_count": len(publish),
        "game_auth_user_id_setter_direct_call_count": len(game_auth_callers),
        "auth_user_id_setter_direct_callers": auth,
        "player_custom_properties_direct_calls": len(props),
        "native_team_related_property_writers": [
            row for row in props if row["method"].startswith(
                ("RoomController.PrepareRespawn", "RoomController.SpawnPlayer"))
        ],
        "team_extension_setter_direct_callers": select("team_setter"),
        "scope": "local iOS executable static analysis; no server-authoritative claims",
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    sys.exit(main())
