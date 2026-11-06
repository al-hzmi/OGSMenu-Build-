# OGS45: bounded host-side explosion protection

## Scope

This is a development build for controlled testing, not a complete shield or a tested multiplayer release. Relative to OGS44, it adds actual suppression of four explosion handlers for a verified local player. The other requested features are not implemented. The stable branch was not modified.

## Implementation

The already prepared BombDmg, BombDmgLong, C4Dmg and C4DmgLong entries route into callbacks. A callback skips the original method only if every condition is true: shield enabled; receiver ownership verified as local; room, local actor and master actor readable; the actor seen during owner identification equals the actor in the room snapshot; actor equals master; the room is locally marked closed and hidden; playerKilled can be read and equals zero. All other cases, including unknown or dead state and shield off, call the original method. It does not overwrite HP, alter other actors, or skip KillPlayer/PrepareRespawn.

The gate's pure decision logic is in OGSMenu/OGSShieldPolicy.h; the callbacks, ownership snapshot and bridge installation are in OGSMenu/ModMenu.mm. Turning the shield on now also checks all four prepared explosion bridges; activation fails if they are missing. Protection is deliberately not asserted when the local player is not master. Room privacy is read from the local room model, not independently confirmed by the server. The checks are separate snapshots; they cannot guarantee the room or player state is unchanged between check and method execution.

This implementation prevents the covered local master's explosion handler from running under those conditions. Static code does not establish that another client or server cannot apply a separate hit, that every explosive path is covered, or that avatar animation and respawn stay synchronized. Those remain device tests.

## Evidence on other features

Scoreboard.ShowTeamSelected has actual buttons whose code invokes PrepareRespawn(1, true, false) and PrepareRespawn(2, true, false) at 0x141a1c4 and 0x141a3dc. Metadata includes Scoreboard.CounterText and TerorText corresponding to GUI text fields, suggesting labels, but their exact runtime field mapping has not been independently validated. Scoreboard.ScoreboardWindow also calls PrepareRespawn(0, true, false) at 0x141af10 from a GUI button path; JoinedTeam's third branch uses a spectator activity label and sends PostActivityRemote. These do not yet establish end-to-end transitions or network acceptance.

The game's scoreboard applies mode, player balance and UI conditions before some team changes. Direct calls to PrepareRespawn would bypass these checks; no speculative direct call or dummy button was added. Native room-controller object lifecycle and correct execution thread need verification before implementation.

FPSController.Start stores a component at +0x90; FPSController.Update passes it to CharacterController.Move at 0x137cd2c. Gravity and the player's vertical movement vector are also updated in Update. Safely suspending/restoring them through death, respawn, room changes and Photon synchronization is unverified; no guessed movement write was added.

## Tests and provenance

- Host unit tests exhaustively tested all 2,048 combinations of the eleven gate conditions: only the all-true case suppresses.
- macOS CI run 42147761120 compiled the ARM64 dylib for source commit e749ef4f0202beb030159908699311855bb03989 and ran the policy test.
- Artifact ZIP SHA256 6737e6deaf0da8a757393aefadc43ac479691dcc353bacb412a3a4a055168af8; dylib SHA256 e7327f7af1fb89583b6b09e8ceccca9a62cc6c41827cf3124b118ba63813eb19.
- Unsigned IPA SHA256 4ea314086ef7f8a868455a0b9e851d59dec92eb6a648ef6a331fafb057fd240c.
- Full ZIP CRC and uncompressed entry comparison passed; prepared executable rebuilt identically from the known original; four entry branches and empty-slot fallback continuations passed; modified game bytes were rejected.
- Original KillPlayer/PrepareRespawn static assertions passed. Existing name and capacity implementation unchanged, but runtime regression not performed.
- Not performed: Apple signature validation, installation, actual hook attachment, grenade/C4 gameplay, all other damage types, remote observer, death/respawn, team/spectator transitions and flight.

## Controlled acceptance test

In a private closed, hidden room with consenting accounts, use local player as master, enable shield, confirm all four bridge statuses are 1, and test near/far grenade and C4 separately. Repeat with shield off. Capture local and second client health, avatar state, death/respawn, and counter changes. Repeat with master held by the other account to explicitly establish the known protection gap. Do not infer network acceptance or safe state from a counter or a successful build.
