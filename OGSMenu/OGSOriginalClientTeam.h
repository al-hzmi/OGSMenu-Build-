#pragma once
#include "OGSOriginalClientTeamPolicy.h"

// OGS48 controlled test: invoke the game's own TeamExtensions.SetTeam on the
// selected PhotonPlayer. Unlike the OGS47 cooperative protocol, the recipient
// is an unmodified client. We cannot infer remote/server acceptance from the
// native void return or from the sender's local team cache.
namespace ogs46 {
struct OriginalClientTeamRequest {
    uintptr_t room = 0;
    int actor = 0;
    int target = 0;
    int team = -1;
    double at = 0;
};
static OriginalClientTeamRequest originalClientPending, originalClientIssued;
static NSString *originalClientMessage = @"اختر حسابك الثاني من القائمة، حتى في الغرف متعددة اللاعبين";
static double originalClientLastSubmitAt = -100.;

static int selectedActorMatches(const OGSRoomSnapshot &roster, int actor) {
    int matches = 0;
    for (uint32_t i = 0; i < roster.count; ++i)
        if (roster.peers[i].actorID == actor) ++matches;
    return matches;
}

static NSString *originalClientTeamStatus() {
    os_unfair_lock_lock(&lock);
    NSString *message = originalClientMessage;
    os_unfair_lock_unlock(&lock);
    return message;
}

static bool queueOriginalClientTeam(int target, int team) {
    uintptr_t room = 0;
    int32_t localActor = 0, masterActor = 0;
    bool photonRoomValid = OGSReadAutoRoom(&room, &localActor, &masterActor);
    OGSRoomSnapshot roster = OGSCurrentSnapshot();
    double t = now();
    ogs48::TeamRequestFacts f = {};
    f.queuedRoom = room;
    f.liveRoom = room;
    f.queuedActor = localActor;
    f.liveActor = localActor;
    f.photonRoomValid = photonRoomValid;
    f.rosterValid = roster.inRoom && roster.roomAddress == room;
    f.otherPlayers = (int)roster.count;
    f.targetMatches = selectedActorMatches(roster, target);
    f.targetActor = target;
    f.destination = team;
    f.mode = snapshot().mode;
    f.age = 0.;
    bool accepted = ogs48::allowTeamRequest(f);
    os_unfair_lock_lock(&lock);
    if (!accepted) originalClientMessage = @"تعذر التحقق من هوية اللاعب المحدد أو حالة الغرفة؛ أعد اختياره";
    else if (originalClientPending.target || t - originalClientLastSubmitAt < 3.) {
        accepted = false;
        originalClientMessage = @"انتظر 3 ثوانٍ قبل طلب نقل آخر";
    } else {
        originalClientPending = {room, localActor, target, team, t};
        originalClientLastSubmitAt = t;
        originalClientMessage = @"تجهيز تغيير فريق الحساب الثاني الأصلي";
    }
    os_unfair_lock_unlock(&lock);
    return accepted;
}

// Called on the verified, continuously active PhotonHandler.Update hook, not
// RoomController.Update. The latter can be absent even while Photon runs.
static void originalClientTeamPhotonTick() {
    OriginalClientTeamRequest req;
    os_unfair_lock_lock(&lock);
    req = originalClientPending;
    originalClientPending = {};
    os_unfair_lock_unlock(&lock);
    if (!req.target) return;

    uintptr_t room = 0;
    int32_t localActor = 0, masterActor = 0;
    bool photonRoomValid = OGSReadAutoRoom(&room, &localActor, &masterActor);
    OGSRoomSnapshot roster = OGSCurrentSnapshot();
    ogs48::TeamRequestFacts f = {};
    f.queuedRoom = req.room;
    f.liveRoom = room;
    f.queuedActor = req.actor;
    f.liveActor = localActor;
    f.photonRoomValid = photonRoomValid;
    f.rosterValid = roster.inRoom && roster.roomAddress == room;
    f.otherPlayers = (int)roster.count;
    f.targetMatches = selectedActorMatches(roster, req.target);
    f.targetActor = req.target;
    f.destination = req.team;
    f.mode = snapshot().mode;
    f.age = now() - req.at;
    NSString *result = @"ألغي الطلب: تغيّرت الغرفة أو لم يعد الحساب المحدد ظاهرًا";
    if (ogs48::allowTeamRequest(f)) {
        void *target = findActor(req.target);
        uintptr_t getAddress = OGSResolveRVA(0x14232D8); // TeamExtensions.GetTeam
        uintptr_t setAddress = OGSResolveRVA(0x1423388); // TeamExtensions.SetTeam
        if (target && OGSIsExecutableGameAddress(getAddress) &&
            OGSIsExecutableGameAddress(setAddress)) {
            using GetTeamFn = int32_t (*)(void *, const void *);
            using SetTeamFn = void (*)(void *, int32_t, const void *);
            int32_t current = ((GetTeamFn)getAddress)(target, nullptr);
            if (current == req.team) result = @"حالة الفريق لهذا الحساب مطابقة محليًا؛ تحقق على جهازه";
            else if (current >= 0 && current <= 2) {
                ((SetTeamFn)setAddress)(target, req.team, nullptr);
                originalClientIssued = req;
                result = @"أُرسل تحديث الفريق بالطريقة الأصلية؛ انتظر ظهوره على جهاز الحساب الثاني";
            } else result = @"فشل التحقق من فريق الحساب الثاني؛ لم يُرسل الطلب";
        } else result = @"تعذّر التحقق من اللاعب أو دوال الفريق؛ لم يُرسل الطلب";
    }
    os_unfair_lock_lock(&lock);
    originalClientMessage = result;
    os_unfair_lock_unlock(&lock);
}
}
