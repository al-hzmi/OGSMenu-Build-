# OGS38 — room capacity reductions and evidence-based feature status

## OGS37 user report

- Room capacity increase was accepted by the local native setter:
  `queued=1`, `attempted=1`, `local applied=1`, before=8, after=32.
  User reports success. The report does not independently prove a server
  acknowledgment or that another client joined the expanded room.
- Shield while enabled: 24 incoming DamageRemote callbacks, of which 8
  were confirmed local and bypassed, 16 belonged to others, and none were
  owner-unreadable. User still died, regardless of MasterClient status.
  Therefore avoiding DamageRemote on the local player does **not** provide
  proven invulnerability; another damage/health/death path may exist.
- Grenade: 4 throw callbacks, 2 rejected owner checks, 2 local-owner
  callbacks rejected by the invalid ammo value; no memory writes. The latest
  `+0x12C` raw value was 6250139 and adjacent `+0x130` 6250138, unchanged
  across GrenadeShootm. Treating either as an ordinary ammo count is invalid.

## Capacity change

- Replace the increase-only choices with a numeric entry accepting **2..32**.
  It supports both expansion and reduction, for example 32 -> 6 or 6 -> 12.
- Do not allow a capacity smaller than the number of *currently present*
  players; changing the limit is not a way to forcibly evict occupants.
- Bind the request to the room pointer, actor ID, and observed starting
  capacity. Reject if the room, MasterClient, or starting capacity changed
  before the callback executes. Use the original Room.set_MaxPlayers method
  (MD31704, MI29298), no direct room memory writes.
- Maintain the 10-second rate limit; preserve independent counts for
  rejection, below-occupancy rejection, function entry, and local readback.
- This change does not authorize 100 or 200 slots. The current UI and roster
  limits have not been validated above 32.

## Shield and grenade diagnosis

- Change the shield UI label from 'armed' to 'experimental' because the
  user's death during 8 local bypasses refutes an invulnerability claim.
  The shield still attempts to bypass DamageRemote but its coverage is partial.
- Binary inspection identifies FPSWeapon.RefillAmmo (MD30451, MI27864,
  RVA 0x01382C10). Native code uses object fields +0x124, +0x128 and +0x130,
  and dereferences a pointer at +0xA8. That API is **not** proven safe for
  a grenade object, so OGS38 does not call it blindly.
- GrenadeShootm RVA 0x01381160 does not directly modify +0x12C or +0x130
  in its inspected native body. The actual grenade inventory decrement may
  occur in another function or on a different object.
- New role controls are not included: RoomController.JoinedTeam recognizes
  integer arguments 1 and 2 but does not establish authorization to change
  another client's team or spectator status.

## Test criteria

1. In an owned room with 3 players and capacity 32, set a new capacity of 6.
   Expect a local setter attempt and local readback 6; independently check
   the room list from a second account.
2. In the same room, try setting 2. The UI must reject because 3 players
   are present. It must not evict players or submit a Photon property request.
3. Try 4 -> 8 to verify expansion still works. Test a master transfer
   before the queued callback; it must reject a stale request.
4. Do not infer shield or grenade success from a green button or counters
   alone; both remain unverified gameplay features.
