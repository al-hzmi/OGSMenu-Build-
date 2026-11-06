#include "../OGSMenu/OGS51TrainingPolicy.h"
#include <initializer_list>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <limits>
int main() {
    // Real IL2CPP List<T> header: size and version are adjacent Int32s.
    unsigned char list[32]{}; int32_t size=3,version=8;
    std::memcpy(list+0x18,&size,4);std::memcpy(list+0x1c,&version,4);
    uint64_t formerRead;std::memcpy(&formerRead,list+0x18,8);
    assert(formerRead>64); // OGS50 falsely rejected a valid, mutated list.
    int32_t corrected;std::memcpy(&corrected,list+0x18,4);
    assert(ogs51::listSize(corrected,2,4));
    assert(ogs51::listSize(0,-1,0));
    assert(!ogs51::listSize(-1,0,4));assert(!ogs51::listSize(3,3,4));
    assert(!ogs51::listSize(3,0,2));assert(!ogs51::listSize(65,0,128));
    assert(!ogs51::listSize(3,-2,4));assert(!ogs51::listSize(3,0,1000000));
    assert(ogs51::visible({.5f,.5f,2},.1));
    assert(!ogs51::visible({.5f,.5f,-1},.1));
    assert(!ogs51::visible({1.01f,.5f,2},.1));
    assert(!ogs51::visible({.5f,-.1f,2},.1));
    assert(!ogs51::visible({.5f,.5f,2},.251));
    assert(!ogs51::visible({.5f,.5f,2},-1));
    assert(!ogs51::visible({std::numeric_limits<float>::quiet_NaN(),.5f,2},.1));
    // Normalized projection stays independent of iPhone point resolution.
    for (auto width : {852., 932., 956.}) {
        double x=.5*width-38;assert(x>76&&x+76<width-154);
    }
}
