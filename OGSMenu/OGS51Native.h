#pragma once
// Exact OGS50 binary; installed through checked pre-sign native bridges.
namespace ogs46 {
using ActorPropertiesFn = bool (*)(void *, int32_t, void *, void *, bool, const void *);
static ActorPropertiesFn actorPropertiesOriginal = nullptr;
static Update0Fn playerUpdate51Original = nullptr;
using Weapon51Fn = void (*)(void *, const void *);
static Weapon51Fn fire51Original = nullptr, throw51Original = nullptr;
static thread_local uint64_t propertiesRequestID = 0;
static thread_local int propertiesTargetActor = 0;
static NSMutableArray<NSString *> *trace51;
static void trace51Add(uint64_t id, NSString *stage) {
    os_unfair_lock_lock(&lock);
    if (!trace51) trace51 = [NSMutableArray array];
    if (trace51.count >= 64) [trace51 removeObjectAtIndex:0];
    [trace51 addObject:[NSString stringWithFormat:@"R%llu %.3f %@", (unsigned long long)id, now(), stage]];
    os_unfair_lock_unlock(&lock);
}
static NSString *trace51Text() {
    os_unfair_lock_lock(&lock); NSString *s = [trace51 componentsJoinedByString:@"\n"] ?: @"لا طلبات OGS51"; os_unfair_lock_unlock(&lock); return s;
}
static bool actorProperties51(void *self, int32_t actor, void *props, void *expected, bool web, const void *method) {
    uint64_t id = propertiesRequestID;
    bool relevant = id && actor == propertiesTargetActor;
    if (relevant) trace51Add(id, @"OpSetPropertiesOfActor ENTER (CAS)");
    bool queued = actorPropertiesOriginal ? actorPropertiesOriginal(self, actor, props, expected, web, method) : false;
    if (relevant) trace51Add(id, queued ? @"transport queued=true; NOT server ACK" : @"transport queued=false; NOT permission verdict");
    return queued;
}
static void *table51New() {
    void *klass = nullptr;
    if (!OGSReadPointer(OGSResolveRVA(0x281A3F8), &klass) || !klass) return nullptr;
    using Alloc = void *(*)(void *); using Ctor = void (*)(void *, const void *);
    void *v = ((Alloc)OGSResolveRVA(0x1294520))(klass);
    if (v) ((Ctor)OGSResolveRVA(0x173AEE4))(v, nullptr);
    return v;
}
static void *table51Get(void *table, void *key) {
    if (!table || !key) return nullptr;
    using Fn = void *(*)(void *, void *, const void *);
    return ((Fn)OGSResolveRVA(0x173AF94))(table,key,nullptr);
}
static void table51Put(void *table, void *key, void *value) {
    using Fn = void (*)(void *, void *, void *, const void *);
    ((Fn)OGSResolveRVA(0x173B00C))(table,key,value,nullptr);
}
static bool int51Read(void *value, int32_t &out) {
    void *expected = nullptr, *actual = nullptr;
    return OGSReadPointer(OGSResolveRVA(0x2815340), &expected) && expected &&
        read(value,0,actual) && actual == expected && read(value,0x10,out);
}
static void *int51Box(int32_t v) {
    void *klass = nullptr;
    if (!OGSReadPointer(OGSResolveRVA(0x2815340),&klass) || !klass) return nullptr;
    using Fn = void *(*)(void *, const void *);
    return ((Fn)OGSResolveRVA(0x1294484))(klass,&v);
}
static void *player51Properties(void *p) {
    if (!p) return nullptr;
    using Fn=void *(*)(void *,const void *);
    return ((Fn)OGSResolveRVA(0x13D756C))(p,nullptr);
}
// Case-sensitive game key. PunTeams' lowercase "team" is a separate Byte enum.
static constexpr const char *gameTeam51Key = "Team";
static bool gameTeam51Read(void *p, int32_t &v) {
    void *key=OGSManagedStringFromNSString(@"Team");
    return key && int51Read(table51Get(player51Properties(p),key),v) && v>=0 && v<=2;
}
}
