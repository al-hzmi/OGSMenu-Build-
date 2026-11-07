#pragma once
#include "OGS55ProbeBytes.h"
namespace causal55 {
using RpcFn=void(*)(void*,void*,int32_t,const void*);
using RespawnFn=void(*)(void*,int32_t,bool,bool,const void*);
using CacheFn=void(*)(void*,void*,const void*);
using PropsFn=void(*)(void*,void*,void*,bool,const void*);
static RpcFn rpcOriginal=nullptr,transportOriginal=nullptr;
static thread_local bool nextRpcFromTransport=false;static RespawnFn respawnOriginal=nullptr;
static CacheFn cacheOriginal=nullptr;static PropsFn propsOriginal=nullptr;
static std::atomic<unsigned> nativeStatus[11];
static int property(void *table,uintptr_t literal){
 uintptr_t key=0,type=0,expected=0,boxedType=0,intType=0;
 if(!read((uintptr_t)table,0,type)||!read(OGSResolveRVA(0x281a3f8),0,expected)||!expected||type!=expected||!read(OGSResolveRVA(literal),0,key)||!key)return unknown;
 // Verified Hashtable.get_Item is a TryGetValue lookup; no allocations here
 // except original one-time metadata initialization inside the getter itself.
 using Get=void*(*)(void*,void*,const void*);
 void *boxed=((Get)OGSResolveRVA(0x173af94))(table,(void*)key,nullptr);int value=unknown;
 if(read((uintptr_t)boxed,0,boxedType)&&read(OGSResolveRVA(0x2815340),0,intType)&&intType&&boxedType==intType)read((uintptr_t)boxed,0x10,value);
 return value;
}
static void *playerProperties(void *player){uintptr_t table=0;read((uintptr_t)player,0x30,table);return (void*)table;}
static void augment(State &s){
 uintptr_t local=0,peer=peerAddress();read(peer,0x160,local);
 s.photonTeam=property(playerProperties((void*)local),0x283d770);s.photonHP=property(playerProperties((void*)local),0x283d768);
}
static void rpc(void *peer,void *data,int32_t sender,const void *method){
 bool received=nextRpcFromTransport;nextRpcFromTransport=false;
 RpcScope scope(sender,received?1:2);
 auto original=__atomic_load_n(&rpcOriginal,__ATOMIC_ACQUIRE);if(original)original(peer,data,sender,method);
}
static void transport(void *peer,void *data,int32_t sender,const void *method){
 struct Restore {bool previous;~Restore(){nextRpcFromTransport=previous;}} restore{nextRpcFromTransport};
 nextRpcFromTransport=true;
 auto original=__atomic_load_n(&transportOriginal,__ATOMIC_ACQUIRE);if(original)original(peer,data,sender,method);
}
static void respawn(void *self,int32_t team,bool switched,bool reset,const void *method){
 State before=captureFull();Row r=make(50,0x13f65c0,before,before);r.caller=callerRVA((uintptr_t)__builtin_return_address(0));r.newValue=team;r.v0=switched;r.v1=reset;push(r);
 auto original=__atomic_load_n(&respawnOriginal,__ATOMIC_ACQUIRE);if(original)original(self,team,switched,reset,method);
 r.kind=51;r.seq=++serial;r.at=CACurrentMediaTime();r.after=captureFull();push(r);
}
static void cache(void *self,void *props,const void *method){
 State before=captureFull();int oldTeam=property(playerProperties(self),0x283d770),oldHP=property(playerProperties(self),0x283d768);
 int incomingTeam=property(props,0x283d770),incomingHP=property(props,0x283d768);
 uint32_t caller=callerRVA((uintptr_t)__builtin_return_address(0));
 auto original=__atomic_load_n(&cacheOriginal,__ATOMIC_ACQUIRE);if(original)original(self,props,method);
 int team=property(playerProperties(self),0x283d770),hp=property(playerProperties(self),0x283d768);
 if(oldTeam!=team||oldHP!=hp||incomingTeam!=unknown||incomingHP!=unknown){
  Row r=make(60,0x13d0f70,before,captureFull());read((uintptr_t)self,0x10,r.target);r.caller=caller;r.propTeam=team;r.propHP=hp;r.oldValue=oldTeam;r.newValue=team;r.v0=oldHP;r.v1=hp;r.v2=incomingTeam;push(r);
 }
}
static void props(void *self,void *values,void *expected,bool web,const void *method){
 int team=property(values,0x283d770),hp=property(values,0x283d768);
 State before=captureFull();Row r=make(61,0x13d0cc0,before,before);r.caller=callerRVA((uintptr_t)__builtin_return_address(0));
 read((uintptr_t)self,0x10,r.target);r.propTeam=team;r.propHP=hp;r.oldValue=property(playerProperties(self),0x283d770);r.v0=property(playerProperties(self),0x283d768);r.v2=expected?1:0;
 if(team!=unknown||hp!=unknown)push(r);
 auto original=__atomic_load_n(&propsOriginal,__ATOMIC_ACQUIRE);if(original)original(self,values,expected,web,method);
 if(team!=unknown||hp!=unknown){r.kind=62;r.seq=++serial;r.at=CACurrentMediaTime();r.after=captureFull();r.newValue=property(playerProperties(self),0x283d770);r.v1=property(playerProperties(self),0x283d768);push(r);}
}
static void (*originalSendEvent)(id,SEL,UIEvent*)=nullptr;
static std::atomic<unsigned> touchStatus{0};
static void sendEvent(id self,SEL cmd,UIEvent *event){
 if(event.type==UIEventTypeTouches){
  for(UITouch *touch in event.allTouches){
   if(touch.phase==UITouchPhaseBegan||touch.phase==UITouchPhaseEnded){lastTouch=CACurrentMediaTime();++touchCount;break;}
  }
 }
 if(originalSendEvent)originalSendEvent(self,cmd,event);
}
static void installTouch(){
 static dispatch_once_t once;
 dispatch_once(&once,^{
  dispatch_async(dispatch_get_main_queue(),^{
   appActive=[UIApplication sharedApplication].applicationState==UIApplicationStateActive?1:0;
   [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){(void)n;appActive=1;}];
   [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n){(void)n;appActive=0;}];
   Class cls=object_getClass([UIApplication sharedApplication]);SEL sel=@selector(sendEvent:);Method m=class_getInstanceMethod(cls,sel);
   if(!m){touchStatus=2;return;}
   originalSendEvent=(void(*)(id,SEL,UIEvent*))method_getImplementation(m);
   // Override the concrete application class without changing superclass dispatch.
   if(!class_addMethod(cls,sel,(IMP)&sendEvent,method_getTypeEncoding(m)))method_setImplementation(class_getInstanceMethod(cls,sel),(IMP)&sendEvent);
   touchStatus=1;
  });
 });
}
// Two capped snapshots on a background queue. No Unity/Photon calls there.
// Keeps evidence when the Unity/main thread stalls; iOS suspension can still stop it.
static NSString *statusText();
static NSString *tracePath(NSString *name){
 return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:name];
}
static std::atomic<unsigned> saveStatus{0};
static void installPersistence(){
 static dispatch_once_t once;
 dispatch_once(&once,^{
  dispatch_queue_t q=dispatch_queue_create("ogs55.causal.snapshot",DISPATCH_QUEUE_SERIAL);
  dispatch_async(q,^{@autoreleasepool{
   NSFileManager *fm=[NSFileManager defaultManager];NSString *old=tracePath(@"OGS55-latest.txt"),*previous=tracePath(@"OGS55-previous.txt");
   if([fm fileExistsAtPath:old]){[fm removeItemAtPath:previous error:nil];[fm copyItemAtPath:old toPath:previous error:nil];}
  }});
  static dispatch_source_t timer;
  timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,q);
  dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),2*NSEC_PER_SEC,NSEC_PER_SEC/2);
  dispatch_source_set_event_handler(timer,^{@autoreleasepool{
   NSString *snapshot=[text() stringByAppendingString:statusText()];NSData *data=[snapshot dataUsingEncoding:NSUTF8StringEncoding];
   if(data.length<=512*1024)saveStatus=[data writeToFile:tracePath(@"OGS55-latest.txt") options:NSDataWritingAtomic error:nil]?1:2;
   else saveStatus=3;
  }});dispatch_resume(timer);
 });
}
static NSString *previousText(){return [NSString stringWithContentsOfFile:tracePath(@"OGS55-previous.txt") encoding:NSUTF8StringEncoding error:nil]?:@"No previous OGS55 test snapshot";}
static void install(){
 os_unfair_lock_lock(&gHookInstallLock);
 augmentProperties.store(&augment,std::memory_order_release);
 uintptr_t base=OGSFindGameImage();
 const uintptr_t callbacks[]={(uintptr_t)&rpc,(uintptr_t)&respawn,(uintptr_t)&cache,(uintptr_t)&props,(uintptr_t)&transport,
 (uintptr_t)&storeProbe,(uintptr_t)&storeProbe,(uintptr_t)&storeProbe,(uintptr_t)&storeProbe,(uintptr_t)&storeProbe,(uintptr_t)&storeProbe};
 uintptr_t *originals[]={(uintptr_t*)&rpcOriginal,(uintptr_t*)&respawnOriginal,(uintptr_t*)&cacheOriginal,(uintptr_t*)&propsOriginal,(uintptr_t*)&transportOriginal};
 for(size_t i=0;i<11;++i){
  if(nativeStatus[i]==1)continue;
  const auto &p=ogs55Probes[i];uint32_t entry=0;uintptr_t prior=0;std::array<uint32_t,96> actual{};
  uint32_t branch=0x14000000u|((uint32_t)(((int64_t)p.stub-p.site)/4)&0x3ffffffu);
  bool ok=base&&p.count<=actual.size()&&OGSIsExecutableGameAddress(base+p.site)&&OGSIsExecutableGameAddress(base+p.stub)&&OGSIsWritableMappedSlot(base+p.slot)&&
   OGSReadMemory(base+p.site,&entry,4)&&entry==branch&&OGSReadMemory(base+p.stub,actual.data(),p.count*4)&&!memcmp(actual.data(),p.words,p.count*4)&&OGSReadMemory(base+p.slot,&prior,8)&&(!prior||prior==callbacks[i]);
  if(!ok){nativeStatus[i]=2;continue;}
  if(i<5)__atomic_store_n(originals[i],base+p.stub+20,__ATOMIC_RELEASE);
  __atomic_store_n((uintptr_t*)(base+p.slot),callbacks[i],__ATOMIC_RELEASE);nativeStatus[i]=1;
 }
 os_unfair_lock_unlock(&gHookInstallLock);installTouch();installPersistence();
}
static NSString *statusText(){
 NSMutableString *s=[NSMutableString stringWithFormat:@"\nCausal probes: touch=%u (1 installed; 2 failed). ",touchStatus.load()];
 [s appendFormat:@"saved=%u (1 OK, 2 I/O failed, 3 size cap). ",saveStatus.load()];
 for(size_t i=0;i<11;++i)[s appendFormat:@"%x=%u ",ogs55Probes[i].site,nativeStatus[i].load()];
 [s appendString:@"\nNative status 1=bytes validated + callback registered, NOT device proof. Store sites cover known paths only; unexplained sampled writes remain unattributed.\n"];return s;
}
}
