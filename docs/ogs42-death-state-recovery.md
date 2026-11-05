# OGS42 — Fixing the shield's dead-but-moving regression

## What the device log established

- Shield was enabled; `DamageRemote` saw 16 verified local bypasses and 64 other-player forwards.
- The `KillPlayer` native bridge received 13 calls: one verified local and twelve other-player calls. The single local call was bypassed in OGS41.
- `ApplyDamage` received 20 calls, none verified as the local actor. That bridge did not prevent the observed death.
- The local player was actor 44 while the MasterClient was actor 1. The user was not the local MasterClient.
- A moving avatar lying on the ground persisted after the initial death. Neither local counters nor MasterClient snapshots establish which server-side event first caused death.

## Verified root of an OGS41 regression

The original `PlayerNetwork.KillPlayer` (`0x13E8FBC`) writes the `playerKilled` flag at receiver offset `+0x12C` and directly calls `RoomController.PrepareRespawn` (`0x13F65C0`) from `BL` at `0x13E9130`.

OGS41's shield returned before calling original `KillPlayer`. This suppressed **both** the death-state handling and the game's legitimate respawn scheduling. It can strand a locally animated dead avatar with movement input still active if another path has already displayed death or applied network state.

OGS42 **always calls the original** `KillPlayer`, including verified local-player calls while shield is enabled. When shielded it logs whether the `playerKilled` flag was 0, 1, or unreadable immediately **before** forwarding. The earlier pre-death `DamageRemote` and `ApplyDamage` shielding remains separately gated to local player ownership; non-local and unknown targets are still forwarded. This is a **state-consistency and respawn mitigation**, not guaranteed death prevention.

## Unproven / deliberately untouched

- Host-independent invulnerability is not proven and cannot be guaranteed by a local hook if another client's Photon state or server-accepted event can mark the actor dead. Do not equate local bypass counters with remote health or authority.
- There is no verified legitimate API here for forcing another participant into spectator, thief, or police. The local `RoomController.JoinedTeam` code path is not proof of remote authorization.
- Flight requires verified player movement authority, state sync, and clean reversal; no speculative movement writes were made.
- Grenade restock has unresolved inventory-field identity and remains unmodified.
- Exact source IPA is `OGS34(1).ipa`, game SHA256 `ad1794ad50d976e042bbbe0c604a4e8bbb3fe8092787ee9ce24d07e7a530ac2f`. OGS42 package retains the OGS40/41 native bridge and patches no new instructions.

## Controlled two-account verification (not yet performed)

1. Install the complete OGS42 IPA after valid signing. Observe `OGS42` UI; enable shield while **not MasterClient**.
2. Have a consenting test player defeat the local avatar once. Determine whether respawn happens normally rather than leaving a permanently prone moving avatar. If the player does not respawn, capture recording and OGS42 local pre-kill flag counters.
3. Repeat while MasterClient. Separate observed local position/animation from the other test account's view, and record normal damage vs explosive damage.
4. Disable shield; verify ordinary death and respawn work, and verify other actors' damage still applies normally.

Static inspection and successful building cannot substitute for in-game reproduction and remote confirmation.
