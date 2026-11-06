# OGS46 — self gameplay candidate, not a verified multiplayer release

## Delivered implementation

Built from development baseline `db904e127c3232211e7946a81f9d226acc492a36`, using the supplied OGS41 IPA as the binary input. Stable `main` is untouched. This candidate adds real game calls and movement integration, but device acceptance remains unexecuted.

- Spectator / police / thieves: native `RoomController.Update` consumes room/actor/avatar-bound UI requests. It reproduces the scoreboard's mode, balance, current-team and respawn restrictions and calls `PrepareRespawn(team, true, false)`. No fake local team assignment, fabricated RPC or other-player operation. Local completion is observed separately from request dispatch. A timeout is a failure, not success.
- Flight: native `FPSController.Update` borrows zero gravity and air-control for that one call, preserving the original update. During that call only, the matching local `CharacterController.Move` receives the selected vertical displacement (5 units/s). X/Z, collision handling, grounded result and velocity handling stay in the original game. C++ scope guards restore gravity/air-control and thread-local context. The vertical velocity and falling baseline are reset each flight frame so stopping begins a normal fall at the current height. Death, respawn/avatar replacement, session change, privacy loss, stale updates, ladders and app deactivation disarm flight. Ordinary falls after stopping can still damage the player.
- Self protection: the existing damage and four explosion interceptors now share a local/alive/master/private/room/actor/avatar identity gate. The UI declines activation with another master and automatically disarms on lost authority. `KillPlayer` always forwards, including direct/network kills; death and respawn must not be suppressed after the game has committed a death.
- Controls: three team buttons and flight toggle at the bottom of the scrollable menu; hold arrows outside the menu for vertical movement and use the game's joystick for horizontal movement. Close and hide the private test room after both consenting accounts join.

## Independent binary evidence

Input game SHA-256: `e46148304090f8de5a4fadb009883d0e7a2e0c5541e8628261164b6457b735b2`.
Metadata SHA-256: `80f36c11ca253385d693a505b2693c442c4e0c981f665e285587c6cfdd403faf`.
The metadata header reports 24; the record layouts match 24.1. Field offsets are resolved from the 5,061-entry native registration at RVA `0x232dd80`, table `0x26bea10`. Strings are resolved through metadata usage destinations, not guessed from textual proximity. `LC_FUNCTION_STARTS` delimits the 133 disassembled method bodies. Generated evidence includes direct calls, conditional branches, inbound direct callers across all executable sections, unresolved indirect sites and 16 short ADRP-based PlayerHP reference candidates. This scan does not prove coverage of computed/aliased accesses. PlayerNetwork.Start initializes HP to 100 at 0x13e5038 and publishes it at 0x13e50bc; PrepareRespawn can publish -1 for the native NORMAL lifecycle. RoomController.FixedUpdate and OnPhotonCustomRoomPropertiesChanged read HP for live-player/spectating and round decisions; the property callback copies HP into currentHP +0x1dc at 0x13f7ef4. These lifecycle/round paths remain intact.

| Evidence | Native instruction / table |
|---|---|
| `Team` / `PlayerHP` property keys | Usage destinations `0x283d770` / `0x283d768` resolve to those exact literals |
| Police / thieves IDs | `PlayerNetwork.Start`: team 1 at `0x13e5164` enables `Counter +0x28` and disables `Teror +0x30`; team 2 branches to `0x13e5200` |
| Modes | Usage slots `0x283be98`, `0x283c3f8`, `0x283bdd0` resolve to `TDM`, `NORMAL`, `FFA` |
| Actual GUI transitions | `PrepareRespawn(1,true,false)` at `0x141aa80`; team 2 at `0x141acb4`; spectator 0 at `0x141af10` |
| Team switch lifecycle | `PrepareRespawn` destroys the existing network object at `0x13f69e0`, activates/repositions welcome camera, writes local player's `Team` through `SetCustomProperties` at `0x13f6b64`, starts the original coroutine, and calls `JoinedTeam` at `0x13f6e04` |
| Network activity | `JoinedTeam` sends the native `PostActivityRemote` RPC through `PhotonView.RPC` at `0x13f7164` |
| Respawn uses actual team property | `<PrepareRespawnCoroutine>d__128.MoveNext` reads `Team` at `0x13fb928` and calls `SpawnPlayer` at `0x13fb944`; `SpawnPlayer` only instantiates for teams 1/2 (`0x13f749c–0x13f74a4`) |
| Spectator roster | `RefreshPlayerList` classifies the native `Team` property and updates spectator names; these native callbacks are unchanged |
| Bullet authority | `DamageRemote` checks `get_isMasterClient` at `0x13e781c`, calculates `GetDMG` at `0x13e792c`, subtracts from HP at `0x13e7930`, writes player properties at `0x13e79c8`, then sends kill RPC at `0x13e7a84` if HP <= 0 |
| Explosion authority | Master checks: near grenade `0x13e7f18`, far grenade `0x13e82c4`, C4 `0x13e8634`, far C4 `0x13e89d0`. Near paths subtract 101, far paths 33; all write properties and issue the kill RPC separately from DamageRemote |
| Fall path | `FPSController.FallingDamageAlert` calls `ApplyDamage` at `0x137cf70`; HitBox also calls `ApplyDamage` at `0x138a8a0` |
| Partial death cause | `KillPlayer` stores playerKilled=1 at `0x13e900c`, disables local weapon/look components, and calls `PrepareRespawn` at `0x13e9130`. Blocking it leaves HP/remote death and local lifecycle inconsistent |
| Native movement | `FPSController.gravity +0x3c`, `airControl +0x4c`, `moveDirection +0x7c`, `controller +0x90`, `myTransform +0x98`, `fallStartLevel +0xcc`, `falling +0xd0`, `pn +0x60` independently mapped from field registration |
| Gravity / collision | Gravity integration at `0x137cc9c–0x137ccb4`; `CharacterController.Move` at `0x137cd2c`; grounded is computed from its returned collision flags at `0x137cd30` |
| Position transmission | `OnPhotonSerializeView` obtains position at `0x13e589c` and passes it into PhotonStream.SendNext at `0x13e58c4`; receiving clients consume it through ReceiveNext. Serialization is unchanged; actual remote acceptance is not inferred |

The proper team identifiers are specific to this game's `Team` integer property. PUN's generic `PunTeams` helper is not substituted for the native game path.

## Confirmed limitations, with reasons

**Shield without local master:** The verified damage/explosion paths update `PlayerHP` on the master client's copy and issue `KillPlayer` by RPC. A hook in the victim's process cannot stop instructions executing in the other process. The supplied file contains no server implementation or separately authorized master-side protection protocol. Blocking the local kill RPC or overwriting local HP would produce the inconsistent state already observed. A synchronized non-master shield would require explicit support in the controlling master's game logic (and an authenticated agreed protection rule), or official authoritative game changes. The code therefore does not claim it. This finding concerns these verified client paths; it does not assert how an unseen Photon server plugin is configured.

**Direct / network kills:** Intentionally forwarded. Preventing death after network state changed would break the requested consistency guarantee. The delivered shield covers the verified pre-death damage paths on the local master; it is not an absolute promise of immortality.

**Team restrictions:** The original UI allows joining the smaller team, or either team from spectator when counts match; current-team repeats and active respawn are rejected. NORMAL mode can defer spawning to the game's round logic. FFA supports player team 1 and spectator, not police-vs-thieves switching. These checks are preserved rather than bypassed.

**Runtime verification:** This environment has no connected iOS device, Apple provisioning identity, running copy of the game, or two-client private-room session. ARM64 emulation here executes the short bridge stubs only, not Unity/Photon. It cannot establish actual callback reachability, touch behavior, camera/weapon restoration, absence of runtime crashes or network agreement. Those rows are marked NOT RUN in the acceptance matrix.

**Inherited baseline:** Older unrelated host/kick/weapon functions remain as they were; they are not newly validated by this work. No claim is made that they are all stable.

## Validation and reproduction

```
python -m pip install capstone unicorn
python tools/audit_ogs46.py OGS41.ipa evidence
python tools/test_ogs46.py OGS41.ipa
c++ -std=c++17 -Wall -Wextra -Werror -pedantic tests/test_gameplay_policy.cpp -o /tmp/ogs46-policy
/tmp/ogs46-policy
c++ -std=c++17 tests/test_shield_policy.cpp -o /tmp/ogs46-shield
/tmp/ogs46-shield
python tools/package_ogs46.py OGS41.ipa OGS46.dylib OGS46-CANDIDATE-UNSIGNED.ipa
```

Passed locally: exact input checks; method/field/literal identities; mutation rejection; patch confinement (202 changed executable bytes); 14 ARM64 emulated callback/fallback paths with integer/vector arguments, LR and stack verified; team-policy rejection cases; scene/avatar identity mismatch; finite/clamped movement timing; gravity/air-control restoration including exception unwinding; all 2,048 shield policy combinations. Nickname application, Unicode checks, room capacity and the KillPlayer forwarding implementation are byte-identical source bodies to the OGS45 baseline. This is source regression evidence, not device regression.

Build/package result and hashes are supplied in the artifact manifest. Do not mark gameplay accepted from these tests. Use `ogs46-acceptance.csv` with two consenting accounts in a hidden, closed room; record local and remote evidence separately.

Rollback: use the original OGS41 IPA or build the previous development branch. No merge into main and no in-place overwrite of the supplied file are required. The candidate retains the original bundle ID and resources. Its embedded app signatures are invalid after modification; authorized re-signing of the full app, nested libraries and entitlements is required before installation.

## Build and packaging result

Source commit `13fd990633b12980715c61c1b19537a02cca8145` passed [macOS ARM64 CI](https://github.com/al-hzmi/OGSMenu-Build-/actions/runs/42203148970), including both C++ suites. The subsequent documentation/audit-only commit does not change the built runtime. Library SHA-256: `b6902708af659d2a77e929c368a68857b16629dd6bdaa110618f2a1c8d617f41`. Prepared executable SHA-256: `766b1cfe693304faab1160b7696ce803780f0087ca50a17c9d94fc3e73ed10dc`. IPA SHA-256: `e45cbc4f18450fb205f5a5d55fbcb3bdaf144776f433f4ef992be538fd08578b`. Exact archive member comparison passed: only fps and OGSMenu.dylib were replaced; 170 other entries remained identical. The new library is MH_DYLIB ARM64, install name @rpath/OGSMenu.dylib, iOS minimum 14.0, with only platform/system dynamic dependencies. Installation and two-device tests remain NOT RUN.
