#include "../OGSMenu/OGSGameplayPolicy.h"
#include <cassert>
#include <initializer_list>
#include <limits>
#include <stdexcept>
using namespace ogs46;
int main() {
    // Valid transitions and intentional restrictions, including spectator return.
    assert(teamDecision(0,1,-1,1,1,Mode::TDM)==Denial::None);
    assert(teamDecision(1,0,-1,1,1,Mode::TDM)==Denial::None);
    assert(teamDecision(2,0,-1,1,1,Mode::Normal)==Denial::None);
    assert(teamDecision(2,1,-1,2,1,Mode::Normal)==Denial::None);
    assert(teamDecision(2,1,-1,1,1,Mode::Normal)==Denial::Balance);
    assert(teamDecision(1,2,-1,1,2,Mode::TDM)==Denial::None);
    assert(teamDecision(1,0,5,0,0,Mode::TDM)==Denial::Busy);
    assert(teamDecision(0,1,0,0,0,Mode::TDM)==Denial::Busy);
    assert(teamDecision(1,0,-1,0,0,Mode::FFA)==Denial::None);
    assert(teamDecision(2,0,-1,0,0,Mode::FFA)==Denial::Mode);
    assert(teamDecision(2,0,-1,0,0,Mode::Unknown)==Denial::Mode);
    assert(teamDecision(3,0,-1,0,0,Mode::TDM)==Denial::Invalid);
    assert(teamDecision(1,1,-1,0,0,Mode::TDM)==Denial::SameTeam);
    // Stale queued actions cannot follow actor reuse, respawn, or scene reload.
    Identity a{11,22,33,4}; assert(same(a,a));
    for(int k=0;k<4;++k) {
        Identity b=a;if(k==0)++b.room;if(k==1)++b.controller;if(k==2)++b.player;if(k==3)++b.actor;
        assert(!same(a,b));
    }
    assert(!same({},{}));
    // Real scoped restoration, including exceptions and nested frame calls.
    for(float original : {0.f,9.81f,20.f}) for(uint8_t originalAir : {uint8_t(0),uint8_t(1)}) {
        float gravity=original; uint8_t air=originalAir;
        try {
            MovementLease outer(gravity,air);assert(gravity==0.f&&air==1);
            { MovementLease inner(gravity,air); }
            assert(gravity==0.f&&air==1);throw std::runtime_error("native update failure");
        } catch(const std::runtime_error&) {}
        assert(gravity==original && air==originalAir);
    }
    float nan=std::numeric_limits<float>::quiet_NaN();
    for(float dt : {0.f,-1.f,1.f,nan}) assert(verticalStep(1,dt,false)==0.f);
    assert(std::fabs(verticalStep(1,.02f,false)-.1f)<1e-6f);
    assert(std::fabs(verticalStep(-1,.02f,false)+.1f)<1e-6f);
    assert(verticalStep(0,.02f,false)==0.f);
    assert(verticalStep(1,.02f,true)==0.f);
    // Independent of Time.timeScale: only monotonic wall-clock elapsed time
    // is fed into verticalStep, so a 10x speed setting cannot zero the ascent.
    assert(std::fabs(realFlightInterval(100.02,100.)-.02f)<1e-5f);
    assert(realFlightInterval(100.2,100.)==0.f);
    assert(realFlightInterval(99.,100.)==0.f);
    assert(realFlightInterval(100.,0.)==0.f);
    assert(realFlightInterval(std::numeric_limits<double>::quiet_NaN(),100.)==0.f);
}
