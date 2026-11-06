# OGS51 — corrected Team property, experimental private-room candidate

**Confirmed source defects repaired; stock-client gameplay is NOT VERIFIED.**
No iOS device, signed installation, running Photon session or second account is
available in this environment. No live test below is reported as passed.

## Provenance

Baseline: `a4f108446190894791845fd5a48921611e851631`, branch
`experiment/ogs50-photon-dispatch-flight-ui`. The attached OGS50 IPA's dylib is
byte-identical to artifact 13504876335 from successful CI run 42223044098 for
that exact commit. The downloaded artifact ZIP matches its published SHA-256
`f309693b6b7c7d7db2691fcdb481460d68827c3339f4d30ad92144b91ec268d2`.

| Input | SHA-256 |
|---|---|
| OGS50 IPA | `11eb103f0c4972292f7f3a97403c4e1c3154436f5671e2daccc62890f515e742` |
| Embedded ARM64 executable | `766b1cfe693304faab1160b7696ce803780f0087ca50a17c9d94fc3e73ed10dc` |
| Metadata | `80f36c11ca253385d693a505b2693c442c4e0c981f665e285587c6cfdd403faf` |
| OGS50 library | `f4484148e1fbe7a5b5831e2c7ec0a6f0bf2d3130404445b66283fb15379a1b0a` |

## Team failure: concrete root cause and remaining boundary

OGS50 called `TeamExtensions.SetTeam` (MD31983/RVA1423388). This helper
writes **lowercase `team`, boxed Byte**. The actual game writes/reads
**capital `Team`, boxed Int32**. These are distinct case-sensitive properties,
not alternative spellings. Activity in PhotonHandler.Update cannot fix that.
This is a sufficient source-level reason the previous request did not change
the game's team; it does not rule out additional server/lifecycle failures.

The new audit resolves string-literal usage destinations, type-info usage
indices and native type registration independently from the attached binary:
`283de90 -> team`, `283d770 -> Team`, `2815438 -> Byte`, `2815340 -> Int32`.
`GetTeam` loads a byte at 1423374; `PrepareRespawn` boxes the Int32 at
13f6aec, loads `Team` at 13f6b08 and calls SetCustomProperties at 13f6b64.

| Native consumer | Evidence and implication |
|---|---|
| Player property callback | 13f7e20 calls RefreshPlayerList; scoreboard and spectator lists consume the capital key |
| Room state | RefreshPlayerList stores own team at `RoomController+1b0`, 13f3b0c |
| Existing avatar | PlayerNetwork.Update reads capital Team at 13e6138, stores `playerTeam+154` at 13e615c, branches on 1/2 to update models; 0 does not perform the full self-transition |
| Correct self transition | PrepareRespawn destroys the old network avatar at 13f69e0, handles camera/respawn, writes Team and calls JoinedTeam; property-only updates do not execute this whole sequence |
| Respawn | Coroutine reads Team at 13fb928 and calls SpawnPlayer at 13fb944; SpawnPlayer instantiates for 1/2 |
| Round | OnPhotonCustomRoomPropertiesChanged uses ourTeam at 13f95a0 and SpawnPlayer at 13f95b4; another branch rereads Team and spawns at 13f97ac |
| Identity | Team 1 activates Counter, 2 activates Teror in PlayerNetwork.Start/Update; 0 is spectator in native roster/spawn logic |

This supports the reported split between spectator roster and still-living
avatar. It is not evidence the new request succeeds on a stock recipient, nor
a guarantee of immediate spectator entry/return. No remote KillPlayer,
fabricated respawn RPC or repeated property overwrite was added. The existing
cooperative receiver is not used; the second account remains unmodified.

The new request path is UI -> actor/room validation -> PhotonHandler.Update ->
capital Int32 Team with expected old Team -> PhotonPlayer.SetCustomProperties
-> native OpSetPropertiesOfActor. It is restricted to an explicitly selected
other account in a closed/hidden test room; **no local-host gate** is imposed,
so both authority cases can be tested. FFA team 2, stale/duplicate requests,
missing actors, offline mode and incompatible native bridges are rejected.

The nonempty expected-properties table selects the native non-optimistic CAS
path. ARM64 emulation of the actual guard confirms expected count 1 skips
local Merge, whereas count 0 enters it. External helper calls are stubbed in
that isolated test; no networking is emulated.

Each request has R-ID plus one UUID stored in the bounded `ogs51.request`
actor property. The 64-line trace records UI, queue, consume, validated actor,
original call, transport return and local read. An inbound Event253 is matched
only on target parameter **253** (not sender 254), properties parameter 251,
UUID and correctly typed Team. Such a match is labelled a received update,
not proof of the stock client's camera, avatar or next round. Generic Op252
responses cannot be attributed; a 12-second timeout reports **unknown reason**,
not an invented permission rejection. Subsequent cache changes are observed
for up to 120 seconds without forcing the value back.

## Grenades and damage identity

The old inventory probe read eight bytes at PlayerWeapons.Grenade+18 as an
array length. The native field is a List, and its size is a four-byte Int32.
The corrected probe checks signed size, selected index and backing-array
capacity. A fixture with size 3/version 8 reproduces the old rejection.

FireOneShot decrements bulletsLeft+12c at 13809f8–1380a00.
GrenadeShootm creates/moves the projectile, but does not itself decrement that
field. Thus a throw-only hook is insufficient to bracket consumption. New
native-entry observers surround both methods, forwarding the original exactly
once, and record ammo, inventory/selection before and after, local/host actor
and target's replicated HP changes. No restock, damage or radius changes were
added. Training suspends legacy ammo/melee modifiers for a clean baseline;
reenabling them disarms the measurement session.

Grenade.Update uses OverlapSphere radii 6 and 12 at 1389cb0/1389ce4. They are
game units and overlapping spheres, not proven metres or disjoint annuli.
Near/far handlers have separate conditions. Existing-HP branches subtract
101/33; multiple colliders, mode and ordering prevent treating this as measured
aggregate damage. Master checks are independently verified at 13e7f18,
13e82c4, 13e8634 and 13e89d0. Repeated throws/actual blast damage remain NOT RUN.

ShootBullet chooses the Int32 knife range +10c for type 4 and bullet range
+108 otherwise (1381be0–1381bf4), raycasts at 1381c18, then invokes the hit
collider's HitBox.Damage at 1381e38. HitBox builds damage data and calls
ApplyDamage; the latter sends DamageRemote, whose master branch writes HP and
can issue KillPlayer. This inspected path does not select a victim by display
name. No remote-hit/kill-by-name implementation is added. Equal names are not
unique identities; all new selection uses room + Actor and fresh object
ownership. Sender/server validation of every RPC cannot be proven from this
client binary: ExecuteRpc includes reflection/indirect dispatch, and no server
implementation or authenticated server logs were supplied.

## Host, shield and movement

The native host paths include both a property request with key 248 and expected
previous master (13b0c54–13b0d98), and a RaiseEvent208 path (13b0a20,
indirect dispatch 13b0b50) that also updates the local master after submission.
CheckMasterClient scans actor IDs and selects a replacement (13af820–13af8a0).
Consequently a local master value or API true is not a permanent server lock.
Disconnect/leave/room-event paths can change it. The supplied counters alone
cannot identify which peer initiated a historical change or explain a freeze.
No retry-rate increase, blocking wait, host-steal bypass or new packet filter
was introduced. Existing host machinery remains inherited and unverified.

DamageRemote's master check at 13e781c precedes HP subtraction, property write
and kill RPC. A victim-only hook cannot modify the other master's process.
OGS50's master/local/alive shield guards and KillPlayer forwarding are
unchanged. Non-master immunity is not delivered; disabling death handling
would undermine respawn consistency. The toggle remains available without
room visibility/occupancy restrictions, while actual protection still has
its existing ownership/authority checks.

Flight, speed integration, gravity restoration and draggable saved controls
are unchanged. Source comparison covers these bodies, name/unicode/capacity,
ApplyDamage and KillPlayer. That is regression evidence at source level,
not runtime verification. Earlier user success is recorded as user feedback,
not substituted for OGS51 device testing.

## Private training marker

A new optional marker projects the selected test account's fresh, already
replicated PlayerNetwork position through the native camera's
WorldToViewportPoint. It stores coordinates, not long-lived Unity pointers;
checks owner, alive state and current room; hides behind-camera/off-screen,
nonfinite or >250ms-old samples; and stops on scope loss/app deactivation.
It is a UIKit overlay, so no material/depth-test patch or hidden-server-data
request is involved. A small noninteractive label avoids the reserved edges,
menu and flight pad. Sampling/display are capped at 30Hz. Screen geometry tests
cover landscape point widths 852/932/956; actual alignment, FPS, thermal cost,
occlusion appearance and crashes still require an iPhone test.

## Reproduce and classify evidence

```sh
python -m pip install capstone unicorn
python tools/audit_ogs51.py OGS50-CANDIDATE-UNSIGNED.ipa --output evidence51
python tools/test_ogs51.py OGS50-CANDIDATE-UNSIGNED.ipa
# Compile/run each tests/test_*.cpp using C++17 (five suites).
python tools/package_ogs51.py OGS50-CANDIDATE-UNSIGNED.ipa OGS51.dylib OGS51-CANDIDATE-UNSIGNED.ipa
```

Passed: fingerprint/CRC, metadata identities and 36 selected instruction
assertions; complete dumps of 75 relevant registered method ranges and direct
call graph; native CAS branch isolation; eight bridge callback/fallback paths
with X0–X5/Q0–Q2/LR/SP; mutation refusal and declared patch spans; five C++ suites.
Reflection, computed references and server code are not claimed exhaustively
resolved. Build/artifact hashes and logs are recorded in the release manifest.

Packaging modifies only four entry instructions, four padding stubs and the
library; 170 other ZIP entries stay byte-identical. No stable branch merge.
The supplied OGS50 remains the rollback copy. Retained embedded signatures are
invalid after modification: re-sign the full app and nested library before
installation. `ogs51-acceptance.csv` and the Arabic test guide contain the
remaining live tests, all explicitly NOT RUN.
