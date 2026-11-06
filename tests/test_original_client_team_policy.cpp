#include "../OGSMenu/OGSOriginalClientTeamPolicy.h"
#include <cassert>
#include <limits>

int main() {
    using namespace ogs46;
    using namespace ogs48;
    TeamRequestFacts f;
    f.queuedRoom = 100;
    f.liveRoom = 100;
    f.queuedActor = 1;
    f.liveActor = 1;
    f.photonRoomValid = true;
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
    f.photonRoomValid = false; assert(!allowTeamRequest(f));
    f.photonRoomValid = true;
    f.age = -1.; assert(!allowTeamRequest(f));
    f.age = 3.1; assert(!allowTeamRequest(f));
    f.age = std::numeric_limits<double>::quiet_NaN(); assert(!allowTeamRequest(f));
    f.age = .1;
    ++f.liveRoom; assert(!allowTeamRequest(f));
    --f.liveRoom;
    ++f.liveActor; assert(!allowTeamRequest(f));
    --f.liveActor;
    // A respawn or stopped RoomController.Update must not interrupt a
    // Photon-bound property submission for a selected actor.
    assert(allowTeamRequest(f));
    f.destination = -1; assert(!allowTeamRequest(f));
    f.destination = 3; assert(!allowTeamRequest(f));
}
