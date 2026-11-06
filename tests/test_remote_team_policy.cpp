#include "../OGSMenu/OGSRemoteTeamPolicy.h"
#include <cassert>
#include <limits>
using namespace ogs46;
using namespace ogs47;
int main() {
    Identity a{10,20,30,2};
    assert(canApply(a,a,1,1,true,1));
    assert(!canApply(a,a,1,1,false,1));
    assert(!canApply(a,a,1,3,true,1));
    assert(!canApply(a,a,2,2,true,1));
    assert(!canApply(a,a,1,1,true,30));
    assert(!canApply(a,a,1,1,true,-1));
    assert(!canApply(a,a,1,1,true,std::numeric_limits<double>::quiet_NaN()));
    for(int i=0;i<4;++i){Identity b=a;if(i==0)++b.room;if(i==1)++b.controller;if(i==2)++b.player;if(i==3)++b.actor;assert(!canApply(a,b,1,1,true,1));}
    assert(approvedTeamDecision(2,1,-1,Mode::TDM)==Denial::None);
    assert(approvedTeamDecision(1,2,-1,Mode::Normal)==Denial::None);
    assert(approvedTeamDecision(0,1,-1,Mode::FFA)==Denial::None);
    assert(approvedTeamDecision(1,0,-1,Mode::FFA)==Denial::None);
    assert(approvedTeamDecision(2,1,-1,Mode::FFA)==Denial::Mode);
    assert(approvedTeamDecision(2,1,-1,Mode::Unknown)==Denial::Mode);
    assert(approvedTeamDecision(2,1,0,Mode::TDM)==Denial::Busy);
    assert(approvedTeamDecision(2,2,-1,Mode::TDM)==Denial::SameTeam);
    assert(approvedTeamDecision(3,1,-1,Mode::TDM)==Denial::Invalid);
}
