# OGS36 — authorized-feature audit and self-name implementation

Scope: fps 3.4.0 iOS ARM64 / Unity IL2CPP / Photon PUN Classic. Evidence is
the exact game executable and metadata shipped in the user's OGS34 IPA,
the OGS35 device log, and repository source. This is not a claim of server
authority or of a working feature until observed on two real clients.

## Self nickname

- Metadata: `PhotonPlayer.set_NickName` MD31598, one managed parameter.
- ARM64 method pointer: MI28961 at RVA `0x02390D08` resolves to native
  RVA `0x013D753C`. `get_NickName` MD31597 immediately precedes this slot.
- The new UI accepts one local name (2–24 UTF-16 units, excluding controls).
  It binds the request to the current room and actor and rate-limits to one
  request per 10 seconds. UIKit never invokes Photon or IL2CPP directly.
- The Photon Update callback validates the original method pointer and
  local player identity, allocates a managed string, invokes the game's own
  setter on the local player only, and checks local readback. A positive local
  readback is **not** proof of server acceptance or visibility to account 2.

## Shield

- `toggleGodMode:` already has no host condition; it requires the prepared
  damage bridge. It intercepts the `DamageRemote` route for the local player.
- OGS36 publishes counters for callback entry, local bypass, other-player
  forwarding, and unknown-owner forwarding in full diagnostics.
- Grenade/explosion damage may follow another route; the original code has
  not proved coverage. No broader damage bypass was added.

## Requested room administration and spectator/team features

- Metadata names include `spectatorNames` and `SwitchTeam`, but `SwitchTeam`
  is **not** matched as a method definition in the version-24 method table.
  A metadata string is not a callable API or signature.
- `PunTeams.SetTeam` MD31983 is a separate PUN utility based on actor custom
  properties; it is not automatically the game's spectator or police/robber
  transition. Do not change remote player properties without a supported
  authorization path and server-side confirmation.
- `Room.set_MaxPlayers` MD31704 exists in metadata. The native RoomInfo
  getter reads a byte, but the menu snapshot has `OGS_MAX_PEERS=64`.
  Increasing to 100 or 200 would exceed the current client's bounded roster
  capacity and is not validated for map spawns, server limits, performance or
  late joins. No capacity mutation was made.

## Grenade continuation

- OGS35 test: `self+0x12C` before=after=`4784601`, adjacent `self+0x130`
  before=after=`4784600`. Neither changes through `GrenadeShootm` original.
- The observed callback is not proof that either field owns grenade inventory.
  Continue tracking the actual purchase/spawn/consume route. No write to
  either observed out-of-range field was added.

## QA acceptance

1. Build on macOS/ARM64; compare the built dylib with the one in the IPA.
2. Test OGS36 name change in a controlled two-account room. Inspect both
   clients' player lists after the update. Leave the result unconfirmed until
   account 2 sees the new name.
3. Test shield with the second account and inspect the callback/bypass counts.
   Do not infer protection from button color or host status.
4. Do not enable mass role changes or room sizes above verified capacities.
