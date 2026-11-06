# OGS48 — selected original-client team transition candidate

Base: `experiment/ogs47-flight-target-team`, commit
`28f16eae9d6cd8ecd184d9149943d2664f4fedd7`.

## User-reported observation that changed the hypothesis

In an unmodified game client, a different player who was *not* MasterClient
apparently changed the reporter's name/team listing to spectator immediately.
The avatar stayed active until death or the end of the round, after which the
spectator status persisted and the reporter could not rejoin police/thieves.
This is a detailed observation, **not proof** of which RPC/property/network
operation caused it. It suggests that the Photon team property and the live
RoomController/avatar lifecycle may be decoupled until respawn/round change.

## Exact-game native evidence

`tools/audit_ogs48_original_client.py` validates the uploaded OGS46 game
executable SHA and IL2CPP metadata SHA, verifies `TeamExtensions.GetTeam`,
`TeamExtensions.SetTeam`, `PhotonPlayer.SetCustomProperties`,
`PunTeams.OnPhotonPlayerPropertiesChanged`, and `PunTeams.UpdateTeams`.
`TeamExtensions.SetTeam` calls the native `GetTeam` and
`PhotonPlayer.SetCustomProperties` on its PhotonPlayer argument. The body
contains no direct call to `PhotonNetwork.get_isMasterClient`; this does not
establish permission to edit a different actor's properties on the server.
The `PunTeams` property callback directly dispatches to `UpdateTeams`.

## Functionality added

The three selected-peer buttons queue a one-shot `TeamExtensions.SetTeam`
invocation on the original Unity room-update thread, using the verified native
`PhotonPlayer.Find` target. No OGS47 installation, cooperative custom command,
or consent-prompt logic is needed on the other (original) client.

Safety restrictions: the live roster must contain exactly one other actor;
the room identity, local actor, roster, target actor, mode, and request age
must all match at invocation; the native target must still be active; a
15-second cooldown prevents rapid repeats. The sender explicitly confirms
that the sole other participant is their own second account. The team buttons
do not require MasterClient or a hidden/closed room, which makes two-account
visible-room testing possible. The game executable is not patched further:
the existing OGS46 bridge layout remains intact.

## Unverified and important limitations

- `SetTeam` returns `void`. Local invocation and immediate local readback do
  **not** establish that Photon accepted a property mutation for another actor.
- No direct server operation response is attributed to the specific request.
- Recipient's scoreboard, eventual spawn, room reload, police/thieves ability,
  and persistence are not device-tested. The new code is an experimental
  functional attempt, not a proven original-client remote team transfer.
- The user's report establishes only a spectator outcome, not police/thieves.
- Flight is allowed in open/visible rooms. After the user found that the speed
  feature makes flight appear to stop, the vertical movement calculation now
  uses monotonic real elapsed time rather than Unity's scaled `Time.deltaTime`.
  Temporary incomplete IL2CPP snapshots pause movement instead of instantly
  cancelling the toggle; confirmed death, spectator mode, player replacement,
  room/actor changes and a sustained >1.5-second failed sample still disarm.
- Host shield activation no longer depends on room hidden/closed flags. It
  requires verified host, alive player, and a live roster with no more than
  one other account in the same room; the damage/explosion callbacks separately
  enforce that condition. The UI now displays an explicit explanation when
  refusing activation. The shield still does NOT work authoritatively without
  MasterClient and no-host immunity is **not** claimed or implemented. Never
  suppress KillPlayer again: OGS41 showed partial-death/lying-avatar regressions.

## Two-account acceptance matrix (must be tested on real devices)

One device: OGS48, second device: stock game, exactly two accounts in a room.
Repeat with the first account *not* MasterClient.

1. Send spectator (team 0) while recipient alive: observe immediate roster,
   existing avatar, and the recipient after death/round end.
2. Send police (team 1): observe roster, respawn, weapon/team placement and
   whether the recipient can play after round change.
3. Send thieves (team 2) in supported mode: same checks.
4. Change sender room / target departs / third player joins before dispatch:
   operation must not be issued.
5. Reopen app, turn flight on/off in visible room, and verify normal death and
   respawn to catch regression.
6. Enable host shield in an open/visible room with only the two accounts and
   verify bullet, explosion, death/respawn behavior; it should refuse when a
   third account enters. Repeat speed settings 0.5x, 1x, 3x, 10x while flying;
   ascent/descent should remain stable per real-world second.

If stock recipient never changes team, remove the functional claim; do not
reinterpret local dispatch as server acceptance. Re-examine network authority
or the reported spectate mechanism instead.
