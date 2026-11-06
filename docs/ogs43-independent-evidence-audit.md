# Independent OGS34/41/42 evidence — 2026-11-06

## Scope
Read-only inspection of the supplied OGS41 IPA, the OGS34 and OGS42 IPA files, the OGS42 source and its published CI artifact. This branch adds a reproducible static verifier, not a gameplay fix. No device, two-client, server, or Apple signature verification was available.

## Package and identity
- OGS41 IPA SHA256: a1a8d993bd0d4cf569edf33e1b773db6b12ff82de5451b1880925db7399de7cf
- OGS42 IPA SHA256: f850d7e104ac21b78e2c22ed14c94426b6837ae2aedf52d2f945d289b0f59654
- OGS34 IPA SHA256: 76b314f1c2136da0950159081cfa2dcd84c2ad3bd4cc32009cee227fb8b8100f
- All IPA ZIP integrity checks pass. ZIP contains a 64-bit ARM64 fps executable and OGSMenu.dylib and IL2CPP metadata magic FAB11BAF, version 24.
- SHA256 comparison of all 172 uncompressed entries in OGS41 and OGS42 found exactly one difference: Frameworks/OGSMenu.dylib. The OGS41 and OGS42 game executable SHA256 is e46148304090f8de5a4fadb009883d0e7a2e0c5541e8628261164b6457b735b2. The original game executable SHA256 is ad1794ad50d976e042bbbe0c604a4e8bbb3fe8092787ee9ce24d07e7a530ac2f.
- OGS34 already includes the ApplyDamage and DamageRemote bridge preparation. Between OGS34 and OGS41/42 the game executable has 29 changed bytes, only in the KillPlayer entry and stub/trampoline ranges.
- The OGS42 IPA dylib SHA256 is 2ba6fce67bf08aedcefd929a378742d7e10f9ceeebd52c22123c6a1cfaf42d59; it matches the extracted OGS42 CI artifact. CI run 42132608186 succeeded on source commit 03e85e97cbf32fc3709eb6c6b7ad08db48e943e3. Compiling this branch was unnecessary for the Python-only audit change.

## Independent method and callsite evidence
Addresses are image-relative RVAs for this exact binary. Direct caller names use nearest-lower method mapping and should be treated as high-confidence static attribution rather than runtime traces.

| Method | RVA | Evidence |
|---|---:|---|
| FPSController.FallingDamageAlert | 0x137ce08 | BL at 0x137cf70 to ApplyDamage |
| HitBox.Damage | 0x138a734 | B at 0x138a8a0 to ApplyDamage |
| PlayerNetwork.ApplyDamage | 0x13e7360 | IL2CPP MD30368; hooked by prepared bridge |
| PlayerNetwork.DamageRemote | 0x13e7588 | IL2CPP MD30369; BL 0x13e792c to GetDMG |
| PlayerNetwork.GetDMG | 0x13e7bb0 | Directly referenced by DamageRemote |
| PlayerNetwork.BombDmg | 0x13e7db0 | Grenade.AreaOfEffectDamage B at 0x138987c |
| PlayerNetwork.C4Dmg | 0x13e8508 | C4.AreaOfEffectDamage B at 0x13548f8 |
| PlayerNetwork.KillPlayer | 0x13e8fbc | Writes byte at self+0x12c; local branch BL at 0x13e9130 to PrepareRespawn |
| RoomController.PrepareRespawn | 0x13f65c0 | Also reached by scoreboard paths; BL at 0x13f6e04 to JoinedTeam |
| RoomController.JoinedTeam | 0x13f6e30 | Tests team IDs 1 and 2; identity of team names and network authority not proved |
| FPSController.Update | 0x137be64 | Update exists; movement control and state restoration not verified |

The original byte store and respawn call were checked against instructions. OGS41 source skips original KillPlayer for a verified local actor when the shield is on; OGS42 forwards it. This explains a plausible mechanism for the regression: bypassing a local death handler can suppress the game's own respawn scheduling after some other path has already changed visible state. The exact source of the observed ragdoll and the end-to-end causal chain remain unproven without an instrumented device run.

Counters supplied by the user indicate 16 local DamageRemote bypasses, zero local ApplyDamage bypasses, and one local KillPlayer bypass in the reported OGS41 scenario. They do not identify the authoritative death decision or prove whether Photon server, master, attacker, or another route caused it. A guaranteed synced shield when another actor controls the authoritative decision would require cooperation from whichever party actually owns that logic; this is conditional, not a verified assertion of server architecture.

## Verification performed
- New `tools/verify_independent_ipa.py` passed on OGS34 versus OGS41 and OGS34 versus OGS42: ZIP test and duplicate member check, exact hashes, architecture, metadata version, eight method identities, five direct callsites, KillPlayer stub and trampoline continuation.
- A copy of OGS42 with one flipped executable byte was rejected as an unexpected executable.
- Existing `tools/verify_ogs42_static.py` passed on OGS34 plus OGS42 source.
- All uncompressed OGS41/42 entries were compared by SHA256.
- Existing GitHub CI run 42132608186 completed successfully; its OGS42 artifact ZIP digest and contained dylib matched the provided artifacts.
- Not performed: Apple signature validity, install, actual hook attachment on device, interactive name/capacity regression, shield/death/respawn, spectator, team, flight or two-client tests. No new IPA was produced.

## Next controlled device test
Install the complete pre-existing OGS42 IPA using the user's legitimate signing method. In a private room with a consenting second account, record: OGS42 label and installed hook status; shield enabled; actors/master IDs; before-and-after counters; local and other client's views; once with local master and once with other master; normal death and respawn with shield off as a control. Capture whether KillPlayer local original forwarded increments, pre-dead flag distribution, and whether respawn completes. Do not treat local counters as server acknowledgment.

Spectator and team transitions require tracing the game's legitimate selection and sync state; the two existing team comparisons do not establish police/thief labels or spectator behavior. Flight requires verified ownership, lifecycle, input, movement restoration and remote sync before implementation.
