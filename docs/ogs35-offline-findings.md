# OGS35 — offline findings and bounded runtime probe

Source: OGS34 device log reported on 2026-11-05; the user's fps 3.4.0 IPA;
original ARM64 executable; and `OGSMenu/ModMenu.mm` at `35bbd590`.

## Grenades

- `GrenadeShootm` was invoked once, weapon type 5 matched, owner was not
  rejected, and reading `self+0x12C` succeeded.
- Raw `self+0x12C` was `5754687` (`0x0057cf3f`). Thus the existing range
  gate rejected the write: `out-of-range=1`, `eligible=0`, `total writes=0`.
- Native `FPSWeapon.FireOneShot` has a separate path that loads `self+0x12C`
  at RVA `0x013809f8`, subtracts one at `0x013809fc`, and stores it back at
  `0x01380a00`. That does **not** prove this path runs for grenade type 5.
- In the observed OGS34 case, `Raw ammo after` remained `INT32_MIN` because
  post-original sampling was incorrectly gated on eligibility.
- OGS35 reads `self+0x12C` after the original grenade callback even when the
  range gate rejects. It also records read-only `self+0x130` before/after.
  Neither field is made write-eligible by the probe. The previous safety gate
  remains unchanged; no server acceptance is claimed.

## Other requested capabilities — discovery, not an authority claim

- The metadata contains gameplay names `spectatorNames` and `SwitchTeam` and
  Photon/PUN names `SetTeam`, `set_NickName`, and `set_MaxPlayers`.
  Presence of a string is not a verified ABI, callable method, or entitlement
  to change another player's state.
- Existing `toggleGodMode:` has **no MasterClient gate**. It installs the
  offline-prepared damage bridge, then toggles a local flag. Its coverage for
  grenade explosions or other damage routes has not been demonstrated.
- Native `RoomInfo.get_MaxPlayers` reads a byte at room offset `+0x20`, but
  this alone says nothing about a supported server-authorized limit. The menu
  maintains a fixed 64-peer snapshot cap. In particular, a claim that rooms
  can safely hold 100 or 200 players is unverified.
- Self nickname changes and room-owner capacity changes should go through
  authenticated game/Photon interfaces, with acceptance verified by the
  server or subsequent property update, and with game/UI limits respected.
- Moving another player to spectator or switching their team requires a
  supported game moderation/admin authorization path. No forced remote-state
  mutation was implemented.

## Status and next test

1. This is a diagnostic-only release for grenade-phase visibility; no new
   ammo range, raw-pointer write, forged event, or authority bypass was added.
2. Build and check ARM64 on GitHub Actions.
3. Compare the versioned artifact with the dylib embedded in the packaged
   IPA, test archive integrity and original game file hashes.
4. In a controlled room, compare the OGS35 before/after raw fields and the
   `changed during GrenadeShootm` count following a genuine throw.
5. If values do not change, do not infer that `+0x12C` is the grenade inventory
   field. Locate the actual consumption state before attempting any write.
