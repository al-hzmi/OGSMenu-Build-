#pragma once
#include "OGSGameplayPolicy.h"

// Validate an explicitly selected target in the current verified roster.
// This is a local safety predicate, NOT proof the Photon server authorizes
// setting a different actor's player properties.
namespace ogs48 {
// The native operation hook only records transport calls; its installation
// state must never become an authorization condition for SetCustomProperties.
static inline bool allowNativeTeamDispatch(bool originalSetterExecutable,
                                           unsigned observerBridgeStatus) {
    (void)observerBridgeStatus;
    return originalSetterExecutable;
}
struct TeamRequestFacts {
    uintptr_t queuedRoom = 0;
    uintptr_t liveRoom = 0;
    int queuedActor = 0;
    int liveActor = 0;
    bool photonRoomValid = false;
    bool rosterValid = false;
    int otherPlayers = 0;
    int targetMatches = 0;
    int targetActor = 0;
    int destination = -1;
    ogs46::Mode mode = ogs46::Mode::Unknown;
    double age = -1.0;
};

static inline bool allowTeamRequest(const TeamRequestFacts &f) {
    // PhotonHandler.Update continues while the separate RoomController.Update
    // may be absent. Remote actor property writes only require the room and
    // actor to remain stable; they do not need an FPS avatar/controller.
    if (!f.photonRoomValid || !f.queuedRoom || f.queuedRoom != f.liveRoom ||
        f.queuedActor <= 0 || f.queuedActor != f.liveActor || !f.rosterValid ||
        f.otherPlayers < 1 || f.targetMatches != 1 ||
        f.targetActor <= 0 || f.targetActor == f.liveActor ||
        f.destination < 0 || f.destination > 2 ||
        !std::isfinite(f.age) || f.age < 0.0 || f.age > 3.0) return false;
    // Native SetTeam can be reached regardless of the local game-mode text.
    // A localized/unrecognized mode must not silently suppress a *selected*
    // actor request; game/Photon authorization remains authoritative.
    if (f.mode == ogs46::Mode::FFA && f.destination == 2) return false;
    return true;
}
}
