#include "../OGSMenu/OGSOriginalClientTeamPolicy.h"
#include <cassert>
#include <limits>

int main() {
    using namespace ogs46;
    using namespace ogs48;
    TeamRequestFacts f;
    f.queued = {100, 200, 300, 1};
    f.live = f.queued;
    f.snapshotValid = true;
    f.rosterValid = true;
    f.otherPlayers = 1;
    f.targetMatches = 1;
    f.targetActor = 2;
    f.destination = 0;
    f.mode = Mode::TDM;
    f.age = .25;
    assert(allowTeamRequest(f));
    f.destination = 1; assert(allowTeamRequest(f));
    f.destination = 2; assert(allowTeamRequest(f));
    f.mode = Mode::FFA; assert(!allowTeamRequest(f));
    f.destination = 1; assert(allowTeamRequest(f));
    f.mode = Mode::Unknown; assert(allowTeamRequest(f));
    f.mode = Mode::Normal;
    f.otherPlayers = 2; assert(allowTeamRequest(f));
    f.otherPlayers = 12; assert(allowTeamRequest(f));
    f.otherPlayers = 0; assert(!allowTeamRequest(f));
    f.otherPlayers = 1;
    f.targetMatches = 0; assert(!allowTeamRequest(f));
    f.targetMatches = 2; assert(!allowTeamRequest(f));
    f.targetMatches = 1;
    f.targetActor = 1; assert(!allowTeamRequest(f));
    f.targetActor = 2;
    f.rosterValid = false; assert(!allowTeamRequest(f));
    f.rosterValid = true;
    f.snapshotValid = false; assert(!allowTeamRequest(f));
    f.snapshotValid = true;
    f.age = -1.; assert(!allowTeamRequest(f));
    f.age = 3.1; assert(!allowTeamRequest(f));
    f.age = std::numeric_limits<double>::quiet_NaN(); assert(!allowTeamRequest(f));
    f.age = .1;
    ++f.live.room; assert(!allowTeamRequest(f));
    --f.live.room;
    ++f.live.actor; assert(!allowTeamRequest(f));
    --f.live.actor;
    ++f.live.controller; assert(!allowTeamRequest(f));
    --f.live.controller;
    // A respawn can replace the local avatar while staying in the same room.
    ++f.live.player; assert(allowTeamRequest(f));
    f.destination = -1; assert(!allowTeamRequest(f));
    f.destination = 3; assert(!allowTeamRequest(f));
}
