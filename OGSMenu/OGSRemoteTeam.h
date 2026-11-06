#pragma once
#include "OGSRemoteTeamPolicy.h"

// Cooperative protocol. Both devices require OGS47. Photon custom properties
// are NOT authenticated sender identity: each receiver explicitly approves the
// actual requested team. Never invoke a remote object's local respawn method.
namespace ogs46 {
struct RemoteRequest {
    Identity id; int sender = 0, target = 0, team = -1;
    NSString *nonce = nil; NSString *wire = nil; double at = 0;
};
static RemoteRequest sendCommand, consentPrompt;
static int receiveCommand = 0, consentDecision = 0;
static Identity receiveCommandID;
static bool receivingUI = false, promptShown = false;
static NSString *remoteMessage = @"نقل المحدد: يلزم OGS47 على الجهازين";
// The following state is owned exclusively by the RoomController.Update thread.
static RemoteRequest outgoing, incoming;
static Identity receiverSession;
static int receiverMaster = 0;
static bool receiving = false, incomingIssued = false;
static NSString *lastWire = nil;
static double nextRemotePoll = 0, incomingIssuedAt = 0;

static void remoteMessageSet(NSString *s) {
    os_unfair_lock_lock(&lock); remoteMessage = s; os_unfair_lock_unlock(&lock);
}
static NSString *remoteStatusText() {
    os_unfair_lock_lock(&lock); NSString *s = remoteMessage; os_unfair_lock_unlock(&lock); return s;
}
static void *findActor(int actor) {
    if (actor <= 0 || actor >= 1000000) return nullptr;
    using Fn = void *(*)(int32_t, const void *);
    void *p = ((Fn)OGSResolveRVA(0x13D6D08))(actor, nullptr);
    int32_t found = 0; uint8_t inactive = 1;
    if (!read(p, 0x10, found) || found != actor) return nullptr;
    using InactiveFn = bool (*)(void *, const void *);
    inactive = ((InactiveFn)OGSResolveRVA(0x13D694C))(p, nullptr);
    return inactive ? nullptr : p;
}
static NSString *propertyString(void *player, NSString *key) {
    if (!player) return nil;
    using PropsFn = void *(*)(void *, const void *);
    void *props = ((PropsFn)OGSResolveRVA(0x13D756C))(player, nullptr);
    void *managedKey = OGSManagedStringFromNSString(key);
    if (!props || !managedKey) return nil;
    using GetFn = void *(*)(void *, void *, const void *);
    void *value = ((GetFn)OGSResolveRVA(0x173AF94))(props, managedKey, nullptr);
    // Only decode System.String, verified against the allocated key's class.
    void *keyClass = nullptr, *valueClass = nullptr;
    if (!read(managedKey, 0, keyClass) || !read(value, 0, valueClass) || keyClass != valueClass) return nil;
    return OGSReadIl2CppString(value);
}
static bool publishOwn(const Snapshot &s, NSString *key, NSString *value) {
    // This protocol writes ONLY the local PhotonPlayer's own custom property.
    using LocalFn = void *(*)(const void *);
    void *local = ((LocalFn)OGSResolveRVA(0x13CABF0))(nullptr);
    int32_t actor = 0;
    if (!s.valid || !read(local, 0x10, actor) || actor != s.id.actor) return false;
    void *klass = nullptr;
    if (!OGSReadPointer(OGSResolveRVA(0x281A3F8), &klass) || !klass) return false;
    using NewFn = void *(*)(void *);
    void *table = ((NewFn)OGSResolveRVA(0x1294520))(klass);
    if (!table) return false;
    using CtorFn = void (*)(void *, const void *);
    ((CtorFn)OGSResolveRVA(0x173AEE4))(table, nullptr);
    void *k = OGSManagedStringFromNSString(key), *v = OGSManagedStringFromNSString(value);
    if (!k || !v) return false;
    using ItemFn = void (*)(void *, void *, void *, const void *);
    ((ItemFn)OGSResolveRVA(0x173B00C))(table, k, v, nullptr);
    using SetFn = void (*)(void *, void *, void *, bool, const void *);
    ((SetFn)OGSResolveRVA(0x13D0CC0))(local, table, nullptr, false, nullptr);
    return true; // dispatch only, not remote delivery/acceptance
}
static void acknowledge(const Snapshot &s, const RemoteRequest &r, int code) {
    publishOwn(s, @"ogs47.ack", [NSString stringWithFormat:@"47|%@|%d|%d", r.nonce, code, r.team]);
}
static bool parseRequest(NSString *wire, int sender, int target, RemoteRequest &r) {
    if (!wire || wire.length > 100) return false;
    NSArray<NSString *> *v = [wire componentsSeparatedByString:@"|"];
    if (v.count != 5 || ![v[0] isEqualToString:@"47"] ||
        ![v[1] isEqualToString:[NSString stringWithFormat:@"%d", sender]] ||
        ![v[2] isEqualToString:[NSString stringWithFormat:@"%d", target]] ||
        ![@[@"0", @"1", @"2"] containsObject:v[3]] || v[4].length != 32 ||
        [v[4] rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location != NSNotFound) return false;
    r.sender = sender; r.target = target; r.team = v[3].intValue; r.nonce = v[4]; r.wire = wire; return true;
}
static bool queueRemoteTeam(int target, int team) {
    Snapshot s = snapshot();
    if (!s.valid || !s.master || target <= 0 || target == s.id.actor || team < 0 || team > 2) {
        remoteMessageSet(@"اختر حسابك الثاني؛ إرسال النقل يتطلب أن تكون الهوست"); return false;
    }
    RemoteRequest r; r.id = s.id; r.sender = s.id.actor; r.target = target; r.team = team; r.at = now();
    r.nonce = [[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
    r.wire = [NSString stringWithFormat:@"47|%d|%d|%d|%@", r.sender, target, team, r.nonce];
    os_unfair_lock_lock(&lock); sendCommand = r; remoteMessage = @"طلب نقل المحدد في الانتظار"; os_unfair_lock_unlock(&lock); return true;
}
static void toggleReceiving() {
    Snapshot s = snapshot();
    os_unfair_lock_lock(&lock);
    receiveCommand = receivingUI ? -1 : 1; receiveCommandID = s.id;
    os_unfair_lock_unlock(&lock);
}
static void stopRemote() {
    os_unfair_lock_lock(&lock); receiveCommand = -1; receivingUI = false;
    consentPrompt = {}; consentDecision = 0; sendCommand = {}; os_unfair_lock_unlock(&lock);
}
static RemoteRequest takeConsentPrompt() {
    os_unfair_lock_lock(&lock); RemoteRequest r;
    if (consentPrompt.nonce && !promptShown) { r = consentPrompt; promptShown = true; }
    os_unfair_lock_unlock(&lock); return r;
}
static void decideConsent(NSString *nonce, bool approve) {
    os_unfair_lock_lock(&lock);
    if ([consentPrompt.nonce isEqualToString:nonce]) consentDecision = approve ? 1 : -1;
    os_unfair_lock_unlock(&lock);
}
static void clearPrompt() {
    os_unfair_lock_lock(&lock); consentPrompt = {}; consentDecision = 0; promptShown = false; os_unfair_lock_unlock(&lock);
}
static int applyApprovedTeam(void *rc, const Snapshot &s, int team) {
    Denial d = ogs47::approvedTeamDecision(team, s.team, s.respawn, s.mode);
    if (d == Denial::SameTeam) return (team == 0 ? !s.id.player : s.alive) ? 4 : -3;
    if (d != Denial::None || awaitingTeam >= 0) return -3;
    void *camera = nullptr, *ui = nullptr, *xml = nullptr;
    if (!read(rc, 0x28, camera) || !objectAlive(camera) ||
        !read(rc, 0x2E8, ui) || !objectAlive(ui) || !read(rc, 0x2F8, xml) || !objectAlive(xml)) return -4;
    stopFlight();
    using PrepareFn = void (*)(void *, int32_t, bool, bool, const void *);
    ((PrepareFn)OGSResolveRVA(0x13F65C0))(rc, team, true, false, nullptr);
    return 3;
}
static void remoteTick(void *self, const Snapshot &s) {
    @autoreleasepool {
    RemoteRequest send; int enable, decision; Identity enableID;
    os_unfair_lock_lock(&lock);
    send = sendCommand; sendCommand = {}; enable = receiveCommand; receiveCommand = 0;
    enableID = receiveCommandID; decision = consentDecision; consentDecision = 0;
    os_unfair_lock_unlock(&lock);
    uintptr_t room = 0; int32_t actor = 0, master = 0;
    bool live = s.valid && OGSReadAutoRoom(&room, &actor, &master) && room == s.id.room && actor == s.id.actor;
    if (!live) {
        receiving = false; incoming = {}; outgoing = {}; clearPrompt();
        os_unfair_lock_lock(&lock); receivingUI = false; os_unfair_lock_unlock(&lock); return;
    }
    if (receiving && (!sameSession(s.id, receiverSession) || master != receiverMaster)) enable = -1;
    if (enable < 0) {
        receiving = false; incoming = {}; clearPrompt();
        remoteMessageSet(@"استقبال طلبات النقل متوقف");
    } else if (enable > 0 && sameSession(s.id, enableID) && master != actor) {
        receiving = true; receiverSession = s.id; receiverMaster = master;
        incoming = {}; clearPrompt();
        // Baseline ignores a retained property from a previous session/request.
        lastWire = propertyString(findActor(master), @"ogs47.req");
        remoteMessageSet(@"الاستقبال جاهز؛ أرسل الطلب من جهاز الهوست ثم وافق هنا");
    } else if (enable > 0) remoteMessageSet(@"فعّل الاستقبال على الحساب الثاني الذي ليس هوست");
    os_unfair_lock_lock(&lock); receivingUI = receiving; os_unfair_lock_unlock(&lock);

    if (send.nonce) {
        if (outgoing.nonce) remoteMessageSet(@"انتظر انتهاء طلب النقل السابق");
        else if (sameSession(send.id, s.id) && actor == master && now() - send.at < 3. && findActor(send.target) &&
                 publishOwn(s, @"ogs47.req", send.wire)) {
            outgoing = send;
            remoteMessageSet(@"أُرسل طلب النقل؛ ينتظر موافقة الحساب الثاني");
        } else remoteMessageSet(@"تعذر إرسال النقل: تغيرت الغرفة أو الهوست أو غادر المحدد");
    }
    if (incoming.nonce && !incomingIssued && decision) {
        bool valid = receiving && ogs47::canApply(incoming.id, s.id, incoming.sender, master, decision > 0, now()-incoming.at) &&
            [propertyString(findActor(master), @"ogs47.req") isEqualToString:incoming.wire];
        int code = valid ? applyApprovedTeam(self, s, incoming.team) : -1;
        acknowledge(s, incoming, code); clearPrompt();
        if (code == 3) { incomingIssued = true; incomingIssuedAt = now(); remoteMessageSet(@"نُفّذ انتقال حسابك؛ انتظار الشخصية"); }
        else { incoming = {}; remoteMessageSet(code == 4 ? @"أنت في الفريق المطلوب بالفعل" : @"لم يُنفّذ النقل: رفض أو حالة لاعب غير جاهزة"); }
    }
    if (incoming.nonce && (!sameSession(incoming.id,s.id) || master != incoming.sender ||
        now() - (incomingIssued ? incomingIssuedAt : incoming.at) > 30.)) {
        acknowledge(s, incoming, -2); incoming = {}; clearPrompt(); remoteMessageSet(@"انتهت مهلة نقل الفريق");
    }
    if (incoming.nonce && incomingIssued && s.team == incoming.team &&
        (incoming.team == 0 ? !s.id.player : s.alive)) {
        acknowledge(s, incoming, 4); incoming = {}; clearPrompt(); remoteMessageSet(@"اكتملت حالة حسابك محليًا؛ راجع الجهاز الآخر");
    }
    if (now() < nextRemotePoll) return;
    nextRemotePoll = now() + .25;
    if (outgoing.nonce) {
        void *target = findActor(outgoing.target);
        if (!sameSession(outgoing.id,s.id) || actor != master || !target || now()-outgoing.at > 65.) {
            outgoing = {}; remoteMessageSet(@"لم يصل تأكيد النقل؛ تحقق من نسخة الحساب الثاني والاستقبال");
        } else {
            NSArray<NSString *> *a = [propertyString(target, @"ogs47.ack") componentsSeparatedByString:@"|"];
            if (a.count == 4 && [a[0] isEqualToString:@"47"] && [a[1] isEqualToString:outgoing.nonce] &&
                [a[3] isEqualToString:[NSString stringWithFormat:@"%d",outgoing.team]]) {
                if ([a[2] isEqualToString:@"4"]) { outgoing = {}; remoteMessageSet(@"الجهاز الثاني أفاد باكتمال حالته؛ تحقق بصريًا"); }
                else if ([a[2] isEqualToString:@"3"]) remoteMessageSet(@"وافق الحساب الثاني وبدأ انتقاله");
                else if ([@[@"-1",@"-2",@"-3",@"-4"] containsObject:a[2]]) { outgoing = {}; remoteMessageSet(@"رفض الحساب الثاني الطلب أو تعذر انتقاله"); }
            }
        }
    }
    if (receiving && !incoming.nonce) {
        NSString *wire = propertyString(findActor(master), @"ogs47.req");
        if (wire && ![wire isEqualToString:lastWire]) {
            lastWire = wire; RemoteRequest r;
            if (parseRequest(wire, master, actor, r)) {
                r.id = s.id; r.at = now(); incoming = r; incomingIssued = false;
                os_unfair_lock_lock(&lock); consentPrompt = r; promptShown = false; consentDecision = 0; os_unfair_lock_unlock(&lock);
                remoteMessageSet(@"طلب نقل جديد؛ وافق على جهازك لتنفيذه");
            }
        }
    }
    }
}
}
