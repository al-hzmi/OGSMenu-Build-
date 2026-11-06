#pragma once

#include <cmath>

// A Photon ActorNumber identifies a room membership, not an account.
// These guards never infer an account from names, timing or adjacent actor IDs.
namespace ogsname {

constexpr double kTransientRoomReadGraceSeconds = 1.25;

inline bool HasUniquePublishedUserId(const char *userId, unsigned occurrences) {
    return userId && userId[0] != '\0' && occurrences == 1u;
}

inline bool CanPromoteActorHistory(bool uniquePublishedUserId,
                                   bool actorHistoryExists,
                                   bool publishedHistoryExists) {
    return uniquePublishedUserId && actorHistoryExists && !publishedHistoryExists;
}

inline bool ShouldPreserveHistoryDuringMissingRoom(double now,
                                                    double missingSince,
                                                    bool hadPreviousRoom,
                                                    bool confirmedOutside,
                                                    bool changedLocalActor,
                                                    bool changedRoomEpoch) {
    if (!hadPreviousRoom || confirmedOutside || changedLocalActor ||
        changedRoomEpoch || !std::isfinite(now) ||
        !std::isfinite(missingSince) || missingSince <= 0.0)
        return false;
    return now >= missingSince &&
           now - missingSince < kTransientRoomReadGraceSeconds;
}

} // namespace ogsname
