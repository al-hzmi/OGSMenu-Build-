#pragma once

// Pure, host-testable decision. Unknowns always pass through to game logic.
struct OGSExplosionFacts {
    bool enabled;
    bool ownerVerified;
    bool localOwner;
    bool roomVerified;
    bool actorMatches;
    bool localMaster;
    bool privacyVerified;
    bool hidden;
    bool closed;
    bool deadFlagVerified;
    bool alive;
};

static constexpr bool OGSShouldBlockLocalExplosion(const OGSExplosionFacts &f) {
    return f.enabled && f.ownerVerified && f.localOwner && f.roomVerified &&
           f.actorMatches && f.localMaster && f.privacyVerified && f.hidden &&
           f.closed && f.deadFlagVerified && f.alive;
}
