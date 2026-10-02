#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <string.h>
static const uintptr_t TBL_CASH_UPDATE=0x23918b8,RVA_ADD_CASH=0x13fa064,TBL_SUB_CASH=0x2391988,RVA_SETUP_BOXES=0x13e5554,TBL_SETUP_BOXES=0x23912a0,TBL_GET_DMG=0x2391388,TBL_WPN_HOOK=0x238ea10,RVA_REFILL_AMMO=0x1382c10,RVA_SET_TIMESCALE=0x198ac4c;
static const uint32_t FIELD_CASH_OFF=0,FIELD_HP_OFF=0;
typedef void (*Update0Fn)(void*,void*);
typedef void (*Refill0Fn)(void*,void*);
typedef void (*AddCash1Fn)(void*,int32_t,void*);
typedef bool (*SubCash1Fn)(void*,int32_t,void*,uintptr_t,double,double);
typedef int32_t (*GetDMG2Fn)(void*,uintptr_t,uintptr_t,void*,double,double,double);
typedef void (*SetupBoxes2Fn)(void*,uintptr_t,uintptr_t,void*,double,double,double);
typedef void (*WpnHookFn)(void*,uintptr_t,uintptr_t,uintptr_t,void*,double,double,double,double);
typedef void (*SetTime1Fn)(float,void*);
static Update0Fn orig_CashUpdate=NULL;
static SubCash1Fn orig_SubCash=NULL;
static GetDMG2Fn orig_GetDMG=NULL;
static SetupBoxes2Fn orig_SetupBoxes=NULL;
static WpnHookFn orig_WpnHook=NULL;
static volatile int32_t g_hp_val=0,g_cash_val=0,g_cash_q=0,g_ammo_on=0,g_vis_on=0,g_vis_trig=0;
static uintptr_t getSlide(){
 for(uint32_t i=0;i<_dyld_image_count();i++){
  const char*n=_dyld_get_image_name(i);
  if(n&&strstr(n,"/fps.app/fps"))return _dyld_get_image_vmaddr_slide(i);
 }
 return _dyld_get_image_vmaddr_slide(0);
}
static int32_t hook_GetDMG(void*s,uintptr_t p1,uintptr_t p2,void*m,double d0,double d1,double d2){
 return g_hp_val>0?g_hp_val:(orig_GetDMG?orig_GetDMG(s,p1,p2,m,d0,d1,d2):0);
}
static bool hook_SubCash(void*s,int32_t a,void*m,uintptr_t x3,double d0,double d1){
 if(g_cash_val>0&&s){
  if(RVA_ADD_CASH>0)((AddCash1Fn)(0x100000000ULL+getSlide()+RVA_ADD_CASH))(s,g_cash_val,NULL);
  return true;
 }
 return orig_SubCash?orig_SubCash(s,a,m,x3,d0,d1):false;
}
static void hook_CashUpdate(void*s,void*m){
 if(orig_CashUpdate)orig_CashUpdate(s,m);
 if(!s)return;
 if(g_hp_val>0&&FIELD_HP_OFF>=0x10)*(int32_t*)((uint8_t*)s+FIELD_HP_OFF)=g_hp_val;
 if(g_cash_q>0&&RVA_ADD_CASH>0){
  int32_t bonus=g_cash_q;g_cash_q=0;
  ((AddCash1Fn)(0x100000000ULL+getSlide()+RVA_ADD_CASH))(s,bonus,NULL);
 }
 if(g_cash_val>0&&FIELD_CASH_OFF>=0x10)*(int32_t*)((uint8_t*)s+FIELD_CASH_OFF)=g_cash_val;
 if(g_vis_trig&&RVA_SETUP_BOXES>0){
  g_vis_trig=0;
  ((SetupBoxes2Fn)(0x100000000ULL+getSlide()+RVA_SETUP_BOXES))(s,g_vis_on?1:0,0,NULL,0,0,0);
 }
}
static void hook_Wpn(void*s,uintptr_t p1,uintptr_t p2,uintptr_t p3,void*m,double d0,double d1,double d2,double d3){
 if(orig_WpnHook)orig_WpnHook(s,p1,p2,p3,m,d0,d1,d2,d3);
 if(s&&g_ammo_on&&RVA_REFILL_AMMO>0)((Refill0Fn)(0x100000000ULL+getSlide()+RVA_REFILL_AMMO))(s,NULL);
}
static void hook_SetupBoxes(void*s,uintptr_t p1,uintptr_t p2,void*m,double d0,double d1,double d2){
 if(g_vis_on)p1=1;
 if(orig_SetupBoxes)orig_SetupBoxes(s,p1,p2,m,d0,d1,d2);
}
static void installHooks(){
 uintptr_t base=0x100000000ULL+getSlide();
 if(TBL_CASH_UPDATE){void**sl=(void**)(base+TBL_CASH_UPDATE);orig_CashUpdate=(Update0Fn)*sl;*sl=(void*)&hook_CashUpdate;}
 if(TBL_SUB_CASH){void**sl=(void**)(base+TBL_SUB_CASH);orig_SubCash=(SubCash1Fn)*sl;*sl=(void*)&hook_SubCash;}
 if(TBL_GET_DMG){void**sl=(void**)(base+TBL_GET_DMG);orig_GetDMG=(GetDMG2Fn)*sl;*sl=(void*)&hook_GetDMG;}
 if(TBL_WPN_HOOK){void**sl=(void**)(base+TBL_WPN_HOOK);orig_WpnHook=(WpnHookFn)*sl;*sl=(void*)&hook_Wpn;}
 if(TBL_SETUP_BOXES){void**sl=(void**)(base+TBL_SETUP_BOXES);orig_SetupBoxes=(SetupBoxes2Fn)*sl;*sl=(void*)&hook_SetupBoxes;}
}
@interface OGSPassthroughContainer:UIView
@property(weak,nonatomic)UIButton*floatingButton;
@property(weak,nonatomic)UIView*menuPanel;
@end
@implementation OGSPassthroughContainer
-(BOOL)pointInside:(CGPoint)p withEvent:(UIEvent*)e{
 if(self.floatingButton&&!self.floatingButton.hidden&&[self.floatingButton pointInside:[self convertPoint:p toView:self.floatingButton] withEvent:e])return YES;
 if(self.menuPanel&&!self.menuPanel.hidden&&[self.menuPanel pointInside:[self convertPoint:p toView:self.menuPanel] withEvent:e])return YES;
 return NO;
}
@end
@interface OGSModMenu:NSObject
@property(strong,nonatomic)OGSPassthroughContainer*containerView;
@property(strong,nonatomic)UIButton*floatingButton;
@property(strong,nonatomic)UIView*menuPanel;
@property(strong,nonatomic)UILabel*statusLabel;
@property(assign,nonatomic)NSInteger hpStep,cashStep,timeStep;
@property(assign,nonatomic)BOOL ammoActive,visionActive;
+(instancetype)sharedInstance;
-(void)setupMenu;
@end
@implementation OGSModMenu
+(instancetype)sharedInstance{
 static OGSModMenu*inst=nil;static dispatch_once_t t;dispatch_once(&t,^{inst=[[OGSModMenu alloc]init];});return inst;
}
-(UIWindow*)gameMainWindow{
 for(UIScene*s in[UIApplication sharedApplication].connectedScenes)
  if([s isKindOfClass:[UIWindowScene class]])
   for(UIWindow*w in((UIWindowScene*)s).windows)if(w.isKeyWindow||!w.hidden)return w;
 return[UIApplication sharedApplication].windows.firstObject;
}
-(UIButton*)makeBtn:(CGRect)f title:(NSString*)t action:(SEL)a{
 UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=f;
 b.backgroundColor=[UIColor colorWithRed:0.20 green:0.21 blue:0.25 alpha:1.0];
 [b setTitle:t forState:UIControlStateNormal];[b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
 b.titleLabel.font=[UIFont boldSystemFontOfSize:13];b.layer.cornerRadius=8.0;
 [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];return b;
}
-(void)setupMenu{
 dispatch_async(dispatch_get_main_queue(),^{
  if(self.containerView)return;
  UIWindow*gw=[self gameMainWindow];if(!gw)return;
  self.containerView=[[OGSPassthroughContainer alloc]initWithFrame:gw.bounds];
  self.floatingButton=[UIButton buttonWithType:UIButtonTypeCustom];
  self.floatingButton.frame=CGRectMake(25,130,58,58);
  self.floatingButton.backgroundColor=[UIColor blackColor];self.floatingButton.opaque=YES;
  [self.floatingButton setTitle:@"OGS" forState:UIControlStateNormal];
  self.floatingButton.layer.cornerRadius=29.0;self.floatingButton.layer.borderWidth=2.5f;
  self.floatingButton.layer.borderColor=[UIColor systemRedColor].CGColor;
  [self.floatingButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
  [self.floatingButton addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(handlePan:)]];
  [self.containerView addSubview:self.floatingButton];
  self.menuPanel=[[UIView alloc]initWithFrame:CGRectMake(95,35,275,335)];
  self.menuPanel.backgroundColor=[UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0];
  self.menuPanel.layer.cornerRadius=14.0;self.menuPanel.layer.borderWidth=2.0f;
  self.menuPanel.layer.borderColor=[UIColor systemRedColor].CGColor;self.menuPanel.hidden=YES;
  UILabel*tl=[[UILabel alloc]initWithFrame:CGRectMake(15,10,245,26)];
  tl.text=@"لوحة تحكم OGS الفعالة";tl.textColor=[UIColor whiteColor];
  tl.textAlignment=NSTextAlignmentCenter;tl.font=[UIFont boldSystemFontOfSize:16];
  [self.menuPanel addSubview:tl];
  [self.menuPanel addSubview:[self makeBtn:CGRectMake(15,44,245,42) title:@"الدم والقوة: افتراضي" action:@selector(cycleHP:)]];
  [self.menuPanel addSubview:[self makeBtn:CGRectMake(15,94,245,42) title:@"الفلوس والشراء: افتراضي" action:@selector(cycleCash:)]];
  [self.menuPanel addSubview:[self makeBtn:CGRectMake(15,144,245,42) title:@"الذخيرة بدون تعشيق: متوقف" action:@selector(toggleAmmo:)]];
  [self.menuPanel addSubview:[self makeBtn:CGRectMake(15,194,245,42) title:@"الرؤية خلف الجدران: متوقف" action:@selector(toggleVision:)]];
  [self.menuPanel addSubview:[self makeBtn:CGRectMake(15,244,245,42) title:@"سرعة الوقت: 1.0x طبيعي" action:@selector(cycleTime:)]];
  self.statusLabel=[[UILabel alloc]initWithFrame:CGRectMake(10,294,255,30)];
  self.statusLabel.text=@"جميع الميزات الـ 5 متصلة وفعالة";
  self.statusLabel.textColor=[UIColor systemGreenColor];self.statusLabel.textAlignment=NSTextAlignmentCenter;
  self.statusLabel.font=[UIFont boldSystemFontOfSize:11];[self.menuPanel addSubview:self.statusLabel];
  [self.containerView addSubview:self.menuPanel];
  self.containerView.floatingButton=self.floatingButton;self.containerView.menuPanel=self.menuPanel;
  [gw addSubview:self.containerView];[gw bringSubviewToFront:self.containerView];
 });
}
-(void)toggleMenu{self.menuPanel.hidden=!self.menuPanel.hidden;}
-(void)handlePan:(UIPanGestureRecognizer*)g{
 CGPoint t=[g translationInView:self.containerView];
 g.view.center=CGPointMake(g.view.center.x+t.x,g.view.center.y+t.y);
 [g setTranslation:CGPointZero inView:self.containerView];
}
-(void)cycleHP:(UIButton*)s{
 int32_t v[]={100,200,300,1000,10000,0};int32_t val=v[self.hpStep++%6];g_hp_val=val;
 [s setTitle:(val>0?[NSString stringWithFormat:@"الدم والقوة: %d",val]:@"الدم والقوة: افتراضي") forState:UIControlStateNormal];
}
-(void)cycleCash:(UIButton*)s{
 int32_t v[]={100,200,300,1000,10000,0};int32_t val=v[self.cashStep++%6];g_cash_val=val;g_cash_q=val;
 [s setTitle:(val>0?[NSString stringWithFormat:@"الفلوس والشراء: +%d",val]:@"الفلوس والشراء: افتراضي") forState:UIControlStateNormal];
}
-(void)toggleAmmo:(UIButton*)s{
 self.ammoActive=!self.ammoActive;g_ammo_on=self.ammoActive?1:0;
 [s setTitle:(self.ammoActive?@"الذخيرة بدون تعشيق: مفعّل":@"الذخيرة بدون تعشيق: متوقف") forState:UIControlStateNormal];
}
-(void)toggleVision:(UIButton*)s{
 self.visionActive=!self.visionActive;g_vis_on=self.visionActive?1:0;g_vis_trig=1;
 [s setTitle:(self.visionActive?@"الرؤية خلف الجدران: مفعّل":@"الرؤية خلف الجدران: متوقف") forState:UIControlStateNormal];
}
-(void)cycleTime:(UIButton*)s{
 float sc[]={1.0f,0.5f,0.0f,2.0f};NSArray*lb=@[@"1.0x طبيعي",@"0.5x بطيء",@"0.0x تجميد",@"2.0x سريع"];
 NSInteger i=self.timeStep++%4;
 if(RVA_SET_TIMESCALE)((SetTime1Fn)(0x100000000ULL+getSlide()+RVA_SET_TIMESCALE))(sc[i],NULL);
 [s setTitle:[NSString stringWithFormat:@"سرعة الوقت: %@",lb[i]] forState:UIControlStateNormal];
}
@end
__attribute__((constructor))static void ogs_init(){
 installHooks();
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  [[OGSModMenu sharedInstance]setupMenu];
 });
}