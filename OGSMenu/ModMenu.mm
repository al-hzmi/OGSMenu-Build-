#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include <strings.h>
typedef void*(*get_domain_t)(void);
typedef void**(*assemblies_t)(void*,size_t*);
typedef void*(*image_t)(void*);
typedef void*(*klass_t)(void*,const char*,const char*);
typedef void*(*get_method_t)(void*,const char*,int);
typedef void*(*invoke_t)(void*,void*,void**,void**);
typedef void*(*get_type_t)(void*);
typedef void*(*type_obj_t)(void*);
typedef void*(*fields_t)(void*,void**);
typedef const char*(*field_name_t)(void*);
typedef int(*field_flags_t)(void*);
typedef void(*set_field_t)(void*,void*,void*);
typedef int(*type_code_t)(void*);
typedef uint32_t(*array_len_t)(void*);
static get_domain_t dg;static assemblies_t ga;static image_t gi;static klass_t cf;
static get_method_t gm;static invoke_t ri;static get_type_t ct;static type_obj_t to;
static fields_t gf;static field_name_t gn;static field_flags_t gflags;
static get_type_t ft;static type_code_t tc;static set_field_t sf;static array_len_t al;
static void*(*icall)(const char*);
static BOOL ready(void){
 if(dg)return YES;
 dg=(get_domain_t)dlsym(RTLD_DEFAULT,"il2cpp_domain_get");
 ga=(assemblies_t)dlsym(RTLD_DEFAULT,"il2cpp_domain_get_assemblies");
 gi=(image_t)dlsym(RTLD_DEFAULT,"il2cpp_assembly_get_image");
 cf=(klass_t)dlsym(RTLD_DEFAULT,"il2cpp_class_from_name");
 gm=(get_method_t)dlsym(RTLD_DEFAULT,"il2cpp_class_get_method_from_name");
 ri=(invoke_t)dlsym(RTLD_DEFAULT,"il2cpp_runtime_invoke");
 ct=(get_type_t)dlsym(RTLD_DEFAULT,"il2cpp_class_get_type");
 to=(type_obj_t)dlsym(RTLD_DEFAULT,"il2cpp_type_get_object");
 gf=(fields_t)dlsym(RTLD_DEFAULT,"il2cpp_class_get_fields");
 gn=(field_name_t)dlsym(RTLD_DEFAULT,"il2cpp_field_get_name");
 gflags=(field_flags_t)dlsym(RTLD_DEFAULT,"il2cpp_field_get_flags");
 ft=(get_type_t)dlsym(RTLD_DEFAULT,"il2cpp_field_get_type");
 tc=(type_code_t)dlsym(RTLD_DEFAULT,"il2cpp_type_get_type");
 sf=(set_field_t)dlsym(RTLD_DEFAULT,"il2cpp_field_set_value");
 al=(array_len_t)dlsym(RTLD_DEFAULT,"il2cpp_array_length");
 icall=(void*(*)(const char*))dlsym(RTLD_DEFAULT,"il2cpp_resolve_icall");
 return dg&&ga&&gi&&cf&&gm&&ri;
}
static void* findClass(const char*ns,const char*name){
 if(!ready())return NULL;void*d=dg();if(!d)return NULL;size_t n=0;void**a=ga(d,&n);
 if(!a||n>10000)return NULL;
 for(size_t i=0;i<n;i++){void*img=gi(a[i]);if(img){void*k=cf(img,ns,name);if(k)return k;}}
 return NULL;
}
static int modify(const char*klass,const char*k1,const char*k2,int value,const char*method,BOOL withBool,BOOL flag){
 if(!ready()||!ct||!to||!al)return 0;
 void*k=findClass("",klass),*obj=findClass("UnityEngine","Object");
 if(!k||!obj)return 0;
 void*m=gm(obj,"FindObjectsOfType",1);
 if(!m){void*r=findClass("UnityEngine","Resources");if(r)m=gm(r,"FindObjectsOfTypeAll",1);}
 if(!m)return 0;
 void*type=to(ct(k));if(!type)return 0;
 void*args[]={type},*exc=NULL,*arr=ri(m,NULL,args,&exc);
 if(!arr||exc)return 0;uint32_t n=al(arr);if(!n||n>500)return 0;
 // IL2CPP array header layout is version-dependent; validate on target before use.
 void**items=(void**)((char*)arr+32);int changed=0;
 for(uint32_t i=0;i<n;i++){
  void*inst=items[i];if(!inst)continue;
  if(method){void*fn=gm(k,method,withBool?1:0);if(fn){
   void*e=NULL;BOOL b=flag;void*params[]={&b};
   ri(fn,inst,withBool?params:NULL,&e);if(!e)changed++;
  }}
  if((k1||k2)&&gf&&gn&&sf&&ft&&tc){
   void*it=NULL,*field;
   while((field=gf(k,&it))){
    if(gflags&&(gflags(field)&0x10))continue;
    const char*name=gn(field);if(!name)continue;
    if(!((k1&&strcasestr(name,k1))||(k2&&strcasestr(name,k2))))continue;
    int code=tc(ft(field));
    if(code==8){int32_t v=value;sf(inst,field,&v);changed++;}
    else if(code==12){float v=value;sf(inst,field,&v);changed++;}
   }
  }
 }
 return changed;
}
static void timeScale(float scale){
 if(!ready())return;
 if(icall){void(*set)(float)=(void(*)(float))icall("UnityEngine.Time::set_timeScale(System.Single)");
  if(set){set(scale);return;}}
 void*k=findClass("UnityEngine","Time");if(!k)return;
 void*m=gm(k,"set_timeScale",1);if(m){void*args[]={&scale},*exc=NULL;ri(m,NULL,args,&exc);}
}
@interface OGSTouchView:UIView
@property(nonatomic,weak) UIButton*button;
@property(nonatomic,weak) UIView*panel;
@end
@implementation OGSTouchView
-(BOOL)pointInside:(CGPoint)p withEvent:(UIEvent*)e{
 if(self.button&&!self.button.hidden&&[self.button pointInside:[self convertPoint:p toView:self.button] withEvent:e])return YES;
 if(self.panel&&!self.panel.hidden&&[self.panel pointInside:[self convertPoint:p toView:self.panel] withEvent:e])return YES;
 return NO;
}
@end
@interface OGSModMenu:NSObject
@property(nonatomic,strong) OGSTouchView*container;
@property(nonatomic,strong) UIButton*button;
@property(nonatomic,strong) UIView*panel;
@property(nonatomic,strong) UILabel*status;
@property(nonatomic,strong) NSTimer*timer;
@property(nonatomic) NSInteger hpStep,cashStep,timeStep;
@property(nonatomic) int hp,cash;
@property(nonatomic) BOOL ammo,vision;
+(instancetype)shared;
-(void)setup;
@end
@implementation OGSModMenu
+(instancetype)shared{static OGSModMenu*x;static dispatch_once_t once;dispatch_once(&once,^{x=[OGSModMenu new];});return x;}
-(UIWindow*)window{
 for(UIScene*s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive){
  UIWindowScene*ws=(UIWindowScene*)s;for(UIWindow*w in ws.windows)if(w.isKeyWindow)return w;
  for(UIWindow*w in ws.windows)if(!w.hidden&&w.windowLevel==UIWindowLevelNormal)return w;
 }
 return UIApplication.sharedApplication.keyWindow;
}
-(UIButton*)make:(NSString*)title y:(CGFloat)y action:(SEL)action{
 UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=CGRectMake(15,y,245,42);
 b.backgroundColor=[UIColor colorWithRed:.2 green:.21 blue:.25 alpha:1];b.layer.cornerRadius=8;
 [b setTitle:title forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
 b.titleLabel.font=[UIFont boldSystemFontOfSize:13];[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;
}
-(void)setup{dispatch_async(dispatch_get_main_queue(),^{
 if(self.container)return;UIWindow*w=[self window];if(!w)return;
 self.container=[[OGSTouchView alloc]initWithFrame:w.bounds];self.container.backgroundColor=UIColor.clearColor;
 self.container.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 self.button=[UIButton buttonWithType:UIButtonTypeCustom];self.button.frame=CGRectMake(25,130,58,58);
 self.button.backgroundColor=[UIColor colorWithWhite:.06 alpha:1];self.button.layer.cornerRadius=29;
 self.button.layer.borderWidth=2.5;self.button.layer.borderColor=UIColor.systemRedColor.CGColor;
 [self.button setTitle:@"OGS" forState:UIControlStateNormal];[self.button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
 [self.button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
 [self.button addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];
 [self.container addSubview:self.button];
 self.panel=[[UIView alloc]initWithFrame:CGRectMake(95,35,275,335)];
 self.panel.backgroundColor=[UIColor colorWithRed:.1 green:.1 blue:.12 alpha:1];self.panel.layer.cornerRadius=14;
 self.panel.layer.borderWidth=2;self.panel.layer.borderColor=UIColor.systemRedColor.CGColor;self.panel.hidden=YES;
 UILabel*t=[[UILabel alloc]initWithFrame:CGRectMake(15,10,245,26)];t.text=@"لوحة تحكم OGS";
 t.textColor=UIColor.whiteColor;t.textAlignment=NSTextAlignmentCenter;[self.panel addSubview:t];
 [self.panel addSubview:[self make:@"الدم: اضغط للتفعيل" y:44 action:@selector(hpAction:)]];
 [self.panel addSubview:[self make:@"الفلوس: اضغط للزيادة" y:94 action:@selector(cashAction:)]];
 [self.panel addSubview:[self make:@"الذخيرة: متوقف" y:144 action:@selector(ammoAction:)]];
 [self.panel addSubview:[self make:@"الرؤية: متوقف" y:194 action:@selector(visionAction:)]];
 [self.panel addSubview:[self make:@"سرعة الوقت: طبيعي" y:244 action:@selector(timeAction:)]];
 self.status=[[UILabel alloc]initWithFrame:CGRectMake(10,294,255,30)];
 self.status.text=ready()?@"تم العثور على واجهات IL2CPP":@"تعذر العثور على واجهات IL2CPP";
 self.status.textColor=UIColor.systemGreenColor;self.status.textAlignment=NSTextAlignmentCenter;
 self.status.font=[UIFont systemFontOfSize:11];[self.panel addSubview:self.status];
 [self.container addSubview:self.panel];self.container.button=self.button;self.container.panel=self.panel;
 [w addSubview:self.container];[w bringSubviewToFront:self.container];
 self.timer=[NSTimer scheduledTimerWithTimeInterval:.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
});}
-(void)toggle{self.panel.hidden=!self.panel.hidden;}
-(void)pan:(UIPanGestureRecognizer*)g{
 CGPoint t=[g translationInView:self.container],c=CGPointMake(g.view.center.x+t.x,g.view.center.y+t.y);
 CGRect b=self.container.bounds;c.x=MAX(32,MIN(b.size.width-32,c.x));c.y=MAX(32,MIN(b.size.height-32,c.y));
 g.view.center=c;[g setTranslation:CGPointZero inView:self.container];
}
-(void)tick{
 if(self.hp){modify("RoomController","hp","health",self.hp,NULL,NO,NO);modify("PlayerNetwork","hp","health",self.hp,NULL,NO,NO);}
 if(self.cash)modify("RoomController","cash","money",self.cash,NULL,NO,NO);
 if(self.ammo)modify("FPSWeapon","bullet","ammo",999,"RefillAmmo",NO,NO);
 if(self.vision)modify("RoomController",NULL,NULL,1,"SetupBoxes",YES,YES);
}
-(void)hpAction:(UIButton*)b{
 int v[]={100,200,300,1000,10000};self.hp=v[self.hpStep++%5];
 int n=modify("RoomController","hp","health",self.hp,NULL,NO,NO);
 [b setTitle:[NSString stringWithFormat:@"الدم: %d",self.hp] forState:UIControlStateNormal];
 self.status.text=[NSString stringWithFormat:@"عدد التحديثات: %d",n];
}
-(void)cashAction:(UIButton*)b{
 int v[]={100,200,300,1000,10000};self.cash=v[self.cashStep++%5];
 int n=modify("RoomController","cash","money",self.cash,NULL,NO,NO);
 [b setTitle:[NSString stringWithFormat:@"الفلوس: %d",self.cash] forState:UIControlStateNormal];
 self.status.text=[NSString stringWithFormat:@"عدد التحديثات: %d",n];
}
-(void)ammoAction:(UIButton*)b{
 self.ammo=!self.ammo;[b setTitle:self.ammo?@"الذخيرة: مفعّل":@"الذخيرة: متوقف" forState:UIControlStateNormal];
}
-(void)visionAction:(UIButton*)b{
 self.vision=!self.vision;
 modify("RoomController",NULL,NULL,1,"SetupBoxes",YES,self.vision);
 [b setTitle:self.vision?@"الرؤية: مفعّل":@"الرؤية: متوقف" forState:UIControlStateNormal];
}
-(void)timeAction:(UIButton*)b{
 float v[]={1,.5,0,2};NSArray*names=@[@"طبيعي",@"بطيء",@"تجميد",@"سريع"];
 NSUInteger i=self.timeStep++%4;timeScale(v[i]);
 [b setTitle:[@"سرعة الوقت: " stringByAppendingString:names[i]] forState:UIControlStateNormal];
}
@end
__attribute__((constructor)) static void ogs_init(void){
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[[OGSModMenu shared]setup];});
}
