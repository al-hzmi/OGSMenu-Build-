#pragma once
#include "OGS55ProbeBytes.h"
namespace causal55 {
using RpcFn=void(*)(void*,void*,int32_t,const void*);
using RespawnFn=void(*)(void*,int32_t,bool,bool,const void*);
using CacheFn=void(*)(void*,void*,const void*);
using PropsFn=void(*)(void*,void*,void*,bool,const void*);
static RpcFn rpcOriginal=nullptr;static RespawnFn respawnOriginal=nullptr;
static CacheFn cacheOriginal=nullptr;static PropsFn propsOriginal=nullptr;
static std::atomic<unsigned> nativeStatus[10];
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
static void rpc(void *peer,void *data,int32_t sender,const void *method){
 RpcScope scope(sender);
 if(rpcOriginal)rpcOriginal(peer,data,sender,method);
}
static void respawn(void *self,int32_t team,bool switched,bool reset,const void *method){
 State before=capture();Row r=make(50,0x13f65c0,before,before);r.caller=callerRVA((uintptr_t)__builtin_return_address(0));r.newValue=team;r.v0=switched;r.v1=reset;push(r);
 if(respawnOriginal)respawnOriginal(self,team,switched,reset,method);
 r.kind=51;r.seq=++serial;r.at=CACurrentMediaTime();r.after=capture();push(r);
}
static void cache(void *self,void *props,const void *method){
 State before=capture();int oldTeam=property(playerProperties(self),0x283d770),oldHP=property(playerProperties(self),0x283d768);
 int incomingTeam=property(props,0x283d770),incomingHP=property(props,0x283d768);
 uint32_t caller=callerRVA((uintptr_t)__builtin_return_address(0));
 if(cacheOriginal)cacheOriginal(self,props,method);
 int team=property(playerProperties(self),0x283d770),hp=property(playerProperties(self),0x283d768);
 if(oldTeam!=team||oldHP!=hp||incomingTeam!=unknown||incomingHP!=unknown){
  Row r=make(60,0x13d0f70,before,capture());read((uintptr_t)self,0x10,r.target);r.caller=caller;r.propTeam=team;r.propHP=hp;r.oldValue=oldTeam;r.newValue=team;r.v0=oldHP;r.v1=hp;r.v2=incomingTeam;push(r);
 }
}
static void props(void *self,void *values,void *expected,bool web,const void *method){
 int team=property(values,0x283d770),hp=property(values,0x283d768);
 State before=capture();Row r=make(61,0x13d0cc0,before,before);r.caller=callerRVA((uintptr_t)__builtin_return_address(0));
 read((uintptr_t)self,0x10,r.target);r.propTeam=team;r.propHP=hp;r.oldValue=property(playerProperties(self),0x283d770);r.v0=property(playerProperties(self),0x283d768);r.v2=expected?1:0;
 if(team!=unknown||hp!=unknown)push(r);
 if(propsOriginal)propsOriginal(self,values,expected,web,method);
 if(team!=unknown||hp!=unknown){r.kind=62;r.seq=++serial;r.at=CACurrentMediaTime();r.after=capture();r.newValue=property(playerProperties(self),0x283d770);r.v1=property(playerProperties(self),0x283d768);push(r);}
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
   Class cls=object_getClass([UIApplication sharedApplication]);SEL sel=@selector(sendEvent:);Method m=class_getInstanceMethod(cls,sel);
   if(!m){touchStatus=2;return;}
   originalSendEvent=(void(*)(id,SEL,UIEvent*))method_getImplementation(m);
   // Override the concrete application class without changing superclass dispatch.
   if(!class_addMethod(cls,sel,(IMP)&sendEvent,method_getTypeEncoding(m)))method_setImplementation(class_getInstanceMethod(cls,sel),(IMP)&sendEvent);
   touchStatus=1;
  });
 });
}
static void install(){
 os_unfair_lock_lock(&gHookInstallLock);
 uintptr_t base=OGSFindGameImage();
 const uintptr_t callbacks[]={(uintptr_t)&rpc,(uintptr_t)&respawn,(uintptr_t)&cache,(uintptr_t)&props,
 (uintptr_t)&storeProbe,(uintptr_t)&storeProbe,(uintptr_t)&storeProbe,(uintptr_t)&storeProbe,(uintptr_t)&storeProbe,(uintptr_t)&storeProbe};
 uintptr_t *originals[]={(uintptr_t*)&rpcOriginal,(uintptr_t*)&respawnOriginal,(uintptr_t*)&cacheOriginal,(uintptr_t*)&propsOriginal};
 for(size_t i=0;i<10;++i){
  if(nativeStatus[i]==1)continue;
  const auto &p=ogs55Probes[i];uint32_t entry=0;uintptr_t prior=0;std::array<uint32_t,96> actual{};
  uint32_t branch=0x14000000u|((uint32_t)(((int64_t)p.stub-p.site)/4)&0x3ffffffu);
  bool ok=base&&p.count<=actual.size()&&OGSIsExecutableGameAddress(base+p.site)&&OGSIsExecutableGameAddress(base+p.stub)&&OGSIsWritableMappedSlot(base+p.slot)&&
   OGSReadMemory(base+p.site,&entry,4)&&entry==branch&&OGSReadMemory(base+p.stub,actual.data(),p.count*4)&&!memcmp(actual.data(),p.words,p.count*4)&&OGSReadMemory(base+p.slot,&prior,8)&&(!prior||prior==callbacks[i]);
  if(!ok){nativeStatus[i]=2;continue;}
  if(i<4)__atomic_store_n(originals[i],base+p.stub+20,__ATOMIC_RELEASE);
  __atomic_store_n((uintptr_t*)(base+p.slot),callbacks[i],__ATOMIC_RELEASE);nativeStatus[i]=1;
 }
 os_unfair_lock_unlock(&gHookInstallLock);installTouch();
}
static NSString *statusText(){
 NSMutableString *s=[NSMutableString stringWithFormat:@"\nCausal probes: touch=%u (1 installed; 2 failed). ",touchStatus.load()];
 for(size_t i=0;i<10;++i)[s appendFormat:@"%x=%u ",ogs55Probes[i].site,nativeStatus[i].load()];
 [s appendString:@"\nNative status 1=bytes validated + callback registered, NOT device proof. Store sites cover known paths only; unexplained sampled writes remain unattributed.\n"];return s;
}
}
