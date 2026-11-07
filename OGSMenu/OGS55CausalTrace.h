#pragma once
// Test-only. Every sender is SDK room-local context, never an account identity.
// No gameplay mutations, native calls, allocation or blocking lock in store probes.
namespace causal55 {
constexpr int unknown=-9999;
struct Context {uint64_t event=0,rpc=0;int eventCode=0,sender=-1;};
static thread_local Context context;
static std::atomic<uint64_t> serial{0},frame{0},photonFrame{0};
static std::atomic<double> lastFrame{0},lastPhoton{0},lastTouch{0},lastNetwork{0};
static std::atomic<uint64_t> touchCount{0};
static std::atomic<int> appActive{-1};
static std::atomic<int> lastNetworkCode{0};
struct EventScope {
 Context prior;
 explicit EventScope(int code):prior(context){context={++serial,0,code,-1};lastNetwork=CACurrentMediaTime();lastNetworkCode=code;}
 ~EventScope(){context=prior;}
};
struct RpcScope {
 Context prior;
 explicit RpcScope(int sender):prior(context){context.rpc=++serial;context.sender=sender;}
 ~RpcScope(){context=prior;}
};
struct State {
 int actor=unknown,master=unknown,connection=unknown,team=unknown,playerTeam=unknown,gameTeam=unknown;
 int photonTeam=unknown,photonHP=unknown;
 int hp=unknown,killed=unknown,ui=unknown,menu=unknown,respawn=unknown;
 float round=-1;
 uintptr_t room=0,rc=0,pn=0,fields=0;
};
template<class T> static bool read(uintptr_t p,uintptr_t o,T &v){return p && OGSReadMemory(p+o,&v,sizeof(v));}
static uintptr_t peerAddress(){
 uintptr_t type=0,fields=0,peer=0;read(OGSResolveRVA(0x281b1c8),0,type);read(type,0xb8,fields);read(fields,0x10,peer);return peer;
}
static State capture(){
 State s;uintptr_t peer=peerAddress(),local=0,klass=0;
 read(peer,0x11c,s.connection);read(peer,0x158,s.room);read(peer,0x160,local);read(local,0x10,s.actor);read(s.room,0x48,s.master);
 read(OGSResolveRVA(0x281b1b8),0,klass);read(klass,0xb8,s.fields);read(s.fields,0x30,s.rc);
 read(s.fields,0x14c,s.gameTeam);uint8_t b=255;
 if(read(s.fields,0x158,b)&&b<=1)s.menu=b;
 if(read(s.rc,0xfd,b)&&b<=1)s.ui=b;
 read(s.rc,0x1b0,s.team);read(s.rc,0x1dc,s.hp);read(s.rc,0x1c0,s.respawn);read(s.rc,0x17c,s.round);
 read(s.rc,0x108,s.pn);read(s.pn,0x154,s.playerTeam);
 if(read(s.pn,0x12c,b)&&b<=1)s.killed=b;
 return s;
}
static std::atomic<void(*)(State&)> augmentProperties{nullptr};
static State captureFull(){State s=capture();auto fn=augmentProperties.load(std::memory_order_acquire);if(fn)fn(s);return s;}
struct Row {
 uint64_t seq=0,epoch=0,ev=0,rpc=0,frames=0,touches=0;
 double at=0,touchAge=-1,netAge=-1,frameAge=-1;
 uint32_t kind=0,site=0,caller=0;
 int code=0,sender=-1,target=unknown,view=unknown,owner=unknown,claimed=unknown;
 int v0=unknown,v1=unknown,v2=unknown,oldValue=unknown,newValue=unknown,propTeam=unknown,propHP=unknown;
 State before,after;
};
static std::array<Row,256> rows;
static std::atomic_flag ringLock=ATOMIC_FLAG_INIT;
static size_t used=0,next=0;
static uint64_t epoch=0;static uintptr_t epochRoom=0;static int epochActor=0;
static std::atomic<uint64_t> drops{0};
static uint32_t callerRVA(uintptr_t p){uintptr_t b=OGSFindGameImage();return b && p>=b && p-b<0x22d8000?(uint32_t)(p-b):0;}
static Row make(uint32_t kind,uint32_t site,const State &before,const State &after){
 Row r;r.seq=++serial;r.at=CACurrentMediaTime();r.kind=kind;r.site=site;r.ev=context.event;r.rpc=context.rpc;r.code=context.eventCode;r.sender=context.sender;
 r.frames=frame.load();r.touches=touchCount.load();double t=lastTouch.load(),n=lastNetwork.load(),f=lastFrame.load();
 r.touchAge=t>0?r.at-t:-1;r.netAge=n>0?r.at-n:-1;r.frameAge=f>0?r.at-f:-1;r.before=before;r.after=after;return r;
}
static void push(Row r){
 if(ringLock.test_and_set(std::memory_order_acquire)){++drops;return;}
 if(r.after.room!=epochRoom||r.after.actor!=epochActor){++epoch;epochRoom=r.after.room;epochActor=r.after.actor;}
 r.epoch=epoch; // raw addresses are transient, erased before retention/export
 r.before.room=r.before.rc=r.before.pn=r.before.fields=0;r.after.room=r.after.rc=r.after.pn=r.after.fields=0;
 rows[next]=r;next=(next+1)%rows.size();if(used<rows.size())++used;ringLock.clear(std::memory_order_release);
}
// Existing array/type validation lives in DamageRemote; this scope observes entry
// and return even on existing shield/shape early exits. It never changes verdicts.
struct DamageScope {
 State before;Row row;void *self;
 DamageScope(void *pn,void *values,int claimed):before(captureFull()),row(make(10,0x13e7588,before,before)),self(pn){
  row.claimed=claimed;uintptr_t view=0;read((uintptr_t)pn,0x18,view);read(view,0x20,row.owner);read(view,0x68,row.view);
  uintptr_t klass=0,expected=0;uint64_t count=0;
  if(read((uintptr_t)values,0,klass)&&read(OGSResolveRVA(0x28154b8),0,expected)&&expected==klass&&read((uintptr_t)values,0x18,count)&&count>=3){
   read((uintptr_t)values,0x20,row.v0);read((uintptr_t)values,0x24,row.v1);read((uintptr_t)values,0x28,row.v2);
  }
  push(row);
 }
 ~DamageScope(){row.kind=11;row.seq=++serial;row.at=CACurrentMediaTime();row.after=captureFull();push(row);}
};
static bool changed(const State&a,const State&b){return a.room!=b.room||a.actor!=b.actor||a.master!=b.master||a.photonTeam!=b.photonTeam||a.photonHP!=b.photonHP||a.connection!=b.connection||a.team!=b.team||a.playerTeam!=b.playerTeam||a.gameTeam!=b.gameTeam||a.ui!=b.ui||a.menu!=b.menu||a.hp!=b.hp||a.killed!=b.killed||a.respawn!=b.respawn;}
static void roomTick(){
 double now=CACurrentMediaTime(),prev=lastFrame.exchange(now);++frame;
 static thread_local State prior;static thread_local double sampleAt=0;
 if(now-sampleAt<0.1)return;sampleAt=now;State s=captureFull();
 if(changed(prior,s)||(prev>0 && now-prev>0.25)){Row r=make(30,0x13f3f2c,prior,s);r.oldValue=prev>0?(int)((now-prev)*1000):unknown;push(r);}prior=s;
}
static void storeProbe(void *object,int value,uint32_t site,int old){
 if(old==value)return;
 State s=capture();uintptr_t target=(uintptr_t)object;bool local=false;
 if(site==0x13e615c)local=target==s.pn;
 else if(site==0x13f3b38||site==0x13f41d8)local=target==s.fields;
 else local=target==s.rc;
 if(!local)return;
 Row r=make(20,site,s,s);r.oldValue=old;r.newValue=value;
 if(site==0x141afd4||site==0x141afec)r.before.ui=old;
 if(site==0x13e615c)r.before.playerTeam=old;
 if(site==0x13f3b0c)r.before.team=old;
 if(site==0x13f3b38)r.before.gameTeam=old;
 if(site==0x13f41d8)r.before.menu=old;
 push(r);
}
static NSString *text(){
 std::array<Row,256> copy;size_t count=0;
 if(!ringLock.test_and_set(std::memory_order_acquire)){count=used;size_t first=(next+rows.size()-used)%rows.size();for(size_t i=0;i<count;++i)copy[i]=rows[(first+i)%rows.size()];ringLock.clear(std::memory_order_release);}
 NSMutableString *out=[NSMutableString stringWithFormat:@"\nOGS55 TEST causal-v1 (not protected) n=%zu dropped=%llu frames=%llu photon=%llu roomAge=%.3f photonAge=%.3f active=%d\n",count,(unsigned long long)drops.load(),(unsigned long long)frame.load(),(unsigned long long)photonFrame.load(),lastFrame>0?CACurrentMediaTime()-lastFrame.load():-1,lastPhoton>0?CACurrentMediaTime()-lastPhoton.load():-1,appActive.load()];
 [out appendString:@"Unknown=-9999/-1. M=SDK cache, NOT server confirmation. Sender=ExecuteRpc argument, claimed=killerID. ev=local dispatch ID. Near touch/network does NOT prove origin.\n"];
 for(size_t i=0;i<count;++i){const Row&r=copy[i];
  [out appendFormat:@"#%llu t%.4f E%llu k%u @%x caller%x ev%llu/%d rpc%llu src%d target%d view%d owner%d claim%d vals[%d,%d,%d] write%d>%d propT%d propHP%d touch%.3f/%llu net%.3f frames%llu age%.3f | A%d M%d>%d conn%d>%d T%d>%d PN%d>%d GS%d>%d PhotonT%d>%d PhotonHP%d>%d HP%d>%d dead%d>%d UI%d>%d menu%d>%d resp%d>%d round%.2f\n",
   (unsigned long long)r.seq,r.at,(unsigned long long)r.epoch,r.kind,r.site,r.caller,(unsigned long long)r.ev,r.code,(unsigned long long)r.rpc,r.sender,r.target,r.view,r.owner,r.claimed,r.v0,r.v1,r.v2,r.oldValue,r.newValue,r.propTeam,r.propHP,r.touchAge,(unsigned long long)r.touches,r.netAge,(unsigned long long)r.frames,r.frameAge,r.after.actor,r.before.master,r.after.master,r.before.connection,r.after.connection,r.before.team,r.after.team,r.before.playerTeam,r.after.playerTeam,r.before.gameTeam,r.after.gameTeam,r.before.photonTeam,r.after.photonTeam,r.before.photonHP,r.after.photonHP,r.before.hp,r.after.hp,r.before.killed,r.after.killed,r.before.ui,r.after.ui,r.before.menu,r.after.menu,r.before.respawn,r.after.respawn,r.after.round];
 }return out;
}
}
