# OGS41 — verified missing direct-damage shield path

## Evidence from the supplied device log

- OGS40 KillPlayer native bridge **installed** (`status=1`).
- `KillPlayer callbacks=3`, `local=1`, `other=2`, `local bypass=1`.
- The user observed death anyway: shielding KillPlayer alone was insufficient.
- The supplied snapshot says shield `enabled=0` **at the time of the report**;
  counters persist across switching off, and are not a synchronized death trace.

## Verified exact game binary call graph

Read-only metadata method table and ARM64 `b`/`bl` scan against the actual
fps 3.4.0 executable reveal these concrete paths:

| Caller | Native branch | Callee |
| --- | --- | --- |
| `HitBox.Damage` | `B` at `0x138A8A0` | `PlayerNetwork.ApplyDamage` at `0x13E7360` |
| `FPSController.FallingDamageAlert` | `BL` at `0x137CF70` | `PlayerNetwork.ApplyDamage` |
| `PlayerNetwork.KillPlayer` | `BL` at `0x13E9130` | `RoomController.PrepareRespawn` at `0x13F65C0` |
| `Grenade.AreaOfEffectDamage` | `B` at `0x138987C` | `PlayerNetwork.BombDmg` |
| `C4.AreaOfEffectDamage` | `B` at `0x13548F8` | `PlayerNetwork.C4Dmg` |

`ApplyDamage` is not necessarily reached via the existing `DamageRemote` hook.
OGS40 installed its ApplyDamage bridge **only when the separate magic-bullet
experiment was enabled**, so normal incoming hit/fall damage was not covered
by the shield toggle.

## Implemented

1. The shield toggle now installs all three already-prepared bridges:
   `DamageRemote`, `ApplyDamage`, `KillPlayer`.
2. `OGSBridgeOutgoingDamage` first verifies that the `PlayerNetwork` receiver
   belongs to the *local* Photon actor; it skips this one application only
   while the shield is armed. Other actors or unknown owners are forwarded.
3. The prior magic-bullet experiment remains separately controlled, and
   all original function calls are made when shielding is off.
4. New `OGS41 ApplyDamage` counters distinguish callbacks, verified local
   bypasses, other-actor forwards, and unknown-owner forwards.
5. Game executable bridge bytes are identical to OGS40. Only the new dylib
   and label/artifact version are changed. Main branch remains untouched.

## Research into other requested features (not implemented)

- `RoomController.PrepareRespawn(int team, bool wasSwitched, bool ResetOn)`
  MD30044 calls `RoomController.JoinedTeam(int team)` MD30056.
- `JoinedTeam` compares teams 1 and 2. A third code path exists, but equating
  it to spectator, or assuming this lets the local client reassign *other*
  Photon actors, is not yet supported by network/server evidence.
- `RoomController.spectatorNames` is a real metadata field, not proof of a
  synchronized spectator transition API.
- `FPSController` has movement, gravity, and jump fields and `Update` at
  RVA `0x137BE64`. Safe fly control needs verified object lifecycle, field
  offsets, main-thread movement, server reconciliation and a reversal plan.
  Arbitrary writes were intentionally not attempted.

## Required tests on two controlled clients

1. Install *complete* OGS41 IPA; verify `OGS41` title, enable shield, capture
   `OGS41 ApplyDamage native bridge` and KillPlayer status while **armed**.
2. With and without local host ownership, fire one normal bullet from the
   other controlled account. Log callbacks/local bypass and actual HP/death.
3. Separately test falling, a grenade, and C4. A count for ApplyDamage does
   **not** prove protection from all those pathways.
4. Disable the shield; confirm legitimate damage/death resumes for the local
   account and the other account was never protected by this toggle.

Offline ARM64 branches and successful compilation cannot establish server-
authoritative immunity or a feature working across network clients.
