# OGS52 — do not gate team requests on an optional observer

User evidence: OGS51 request traces R1/R2/R4/R6 reached a validated target
`actor=1, Team=2` but ended with `REJECTED missing exact OGS51 operation bridge`.
The UI and Photon update were operational; no game property update was sent.

OGS52 keeps room identity, explicitly selected other Actor, private-test-room,
original Team Int32, expected-old-Team CAS, duplicate/cooldown protections and
native executable-address checks. It removes only the incorrect dependency on
the optional OpSetPropertiesOfActor observation bridge. When missing, the trace
states the bridge status and continues through the game's native
`PhotonPlayer.SetCustomProperties` entry. Local method return does not prove
network transport, server acceptance or recipient gameplay.

This directly fixes the observed **pre-send blocker**. Whether the server
permits changing another actor's property and whether the stock recipient
transitions remains unverified, as no user devices or session are available.

Previous OGS51 packages need the four native bridge patches in `fps`, not just
the dylib. The OGS52 package must be constructed from the exact OGS50 IPA with
`tools/package_ogs51.py`, which verifies the original executable and metadata
and patches all four required entries.

Do not infer kick or detection by another player from the user's second trace:
the local master shows actor 6, the generic event 203 count is 0, and no
disconnect/leave callback was observed. The six local SetMasterClient API
returns are submission results, not server proof. Host-recovery behavior is
unchanged in this release.
