#import <UIKit/UIKit.h>
@interface OGSPassthroughContainer : UIView
@property(nonatomic,weak) UIButton *floatingButton;
@property(nonatomic,weak) UIView *menuPanel;
@end
@implementation OGSPassthroughContainer
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
 if(self.floatingButton && !self.floatingButton.hidden && [self.floatingButton pointInside:[self convertPoint:p toView:self.floatingButton] withEvent:e]) return YES;
 if(self.menuPanel && !self.menuPanel.hidden && [self.menuPanel pointInside:[self convertPoint:p toView:self.menuPanel] withEvent:e]) return YES;
 return NO;
}
@end
@interface OGSModMenu:NSObject
@property(nonatomic,strong) OGSPassthroughContainer *containerView;
@property(nonatomic,strong) UIButton *floatingButton;
@property(nonatomic,strong) UIView *menuPanel;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic) NSInteger hpStep,cashStep,timeStep;
@property(nonatomic) BOOL ammoActive,visionActive;
+ (instancetype)sharedInstance;
- (void)setupMenu;
@end
@implementation OGSModMenu
+ (instancetype)sharedInstance {static OGSModMenu *m;static dispatch_once_t once;dispatch_once(&once,^{m=[OGSModMenu new];});return m;}
- (UIWindow *)gameMainWindow {
 for(UIScene *s in UIApplication.sharedApplication.connectedScenes) if([s isKindOfClass:UIWindowScene.class] && s.activationState==UISceneActivationStateForegroundActive) {
  UIWindowScene *scene=(UIWindowScene *)s;
  for(UIWindow *w in scene.windows) if(w.isKeyWindow) return w;
  for(UIWindow *w in scene.windows) if(!w.hidden && w.windowLevel==UIWindowLevelNormal) return w;
 }
 return UIApplication.sharedApplication.keyWindow;
}
- (UIButton *)makeButton:(CGRect)frame title:(NSString *)title action:(SEL)action {
 UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=frame;
 b.backgroundColor=[UIColor colorWithRed:.20 green:.21 blue:.25 alpha:1];
 [b setTitle:title forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
 b.titleLabel.font=[UIFont boldSystemFontOfSize:13];b.layer.cornerRadius=8;
 [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;
}
- (void)setupMenu {dispatch_async(dispatch_get_main_queue(),^{
 if(self.containerView)return;
 UIWindow *w=[self gameMainWindow];if(!w)return;
 self.containerView=[[OGSPassthroughContainer alloc]initWithFrame:w.bounds];
 self.containerView.backgroundColor=UIColor.clearColor;
 self.containerView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 self.floatingButton=[UIButton buttonWithType:UIButtonTypeCustom];
 self.floatingButton.frame=CGRectMake(25,130,58,58);
 self.floatingButton.backgroundColor=[UIColor colorWithRed:.06 green:.06 blue:.06 alpha:1];
 self.floatingButton.alpha=1;self.floatingButton.opaque=YES;
 [self.floatingButton setTitle:@"OGS" forState:UIControlStateNormal];
 [self.floatingButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
 self.floatingButton.titleLabel.font=[UIFont boldSystemFontOfSize:15];
 self.floatingButton.layer.cornerRadius=29;self.floatingButton.layer.borderWidth=2.5;
 self.floatingButton.layer.borderColor=UIColor.systemRedColor.CGColor;
 [self.floatingButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
 [self.floatingButton addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(handlePan:)]];
 [self.containerView addSubview:self.floatingButton];
 self.menuPanel=[[UIView alloc]initWithFrame:CGRectMake(95,40,270,330)];
 self.menuPanel.backgroundColor=[UIColor colorWithRed:.11 green:.11 blue:.13 alpha:1];
 self.menuPanel.alpha=1;self.menuPanel.opaque=YES;self.menuPanel.layer.cornerRadius=14;
 self.menuPanel.layer.borderWidth=2;self.menuPanel.layer.borderColor=UIColor.systemRedColor.CGColor;
 self.menuPanel.hidden=YES;
 UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(15,10,240,26)];
 title.text=@"لوحة تحكم OGS";title.textColor=UIColor.whiteColor;
 title.textAlignment=NSTextAlignmentCenter;title.font=[UIFont boldSystemFontOfSize:16];
 [self.menuPanel addSubview:title];
 NSArray *labels=@[@"الدم: اضغط للتبديل",@"الفلوس: اضغط للتبديل",@"الذخيرة (تجريبي): متوقف",@"الرؤية (تجريبي): متوقف",@"سرعة الوقت: 1.0x طبيعي"];
 SEL actions[]={@selector(cycleHP:),@selector(cycleCash:),@selector(toggleAmmo:),@selector(toggleVision:),@selector(cycleTime:)};
 for(int i=0;i<5;i++)[self.menuPanel addSubview:[self makeButton:CGRectMake(15,44+50*i,240,42) title:labels[i] action:actions[i]]];
 self.statusLabel=[[UILabel alloc]initWithFrame:CGRectMake(15,292,240,28)];
 self.statusLabel.text=@"واجهة تجريبية — اللمس مفعّل";
 self.statusLabel.textColor=UIColor.systemGreenColor;self.statusLabel.textAlignment=NSTextAlignmentCenter;
 self.statusLabel.font=[UIFont boldSystemFontOfSize:12];[self.menuPanel addSubview:self.statusLabel];
 [self.containerView addSubview:self.menuPanel];
 self.containerView.floatingButton=self.floatingButton;self.containerView.menuPanel=self.menuPanel;
 [w addSubview:self.containerView];[w bringSubviewToFront:self.containerView];
});}
- (void)toggleMenu {self.menuPanel.hidden=!self.menuPanel.hidden;[self.containerView.superview bringSubviewToFront:self.containerView];}
- (void)handlePan:(UIPanGestureRecognizer *)g {
 CGPoint t=[g translationInView:self.containerView],c=CGPointMake(g.view.center.x+t.x,g.view.center.y+t.y);
 CGRect b=self.containerView.bounds;c.x=MAX(32,MIN(b.size.width-32,c.x));c.y=MAX(32,MIN(b.size.height-32,c.y));
 g.view.center=c;[g setTranslation:CGPointZero inView:self.containerView];
}
- (void)cycleHP:(UIButton *)b {NSArray *v=@[@100,@200,@300,@1000,@10000];NSNumber *n=v[self.hpStep++%v.count];[b setTitle:[NSString stringWithFormat:@"الدم: %@",n] forState:UIControlStateNormal];self.statusLabel.text=[NSString stringWithFormat:@"اختيار تجريبي: %@",n];}
- (void)cycleCash:(UIButton *)b {NSArray *v=@[@100,@200,@300,@1000,@10000];NSNumber *n=v[self.cashStep++%v.count];[b setTitle:[NSString stringWithFormat:@"الفلوس: %@",n] forState:UIControlStateNormal];self.statusLabel.text=[NSString stringWithFormat:@"اختيار تجريبي: %@",n];}
- (void)toggleAmmo:(UIButton *)b {self.ammoActive=!self.ammoActive;[b setTitle:self.ammoActive?@"الذخيرة (تجريبي): مفعّل":@"الذخيرة (تجريبي): متوقف" forState:UIControlStateNormal];self.statusLabel.text=@"الواجهة فقط — لا تعديل للعبة";}
- (void)toggleVision:(UIButton *)b {self.visionActive=!self.visionActive;[b setTitle:self.visionActive?@"الرؤية (تجريبي): مفعّل":@"الرؤية (تجريبي): متوقف" forState:UIControlStateNormal];self.statusLabel.text=@"الواجهة فقط — لا تعديل للعبة";}
- (void)cycleTime:(UIButton *)b {NSArray *v=@[@"1.0x طبيعي",@"0.5x بطيء",@"0.0x تجميد",@"2.0x سريع"];NSString *s=v[self.timeStep++%v.count];[b setTitle:[@"سرعة الوقت: " stringByAppendingString:s] forState:UIControlStateNormal];self.statusLabel.text=@"الواجهة فقط — لا تعديل للعبة";}
@end
__attribute__((constructor)) static void ogs_init(void){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[[OGSModMenu sharedInstance]setupMenu];});}
