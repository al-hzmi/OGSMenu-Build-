#pragma once
#include "OGSGameplayPolicy.h"

// Exact fps 3.4.0 metadata + ARM64 evidence: tools/audit_ogs46.py.
// Included after the existing OGS memory/ownership/room helpers.
namespace ogs46 {
struct Snapshot {
    Identity id; double at = 0;
    bool valid = false, privateRoom = false, alive = false, aliveVerified = false, master = false;
    int team = -1, respawn = -2, a = -1, b = -1;
    Mode mode = Mode::Unknown;
};
struct Request { Identity id; int team = -1; double at = 0; };
static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
static Snapshot latest;
static Request pending;
static Identity flightIdentity;
static bool flightWanted = false;
static double flightLastGoodAt = 0.;
static int axis = 0;
static int status = 0; // 1=requested, 2=issued, 3=local state observed, negatives=denial
static int awaitingTeam = -1;
static double issuedAt = 0;
static Identity issuedIdentity;
static volatile uint32_t bridgeStatus[7] = {};
static volatile uint32_t flightFrames = 0;
static Update0Fn roomOriginal = nullptr, fpsOriginal = nullptr;
using MoveFn = int32_t (*)(void *, Vector3, const void *);
static MoveFn moveOriginal = nullptr;
// Only active during one FPSController.Update on its Unity thread. Other
// CharacterControllers and other threads always receive their original vector.
static thread_local void *movingController = nullptr;
static thread_local float vertical = 0.f;

static double now() { return CACurrentMediaTime(); }
template<class T> static bool read(void *p, uintptr_t off, T &v) {
    return p && OGSReadMemory((uintptr_t)p + off, &v, sizeof(v));
}
static bool objectAlive(void *p) {
    uintptr_t native = 0;
    return read(p, 0x10, native) && native >= 0x100000000ULL;
}
static bool currentRC(void *rc) {
    void *klass = nullptr, *fields = nullptr, *current = nullptr;
    return OGSReadPointer(OGSResolveRVA(0x281B1B8), &klass) &&
        OGSReadPointer((uintptr_t)klass + 0xB8, &fields) &&
        OGSReadPointer((uintptr_t)fields + 0x30, &current) && current == rc && objectAlive(rc);
}
static bool listCount(void *rc, uintptr_t off, int &count) {
    void *list = nullptr;
    return read(rc, off, list) && read(list, 0x18, count) && count >= 0 && count <= 255;
}
static Snapshot sample(void *rc) {
    Snapshot s; s.at = now();
    uintptr_t room = 0; int32_t actor = 0, master = 0;
    uint8_t leaving = 1;
    if (!currentRC(rc) || !read(rc, 0xFA, leaving) || leaving ||
        !OGSReadAutoRoom(&room, &actor, &master)) return s;
    s.id.room = room; s.id.actor = actor; s.id.controller = (uintptr_t)rc;
    s.master = actor == master;
    bool open = true, visible = true;
    s.privateRoom = OGSReadRoomPrivacy(room, &open, &visible) && !open && !visible;
    void *player = nullptr, *mode = nullptr;
    if (!read(rc, 0x108, player) || !read(rc, 0x1B0, s.team) ||
        !read(rc, 0x1C0, s.respawn) || !read(rc, 0x1B8, mode) ||
        !listCount(rc, 0xD8, s.a) || !listCount(rc, 0xE0, s.b)) return s;
    NSString *name = OGSReadIl2CppString(mode);
    s.mode = [name isEqualToString:@"TDM"] ? Mode::TDM :
        [name isEqualToString:@"NORMAL"] ? Mode::Normal :
        [name isEqualToString:@"FFA"] ? Mode::FFA : Mode::Unknown;
    if (player && objectAlive(player)) {
        bool verified = false; int32_t ownerActor = 0; uint8_t killed = 255;
        bool mine = OGSIsDamageToLocalPlayerWithActor(player, &verified, &ownerActor);
        if (!verified || !mine || ownerActor != actor) return s;
        s.id.player = (uintptr_t)player;
        s.aliveVerified = read(player, 0x12C, killed) && killed <= 1;
        s.alive = s.aliveVerified && killed == 0;
    }
    s.valid = actor > 0 && s.team >= 0 && s.team <= 2;
    return s;
}
static Snapshot snapshot() {
    os_unfair_lock_lock(&lock); Snapshot s = latest; os_unfair_lock_unlock(&lock);
    if (now() - s.at > 1.) s.valid = false;
    return s;
}
static bool sameSession(Identity a, Identity b) {
    a.player = b.player = 0; return same(a, b);
}
static void stopFlight() {
    os_unfair_lock_lock(&lock); flightWanted = false; axis = 0; flightLastGoodAt = 0.; os_unfair_lock_unlock(&lock);
}
static void remoteTick(void *self, const Snapshot &s);
static void processSelfRequest(void *self, const Snapshot &s, const Request &req);
static void roomUpdate(void *self, void *method) {
    if (roomOriginal) roomOriginal(self, method);
    Snapshot s = sample(self);
    if (__atomic_load_n(&gOGS.godModeOn, __ATOMIC_ACQUIRE)) {
        uintptr_t boundRoom = __atomic_load_n(&gOGS46ShieldRoom, __ATOMIC_ACQUIRE);
        int32_t boundActor = __atomic_load_n(&gOGS46ShieldActor, __ATOMIC_ACQUIRE);
        uintptr_t boundPlayer = __atomic_load_n(&gOGS46ShieldPlayer, __ATOMIC_ACQUIRE);
        // No crowd-size or hidden-room predicate. Bind on a verified host
        // sample; a single incomplete sample or temporary host loss merely
        // suspends protection (the native callbacks verify MasterClient).
        if (!boundRoom && s.valid && s.master && s.alive && s.id.player) {
            __atomic_store_n(&gOGS46ShieldRoom, s.id.room, __ATOMIC_RELEASE);
            __atomic_store_n(&gOGS46ShieldActor, s.id.actor, __ATOMIC_RELEASE);
            __atomic_store_n(&gOGS46ShieldPlayer, s.id.player, __ATOMIC_RELEASE);
        } else if (boundRoom && s.valid &&
                   (s.id.room != boundRoom || s.id.actor != boundActor ||
                    (s.id.player && s.id.player != boundPlayer) ||
                    (s.aliveVerified && !s.alive))) {
            // Never carry a protection binding across death, a new avatar,
            // room transition or actor change (OGS41 partial-death regression).
            __atomic_store_n(&gOGS.godModeOn, 0, __ATOMIC_RELEASE);
            __atomic_store_n(&gOGS46ShieldRoom, 0, __ATOMIC_RELEASE);
            __atomic_store_n(&gOGS46ShieldActor, 0, __ATOMIC_RELEASE);
            __atomic_store_n(&gOGS46ShieldPlayer, 0, __ATOMIC_RELEASE);
        }
    }
    Request req;
    os_unfair_lock_lock(&lock);
    latest = s;
    if (flightWanted) {
        // Explicit death, actor/room/scene changes and avatar replacement
        // disarm immediately. A single incomplete IL2CPP sample does not.
        bool changed = s.valid && (!sameSession(s.id, flightIdentity) ||
            (s.id.player && s.id.player != flightIdentity.player) || s.team == 0 ||
            (s.aliveVerified && !s.alive));
        uintptr_t liveRoom = 0; int32_t liveActor = 0, liveMaster = 0;
        if (!s.valid && OGSReadAutoRoom(&liveRoom, &liveActor, &liveMaster) &&
            (liveRoom != flightIdentity.room || liveActor != flightIdentity.actor)) changed = true;
        if (s.valid && s.alive && same(s.id, flightIdentity)) flightLastGoodAt = s.at;
        if (changed || now() - flightLastGoodAt > 1.5) {
            flightWanted = false; axis = 0; flightLastGoodAt = 0.;
        }
    }
    req = pending; pending.team = -1;
    os_unfair_lock_unlock(&lock);
    if (awaitingTeam >= 0) {
        if (!s.valid || !sameSession(s.id, issuedIdentity) || now() - issuedAt > 30.) {
            os_unfair_lock_lock(&lock); status = -8; os_unfair_lock_unlock(&lock);
            awaitingTeam = -1;
        } else if (s.team == awaitingTeam && (awaitingTeam == 0 ? !s.id.player : s.alive)) {
            os_unfair_lock_lock(&lock); status = 3; os_unfair_lock_unlock(&lock);
            awaitingTeam = -1; // local observation only; remote acceptance unmeasured
        }
    }
    processSelfRequest(self, s, req);
    remoteTick(self, s);
}
static void processSelfRequest(void *self, const Snapshot &s, const Request &req) {
    if (req.team < 0) return;
    int result = -1;
    if (s.valid && s.privateRoom && same(req.id, s.id) && now() - req.at < 3.) {
        Denial d = teamDecision(req.team, s.team, s.respawn, s.a, s.b, s.mode);
        if (d == Denial::None && awaitingTeam < 0) {
            // Verify all dependencies dereferenced by the normal positive-team
            // transition before entering IL2CPP. No synthetic RPC/property edits.
            void *camera = nullptr, *ui = nullptr, *xml = nullptr;
            bool ready = read(self, 0x28, camera) && objectAlive(camera) &&
                read(self, 0x2E8, ui) && objectAlive(ui) && read(self, 0x2F8, xml) && objectAlive(xml);
            if (ready) {
                stopFlight();
                using PrepareFn = void (*)(void *, int32_t, bool, bool, const void *);
                ((PrepareFn)OGSResolveRVA(0x13F65C0))(self, req.team, true, false, nullptr);
                awaitingTeam = req.team; issuedAt = now(); issuedIdentity = s.id;
                result = 2;
            } else result = -7;
        } else result = d == Denial::Balance ? -4 : d == Denial::Mode ? -5 : -3;
    }
    os_unfair_lock_lock(&lock); status = result; os_unfair_lock_unlock(&lock);
}
static int32_t move(void *self, Vector3 displacement, const void *method) {
    if (self && self == movingController) displacement.y = vertical;
    return moveOriginal ? moveOriginal(self, displacement, method) : 0;
}
static void fpsUpdate(void *self, void *method) {
    static thread_local double previousRealFrame = 0.;
    static thread_local Identity previousFlightID;
    Identity id; bool wanted; int input;
    os_unfair_lock_lock(&lock); id = flightIdentity; wanted = flightWanted; input = axis;
    os_unfair_lock_unlock(&lock);
    if (!wanted) { previousRealFrame = 0.; if (fpsOriginal) fpsOriginal(self, method); return; }
    void *pn = nullptr, *back = nullptr, *cc = nullptr, *transform = nullptr, *ladder = nullptr;
    // Other players must never stop or modify the local player's flight.
    if (!read(self, 0x60, pn) || (uintptr_t)pn != id.player) {
        if (fpsOriginal) fpsOriginal(self, method); return;
    }
    double realNow = now();
    float realDt = same(id, previousFlightID) ? realFlightInterval(realNow, previousRealFrame) : 0.f;
    previousFlightID = id;
    previousRealFrame = realNow;
    Snapshot s = sample((void *)id.controller);
    if (s.valid && (!sameSession(s.id, id) ||
        (s.id.player && s.id.player != id.player) || (s.aliveVerified && !s.alive))) {
        stopFlight(); if (fpsOriginal) fpsOriginal(self, method); return;
    }
    bool usable = s.valid && s.alive && same(s.id, id) &&
        read(pn, 0xF8, back) && back == self && objectAlive(self) &&
        read(self, 0x90, cc) && objectAlive(cc) && read(self, 0x98, transform) && objectAlive(transform) &&
        read(self, 0x108, ladder) && !objectAlive(ladder);
    float gravity = 0; uint8_t air = 0;
    usable = usable && read(self, 0x3C, gravity) && std::isfinite(gravity) && fabsf(gravity) <= 1000.f &&
        read(self, 0x4C, air) && air <= 1;
    // A frame-level transient read failure pauses flight for this one frame;
    // RoomController.Update handles sustained failures and identity changes.
    if (!usable) {
        if (objectAlive(ladder)) stopFlight();
        if (fpsOriginal) fpsOriginal(self, method); return;
    }
    // Validate the actual ranges written (including unaligned bool/float fields).
    for (uintptr_t off : {0x38u, 0x48u, 0x80u, 0xC8u, 0xD0u}) {
        if (!OGSIsWritableMappedSlot((uintptr_t)self + off)) {
            stopFlight(); if (fpsOriginal) fpsOriginal(self, method); return;
        }
    }
    void *settings = nullptr, *settingsClass = nullptr; uint8_t paused = 1;
    bool readPause = OGSReadPointer(OGSResolveRVA(0x281B1B8), &settingsClass) &&
        OGSReadPointer((uintptr_t)settingsClass + 0xB8, &settings) && read(settings, 0x158, paused);
    float step = verticalStep(input, realDt, !readPause || paused != 0);
    auto &g = *(float *)((uintptr_t)self + 0x3C);
    auto &a = *(uint8_t *)((uintptr_t)self + 0x4C);
    auto &vy = *(float *)((uintptr_t)self + 0x80);
    auto &falling = *(uint8_t *)((uintptr_t)self + 0xD0);
    struct ContextLease {
        void *old; float oldVertical;
        ContextLease(void *p, float v) : old(movingController), oldVertical(vertical) {
            movingController = p; vertical = v;
        }
        ~ContextLease() { movingController = old; vertical = oldVertical; }
    };
    {
        MovementLease lease(g, a);
        ContextLease context(cc, step);
        vy = 0.f; falling = 0;
        // Original Update still reads joystick, updates camera/crouch/animations,
        // and computes grounded/velocity from the original collision-aware Move.
        if (fpsOriginal) fpsOriginal(self, method);
    }
    // No accumulated downward speed or fictitious fall from flight's origin.
    // The next normal frame starts a real fall at the current altitude.
    vy = 0.f; falling = 0;
    Vector3 pos = ((Transform_GetPosition_Fn)OGSResolveRVA(0x198B948))(transform, nullptr);
    if (std::isfinite(pos.y)) *(float *)((uintptr_t)self + 0xCC) = pos.y;
    __atomic_fetch_add(&flightFrames, 1u, __ATOMIC_RELAXED);
}
static bool installBridge(unsigned i, uintptr_t entry, uintptr_t stub, uintptr_t slot,
                          uint32_t prolog, uintptr_t callback, uintptr_t *original) {
    if (__atomic_load_n(&bridgeStatus[i], __ATOMIC_ACQUIRE) == 1) return true;
    uintptr_t base = OGSFindGameImage(), prior = 0; uint32_t first = 0, words[7] = {};
    if (!base) return false;
    auto branch = [](uintptr_t a, uintptr_t b) {
        return 0x14000000u | ((uint32_t)(((int64_t)b - (int64_t)a) / 4) & 0x3ffffffu);
    };
    int64_t pages = ((int64_t)(slot & ~0xFFFULL) - (int64_t)(stub & ~0xFFFULL)) / 4096;
    uint32_t expected[7] = {0x90000010u | (((uint32_t)pages & 3u) << 29) |
        ((((uint32_t)pages >> 2) & 0x7ffffu) << 5),
        0x91000210u | ((uint32_t)(slot & 0xfff) << 10), 0xf9400210, 0xb4000050,
        0xd61f0200, prolog, branch(stub + 24, entry + 4)};
    if (!OGSIsExecutableGameAddress(base + entry) || !OGSIsExecutableGameAddress(base + stub) ||
        !OGSIsWritableMappedSlot(base + slot) || !OGSReadMemory(base + entry, &first, 4) ||
        first != branch(entry, stub) || !OGSReadMemory(base + stub, words, sizeof(words)) ||
        memcmp(words, expected, sizeof(words)) || !OGSReadMemory(base + slot, &prior, 8) ||
        (prior && prior != callback)) {
        __atomic_store_n(&bridgeStatus[i], 2u, __ATOMIC_RELEASE); return false;
    }
    __atomic_store_n(original, base + stub + 20, __ATOMIC_RELEASE);
    __atomic_store_n((uintptr_t *)(base + slot), callback, __ATOMIC_RELEASE);
    __atomic_store_n(&bridgeStatus[i], 1u, __ATOMIC_RELEASE); return true;
}
static void install51();
static void install() {
    os_unfair_lock_lock(&gHookInstallLock);
    // Install the movement dependency before allowing FPS.Update to use it.
    installBridge(2, 0x19BB3B4, 0x3240, 0x2A98E08, 0xD10083FF,
        (uintptr_t)&move, (uintptr_t *)&moveOriginal);
    if (__atomic_load_n(&bridgeStatus[2], __ATOMIC_ACQUIRE) == 1)
        installBridge(1, 0x137BE64, 0x3200, 0x2A98E00, 0xD10303FF,
            (uintptr_t)&fpsUpdate, (uintptr_t *)&fpsOriginal);
    installBridge(0, 0x13F3F2C, 0x31C0, 0x2A98DF8, 0x6DBC23E9,
        (uintptr_t)&roomUpdate, (uintptr_t *)&roomOriginal);
    os_unfair_lock_unlock(&gHookInstallLock);
    install51();
}
static bool queueTeam(int team) {
    Snapshot s = snapshot();
    os_unfair_lock_lock(&lock);
    bool ok = s.valid && s.privateRoom && pending.team < 0 && status != 2;
    if (ok) { pending = {s.id, team, now()}; status = 1; }
    else status = -1;
    os_unfair_lock_unlock(&lock); return ok;
}
static bool toggleFlight() {
    Snapshot s = snapshot();
    os_unfair_lock_lock(&lock);
    if (flightWanted) { flightWanted = false; axis = 0; os_unfair_lock_unlock(&lock); return true; }
    bool ok = s.valid && s.alive && s.respawn == -1 &&
        __atomic_load_n(&bridgeStatus[1], __ATOMIC_ACQUIRE) == 1 &&
        __atomic_load_n(&bridgeStatus[2], __ATOMIC_ACQUIRE) == 1;
    if (ok) { flightIdentity = s.id; flightWanted = true; axis = 0; flightLastGoodAt = now(); }
    os_unfair_lock_unlock(&lock); return ok;
}
static NSString *statusText() {
    Snapshot s = snapshot(); int code; bool flying;
    os_unfair_lock_lock(&lock); code = status; flying = flightWanted;
    // An expired snapshot disarms controls even if the old room no longer ticks.
    if (!s.valid && now() - s.at > 1.5) {
        flightWanted = false; axis = 0; flightLastGoodAt = 0.; pending.team = -1; flying = false;
        __atomic_store_n(&gOGS.godModeOn, 0, __ATOMIC_RELEASE);
    }
    os_unfair_lock_unlock(&lock);
    if (!s.valid) return flying ? @"الطيران ينتظر استقرار تحديث اللعبة" : @"انتظار دخول غرفة وتحديث اللاعب";
    if (flying) return @"الطيران مفعّل • الأسهم للارتفاع وعصا اللعبة للحركة";
    if (code == 1) return @"طلب انتقال ينتظر تحديث اللعبة";
    if (code == 2) return @"نُفّذ المسار الأصلي • انتظار الحالة المحلية";
    if (code == -4) return @"رفض الانتقال: شرط توازن الفرق في اللعبة";
    if (code == -5) return @"هذا الفريق غير متاح في نمط اللعب الحالي";
    if (code == -3) return @"انتظر إعادة الظهور أو اختر فريقًا مختلفًا";
    if (code < 0) return @"لم يكتمل الانتقال • أعد المحاولة بعد استقرار الغرفة";
    return [NSString stringWithFormat:@"محليًا: %@ • تحقق من جهازك الثاني",
        s.team == 0 ? @"مشاهد" : s.team == 1 ? @"شرطة" : @"لصوص"];
}
}

#include "OGSRemoteTeam.h"
#include "OGS51Native.h"
#include "OGSOriginalClientTeam.h"
#include "OGS51Training.h"
