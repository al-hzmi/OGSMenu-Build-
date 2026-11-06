# OGS49 — host shield without room-size gating; selected-player team attempt

The user's OGS48 readout showed `local actor=1`, `Master actor=1`,
`match=YOU (local)`, `shield enabled=0`, no damage or explosion callbacks, and
the read-only roster occasionally failed (`failures=123`). The user confirmed
the speed/flight change was satisfactory. There is **no evidence that OGS48
actually armed its shield during this session**.

## Applied native source changes

- Remove **all** room visibility/privacy/player-count and read-only roster
  predicates from host shield arm and native interception. Activation can now
  be queued regardless of a transient RoomController snapshot. It is bound
  only after a verified local host/alive player snapshot. Every damage callback
  separately verifies owner, local actor, room, MasterClient and the alive
  flag, and forwards unknown/nonlocal calls. A verified death, new avatar,
  actor or room disarms. A temporary loss of a snapshot does not drop the UI
  toggle. **Non-host health authority and KillPlayer are not bypassed**.
- Remove the experimental exact-two-account requirement from the UI and team
  request lifecycle. The user must select the exact actor from the live roster,
  then confirm it is their own second account. On the Unity room-update thread
  the target actor must still occur exactly once, in the same room, at dispatch.
  The user's own game mode label being unknown no longer silently prevents
  a request, but an FFA thieves request remains excluded.
- Preserve the OGS48 monotonic flight timing / speed interaction fix unchanged.

## What this does *not* prove

Invoking the original native `TeamExtensions.SetTeam` on a different actor
returns void, and no targeted Photon server ACK or stock client result exists.
The user's report that OGS48 transfer **did not work** is a real negative
live observation. OGS49 fixes premature local rejection and targeting in
crowded rooms, but **is not a demonstrated solution** if Photon rejects
remote writes. Testing with the stock second account is still required before
claiming success. Do not misrepresent a local client cache change as remote
application. The OGS41 partial-death/lying-avatar regression is why
KillPlayer and native respawn are always forwarded.

## Verification boundaries

Host-testable C++ decision predicates cover all 256 combinations of the
shield's eight identity/host/alive flags and selected actor validation with
single/multiple peers, duplicate/missing targets, actor and room mismatches,
invalid destination and stale requests. GitHub macOS ARM64 build validates
Objective-C++ syntax, linking and Mach-O output, not live server behavior.

Acceptance still requires signed-device tests with OGS49 + stock second
account (spectator, police, thieves) and multiple room sizes, including a
third account arriving mid-request; verify the recipient after death and round
change. Host shield should be tested against bullets, grenades, C4 and falling
damage; absence of native callbacks in a report cannot confirm coverage.
