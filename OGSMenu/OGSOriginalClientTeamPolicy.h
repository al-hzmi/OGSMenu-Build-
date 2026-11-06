#pragma once
#include "OGSGameplayPolicy.h"

// Validate an explicitly selected target in the current verified roster.
// This is a local safety predicate, NOT proof the Photon server authorizes
// setting a different actor's player properties.
namespace ogs48 {
struct TeamRequestFacts {
    ogs46::Identity queued;
    ogs46::Identity live;
    bool snapshotValid = false;
    bool rosterValid = false;
    int otherPlayers = 0;
    int targetMatches = 0;
    int targetActor = 0;
    int destination = -1;
    ogs46::Mode mode = ogs46::Mode::Unknown;
    double age = -1.0;
};

static inline bool allowTeamRequest(const TeamRequestFacts &f) {
    ogs46::Identity queued = f.queued, live = f.live;
    queued.player = live.player = 0;
    if (!f.snapshotValid || !f.rosterValid || !ogs46::same(queued, live) ||
        f.otherPlayers < 1 || f.targetMatches != 1 ||
        f.targetActor <= 0 || f.targetActor == f.live.actor ||
        f.destination < 0 || f.destination > 2 ||
        !std::isfinite(f.age) || f.age < 0.0 || f.age > 3.0) return false;
    // Native SetTeam can be reached regardless of the local game-mode text.
    // A localized/unrecognized mode must not silently suppress a *selected*
    // actor request; game/Photon authorization remains authoritative.
    if (f.mode == ogs46::Mode::FFA && f.destination == 2) return false;
    return true;
}
}
