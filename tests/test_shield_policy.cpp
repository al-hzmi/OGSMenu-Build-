#include "../OGSMenu/OGSShieldPolicy.h"
#include <cassert>
#include <cstdio>

int main() {
    constexpr int n = 8;
    for (unsigned mask = 0; mask < (1u << n); ++mask) {
        OGSExplosionFacts f{bool(mask&1),bool(mask&2),bool(mask&4),bool(mask&8),
            bool(mask&16),bool(mask&32),bool(mask&64),bool(mask&128)};
        assert(OGSShouldBlockLocalExplosion(f) == (mask == (1u << n)-1));
    }
    std::puts("PASS all 256 host/verified-local-owner policy combinations, no room-size restriction");
}
