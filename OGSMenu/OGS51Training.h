#pragma once
#include "OGS51TrainingPolicy.h"
namespace ogs46 {
struct Training51 {bool armed=false;uintptr_t room=0;int actor=0,target=0;double sampleAt=0;ogs51::Point point;int hp=-1;uint64_t frames=0,shots=0,throws=0;};
static Training51 training51;
static NSString *training51Message=@"مختبر خاص: علامة المحدد وقياس القنابل دون تعديل الضرر";
static bool training51Scope(Training51 &s) {
    os_unfair_lock_lock(&lock);s=training51;os_unfair_lock_unlock(&lock);
    if(!s.armed)return false;
    uintptr_t room=0;int32_t actor=0,master=0;bool open=true,visible=true;
    OGSRoomSnapshot peers=OGSCurrentSnapshot();
    bool ok=OGSReadAutoRoom(&room,&actor,&master)&&room==s.room&&actor==s.actor&&
        OGSReadRoomPrivacy(room,&open,&visible)&&!open&&!visible&&
        peers.inRoom&&peers.roomAddress==room&&selectedActorMatches(peers,s.target)==1&&
        !__atomic_load_n(&gOGSGrenade31Enabled,__ATOMIC_ACQUIRE)&&
        !__atomic_load_n(&gOGS.magicBulletOn,__ATOMIC_ACQUIRE)&&
        !__atomic_load_n(&gKnife29Mode,__ATOMIC_ACQUIRE)&&!__atomic_load_n(&gKnife28On,__ATOMIC_ACQUIRE);
    if(!ok){os_unfair_lock_lock(&lock);training51.armed=false;training51Message=@"توقف المختبر: تغيرت الجلسة أو فُعّل تعديل الذخيرة/المدى";os_unfair_lock_unlock(&lock);}
    return ok;
}
static bool training51Toggle(int target) {
    Training51 s;os_unfair_lock_lock(&lock);bool on=training51.armed;training51.armed=false;os_unfair_lock_unlock(&lock);
    if(on){os_unfair_lock_lock(&lock);training51Message=@"المختبر متوقف";os_unfair_lock_unlock(&lock);return true;}
    int32_t master=0;bool open=true,visible=true;OGSRoomSnapshot peers=OGSCurrentSnapshot();
    bool ok=OGSReadAutoRoom(&s.room,&s.actor,&master)&&target>0&&target!=s.actor&&
        OGSReadRoomPrivacy(s.room,&open,&visible)&&!open&&!visible&&peers.roomAddress==s.room&&selectedActorMatches(peers,target)==1;
    for(unsigned i=4;i<=6;++i)ok=ok&&__atomic_load_n(&bridgeStatus[i],__ATOMIC_ACQUIRE)==1;
    if(ok) {
        s.armed=true;s.target=target;
        // Read-only measurement baseline: do not silently measure modified ammo/damage.
        __atomic_store_n(&gOGSGrenade31Enabled,0u,__ATOMIC_RELEASE);
        __atomic_store_n(&gOGS.magicBulletOn,0,__ATOMIC_RELEASE);
        __atomic_store_n(&gKnife29Mode,0u,__ATOMIC_RELEASE);
        __atomic_store_n(&gKnife28On,0u,__ATOMIC_RELEASE);
        os_unfair_lock_lock(&lock);training51=s;training51Message=@"قياس دون تعديلات ذخيرة/سكين؛ ارمِ بنفسك. العلامة حسب Actor";os_unfair_lock_unlock(&lock);
        trace51Add(0,[NSString stringWithFormat:@"LAB armed room-local actor=%d target=%d; no name matching",s.actor,target]);
    } else {os_unfair_lock_lock(&lock);training51Message=@"المختبر يتطلب IPA51 كاملًا وحسابًا محددًا وغرفة مخفية ومغلقة";os_unfair_lock_unlock(&lock);}
    return ok;
}
static void training51PhotonTick() {
    static double checked=0.;if(now()-checked<.2)return;checked=now();
    Training51 s;training51Scope(s);
}
static void stop51() {
    os_unfair_lock_lock(&lock);originalClientPending={};originalClientIssued={};training51={};
    training51Message=@"المختبر متوقف";os_unfair_lock_unlock(&lock);
}
static int player51Owner(void *pn) {
    if(!objectAlive(pn))return 0;
    using View=void *(*)(void *,const void *);
    void *view=((View)OGSResolveRVA(0x13A9964))(pn,nullptr);int32_t actor=0;
    return read(view,0x20,actor)&&actor>0&&actor<1000000?actor:0;
}
static void player51Update(void *self,void *method) {
    if(playerUpdate51Original)playerUpdate51Original(self,method);
    Training51 lab;os_unfair_lock_lock(&lock);lab=training51;os_unfair_lock_unlock(&lock);
    if(!lab.armed||now()-lab.sampleAt<1./30.||player51Owner(self)!=lab.target||!training51Scope(lab))return;
    uint8_t killed=1;if(!read(self,0x12c,killed)||killed)return;
    using Get=void *(*)(void *,const void *);using Main=void *(*)(const void *);
    void *trans=((Get)OGSResolveRVA(0x1966984))(self,nullptr);
    void *camera=((Main)OGSResolveRVA(0x19655A4))(nullptr);
    if(!objectAlive(trans)||!objectAlive(camera))return;
    Vector3 p=((Transform_GetPosition_Fn)OGSResolveRVA(0x198B948))(trans,nullptr);p.y+=1.8f;
    if(!std::isfinite(p.x)||!std::isfinite(p.y)||!std::isfinite(p.z))return;
    using Project=Vector3 (*)(void *,Vector3,const void *);
    Vector3 v=((Project)OGSResolveRVA(0x1964F6C))(camera,p,nullptr);
    int32_t hp=-1;int51Read(table51Get(player51Properties(findActor(lab.target)),OGSManagedStringFromNSString(@"PlayerHP")),hp);
    if(hp!=lab.hp) trace51Add(0,[NSString stringWithFormat:@"LAB target actor=%d PlayerHP %d -> %d (local replicated property, cause unassigned)",lab.target,lab.hp,hp]);
    os_unfair_lock_lock(&lock);
    if(training51.armed&&training51.room==lab.room&&training51.target==lab.target){training51.point={v.x,v.y,v.z};training51.sampleAt=now();training51.hp=hp;++training51.frames;}
    os_unfair_lock_unlock(&lock);
}
static bool grenade51Local(void *weapon,Training51 &lab,int &before) {
    if(!training51Scope(lab)||!objectAlive(weapon))return false;
    void *descriptor=nullptr,*pn=nullptr;int type=-1;
    return read(weapon,0xa8,descriptor)&&read(descriptor,0x24,type)&&type==5&&read(weapon,0xd8,pn)&&
        player51Owner(pn)==lab.actor&&read(weapon,0x12c,before)&&before>=-1&&before<=10000;
}
static void weapon51Measure(void *self,const void *method,bool throwing) {
    Training51 lab;int before=-999;bool observe=grenade51Local(self,lab,before);
    int32_t slots=-1,selected=-1;bool inventory=observe&&OGSReadGrenadeSelectionProbe(self,&slots,&selected);
    Weapon51Fn original=throwing?throw51Original:fire51Original;
    if(original)original(self,method);
    if(!observe)return;
    Training51 afterLab;int after=-999;bool valid=training51Scope(afterLab)&&afterLab.room==lab.room&&objectAlive(self)&&read(self,0x12c,after);
    int32_t afterSlots=-1,afterSelected=-1;
    bool afterInventory=valid&&OGSReadGrenadeSelectionProbe(self,&afterSlots,&afterSelected);
    uintptr_t room=0;int32_t me=0,master=0;bool role=OGSReadAutoRoom(&room,&me,&master)&&room==lab.room;
    trace51Add(0,[NSString stringWithFormat:@"GRENADE %@ ammo %d -> %d read=%d slots %d -> %d selected %d -> %d inventory=%d/%d master=%d local=%d roleRead=%d; local observations only",throwing?@"throw":@"shot",before,after,valid,slots,afterSlots,selected,afterSelected,inventory,afterInventory,master,me,role]);
    os_unfair_lock_lock(&lock);if(throwing)++training51.throws;else ++training51.shots;os_unfair_lock_unlock(&lock);
}
static void fire51(void *s,const void *m){weapon51Measure(s,m,false);}
static void throw51(void *s,const void *m){weapon51Measure(s,m,true);}
static void install51() {
    os_unfair_lock_lock(&gHookInstallLock);
    installBridge(3,0x139231c,0x3280,0x2a98e10,0xd10183ff,(uintptr_t)&actorProperties51,(uintptr_t *)&actorPropertiesOriginal);
    installBridge(4,0x137f584,0x32c0,0x2a98e18,0xd102c3ff,(uintptr_t)&fire51,(uintptr_t *)&fire51Original);
    installBridge(5,0x1381160,0x3300,0x2a98e20,0x6db93bef,(uintptr_t)&throw51,(uintptr_t *)&throw51Original);
    installBridge(6,0x13e6060,0x3340,0x2a98e28,0xd10203ff,(uintptr_t)&player51Update,(uintptr_t *)&playerUpdate51Original);
    os_unfair_lock_unlock(&gHookInstallLock);
}
}
