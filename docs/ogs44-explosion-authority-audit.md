# OGS44 explosion investigation and passive diagnostics

## Scope and provenance

Built from experimental source based on OGS42. CI run 42144308814 succeeded for source commit e19120cd76fe6afbc4caa6865483a75a820c5b08. Its artifact archive SHA256 is 612a46c1827128ac89805d908bbea9fcf6b945afdddc6e711c48a97cd45d7bfa. Unsigned diagnostic IPA SHA256 is 39f9d416732b98195ebb0a3bb7caefee34e0ca1aeb7fd718003cfd7c6e03f41c. This is instrumentation, not an invulnerability repair. No device tests or signature verification were performed.

## New ARM64 / IL2CPP dataflow evidence

The exact OGS34 game hash is ad1794ad50d976e042bbbe0c604a4e8bbb3fe8092787ee9ce24d07e7a530ac2f. Metadata v24 literal and metadata-usage pointer mapping identifies the object accessed at 0x283d768 as the string PlayerHP and the object at 0x283d7a8 as KillPlayer. This is not a name guessed solely from a nearby method.

| Path | Observed local behavior / authority branch | Evidence |
|---|---|---|
| BombDmg near | Checks PhotonView.isMine. Independently, checks isMasterClient; on master retrieves target PhotonPlayer.CustomProperties[PlayerHP], subtracts 101 when present, calls SetCustomProperties, compares resulting value against 0, then on lethal branch calls PhotonView.RPC with KillPlayer and target numeric 0, and stores 1 to self+0x12c. | 0x13e7e14, 0x13e7f18, 0x13e7f70, 0x13e7fd8, 0x13e8078, 0x13e807c, 0x13e8134, 0x13e813c |
| C4Dmg near | Same patterns: local ownership check; master branch retrieves PlayerHP, subtracts 101, requests property update, sends KillPlayer RPC if result is nonpositive, sets self+0x12c. | 0x13e8564, 0x13e8634, 0x13e868c, 0x13e86f4, 0x13e8794, 0x13e8798, 0x13e8880, 0x13e8888 |
| BombDmgLong / C4DmgLong | Long-range paths subtract 33 rather than 101. | 0x13e8384 / 0x13e8a90 |
| DamageRemote | Its master branch obtains PlayerHP, calls GetDMG, subtracts result, requests a custom property update, and can send KillPlayer RPC. Existing OGS42 shield only bypasses this method for the locally owned PlayerNetwork receiver. | master check 0x13e781c, GetDMG 0x13e792c, subtraction 0x13e7930, property call 0x13e79c8, RPC 0x13e7a84 |
| JoinedTeam | Input 1 and 2 are tested. The remaining branch loads an Arabic spectator literal and sets an activity value 0 before an RPC named PostActivityRemote. This is evidence of an activity representation, not proof that team 0 performs a complete network-authorized spectator transition. | 0x13f6e78, 0x13f6e80, 0x13f6ef0, 0x13f6ef4, 0x13f7164 |
| Scoreboard team buttons | Two GUI.Button calls lead to PrepareRespawn with team values 1 and 2 and wasSwitched=1. Role labels and remote permission still require independent identification. | 0x141a158, 0x141a1c4, 0x141a370, 0x141a3dc |
| FPSController.Update | Calls CharacterController.Move and reads its velocity; position and movement are coupled to other logic. It is not enough to overwrite a position or gravity field safely. | 0x137cd2c, 0x137cd50 |

Near explosion damage is 101 in the existing-key branch. The absence/fallback and exact game-mode conditions matter; do not assert 101 is universal. The property setter is a client request; static code does not establish server acceptance. Target value 0 is stated numerically because its enum interpretation has not been independently verified here.

## Interpretation and limits

The old shield bridges DamageRemote and ApplyDamage; the four BombDmg/C4Dmg paths are not directly intercepted by it. Thus an explosion can execute the shown master branch even while the shield is on, including when the local player is master. Explosive handlers can also set playerKilled before KillPlayer finishes on a client, so skipping the KillPlayer body is an unsafe strategy.

When another client is master, its DamageRemote path may process the victim's remote PlayerNetwork instance, update PlayerHP, and send KillPlayer. A hook installed on the victim does not change the remote master's process. This is a concrete explanation consistent with the evidence; the precise runtime path in the user's session still needs two-client logs. Photon server acceptance and anti-cheat behavior have not been established.

## OGS44 implementation

A new offline packager checks exact executable and library hashes, metadata method identities, first instruction, empty ARM64 stub area and a writable zero-fill gap disjoint from declared sections. It inserts four callback stubs and displaced-instruction trampolines into the unsigned IPA. Empty callback slots fall through to originals. When the user enables shield, the library validates the complete stub instructions and slots before registering callbacks; on an older or incompatible IPA, diagnostics report unavailable instead of patching runtime executable code.

Callbacks observe and count BombDmg, BombDmgLong, C4Dmg, C4DmgLong; distinguish local / other / unknown receiver; capture the local client's room master status and playerKilled pre-flag for verified local receivers; and always call the corresponding original function. They do not change HP, network messages, damage, death, or movement. Counters persist after shield is turned off, so compare differences across separate tests. Enabling the shield once is needed to install these on-demand diagnostics. Role classification uses current local room state and is not server acknowledgement.

Instrumented counters cannot establish the exact initiating packet, RPC sender, PlayerHP before/after, remote observations or animation. Failed owner identification is recorded as unknown. Hooks can add overhead and need real device validation.

## Verification

- OGS44 ARM64 dylib compiled and CI succeeded; the downloaded artifact digest matches GitHub's published artifact.
- Test tool rebuilt patched executable from the original and compared it with the diagnostic IPA; ZIP test and SHA256 comparison of all unchanged entries passed.
- Verified metadata string mappings, selected call identities and ARM64 instructions, all four entry branches, fallback stubs, displaced prologues and continuation targets.
- Modified original executable / stub bytes were rejected via exact source hash.
- Source-level checks confirm four callbacks invoke originals.
- Not verified: re-signing, installation, iOS runtime hook attachment, gameplay, two-client sync, health snapshots or real authority.

## Controlled test matrix

For each of bullet, grenade, C4 and falling: run with the instrumented client as master then as non-master; for each, run shield on and off. First enable shield once to install probes, confirm OGS44 bridge=1 for four paths, then toggle off for controls. Record a diagnostic snapshot before and immediately after each single damage event and compare differences. Use only consenting accounts in a private room. Record visible health before/after separately; the OGS44 counters do not read it. Record both screens, avatar animation, playerKilled pre-flag, kill counters, respawn, local/master actor IDs, OGS44 total/local/other/unknown, and master/non-master samples. A zero local count is meaningful only if bridge=1 and the tested damage was observed during the interval. Local or remote proof depends on each observer.

Player names and room capacity have not been regression-tested on a device. Spectator and flight are not implemented. Do not test or claim cross-client immunity from this diagnostic build.
