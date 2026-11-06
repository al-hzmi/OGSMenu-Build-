#pragma once
#include "OGSGameplayPolicy.h"

// Restrict experimental remote-team requests to a verified two-account room.
// This is a local safety predicate, NOT proof the Photon server authorizes
// setting a different actor's player properties.
namespace ogs48 {
struct TeamRequestFacts {
    ogs46::Identity queued;
    ogs46::Identity live;
    bool snapshotValid = false;
    bool rosterValid = false;
    int otherPlayers = 0;
    int soleOtherActor = 0;
    int targetActor = 0;
    int destination = -1;
    ogs46::Mode mode = ogs46::Mode::Unknown;
    double age = -1.0;
};

static inline bool allowTeamRequest(const TeamRequestFacts &f) {
    ogs46::Identity queued = f.queued, live = f.live;
    queued.player = live.player = 0;
    if (!f.snapshotValid || !f.rosterValid || !ogs46::same(queued, live) ||
        f.otherPlayers != 1 || f.soleOtherActor != f.targetActor ||
        f.targetActor <= 0 || f.targetActor == f.live.actor ||
        f.destination < 0 || f.destination > 2 ||
        !std::isfinite(f.age) || f.age < 0.0 || f.age > 3.0) return false;
    if (f.mode == ogs46::Mode::Unknown) return false;
    if (f.mode == ogs46::Mode::FFA && f.destination == 2) return false;
    return true;
}
}
