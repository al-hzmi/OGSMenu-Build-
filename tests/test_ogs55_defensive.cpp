#include "../OGSMenu/OGS55DefensivePolicy.h"
#include <cassert>
#include <thread>
#include <limits>
#include <iostream>
int main() {
    using namespace ogs55;
    RecoveryBudget b;b.arm();
    // 24 hours of callbacks, including periodic local ownership oscillations:
    // only an explicit arm replenishes the absolute submission budget.
    unsigned sends=0;
    for(unsigned frame=0;frame<86400*60;++frame) {
        double t=double(frame)/60;
        if(!b.exhausted(t) && frame%600==0) {b.consume(t);++sends;}
    }
    assert(sends==3);assert(b.exhausted(86400));
    b.arm();b.consume(100);assert(!b.exhausted(129.99));assert(b.exhausted(130));
    assert(b.exhausted(99));assert(b.exhausted(std::numeric_limits<double>::quiet_NaN()));
    b.arm();assert(!b.exhausted(1000));
    assert(reject(damageShape(false,false,false,0)));
    for(uint64_t n=0;n<3;++n)assert(reject(damageShape(true,true,true,n)));
    for(uint64_t n:{3ULL,4ULL,100ULL})assert(!reject(damageShape(true,true,true,n)));
    assert(!reject(damageShape(true,false,true,0)));
    assert(!reject(damageShape(true,true,false,0)));
    IncidentRing<64> ring;
    for(int i=0;i<10000;++i){Incident e;e.localActor=i;assert(ring.push(e));}
    std::array<Incident,64> rows;assert(ring.snapshot(rows)==64);
    assert(rows.front().localActor==9936 && rows.back().localActor==9999);
    std::atomic<bool> go{false};
    auto writer=[&](int actor){while(!go.load()){}for(int i=0;i<100000;++i){Incident e;e.localActor=actor;e.masterBefore=actor;e.masterAfter=actor;ring.push(e);}};
    std::thread a(writer,1),c(writer,2);go=true;
    for(int j=0;j<100000;++j){size_t n=ring.snapshot(rows);for(size_t i=0;i<n;++i)if(rows[i].localActor<=2)assert(rows[i].localActor==rows[i].masterBefore && rows[i].masterBefore==rows[i].masterAfter);}
    a.join();c.join();
    std::cout<<"PASS finite recovery, malformed shape, normal shapes, unknown pass-through, ring wrap and concurrent snapshots; NOT iOS gameplay\n";
}
