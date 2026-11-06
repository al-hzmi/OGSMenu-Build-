#pragma once
#include "OGSOriginalClientTeamPolicy.h"
// OGS51: the game's actual Int32 Team property, not PUN's Byte team demo key.
namespace ogs46 {
struct OriginalClientTeamRequest {
    uintptr_t room=0; int actor=0,target=0,team=-1; double at=0;
    uint64_t id=0; NSString *marker=nil; int before=-1,last=-1;
    bool dispatched=false,echo=false; double nextPoll=0;
};
static OriginalClientTeamRequest originalClientPending,originalClientIssued;
static uint64_t originalClientNextID=0;
static NSString *originalClientMessage=@"نقل حسابك الأصلي: خاصية Team الصحيحة؛ النتيجة تحتاج تحقق الجهاز الثاني";
static double originalClientLastSubmitAt=-100.;
static int selectedActorMatches(const OGSRoomSnapshot &roster,int actor) {
    int n=0;for(uint32_t i=0;i<roster.count;++i)if(roster.peers[i].actorID==actor)++n;return n;
}
static NSString *originalClientTeamStatus() {
    os_unfair_lock_lock(&lock);NSString *s=originalClientMessage;os_unfair_lock_unlock(&lock);return s;
}
static void team51Message(NSString *s) {
    os_unfair_lock_lock(&lock);originalClientMessage=s;os_unfair_lock_unlock(&lock);
}
static bool team51Session(const OriginalClientTeamRequest &r, bool dispatch) {
    uintptr_t room=0;int32_t me=0,master=0;bool open=true,visible=true;
    if(!OGSReadAutoRoom(&room,&me,&master) || room!=r.room || me!=r.actor ||
       !OGSReadRoomPrivacy(room,&open,&visible) || open || visible) return false;
    OGSRoomSnapshot roster=OGSCurrentSnapshot();
    ogs48::TeamRequestFacts f;
    f.queuedRoom=r.room;f.liveRoom=room;f.queuedActor=r.actor;f.liveActor=me;
    f.photonRoomValid=true;f.rosterValid=roster.inRoom&&roster.roomAddress==room;
    f.otherPlayers=roster.count;f.targetMatches=selectedActorMatches(roster,r.target);
    f.targetActor=r.target;f.destination=r.team;Snapshot state=snapshot();f.mode=state.valid?state.mode:Mode::Unknown;
    f.age=dispatch?now()-r.at:0.;return ogs48::allowTeamRequest(f);
}
static bool queueOriginalClientTeam(int target,int team) {
    OriginalClientTeamRequest r;int32_t master=0;
    OGSReadAutoRoom(&r.room,&r.actor,&master);r.target=target;r.team=team;r.at=now();
    os_unfair_lock_lock(&lock);r.id=++originalClientNextID;os_unfair_lock_unlock(&lock);
    trace51Add(r.id,[NSString stringWithFormat:@"UI target=%d Team=%d",target,team]);
    if(target<=0 || team<0 || team>2 || !team51Session(r,true)) {
        trace51Add(r.id,@"DENIED scope/identity: requires private closed room and selected other actor");
        team51Message(@"اختبار النقل: غرفة مخفية ومغلقة، وحدد حسابك الثاني");return false;
    }
    r.marker=NSUUID.UUID.UUIDString;
    os_unfair_lock_lock(&lock);
    bool busy=originalClientPending.target || (originalClientIssued.target && !originalClientIssued.echo && now()-originalClientIssued.at<12.);
    bool ok=!busy && r.at-originalClientLastSubmitAt>=3.;
    if(ok){originalClientPending=r;originalClientLastSubmitAt=r.at;originalClientMessage=@"طلب النقل في طابور Photon";}
    else originalClientMessage=@"انتظر نتيجة الطلب السابق قبل التكرار";
    os_unfair_lock_unlock(&lock);
    trace51Add(r.id,ok?@"QUEUED":@"DENIED duplicate/cooldown");return ok;
}
static void originalClientTeamObserveEvent(void *eventData) {
    OriginalClientTeamRequest r;
    os_unfair_lock_lock(&lock);r=originalClientIssued;os_unfair_lock_unlock(&lock);
    if(!r.target || !r.dispatched || !team51Session(r,false)) return;
    uint8_t code=0;if(!read(eventData,0x10,code)||code!=253)return;
    // Exact NetworkingPeer.OnEvent uses TargetActorNr=253, Properties=251.
    using Get=void *(*)(void *,uint8_t,const void *);
    Get get=(Get)OGSResolveRVA(0x173ACE4);
    int32_t actor=0;if(!int51Read(get(eventData,253,nullptr),actor)||actor!=r.target)return;
    void *props=get(eventData,251,nullptr),*actual=nullptr,*klass=nullptr;
    if(!read(props,0,actual)||!OGSReadPointer(OGSResolveRVA(0x281A3F8),&klass)||actual!=klass)return;
    void *k=OGSManagedStringFromNSString(@"ogs51.request");
    void *marker=table51Get(props,k),*strClass=nullptr,*valueClass=nullptr;
    if(!read(k,0,strClass)||!read(marker,0,valueClass)||strClass!=valueClass)return;
    int32_t team=-1;
    if(![OGSReadIl2CppString(marker) isEqualToString:r.marker] ||
       !int51Read(table51Get(props,OGSManagedStringFromNSString(@"Team")),team) || team!=r.team)return;
    os_unfair_lock_lock(&lock);
    bool fresh=originalClientIssued.id==r.id&&!originalClientIssued.echo;
    if(fresh)originalClientIssued.echo=true;
    os_unfair_lock_unlock(&lock);
    if(fresh){trace51Add(r.id,@"MATCHED inbound Event253: target + UUID + Int32 Team; recipient gameplay NOT verified");
        team51Message(@"وصل تحديث Photon مطابق؛ تحقق من الحساب الثاني وبعد الموت/الجولة");}
}
static void originalClientTeamPhotonTick() {
    OriginalClientTeamRequest req,active;
    os_unfair_lock_lock(&lock);req=originalClientPending;originalClientPending={};active=originalClientIssued;os_unfair_lock_unlock(&lock);
    if(req.target) {
        trace51Add(req.id,@"CONSUMED on PhotonHandler.Update");
        if(!team51Session(req,true)){trace51Add(req.id,@"CANCELLED room/actor/target/authority changed");team51Message(@"ألغي النقل: تغيرت جلسة الاختبار أو الهدف");return;}
        using Offline=bool (*)(const void *);
        if(((Offline)OGSResolveRVA(0x13CA5A8))(nullptr)){trace51Add(req.id,@"REJECTED offline mode: no network proof possible");team51Message(@"النقل الشبكي غير متاح في وضع Offline");return;}
        void *target=findActor(req.target);int32_t current=-1,actualActor=0;
        if(!read(target,0x10,actualActor)||actualActor!=req.target){trace51Add(req.id,@"REJECTED target Actor mismatch");return;}
        if(!target || !gameTeam51Read(target,current)) {trace51Add(req.id,@"REJECTED missing/wrong-typed native Team; no write");team51Message(@"تعذر قراءة Team الأصلي بنوع Int32؛ لم يُرسل شيء");return;}
        req.before=current;req.last=current;
        trace51Add(req.id,[NSString stringWithFormat:@"TARGET verified actor=%d native Team=%d",req.target,current]);
        if(current==req.team){trace51Add(req.id,@"ALREADY same local property; no gameplay claim");team51Message(@"خاصية الفريق مطابقة محليًا؛ لم يُكرر الطلب");return;}
        // The OpSetPropertiesOfActor bridge is an OBSERVER only. Requiring it
        // for dispatch caused OGS51 to drop otherwise validated team requests
        // when the native instrumentation stub was unavailable on-device.
        // The game's SetCustomProperties entry is independent of this hook.
        uint32_t operationBridge = __atomic_load_n(&bridgeStatus[3],__ATOMIC_ACQUIRE);
        uintptr_t setProperties = OGSResolveRVA(0x13D0CC0);
        if(!ogs48::allowNativeTeamDispatch(setProperties && OGSIsExecutableGameAddress(setProperties),operationBridge)) {
            trace51Add(req.id,@"REJECTED original SetCustomProperties entry unavailable");
            team51Message(@"تعذر التحقق من دالة النقل الأصلية؛ لم يُرسل الطلب");
            return;
        }
        if(operationBridge!=1)
            trace51Add(req.id,[NSString stringWithFormat:@"OpSetPropertiesOfActor observer unavailable (status=%u); direct native dispatch will proceed without transport instrumentation",operationBridge]);
        void *props=table51New(),*expected=table51New();
        void *key=OGSManagedStringFromNSString(@"Team"),*value=int51Box(req.team),*old=int51Box(current);
        void *mk=OGSManagedStringFromNSString(@"ogs51.request"),*mv=OGSManagedStringFromNSString(req.marker);
        if(!props||!expected||!key||!value||!old||!mk||!mv){trace51Add(req.id,@"REJECTED allocation/type unavailable");return;}
        table51Put(props,key,value);table51Put(props,mk,mv);table51Put(expected,key,old);
        req.dispatched=true;req.nextPoll=now()+.25;
        os_unfair_lock_lock(&lock);originalClientIssued=req;os_unfair_lock_unlock(&lock);
        struct Scope {uint64_t prior;int actor;Scope(uint64_t id,int a):prior(propertiesRequestID),actor(propertiesTargetActor){propertiesRequestID=id;propertiesTargetActor=a;}~Scope(){propertiesRequestID=prior;propertiesTargetActor=actor;}} scope(req.id,req.target);
        trace51Add(req.id,@"SetCustomProperties ENTER: Team Int32 + request UUID; expected Team (no optimistic cache merge)");
        using Set=void (*)(void *,void *,void *,bool,const void *);
        ((Set)setProperties)(target,props,expected,false,nullptr);
        int32_t after=-1;bool readOK=gameTeam51Read(target,after);
        trace51Add(req.id,[NSString stringWithFormat:@"NATIVE returned; local Team=%d readable=%d; NOT ACK",after,readOK]);
        team51Message(@"أُرسل Team الصحيح بشرط القيمة السابقة؛ انتظار تحديث مطابق، لا تأكيد جهاز ثانٍ");
        return;
    }
    if(!active.target || now()<active.nextPoll)return;
    if(!team51Session(active,false)||now()-active.at>120.) {
        trace51Add(active.id,@"OBSERVATION ENDED: session/target changed or 120s elapsed");
        os_unfair_lock_lock(&lock);if(originalClientIssued.id==active.id)originalClientIssued={};os_unfair_lock_unlock(&lock);return;
    }
    int32_t team=-1;bool ok=gameTeam51Read(findActor(active.target),team);
    if(ok&&team!=active.last)trace51Add(active.id,[NSString stringWithFormat:@"CACHE CHANGE Team %d -> %d; may reflect native round/respawn; not recipient view",active.last,team]);
    bool timeout=!active.echo&&now()-active.at>=12.&&active.nextPoll<active.at+12.;
    if(timeout){trace51Add(active.id,@"NO correlated echo after 12s; rejection/permission reason UNKNOWN");team51Message(@"لم يصل تحديث مطابق؛ لا يمكن نسبة ردود Op252 العامة لهذا الطلب");}
    os_unfair_lock_lock(&lock);if(originalClientIssued.id==active.id){originalClientIssued.nextPoll=now()+.25;if(ok)originalClientIssued.last=team;}os_unfair_lock_unlock(&lock);
}
}
