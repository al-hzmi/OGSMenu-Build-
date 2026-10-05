#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdint.h>
#include <string.h>

// عناوين PhotonNetwork الخاصة بالغرفة واللاعبين والطرد فقط
static const uintptr_t RVA_IN_ROOM    = 0x013CC38C;
static const uintptr_t RVA_IS_MASTER  = 0x013CC2BC;
static const uintptr_t RVA_GET_PEERS  = 0x013CAF78;
static const uintptr_t TBL_PEER_SYNC  = 0x2390a98; // جدول CloseConnection(PhotonPlayer)

typedef bool  (*DiagBool0Fn)(void *);
typedef void* (*DiagGetPeers0Fn)(void *);
typedef bool  (*DiagPeerSync1Fn)(void *, void *);

static volatile uint32_t g_selected_peer = 0;

static uintptr_t getSlide() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "/fps.app/fps")) return _dyld_get_image_vmaddr_slide(i);
    }
    return _dyld_get_image_vmaddr_slide(0);
}

// قراءة آمنة للذاكرة بدون كراش لاستخراج اسم اللاعب من كائن PhotonPlayer
static bool safeReadMem(uintptr_t addr, void *buf, size_t len) {
    if (addr < 0x100000000ULL) return false;
    vm_size_t outSize = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr, (vm_size_t)len, (vm_address_t)buf, &outSize);
    return (kr == KERN_SUCCESS && outSize == len);
}

static NSString *OGSGetPlayerNameAndID(void *peerObj, int32_t *outActorID) {
    if (outActorID) *outActorID = 0;
    if (!peerObj) return @"غير معروف";

    uintptr_t baseObj = (uintptr_t)peerObj;
    int32_t actorID = 0;
    if (safeReadMem(baseObj + 0x10, &actorID, sizeof(int32_t))) {
        if (actorID > 0 && actorID < 10000 && outActorID) {
            *outActorID = actorID;
        }
    }

    // فحص الحقول النصية داخل PhotonPlayer لاستخراج Il2CppString الخاص بالاسم
    const uintptr_t candidateOffsets[] = {0x18, 0x20, 0x28, 0x10, 0x30, 0x38};
    for (size_t i = 0; i < sizeof(candidateOffsets)/sizeof(candidateOffsets[0]); i++) {
        uintptr_t strPtr = 0;
        if (!safeReadMem(baseObj + candidateOffsets[i], &strPtr, sizeof(uintptr_t))) continue;
        if (strPtr < 0x100000000ULL) continue;

        int32_t strLen = 0;
        if (!safeReadMem(strPtr + 0x10, &strLen, sizeof(int32_t))) continue;
        if (strLen <= 0 || strLen > 36) continue;

        uint16_t chars[40] = {0};
        if (!safeReadMem(strPtr + 0x14, chars, (size_t)(strLen + 1) * sizeof(uint16_t))) continue;
        if (chars[strLen] != 0) continue; // يجب أن ينتهي النص بـ Null Terminator

        bool validChars = true;
        for (int32_t c = 0; c < strLen; c++) {
            if (chars[c] < 0x20 || chars[c] == 0xFFFE || chars[c] == 0xFFFF) {
                validChars = false;
                break;
            }
        }
        if (validChars) {
            NSString *name = [NSString stringWithCharacters:chars length:(NSUInteger)strLen];
            if (name.length > 0) return name;
        }
    }

    if (actorID > 0 && actorID < 10000) {
        return [NSString stringWithFormat:@"ID:%d", actorID];
    }
    return [NSString stringWithFormat:@"Player_%p", peerObj];
}

static uint32_t OGSGetPeerCount(void ***outItems) {
    uintptr_t base = 0x100000000ULL + getSlide();
    DiagBool0Fn inRoom = (DiagBool0Fn)(base + RVA_IN_ROOM);
    DiagGetPeers0Fn getPeers = (DiagGetPeers0Fn)(base + RVA_GET_PEERS);
    if (!inRoom || !inRoom(NULL) || !getPeers) return 0;

    void *arr = getPeers(NULL);
    if (!arr) return 0;

    uintptr_t n = 0;
    if (!safeReadMem((uintptr_t)arr + 0x18, &n, sizeof(uintptr_t))) return 0;
    if (n == 0 || n > 64) return 0;

    if (outItems) {
        *outItems = (void **)((uint8_t *)arr + 0x20);
    }
    return (uint32_t)n;
}

static bool OGSDisconnectPeerObject(void *peerObj) {
    if (!peerObj) return false;
    uintptr_t base = 0x100000000ULL + getSlide();
    void *fnPtr = *(void **)(base + TBL_PEER_SYNC);
    if (!fnPtr) return false;
    ((DiagPeerSync1Fn)fnPtr)(peerObj, NULL);
    return true;
}

@interface OGSPassthroughContainer : UIView
@property (weak, nonatomic) UIButton *floatingButton;
@property (weak, nonatomic) UIView *menuPanel;
@end

@implementation OGSPassthroughContainer
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.floatingButton && !self.floatingButton.hidden && [self.floatingButton pointInside:[self convertPoint:p toView:self.floatingButton] withEvent:e]) return YES;
    if (self.menuPanel && !self.menuPanel.hidden && [self.menuPanel pointInside:[self convertPoint:p toView:self.menuPanel] withEvent:e]) return YES;
    return NO;
}
@end

@interface OGSModMenu : NSObject
@property (strong, nonatomic) OGSPassthroughContainer *containerView;
@property (strong, nonatomic) UIButton *floatingButton;
@property (strong, nonatomic) UIView *menuPanel;
@property (strong, nonatomic) UILabel *playerLabel;
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UIButton *unbanButton;
@property (strong, nonatomic) UIButton *lockButton;
@property (strong, nonatomic) NSMutableSet<NSString *> *bannedKeys;
@property (strong, nonatomic) NSMutableSet<NSString *> *allowedKeysWhenLocked;
@property (assign, nonatomic) BOOL roomLockActive;
@property (strong, nonatomic) NSTimer *guardTimer;
+ (instancetype)sharedInstance;
- (void)setupMenu;
@end

@implementation OGSModMenu
+ (instancetype)sharedInstance {
    static OGSModMenu *inst = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        inst = [[OGSModMenu alloc] init];
        inst.bannedKeys = [NSMutableSet set];
        inst.allowedKeysWhenLocked = [NSMutableSet set];
    });
    return inst;
}

- (UIWindow *)gameMainWindow {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]])
            for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow || !w.hidden) return w;
    return [UIApplication sharedApplication].windows.firstObject;
}

- (UIButton *)makeBtn:(CGRect)f title:(NSString *)t bg:(UIColor *)bg action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    b.backgroundColor = bg;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12.5];
    b.layer.cornerRadius = 8.0;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)setupMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.containerView) return;
        UIWindow *gw = [self gameMainWindow];
        if (!gw) return;

        self.containerView = [[OGSPassthroughContainer alloc] initWithFrame:gw.bounds];

        // الزر العائم
        self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatingButton.frame = CGRectMake(20, 110, 52, 52);
        self.floatingButton.backgroundColor = [UIColor blackColor];
        self.floatingButton.opaque = YES;
        [self.floatingButton setTitle:@"OGS" forState:UIControlStateNormal];
        self.floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        self.floatingButton.layer.cornerRadius = 26.0;
        self.floatingButton.layer.borderWidth = 2.0f;
        self.floatingButton.layer.borderColor = [UIColor systemRedColor].CGColor;
        [self.floatingButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [self.floatingButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
        [self.containerView addSubview:self.floatingButton];

        // لوحة قصيرة ومناسبة تماماً للشاشة العرضية (الارتفاع 230 فقط)
        self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(85, 30, 305, 230)];
        self.menuPanel.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:0.96];
        self.menuPanel.layer.cornerRadius = 14.0;
        self.menuPanel.layer.borderWidth = 2.0f;
        self.menuPanel.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.menuPanel.hidden = YES;

        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 281, 22)];
        tl.text = @"إدارة الروم: طرد وحظر اللاعبين";
        tl.textColor = [UIColor whiteColor];
        tl.textAlignment = NSTextAlignmentCenter;
        tl.font = [UIFont boldSystemFontOfSize:14];
        [self.menuPanel addSubview:tl];

        // شاشة عرض اسم اللاعب المحدد حالياً
        UIView *infoBox = [[UIView alloc] initWithFrame:CGRectMake(12, 34, 281, 48)];
        infoBox.backgroundColor = [UIColor colorWithRed:0.16 green:0.17 blue:0.20 alpha:1.0];
        infoBox.layer.cornerRadius = 8.0;

        self.playerLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, 265, 22)];
        self.playerLabel.text = @"المحدد: لا يوجد لاعبين";
        self.playerLabel.textColor = [UIColor systemYellowColor];
        self.playerLabel.textAlignment = NSTextAlignmentCenter;
        self.playerLabel.font = [UIFont boldSystemFontOfSize:13.5];
        [infoBox addSubview:self.playerLabel];

        self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 26, 265, 18)];
        self.statusLabel.text = @"الغرفة: غير متصل";
        self.statusLabel.textColor = [UIColor systemGreenColor];
        self.statusLabel.textAlignment = NSTextAlignmentCenter;
        self.statusLabel.font = [UIFont systemFontOfSize:11];
        [infoBox addSubview:self.statusLabel];
        [self.menuPanel addSubview:infoBox];

        UIColor *darkGray = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
        UIColor *kickOrange = [UIColor colorWithRed:0.80 green:0.35 blue:0.10 alpha:1.0];
        UIColor *banRed = [UIColor colorWithRed:0.70 green:0.12 blue:0.15 alpha:1.0];

        // الصف الأول: التنقل بين اللاعبين بالاسم
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(12, 90, 136, 38) title:@"▶ اللاعب السابق" bg:darkGray action:@selector(prevPlayer:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(157, 90, 136, 38) title:@"اللاعب التالي ◀" bg:darkGray action:@selector(nextPlayer:)]];

        // الصف الثاني: طرد عادي أو طرد مع حظر نهائي
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(157, 136, 136, 40) title:@"طرد المحدد فقط" bg:kickOrange action:@selector(kickSelected:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(12, 136, 136, 40) title:@"طرد وحظر (Ban)" bg:banRed action:@selector(banSelected:)]];

        // الصف الثالث: قفل الروم بالكامل + فك الحظر
        self.lockButton = [self makeBtn:CGRectMake(157, 184, 136, 36) title:@"قفل الروم: مفتوح" bg:darkGray action:@selector(toggleRoomLock:)];
        [self.menuPanel addSubview:self.lockButton];

        self.unbanButton = [self makeBtn:CGRectMake(12, 184, 136, 36) title:@"فك حظر الكل (0)" bg:darkGray action:@selector(clearBanList:)];
        [self.menuPanel addSubview:self.unbanButton];

        [self.containerView addSubview:self.menuPanel];
        self.containerView.floatingButton = self.floatingButton;
        self.containerView.menuPanel = self.menuPanel;
        [gw addSubview:self.containerView];
        [gw bringSubviewToFront:self.containerView];

        // مؤقت دوري يفحص الغرفة ويطرد أي شخص محظور يحاول الدخول تلقائياً
        self.guardTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(onGuardTick) userInfo:nil repeats:YES];
    });
}

- (void)refreshUI {
    uintptr_t base = 0x100000000ULL + getSlide();
    DiagBool0Fn inRoom = (DiagBool0Fn)(base + RVA_IN_ROOM);
    DiagBool0Fn isMaster = (DiagBool0Fn)(base + RVA_IS_MASTER);
    bool room = inRoom ? inRoom(NULL) : false;
    bool master = isMaster ? isMaster(NULL) : false;

    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);

    if (count == 0 || !items) {
        g_selected_peer = 0;
        self.playerLabel.text = @"المحدد: لا يوجد لاعبين معك حالياً";
    } else {
        if (g_selected_peer >= count) g_selected_peer = 0;
        int32_t actorID = 0;
        NSString *pName = OGSGetPlayerNameAndID(items[g_selected_peer], &actorID);
        self.playerLabel.text = [NSString stringWithFormat:@"اللاعب (%u/%u): %@", g_selected_peer + 1, count, pName];
    }

    self.statusLabel.text = [NSString stringWithFormat:@"الهوست: %@ | بالروم: %u | المحظورين: %lu",
                             master ? @"أنت" : @"لا",
                             count,
                             (unsigned long)self.bannedKeys.count];
    [self.unbanButton setTitle:[NSString stringWithFormat:@"فك حظر الكل (%lu)", (unsigned long)self.bannedKeys.count] forState:UIControlStateNormal];
}

- (void)onGuardTick {
    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);
    if (count > 0 && items) {
        for (uint32_t i = 0; i < count; i++) {
            void *peer = items[i];
            if (!peer) continue;
            int32_t actorID = 0;
            NSString *pName = OGSGetPlayerNameAndID(peer, &actorID);

            // 1. إذا كان اسم اللاعب في قائمة المحظورين، اطرده فوراً
            if ([self.bannedKeys containsObject:pName]) {
                OGSDisconnectPeerObject(peer);
                continue;
            }
            // 2. إذا كان قفل الروم مفعلاً واللاعب ليس من ضمن الموجودين وقت القفل، اطرده فوراً
            if (self.roomLockActive && ![self.allowedKeysWhenLocked containsObject:pName]) {
                OGSDisconnectPeerObject(peer);
            }
        }
    }
    if (self.menuPanel && !self.menuPanel.hidden) {
        [self refreshUI];
    }
}

- (void)toggleMenu {
    self.menuPanel.hidden = !self.menuPanel.hidden;
    if (!self.menuPanel.hidden) [self refreshUI];
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.containerView];
    g.view.center = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.containerView];
}

- (void)nextPlayer:(UIButton *)s {
    uint32_t n = OGSGetPeerCount(NULL);
    if (n > 0) g_selected_peer = (g_selected_peer + 1) % n;
    else g_selected_peer = 0;
    [self refreshUI];
}

- (void)prevPlayer:(UIButton *)s {
    uint32_t n = OGSGetPeerCount(NULL);
    if (n > 0) g_selected_peer = (g_selected_peer + n - 1) % n;
    else g_selected_peer = 0;
    [self refreshUI];
}

- (void)kickSelected:(UIButton *)s {
    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);
    if (count == 0 || !items) {
        self.statusLabel.text = @"لا يوجد لاعب لطرده حالياً";
        return;
    }
    if (g_selected_peer >= count) g_selected_peer = 0;
    int32_t actorID = 0;
    NSString *pName = OGSGetPlayerNameAndID(items[g_selected_peer], &actorID);
    OGSDisconnectPeerObject(items[g_selected_peer]);
    self.statusLabel.text = [NSString stringWithFormat:@"تم طرد: %@", pName];
}

- (void)banSelected:(UIButton *)s {
    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);
    if (count == 0 || !items) {
        self.statusLabel.text = @"لا يوجد لاعب لحظره حالياً";
        return;
    }
    if (g_selected_peer >= count) g_selected_peer = 0;
    int32_t actorID = 0;
    NSString *pName = OGSGetPlayerNameAndID(items[g_selected_peer], &actorID);
    [self.bannedKeys addObject:pName];
    OGSDisconnectPeerObject(items[g_selected_peer]);
    [self refreshUI];
    self.statusLabel.text = [NSString stringWithFormat:@"تم طرد وحظر: %@", pName];
}

- (void)toggleRoomLock:(UIButton *)s {
    self.roomLockActive = !self.roomLockActive;
    [self.allowedKeysWhenLocked removeAllObjects];

    if (self.roomLockActive) {
        void **items = NULL;
        uint32_t count = OGSGetPeerCount(&items);
        for (uint32_t i = 0; i < count; i++) {
            if (items && items[i]) {
                NSString *pName = OGSGetPlayerNameAndID(items[i], NULL);
                [self.allowedKeysWhenLocked addObject:pName];
            }
        }
        [s setTitle:@"قفل الروم: مقفل 🔒" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    } else {
        [s setTitle:@"قفل الروم: مفتوح" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
    [self refreshUI];
}

- (void)clearBanList:(UIButton *)s {
    [self.bannedKeys removeAllObjects];
    [self refreshUI];
    self.statusLabel.text = @"تم مسح قائمة المحظورين بالكامل";
}
@end

__attribute__((constructor)) static void ogs_init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[OGSModMenu sharedInstance] setupMenu];
    });
}
