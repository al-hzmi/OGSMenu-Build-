# OGS47: flight in visible/open rooms; selected-account team requests

Base: OGS46 `3520cadc06fd5628ecf129b354f67c2c0a0ce00b`.
The user reports OGS46 flight works. This is a user device observation, not an
independent two-device test. OGS47 removes both closed and hidden requirements
from flight activation, per-frame validation, and lifecycle disarming. Player
ownership, alive/respawn/scene identity, collision movement, gravity restoration,
ladder handling, and app-deactivation guards remain. Shield scope is unchanged.

## Correct target and native limitation

The three menu actions now target the selected OTHER actor, not the operator.
The exact Assembly-CSharp metadata image has attribute range 5895..7168. Type
registration resolves attribute type 11170 to PunRPC. `PrepareRespawn` MD30044
and `JoinedTeam` MD30056 have no PunRPC attribute; `PostActivityRemote` MD30058
and `KillPlayer` MD30380 do. This supplies both positive and negative controls.
`OnCollideSwitchTeam.OnTriggerEnter` checks `PhotonView.isMine` at 0x13c4058 and
calls SetTeam on `PhotonNetwork.player`, not a selected remote avatar.
`OnPhotonPlayerPropertiesChanged` refreshes lists and HP/round state, without
running the avatar teardown/camera/respawn transition on the other device.

Consequently OGS47 does not claim an unmodified second client can be fully moved
by setting a property or calling a local function on its proxy. Both devices
must install OGS47. The sender must be the current master. The receiver opts in
for this room and approves EACH requested transition on its own screen.

## Cooperative lifecycle

The sender publishes `ogs47.req` ONLY on its own PhotonPlayer; the recipient
publishes `ogs47.ack` ONLY on its own PhotonPlayer. These are namespaced string
properties; native Team/PlayerHP properties of other players are never changed.
The receiver reads the current master's request at most four times per second,
validates the exact target/format, and shows the actual destination for approval.
Photon properties are not authenticated sender identity and can be manipulated
by other clients; they never authorize a change without that per-request local
approval. Acknowledgements are target reports, not cryptographic proof.

After approval the Unity update thread rechecks room, controller, actor, avatar,
master, request identity and 30-second freshness. It then calls native
`PrepareRespawn(team,true,false)` on the RECEIVER'S RoomController. The explicit
approved administrative request bypasses the scoreboard's balancing UI condition,
but respects respawn busy state and mode (FFA cannot join team 2). The native
method retains character teardown, camera/weapons and Team publication.

The request is deduplicated; retained properties are baselined when reception is
enabled. Room/master changes or app deactivation disable reception; pending
requests expire. A second request cannot replace an outstanding sender request.
Status distinguishes dispatch, recipient approval/native invocation, and the
recipient's observation of its own resulting team/avatar. None claims verified
multiplayer behavior. No new binary bridge is required: reuse the exact OGS46
game executable patches with the OGS47 library.

## Validation and remaining device checks

- `tools/audit_ogs47.py`: pinned original binary, native method identities/ABIs,
  exact image attribute range, PunRPC positives/negatives, Hashtable native path.
- Portable tests: unapproved, stale, wrong-room/avatar/master requests rejected;
  allowed teams, unsupported FFA, busy respawn, same team and invalid enum.
- Existing movement-restoration and shield policy suites retained.
- Build/artifact results are recorded in the release manifest after CI.
- Device tests NOT RUN for OGS47: public/visible room flight; sender/receiver
  request delivery; approval/rejection/expiry; spectator/return; police/thieves;
  visuals, weapons and synchronization on both devices; room/master changes.

Arabic use: on the SECOND account enable استقبال طلبات النقل first. On the
master device select that account with previous/next, then المحدد: شرطة/لصوص/مشاهد.
Approve on the second screen. No account passwords or additional server needed.
