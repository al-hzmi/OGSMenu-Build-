#pragma once

// Pure, host-testable decision. Unknowns always pass through to game logic.
struct OGSExplosionFacts {
    bool enabled;
    bool ownerVerified;
    bool localOwner;
    bool roomVerified;
    bool actorMatches;
    bool localMaster;
    bool twoAccountRoom;
    bool deadFlagVerified;
    bool alive;
};

static constexpr bool OGSShouldBlockLocalExplosion(const OGSExplosionFacts &f) {
    return f.enabled && f.ownerVerified && f.localOwner && f.roomVerified &&
           f.actorMatches && f.localMaster && f.twoAccountRoom &&
           f.deadFlagVerified && f.alive;
}
