# OGS37 — bounded room capacity changes

User-confirmed OGS36 result: the self nickname changed in game. That confirms
the local setter route in one session, but is not evidence for unrelated APIs.
The grenade test still reported an out-of-range `FPSWeapon +0x12C` value of
`9814925` and zero ammo writes. The shield remained disabled during that test;
its damage coverage cannot be evaluated from those counters.

## Independent native and metadata evidence

- fps 3.4.0 IL2CPP v24 metadata: `Room.set_MaxPlayers`, method definition
  31704, method index 29298, one managed parameter, declaring type `Room`.
- Method pointer table slot RVA `0x02391790` contains native entry
  `0x1013F1AF0`, equivalent to RVA `0x013F1AF0` in the fixed image.
- ARM64 assembly at the entry reads the requested integer in `w1`, clamps
  values above 255, compares against the one-byte field at `room+0x20`,
  calls the game's property-update path, and writes the local `room+0x20`.
  This is direct evidence of a native capacity setter, not proof a server
  will accept a requested value.

## Implementation

- One new button `زيادة سعة الروم` in the scrollable menu. Choices are
  **8, 10, 16 or 32**, and only values above the currently observed capacity
  are shown. No unverified 100/200 option.
- Room pointer, actor identity, and current local MasterClient are validated
  when opening the UI, selecting a value, and executing the queued request.
  A change of room, actor or MasterClient cancels the pending action.
- The setter executes on the existing game's Photon Update callback only.
  Its method pointer must exactly match the expected ARM64 entry.
- The operation uses a 10-second local request cooldown, sends no forged
  Photon messages, and never directly writes `room+0x20`.
- Diagnostics report queued, attempted, locally observed readback,
  rejected, and failed. Positive local readback is **not** server approval.
- The existing nickname, shield telemetry, grenade diagnostics, and original
  game executable remain unchanged by this source edit.

## Live acceptance checks

1. In a controlled room created with capacity 6, activate the new button and
   request 8. Verify `OGS37` attempted and local readback counters.
2. Have the second account inspect the reported room capacity, then test
   admission of a seventh participant if available. A positive host-side
   local readback alone is **not** sufficient.
3. Repeat with 10, without going above the verified game client bound of 32.
4. Test a master transfer before selection to verify the request is rejected
   if the local player is no longer MasterClient.

No spectator or police/robber remote-player transfer has been enabled. The
existing metadata names have not established an authorized, validated game
method for coercing another player's role. Grenade restocking and all-damage
shield effectiveness are also still unconfirmed.
