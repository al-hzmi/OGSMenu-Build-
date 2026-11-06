#include "../OGSMenu/OGSNameIdentityPolicy.h"
#include <cassert>
#include <limits>

int main() {
    using namespace ogsname;
    // ActorNumber cannot identify a returning account without an ID.
    assert(!HasUniquePublishedUserId(nullptr, 0));
    assert(!HasUniquePublishedUserId("", 0));
    assert(!HasUniquePublishedUserId("stable-user", 0));
    assert(!HasUniquePublishedUserId("stable-user", 2));
    assert(HasUniquePublishedUserId("stable-user", 1));

    // Promote the baseline only for the same actor when its ID appears late.
    assert(CanPromoteActorHistory(true, true, false));
    assert(!CanPromoteActorHistory(false, true, false));
    assert(!CanPromoteActorHistory(true, false, false));
    assert(!CanPromoteActorHistory(true, true, true));

    // A transient missing room pointer should not destroy the name baseline.
    assert(ShouldPreserveHistoryDuringMissingRoom(10.0, 9.99,
                                                 true, false, false, false));
    assert(ShouldPreserveHistoryDuringMissingRoom(11.24, 10.0,
                                                 true, false, false, false));
    assert(!ShouldPreserveHistoryDuringMissingRoom(11.25, 10.0,
                                                  true, false, false, false));
    assert(!ShouldPreserveHistoryDuringMissingRoom(10.01, 10.0,
                                                  false, false, false, false));
    assert(!ShouldPreserveHistoryDuringMissingRoom(10.01, 10.0,
                                                  true, true, false, false));
    assert(!ShouldPreserveHistoryDuringMissingRoom(10.01, 10.0,
                                                  true, false, true, false));
    assert(!ShouldPreserveHistoryDuringMissingRoom(10.01, 10.0,
                                                  true, false, false, true));
    assert(!ShouldPreserveHistoryDuringMissingRoom(10.01, 0.0,
                                                  true, false, false, false));
    assert(!ShouldPreserveHistoryDuringMissingRoom(9.0, 10.0,
                                                  true, false, false, false));
    assert(!ShouldPreserveHistoryDuringMissingRoom(
        std::numeric_limits<double>::quiet_NaN(), 10.0,
        true, false, false, false));
    assert(!ShouldPreserveHistoryDuringMissingRoom(
        10.01, std::numeric_limits<double>::infinity(),
        true, false, false, false));
}
