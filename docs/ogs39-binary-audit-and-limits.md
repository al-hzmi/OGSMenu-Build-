# OGS39 — verified ARM64 audit, room capacity, nickname, grenade & death paths

## Scope and evidence

- Exact fps 3.4.0 ARM64 executable from the user-supplied OGS34 IPA and
  IL2CPP v24 method table; immutable method/field checks are recorded in
  `tools/verify_ogs39_static.py`.
- PUN Classic v1 officially distinguishes `Room.PlayerCount` (active players
  **inside** the room) from inherited `RoomInfo.PlayerCount` (lobby cache).
  The previous OGS38 `room+0x50` raw read returned zero even in occupied
  rooms in the user's logs. This was a genuine diagnostic/preflight defect.
- Native `Room.set_MaxPlayers` MD31704 / MI29298 at RVA 0x13F1AF0
  calls an OpSetProperties request, then **unconditionally updates the local
  byte** at `Room+0x20`. Its immediate read-back is *not* server proof.

## Implemented changes

1. The actual `Room.get_PlayerCount` MD31705 / MI29299 (RVA 0x13ED320)
   is called on the Photon callback thread only, after validating its method
   pointer identity. Both UI occupancy preflight and execution-time checks use
   this count, never the stale `RoomInfo` backing field.
2. The UIKit menu reads a throttled, room-scoped count snapshot. If no
   verified count exists, no room-capacity request is queued. Decreasing below
   actual occupants is denied on the Photon thread.
3. Capacity requests carry room identity, local actor, master, and initial
   limit, as before. Extra telemetry counts OpCode252 responses and Event253
   observed within eight seconds of a request; **these are explicitly labeled
   unattributed, not acknowledgments** because room operations overlap.
4. Self nickname now accepts one to 100 user-perceived grapheme clusters
   (including composed Arabic/emoji) instead of two to 24 UTF-16 units.
   Control characters and empty input remain rejected. The game's server
   may enforce a shorter limit; no remote acceptance is asserted.
5. Grenade diagnostics now also read the `PlayerWeapons.Grenade` array and
   `selectedGrenade` index before and after the real throw. Verified actual
   native `SwitchWeaponGrenade` is RVA 0x13EC238, uses array at +0x60 and
   selected index +0x8C. The nearby +0x70/+0x94 pair belongs to C4, not
   grenades. Reads are bounded and guarded; this new probe **never writes**.
6. Added a passive method-pointer hook for `PlayerNetwork.KillPlayer`
   (MD30380 / MI29168 / RVA 0x13E8FBC). It counts which kill callbacks target
   the local player, then always forwards the original call. Native direct
   calls may skip a method-pointer hook; a zero count does not disprove its use.

## Unresolved behavior — do not assert a gameplay fix

- **Room size:** an observed `local applied=1` still does not prove Photon
  accepted a change. Confirm from the second account or a server-room listing
  after the property response. If the host changes or server rejects the
  operation, this client cannot force the authoritative room size.
- **Grenades:** the actual `FPSWeapon.bulletsLeft` (`+0x12C`) had multi-million
  raw values, with adjacent `reserveBulletsLeft` (`+0x130`) one less. Both
  stayed constant during throw; `GrenadeShootm` did not consume them. Neither
  is verified as a grenade inventory counter. Existing range validation
  continues to refuse writes, preserving memory safety. No infinite grenade
  claim is justified.
- **Shield:** local `DamageRemote` callbacks are bypassed, but deaths outside
  the client's MasterClient phase show the damage/kill pipeline is wider.
  The newly observed `PlayerNetwork.KillPlayer` native entry sets death state
  at `self+0x12C` (this is a DIFFERENT class and field from FPSWeapon ammo).
  A passive hook diagnoses that path; it does not suppress a valid death or
  provide immunity from server-side authoritative hits.
- **Spectator, police/thief switches, flight:** static IL2CPP metadata
  contains `RoomController.JoinedTeam`, `ourTeam`, `meTeam`, and a spectator
  names array; `FPSController` contains gravity/jump/movement fields. This
  alone does not prove remote-role authorization or a safe synchronized
  flight path. No arbitrary role packet, teleport or offset write was added.

## Required two-device verification

1. In a room with three real occupants and limit 32, attempt `32 -> 6`.
   Capture `OGS39 room capacity` including `cached players`, `Nearby Op252`
   and the second device's *room listing* after waiting several seconds.
2. Attempt `6 -> 2`: it must refuse while three players remain. Never treat
   this test as a kick or eviction.
3. Test a nickname of 1, 24, 50 and 100 composed characters, and confirm on
   the second account; local readback is insufficient to establish max length.
4. Buy a grenade and throw once with the restock toggle enabled. Capture
   `OGS39 grenade inventory probes`, OGS34 raw ammo, and the game's visible
   inventory state. Do not assert restock from a hook count.
5. With the shield toggle enabled and a second account controlling host,
   record `OGS39 KillPlayer passive hook`, `DamageRemote`, and the observed
   death. All existing damage and kill callbacks remain forwarded as before.

## Audit versus runtime

`python3 tools/verify_ogs39_static.py /path/to/fps` checks original ARM64
method identities and instruction-level offsets. An ARM64 CI build checks
compilation and linking. Neither is an iOS two-client functional test.
