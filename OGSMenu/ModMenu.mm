#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
@interface OGSMenu : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic) NSUInteger hpIndex, cashIndex, timeIndex;
+ (instancetype)shared;
- (void)show;
@end
@implementation OGSMenu
+ (instancetype)shared { static OGSMenu *m; static dispatch_once_t once; dispatch_once(&once, ^{m=[OGSMenu new];}); return m; }
- (void)show {
 dispatch_async(dispatch_get_main_queue(), ^{
  if(self.window) return;
  UIWindowScene *scene=nil;
  for(UIScene *s in UIApplication.sharedApplication.connectedScenes)
   if([s isKindOfClass:UIWindowScene.class] && s.activationState==UISceneActivationStateForegroundActive) {scene=(UIWindowScene *)s;break;}
  if(!scene) return;
  self.window=[[UIWindow alloc] initWithWindowScene:scene];
  self.window.frame=scene.coordinateSpace.bounds;
  self.window.windowLevel=UIWindowLevelAlert+1;
  self.window.backgroundColor=UIColor.clearColor;
  UIViewController *root=[UIViewController new];root.view.backgroundColor=UIColor.clearColor;
  self.window.rootViewController=root;
  UIButton *floating=[UIButton buttonWithType:UIButtonTypeSystem];
  floating.frame=CGRectMake(24,120,58,58);floating.backgroundColor=UIColor.blackColor;
  floating.layer.cornerRadius=29;floating.layer.borderWidth=2;floating.layer.borderColor=UIColor.systemRedColor.CGColor;
  [floating setTitle:@"OGS" forState:UIControlStateNormal];[floating setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
  [floating addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
  [root.view addSubview:floating];
  self.panel=[[UIView alloc]initWithFrame:CGRectMake(90,95,270,340)];
  self.panel.backgroundColor=[UIColor colorWithRed:.11 green:.11 blue:.13 alpha:1];
  self.panel.layer.cornerRadius=14;self.panel.hidden=YES;
  UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(10,10,250,32)];
  title.text=@"OGS UI DEMO";title.textColor=UIColor.whiteColor;title.textAlignment=NSTextAlignmentCenter;
  [self.panel addSubview:title];
  NSArray *names=@[@"HP preset",@"Cash preset",@"Ammo toggle (demo)",@"Vision toggle (demo)",@"Time preset"];
  SEL acts[]={@selector(hp:),@selector(cash:),@selector(ammo:),@selector(vision:),@selector(time:)};
  for(int i=0;i<5;i++){
   UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=CGRectMake(12,48+i*47,246,39);
   b.backgroundColor=[UIColor colorWithWhite:.23 alpha:1];b.layer.cornerRadius=8;
   [b setTitle:names[i] forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
   [b addTarget:self action:acts[i] forControlEvents:UIControlEventTouchUpInside];[self.panel addSubview:b];
  }
  self.status=[[UILabel alloc]initWithFrame:CGRectMake(10,288,250,35)];
  self.status.text=@"UI demo only";self.status.textColor=UIColor.systemGreenColor;self.status.textAlignment=NSTextAlignmentCenter;
  [self.panel addSubview:self.status];[root.view addSubview:self.panel];
  self.window.hidden=NO;
 });
}
- (void)toggle {self.panel.hidden=!self.panel.hidden;}
- (void)hp:(UIButton *)b {NSArray *v=@[@100,@200,@300,@1000,@10000];NSNumber *n=v[self.hpIndex++%v.count];[b setTitle:[NSString stringWithFormat:@"HP: %@",n] forState:UIControlStateNormal];self.status.text=@"Demo: HP selected";}
- (void)cash:(UIButton *)b {NSArray *v=@[@100,@200,@300,@1000,@10000];NSNumber *n=v[self.cashIndex++%v.count];[b setTitle:[NSString stringWithFormat:@"Cash: %@",n] forState:UIControlStateNormal];self.status.text=@"Demo: Cash selected";}
- (void)ammo:(UIButton *)b {b.selected=!b.selected;[b setTitle:b.selected?@"Ammo demo: ON":@"Ammo demo: OFF" forState:UIControlStateNormal];self.status.text=@"UI only; no game changes";}
- (void)vision:(UIButton *)b {b.selected=!b.selected;[b setTitle:b.selected?@"Vision demo: ON":@"Vision demo: OFF" forState:UIControlStateNormal];self.status.text=@"UI only; no game changes";}
- (void)time:(UIButton *)b {NSArray *v=@[@"1.0x",@"0.5x",@"0.0x",@"2.0x"];[b setTitle:[@"Time demo: " stringByAppendingString:v[self.timeIndex++%v.count]] forState:UIControlStateNormal];self.status.text=@"UI only; no game changes";}
@end
__attribute__((constructor)) static void ogs_init(void) {
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[[OGSMenu shared] show];});
}
