# OGS50 — Photon team dispatch + compact draggable flight pad

## User feedback / observed state

OGS49 user test: speed is satisfactory; team transfer to the other *stock*
account still did not work. The new screenshot (1536x707 landscape) shows the
blue flight buttons at the far-right edge, overlapping the native aim/fire
controls. PhotonHandler.Update reached 20,589 calls, but the generic gameplay
update telemetry displayed "stopped". Room roster contained four peers,
including the explicitly selected target. Shield readout was `enabled=0` and
62 DamageRemote callbacks / 15 ApplyDamage callbacks occurred *while not armed*;
that is not proof the OGS49 shield succeeded or failed.

## What changed

1. Original-client remote team requests no longer depend on a fresh
   RoomController.Update snapshot (which may not run or may have incomplete
   player/team/respawn fields). They are queued from the selected roster actor
   and verified read-only Photon room / local actor; an actual
   PhotonHandler.Update callback consumes the request and calls the original
   TeamExtensions.SetTeam on the verified PhotonPlayer. The target must be
   present *exactly once* in the same room and must not be the sender. A
   short three-second cooldown avoids duplicate submissions. This fixes a
   concrete source-side execution-path dependency, but still does not prove
   the server accepts a remote actor's Team property update.
2. Team buttons submit directly on one tap without a modal confirmation.
   UI status identifies the selected actor and requested team. Error notices
   for missing shield bridges are inline rather than interrupting the game.
   The explicit permission confirmation for automatic host recovery when
   the local user is not host is **retained**, because ownership of a room
   cannot be established just from a changed Actor number.
3. Flight pad is 46x106 points, with two 42x40-point controls and a separate
   18-point drag handle. Default position is around 185 points from the right
   edge to avoid the stock game's native right-side controls. A pan gesture
   on the handle allows relocation; normalized position persists between
   launches, clamped to viewport bounds. The flight/speed timing fix itself
   is unchanged.

## Boundaries and verification

The native TeamExtensions.SetTeam method checks Photon connected-and-ready
and calls PhotonPlayer.SetCustomProperties. Decompilation/ARM64 method path
establishes a potential outgoing property update, **not** acceptance on the
server or a change on the stock recipient. If OGS50 still fails, the
remaining work is to verify the server authority/recipient lifecycle using
target-specific observable results, not to claim success from local dispatch.
No host-authoritative shield support outside the local MasterClient is added.
No direct KillPlayer suppression is introduced, to avoid OGS41 partial death.

Local C++ policy tests and macOS iOS ARM64 compile validate code and package,
not actual device controls or Photon round transition. Acceptance requires
one test with OGS50 and the unmodified second account in a visible room,
observing spectator, police and thieves transitions on the second device.
