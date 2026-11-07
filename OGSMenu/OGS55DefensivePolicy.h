#pragma once
#include <array>
#include <atomic>
#include <cstdint>
#include <cstddef>
#include <cmath>
namespace ogs55 {
// Called under the existing state lock. A local SDK ownership observation is
// deliberately NOT a reset: SetMasterClient may update a cache optimistically.
struct RecoveryBudget {
    unsigned attempts = 0;
    double firstAttempt = -1;
    void arm() { attempts = 0; firstAttempt = -1; }
    bool exhausted(double now) const {
        return !std::isfinite(now) || attempts >= 3 ||
            (firstAttempt >= 0 && (now < firstAttempt || now-firstAttempt >= 30));
    }
    void consume(double now) { if (firstAttempt < 0) firstAttempt=now; ++attempts; }
};
enum class Shape : uint8_t { Pass, RejectNull, RejectShort, Unknown };
inline Shape damageShape(bool present, bool typed, bool lengthReadable, uint64_t length) {
    if (!present) return Shape::RejectNull;
    if (!typed || !lengthReadable) return Shape::Unknown;
    return length < 3 ? Shape::RejectShort : Shape::Pass;
}
inline bool reject(Shape s) { return s==Shape::RejectNull || s==Shape::RejectShort; }
struct Incident {
    double at=0;
    uint64_t roomEpoch=0;
    int32_t localActor=0, masterBefore=0, masterAfter=0;
    int16_t teamBefore=-1,teamAfter=-1;
    int8_t uiBefore=-1,uiAfter=-1;
    uint16_t kind=0, event=0;
    uint8_t verdict=0;
    // No peer names, UserIDs, room names, tokens, pointers, or inferred attacker.
};
template<size_t N> class IncidentRing {
    static_assert(N>0,"nonempty ring");
    std::array<Incident,N> rows{};
    std::atomic_flag lock=ATOMIC_FLAG_INIT;
    size_t used=0,next=0;
    std::atomic<uint64_t> dropped{0};
public:
    bool push(const Incident &v) {
        if(lock.test_and_set(std::memory_order_acquire)) {++dropped;return false;}
        rows[next]=v;next=(next+1)%N;if(used<N)++used;
        lock.clear(std::memory_order_release);return true;
    }
    size_t snapshot(std::array<Incident,N> &out) {
        if(lock.test_and_set(std::memory_order_acquire))return 0;
        size_t count=used,first=(next+N-used)%N;
        for(size_t i=0;i<count;++i)out[i]=rows[(first+i)%N];
        lock.clear(std::memory_order_release);return count;
    }
    uint64_t drops() const {return dropped.load(std::memory_order_relaxed);}
};
}
