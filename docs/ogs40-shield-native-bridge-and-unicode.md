# OGS40 — shield-native path and styled Unicode nickname fix

## Confirmed from OGS39 diagnostics

- The user's styled nickname starts with U+200F RIGHT-TO-LEFT MARK.
  Foundation `controlCharacterSet` includes Unicode categories Cc and Cf,
  so OGS39 rejected the nickname *before* submitting it to Photon.
- OGS39 `KillPlayer passive hook=2` means its table entry failed identity
  validation. It recorded no kill callbacks and could not establish whether
  a server-owned host used `KillPlayer` to kill the local player.
- Room capacity changes were user-confirmed working; the capacity protocol,
  bound room checks and occupancy getter are unchanged.

## OGS40 name behavior

- Keep 1..100 grapheme clusters and exact UTF-16 content in the managed
  string (`FastAllocateString` plus verbatim UTF-16 copy).
- Permit selected Unicode format characters U+061C, U+200C, U+200D,
  U+200E and U+200F so stylized Arabic and emoji are not rejected locally.
- Reject remaining control and dangerous bidi override/embedding characters.
- Acceptance or sanitization by the remote Photon/game service remains to be
  confirmed from a second device.

## OGS40 shield behavior

- Use an offline-prepared, native `PlayerNetwork.KillPlayer` hook instead of
  the OGS39 method-pointer hook, which can miss native direct calls.
- Verified MD30380 / MI29168, ARM64 entry RVA `0x013E8FBC`, first instruction
  `sub sp, sp, #112` (machine word `0xD101C3FF`). The pre-sign script copies
  that original instruction into a trampoline and branches back to entry+4.
- The stub occupies 0x3080..0x309B, previously zero-filled __TEXT header pad.
- Dedicated writable callback storage is at RVA 0x02A98DD0, the byte **after**
  `__DATA,__common` ends. There are 0x3230 bytes of unused alignment gap
  before the end of the writable __DATA segment; the older 16-byte gap after
  `__bss` is fully occupied by the existing magic/god bridge slots.
- At runtime only a preallocated writable function-pointer slot is updated;
  the hook does not alter code pages or patch an unverified function pointer.
- When shield is on, **only KillPlayer for a verified local PhotonView owner**
  is bypassed. Other players and unreadable/unknown owner callbacks always
  run the original, unmodified.
- The existing local-owner-only `DamageRemote` bridge is retained.
- Neither bridge requires MasterClient ownership; **server-authoritative death
  or another unobserved game path may still kill the player**. This is an
  explicitly experimental extension, not guaranteed invulnerability.
- The shield UI refuses enabling if the matching OGS40 patched executable is
  missing, to avoid a half-installed/misleading feature.

## Release and regressions

- `tools/package_ogs40_ipa.py` accepts the exact SHA-pinned OGS34 source IPA,
  modifies only the game executable's verified KillPlayer entry/stub and
  swaps the dylib. All remaining ZIP members are hashed and compared.
- The output IPA signature is invalid. Re-sign the entire IPA in the normal
  authorized iOS workflow. Do not just drop the OGS40 dylib into OGS39.
- Room size, grenade experiment, role checks and host request rate-limits
  remain unchanged. No remote team/spectator or flight control is added.

## Two-account runtime test (required)

1. With the shield off, confirm one ordinary kill works. The shield should not
   block kills until enabled and the `KillPlayer bridge` status should be 0.
2. Enable shield and inspect `OGS40 KillPlayer native bridge=1`. First test
   damage and ordinary shooting while the local player owns MasterClient.
3. Transfer MasterClient to the second account, repeat the same kills and
   capture `callbacks`, `local bypass`, `DamageRemote local bypass` and the
   actual survival/death result. Do not infer success from callbacks alone.
4. With shield off, confirm normal kill and respawn still work for both
   accounts. This guards against global suppression of kill handling.
5. Change to the exact nickname `‏²̶²̶ᴀᴅ̶ɴ̶ᴍᴏһ`, including U+200F, and
   verify the second account sees the intended characters.
