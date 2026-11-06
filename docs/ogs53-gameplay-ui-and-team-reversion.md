# OGS53: gameplay-first menu, one-shot handoff, and team reversion

## Observed OGS52 evidence

- Requests R27/R29/R30/R32/R34 entered the game's `SetCustomProperties` path.
- The game reported matching inbound `Event253` payloads with the requested actor,
  nonce, and `Team` value. This confirms matching local network observations,
  **not** that the other device's gameplay accepted the new team.
- Local actor `Team` values subsequently reverted on some requests (e.g.
  `1 -> 2 -> 0` and `0 -> 2 -> 1`). The dump explicitly attributes no cause.
- The dump was collected after leaving a room (`presence: OUT`). Neither that
  state nor the lack of a local `Event203` proves a host request kicked the user.

## Changes

1. Removed the **client-side** room-open/visibility predicate for an already
   selected actor team request. Matchmaking privacy is not server authority.
   Room pointer, local actor, exact selected target, mode, pending request, and
   a bounded 3-second minimum interval are still checked. Requests remain
   subject to Photon and game-side permissions. The same artificial private-room
   predicate was removed from the local team-change queue and processing path.
2. Report a locally observed team reversal after a matching property echo.
   **Do not** auto-resubmit to fight a round/respawn state machine; this would
   risk network spam and connection instability. Test the remote client's
   team before and after respawn to establish causality.
3. Reordered the menu: selected actor and navigation, immediately followed by
   spectator/police/thief; then flight/shield/speed and room actions. Less
   frequently used settings are collapsed by default.
4. Removed the unverified knife-range/chat/local-ban switches from the visible
   interface. Removed the always-running 30 FPS training marker HUD and its
   bottom toggle; retained the underlying instrumentation.
5. Repositioned flight pad upward and reduced its total dimensions to 36x86
   logical points. It is still draggable and saved under new OGS53 location
   keys, which intentionally reset legacy placement.
6. Added one-shot room-master handoff to the **explicitly selected** actor.
   The action is only sent on Photon Update after reconfirming the same room,
   local actor, current local master status, unique roster target, and live
   native target. Auto-recovery and pending manual recovery are disarmed to
   avoid an immediate counter-transfer. The API result is only local request
   submission; there is **no** temporary transfer or automatic return timer.
7. Fixed the previously inert name monitor: the old code bound monitoring to
   `gOGSRosterLastRoom`, which remains zero while the normal Unity update runs.
   It now binds to the actual published snapshot room, never to a fallback
   counter. It reads PhotonPlayer.UserId at the exact getter-verified native
   `+0x20` field, when the game publishes a nonempty value, and uses that
   identifier within the same room session across new actor numbers. When no
   usable UserId exists it safely falls back to the actor ID. A name change
   requires two consecutive matching snapshots before a nonblocking toast.
   First appearance is a silent baseline; same-name entry is silent. Photon
   UserId is an observation, not proof of a real-world/account identity.

## Device acceptance tests (not completed by CI)

- Public, hidden, and closed rooms: selected actor team changes should queue,
  while changing room or selected actor must reject a stale request.
- On both clients, check whether the chosen team survives: immediate update,
  death/respawn, round transition, and reconnect. Record recipient view.
- Observe close/out-of-room sequences with native disconnect callbacks and
  server response if available. Do not infer kick or crash from a single OUT.
- With local MasterClient, give host to a selected second test account and
  verify *on both devices* that authority moved; prove no auto-reclaim. Try
  the non-master case to verify rejection.
- Nickname change for the same actor twice, unchanged names, player join,
  room leave, new room, and rejoin with a new actor but the same published
  UserId. A stable in-session rename/rejoin with a published ID should notify;
  when UserId is absent, do **not** claim to correlate rejoining accounts.
- iPhone landscape: compact menu tap targets, scroll, flight pad holding vs.
  dragging, touch passthrough to the game's native aim/shoot controls.

Passing compilation or matching local Photon events is not a live gameplay
acceptance test. Use a second controlled account for the latter.
