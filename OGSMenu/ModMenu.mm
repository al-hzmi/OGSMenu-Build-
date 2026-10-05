#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

// جداول وعناوين اللعب الأساسية (الدمج 999، الذخيرة، التحديث، السرعة)
static const uintptr_t TBL_CASH_UPDATE       = 0x23918b8;
static const uintptr_t TBL_GET_DMG           = 0x2391388;
static const uintptr_t TBL_WPN_HOOK          = 0x238ea10;
static const uintptr_t RVA_REFILL_AMMO       = 0x1382c10;
static const uintptr_t RVA_SET_TIMESCALE     = 0x198ac4c;

// عناوين PhotonNetwork و PhotonPlayer
static const uintptr_t RVA_IN_ROOM           = 0x013CC38C;
static const uintptr_t RVA_IS_MASTER         = 0x013CC2BC;
static const uintptr_t RVA_ALL_PLAYERS       = 0x013CAEC4;
static const uintptr_t RVA_GET_PEERS         = 0x013CAF78;

static const uintptr_t RVA_PLAYER_GET_NAME   = 0x013D7534;
static const uintptr_t RVA_PLAYER_GET_USERID = 0x013D692C;
static const uintptr_t RVA_PLAYER_GET_ID     = 0x013CC384;
static const uintptr_t RVA_PLAYER_IS_MASTER  = 0x013D305C;
static const uintptr_t RVA_ARABIC_FIX        = 0x0130F538;

static const uintptr_t TBL_PEER_SYNC         = 0x2390a98; // CloseConnection
static const uintptr_t TBL_SET_MASTER        = 0x2390aa0; // SetMasterClient
static const uintptr_t TBL_ON_DISCONNECT     = 0x2391930; // OnPhotonPlayerDisconnected

typedef void    (*Update0Fn)(void *, void *);
typedef void    (*Refill0Fn)(void *, void *);
typedef int32_t (*GetDMG2Fn)(void *, uintptr_t, uintptr_t, void *, double, double, double);
typedef void    (*WpnHookFn)(void *, uintptr_t, uintptr_t, uintptr_t, void *, double, double, double, double);
typedef void    (*SetTime1Fn)(float, void *);

typedef bool    (*DiagBool0Fn)(void *);
typedef void*   (*DiagGetPeers0Fn)(void *);
typedef bool    (*DiagPeerSync1Fn)(void *, void *);
typedef void*   (*PlayerGetStrFn)(void *, void *);
typedef int32_t (*PlayerGetIDFn)(void *, void *);
typedef bool    (*PlayerIsMasterFn)(void *, void *);
typedef void*   (*ArabicFixFn)(void *, void *);
typedef void    (*OnDisconnectFn)(void *, void *, void *);

static Update0Fn      orig_CashUpdate   = NULL;
static GetDMG2Fn      orig_GetDMG       = NULL;
static WpnHookFn      orig_WpnHook      = NULL;
static OnDisconnectFn orig_OnDisconnect = NULL;

static volatile uint32_t g_selected_peer   = 0;
static volatile int32_t  g_super_weapon_on = 1; // مفعّل تلقائياً أول ما تدخل اللعبة (دمج 999 + ذخيرة)
static volatile float    g_custom_speed    = 1.0f;
static volatile int32_t  g_speed_dirty     = 0;
static volatile int32_t  g_kick_msg_armed  = 0;
static volatile int32_t  g_guard_frame_cnt = 0;
static void *g_customKickIl2CppStr = NULL;

static uintptr_t getSlide() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "/fps.app/fps")) return _dyld_get_image_vmaddr_slide(i);
    }
    return _dyld_get_image_vmaddr_slide(0);
}

static bool safeReadMem(uintptr_t addr, void *buf, size_t len) {
    if (addr < 0x100000000ULL) return false;
    vm_size_t outSize = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr, (vm_size_t)len, (vm_address_t)buf, &outSize);
    return (kr == KERN_SUCCESS && outSize == len);
}

static NSString *OGSReadIl2CppString(void *strPtr) {
    if (!strPtr || (uintptr_t)strPtr < 0x100000000ULL) return nil;
    int32_t strLen = 0;
    if (!safeReadMem((uintptr_t)strPtr + 0x10, &strLen, sizeof(int32_t))) return nil;
    if (strLen <= 0 || strLen > 64) return nil;

    uint16_t chars[68] = {0};
    if (!safeReadMem((uintptr_t)strPtr + 0x14, chars, (size_t)strLen * sizeof(uint16_t))) return nil;
    return [NSString stringWithCharacters:chars length:(NSUInteger)strLen];
}

// تنظيف الاسم من المسافات لضمان تطابق الحظر 100%
static NSString *OGSNormalizeKey(NSString *raw) {
    if (!raw) return @"";
    return [[raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

static NSString *OGSGetPlayerIdentity(void *peerObj, NSString **outBanKey, int32_t *outActorID, bool *outIsHost) {
    if (outActorID) *outActorID = 0;
    if (outIsHost)  *outIsHost = false;
    if (outBanKey)  *outBanKey = @"";
    if (!peerObj) return @"غير معروف";

    uintptr_t base = 0x100000000ULL + getSlide();
    PlayerGetIDFn getID       = (PlayerGetIDFn)(base + RVA_PLAYER_GET_ID);
    PlayerGetStrFn getName    = (PlayerGetStrFn)(base + RVA_PLAYER_GET_NAME);
    PlayerGetStrFn getUserId  = (PlayerGetStrFn)(base + RVA_PLAYER_GET_USERID);
    PlayerIsMasterFn isMaster = (PlayerIsMasterFn)(base + RVA_PLAYER_IS_MASTER);

    int32_t actorID = getID ? getID(peerObj, NULL) : 0;
    if (outActorID) *outActorID = actorID;
    if (outIsHost && isMaster) *outIsHost = isMaster(peerObj, NULL);

    NSString *realName = getName ? OGSReadIl2CppString(getName(peerObj, NULL)) : nil;
    NSString *userId   = getUserId ? OGSReadIl2CppString(getUserId(peerObj, NULL)) : nil;

    if (!realName || realName.length == 0) {
        realName = [NSString stringWithFormat:@"ID:%d", actorID];
    }

    if (outBanKey) {
        NSString *normName = OGSNormalizeKey(realName);
        if (userId && userId.length > 0) {
            *outBanKey = [NSString stringWithFormat:@"%@|%@", normName, OGSNormalizeKey(userId)];
        } else {
            *outBanKey = normName;
        }
    }
    return realName;
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

    if (outItems) *outItems = (void **)((uint8_t *)arr + 0x20);
    return (uint32_t)n;
}

static uint32_t OGSGetAllPlayersCount(void ***outItems) {
    uintptr_t base = 0x100000000ULL + getSlide();
    DiagBool0Fn inRoom = (DiagBool0Fn)(base + RVA_IN_ROOM);
    DiagGetPeers0Fn getAll = (DiagGetPeers0Fn)(base + RVA_ALL_PLAYERS);
    if (!inRoom || !inRoom(NULL) || !getAll) return 0;

    void *arr = getAll(NULL);
    if (!arr) return 0;

    uintptr_t n = 0;
    if (!safeReadMem((uintptr_t)arr + 0x18, &n, sizeof(uintptr_t))) return 0;
    if (n == 0 || n > 64) return 0;

    if (outItems) *outItems = (void **)((uint8_t *)arr + 0x20);
    return (uint32_t)n;
}

static void *OGSFindLocalPlayerObject(void) {
    void **allItems = NULL;
    uint32_t allCount = OGSGetAllPlayersCount(&allItems);
    if (allCount == 0 || !allItems) return NULL;

    void **otherItems = NULL;
    uint32_t otherCount = OGSGetPeerCount(&otherItems);
    if (otherCount == 0 || !otherItems) return allItems[0];

    for (uint32_t i = 0; i < allCount; i++) {
        void *cand = allItems[i];
        if (!cand) continue;
        int32_t candID = 0;
        OGSGetPlayerIdentity(cand, NULL, &candID, NULL);

        bool isOther = false;
        for (uint32_t j = 0; j < otherCount; j++) {
            if (otherItems[j] == cand) { isOther = true; break; }
            int32_t otherID = 0;
            OGSGetPlayerIdentity(otherItems[j], NULL, &otherID, NULL);
            if (candID > 0 && otherID == candID) { isOther = true; break; }
        }
        if (!isOther) return cand;
    }
    return NULL;
}

static bool OGSSetRoomMasterObject(void *playerObj) {
    if (!playerObj) return false;
    uintptr_t base = 0x100000000ULL + getSlide();
    void *fnPtr = *(void **)(base + TBL_SET_MASTER);
    if (!fnPtr) return false;
    return ((DiagPeerSync1Fn)fnPtr)(playerObj, NULL);
}

static bool OGSDisconnectPeerRaw(void *peerObj) {
    if (!peerObj) return false;
    g_kick_msg_armed = 1;
    uintptr_t base = 0x100000000ULL + getSlide();
    void *fnPtr = *(void **)(base + TBL_PEER_SYNC);
    if (!fnPtr) return false;
    return ((DiagPeerSync1Fn)fnPtr)(peerObj, NULL);
}

static void OGSKickPeerGuaranteed(void *peerObj) {
    if (!peerObj) return;
    g_kick_msg_armed = 1;
    uintptr_t base = 0x100000000ULL + getSlide();
    DiagBool0Fn isMaster = (DiagBool0Fn)(base + RVA_IS_MASTER);
    if (isMaster && isMaster(NULL)) {
        OGSDisconnectPeerRaw(peerObj);
    } else {
        void *myPlayer = OGSFindLocalPlayerObject();
        if (myPlayer) OGSSetRoomMasterObject(myPlayer);
        OGSDisconnectPeerRaw(peerObj);
    }
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
@property (strong, nonatomic) UIButton *weaponButton;
@property (strong, nonatomic) UIButton *speedSetButton;
@property (strong, nonatomic) NSMutableSet<NSString *> *bannedNames;
@property (strong, nonatomic) NSMutableSet<NSString *> *allowedNamesWhenLocked;
@property (assign, nonatomic) BOOL roomLockActive;
@property (strong, nonatomic) NSTimer *uiTimer;
+ (instancetype)sharedInstance;
- (void)setupMenu;
- (void)runInGameThreadBanCheck;
@end

// بناء نص " تم طرده من الغرفة "
static void *OGSBuildKickLeaveString(void *templateIl2CppStr) {
    if (g_customKickIl2CppStr) return g_customKickIl2CppStr;
    if (!templateIl2CppStr || (uintptr_t)templateIl2CppStr < 0x100000000ULL) return NULL;

    uint8_t header[16] = {0};
    if (!safeReadMem((uintptr_t)templateIl2CppStr, header, 16)) return NULL;

    bool origIsPreFixed = false;
    NSString *origText = OGSReadIl2CppString(templateIl2CppStr);
    if (origText) {
        for (NSUInteger i = 0; i < origText.length; i++) {
            unichar c = [origText characterAtIndex:i];
            if (c >= 0xFE70 && c <= 0xFEFF) { origIsPreFixed = true; break; }
        }
    }

    NSString *kickPhrase = @" تم طرده من الغرفة ";
    NSUInteger len = kickPhrase.length;
    uint8_t *rawObj = (uint8_t *)calloc(1, 0x14 + (len + 2) * sizeof(uint16_t));
    if (!rawObj) return NULL;

    memcpy(rawObj, header, 16);
    *(int32_t *)(rawObj + 0x10) = (int32_t)len;
    [kickPhrase getCharacters:(unichar *)(rawObj + 0x14) range:NSMakeRange(0, len)];

    if (origIsPreFixed) {
        uintptr_t base = 0x100000000ULL + getSlide();
        ArabicFixFn fixFn = (ArabicFixFn)(base + RVA_ARABIC_FIX);
        if (fixFn) {
            void *fixed = fixFn(rawObj, NULL);
            if (fixed) { g_customKickIl2CppStr = fixed; return g_customKickIl2CppStr; }
        }
    }
    g_customKickIl2CppStr = rawObj;
    return g_customKickIl2CppStr;
}

static void hook_OnPhotonPlayerDisconnected(void *self, void *player, void *method) {
    uintptr_t locManager = 0;
    void *origLeaveStr = NULL;
    void **leaveStrSlot = NULL;

    if (self && g_kick_msg_armed > 0 && safeReadMem((uintptr_t)self + 0x2F8, &locManager, sizeof(uintptr_t)) && locManager > 0x100000000ULL) {
        if (safeReadMem(locManager + 0x238, &origLeaveStr, sizeof(void *)) && origLeaveStr != NULL) {
            void *kickStr = OGSBuildKickLeaveString(origLeaveStr);
            if (kickStr) {
                leaveStrSlot = (void **)(locManager + 0x238);
                *leaveStrSlot = kickStr;
            }
        }
        g_kick_msg_armed = 0;
    }

    if (orig_OnDisconnect) orig_OnDisconnect(self, player, method);
    if (leaveStrSlot && origLeaveStr) *leaveStrSlot = origLeaveStr;
}

// خطاف الدمج 999 للسلاح الخاص بك
static int32_t hook_GetDMG(void *s, uintptr_t p1, uintptr_t p2, void *m, double d0, double d1, double d2) {
    if (g_super_weapon_on) return 999;
    return orig_GetDMG ? orig_GetDMG(s, p1, p2, m, d0, d1, d2) : 0;
}

// خطاف الذخيرة اللانهائية للسلاح الخاص بك
static void hook_Wpn(void *s, uintptr_t p1, uintptr_t p2, uintptr_t p3, void *m, double d0, double d1, double d2, double d3) {
    if (orig_WpnHook) orig_WpnHook(s, p1, p2, p3, m, d0, d1, d2, d3);
    if (s && g_super_weapon_on && RVA_REFILL_AMMO > 0) {
        ((Refill0Fn)(0x100000000ULL + getSlide() + RVA_REFILL_AMMO))(s, NULL);
    }
}

// خطاف التحديث الرئيسي داخل خيط Unity: ينفذ السرعة المخصصة + فحص الحظر المضمون
static void hook_CashUpdate(void *s, void *m) {
    if (orig_CashUpdate) orig_CashUpdate(s, m);

    if (g_speed_dirty && RVA_SET_TIMESCALE > 0) {
        g_speed_dirty = 0;
        ((SetTime1Fn)(0x100000000ULL + getSlide() + RVA_SET_TIMESCALE))(g_custom_speed, NULL);
    }

    if (++g_guard_frame_cnt >= 15) {
        g_guard_frame_cnt = 0;
        [[OGSModMenu sharedInstance] runInGameThreadBanCheck];
    }
}

static void installAllHooks() {
    uintptr_t base = 0x100000000ULL + getSlide();
    if (TBL_CASH_UPDATE)   { void **sl = (void **)(base + TBL_CASH_UPDATE);   orig_CashUpdate   = (Update0Fn)*sl;      *sl = (void *)&hook_CashUpdate; }
    if (TBL_GET_DMG)       { void **sl = (void **)(base + TBL_GET_DMG);       orig_GetDMG       = (GetDMG2Fn)*sl;      *sl = (void *)&hook_GetDMG; }
    if (TBL_WPN_HOOK)      { void **sl = (void **)(base + TBL_WPN_HOOK);      orig_WpnHook      = (WpnHookFn)*sl;      *sl = (void *)&hook_Wpn; }
    if (TBL_ON_DISCONNECT) { void **sl = (void **)(base + TBL_ON_DISCONNECT); orig_OnDisconnect = (OnDisconnectFn)*sl; *sl = (void *)&hook_OnPhotonPlayerDisconnected; }
}

@implementation OGSModMenu
+ (instancetype)sharedInstance {
    static OGSModMenu *inst = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        inst = [[OGSModMenu alloc] init];
        inst.bannedNames = [NSMutableSet set];
        inst.allowedNamesWhenLocked = [NSMutableSet set];
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
    b.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
    b.layer.cornerRadius = 7.0;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)setupMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.containerView) return;
        UIWindow *gw = [self gameMainWindow];
        if (!gw) return;

        self.containerView = [[OGSPassthroughContainer alloc] initWithFrame:gw.bounds];

        self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.floatingButton.frame = CGRectMake(20, 100, 50, 50);
        self.floatingButton.backgroundColor = [UIColor blackColor];
        self.floatingButton.opaque = YES;
        [self.floatingButton setTitle:@"OGS" forState:UIControlStateNormal];
        self.floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        self.floatingButton.layer.cornerRadius = 25.0;
        self.floatingButton.layer.borderWidth = 2.0f;
        self.floatingButton.layer.borderColor = [UIColor systemRedColor].CGColor;
        [self.floatingButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [self.floatingButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
        [self.containerView addSubview:self.floatingButton];

        // لوحة مدمجة بالكامل (ارتفاع 296 فقط لتظهر كاملة في الشاشة العرضية)
        self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(80, 15, 310, 296)];
        self.menuPanel.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:0.96];
        self.menuPanel.layer.cornerRadius = 14.0;
        self.menuPanel.layer.borderWidth = 2.0f;
        self.menuPanel.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.menuPanel.hidden = YES;

        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 290, 18)];
        tl.text = @"OGS: الطرد والحظر + السرعة + سلاح 999";
        tl.textColor = [UIColor whiteColor];
        tl.textAlignment = NSTextAlignmentCenter;
        tl.font = [UIFont boldSystemFontOfSize:12.5];
        [self.menuPanel addSubview:tl];

        UIView *infoBox = [[UIView alloc] initWithFrame:CGRectMake(10, 26, 290, 42)];
        infoBox.backgroundColor = [UIColor colorWithRed:0.16 green:0.17 blue:0.20 alpha:1.0];
        infoBox.layer.cornerRadius = 8.0;

        self.playerLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 3, 278, 19)];
        self.playerLabel.text = @"المحدد: لا يوجد لاعبين";
        self.playerLabel.textColor = [UIColor systemYellowColor];
        self.playerLabel.textAlignment = NSTextAlignmentCenter;
        self.playerLabel.font = [UIFont boldSystemFontOfSize:12.5];
        [infoBox addSubview:self.playerLabel];

        self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 22, 278, 17)];
        self.statusLabel.text = @"الغرفة: غير متصل";
        self.statusLabel.textColor = [UIColor systemGreenColor];
        self.statusLabel.textAlignment = NSTextAlignmentCenter;
        self.statusLabel.font = [UIFont systemFontOfSize:10.5];
        [infoBox addSubview:self.statusLabel];
        [self.menuPanel addSubview:infoBox];

        UIColor *darkGray   = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
        UIColor *kickOrange = [UIColor colorWithRed:0.80 green:0.35 blue:0.10 alpha:1.0];
        UIColor *banRed     = [UIColor colorWithRed:0.70 green:0.12 blue:0.15 alpha:1.0];
        UIColor *hostBlue   = [UIColor colorWithRed:0.14 green:0.42 blue:0.72 alpha:1.0];
        UIColor *hostPurple = [UIColor colorWithRed:0.42 green:0.22 blue:0.65 alpha:1.0];
        UIColor *wpnGreen   = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];

        // صف 1: اختيار اللاعب
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 74, 141, 32) title:@"▶ اللاعب السابق" bg:darkGray action:@selector(prevPlayer:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(159, 74, 141, 32) title:@"اللاعب التالي ◀" bg:darkGray action:@selector(nextPlayer:)]];

        // صف 2: طرد أو حظر
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(159, 111, 141, 33) title:@"طرد المحدد فقط" bg:kickOrange action:@selector(kickSelected:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 111, 141, 33) title:@"طرد وحظر (Ban)" bg:banRed action:@selector(banSelected:)]];

        // صف 3: الهوست
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(159, 149, 141, 33) title:@"سحب الهوست لنفسي 👑" bg:hostBlue action:@selector(takeHostForMe:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 149, 141, 33) title:@"منح الهوست للمحدد" bg:hostPurple action:@selector(giveHostToSelected:)]];

        // صف 4: قفل الروم + فك الحظر
        self.lockButton = [self makeBtn:CGRectMake(159, 187, 141, 32) title:@"قفل الروم: مفتوح" bg:darkGray action:@selector(toggleRoomLock:)];
        [self.menuPanel addSubview:self.lockButton];

        self.unbanButton = [self makeBtn:CGRectMake(10, 187, 141, 32) title:@"فك حظر الكل (0)" bg:darkGray action:@selector(clearBanList:)];
        [self.menuPanel addSubview:self.unbanButton];

        // صف 5: التحكم الحر بالسرعة (- / كتابة رقم / +)
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 224, 55, 32) title:@"سرعة -" bg:darkGray action:@selector(speedDown:)]];
        self.speedSetButton = [self makeBtn:CGRectMake(70, 224, 170, 32) title:@"السرعة: 1.0x (اضغط للكتابة)" bg:hostBlue action:@selector(promptCustomSpeed:)];
        [self.menuPanel addSubview:self.speedSetButton];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(245, 224, 55, 32) title:@"سرعة +" bg:darkGray action:@selector(speedUp:)]];

        // صف 6: السلاح الخارق الحصري (دمج 999 + ذخيرة بدون تعشيق)
        self.weaponButton = [self makeBtn:CGRectMake(10, 260, 290, 30) title:@"سلاح خارق (دمج 999 + ذخيرة): مفعّل ⚡" bg:wpnGreen action:@selector(toggleSuperWeapon:)];
        [self.menuPanel addSubview:self.weaponButton];

        [self.containerView addSubview:self.menuPanel];
        self.containerView.floatingButton = self.floatingButton;
        self.containerView.menuPanel = self.menuPanel;
        [gw addSubview:self.containerView];
        [gw bringSubviewToFront:self.containerView];

        self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(onUITick) userInfo:nil repeats:YES];
    });
}

// فحص الحظر المضمون داخل خيط اللعبة الرسمي
- (void)runInGameThreadBanCheck {
    if (self.bannedNames.count == 0 && !self.roomLockActive) return;

    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);
    if (count == 0 || !items) return;

    for (uint32_t i = 0; i < count; i++) {
        void *peer = items[i];
        if (!peer) continue;

        NSString *banKey = nil;
        NSString *pName = OGSGetPlayerIdentity(peer, &banKey, NULL, NULL);
        NSString *normName = OGSNormalizeKey(pName);

        bool isBanned = ([self.bannedNames containsObject:normName] || (banKey.length > 0 && [self.bannedNames containsObject:banKey]));
        if (isBanned) {
            OGSKickPeerGuaranteed(peer);
            continue;
        }
        if (self.roomLockActive && ![self.allowedNamesWhenLocked containsObject:normName]) {
            OGSKickPeerGuaranteed(peer);
        }
    }
}

- (void)onUITick {
    [self runInGameThreadBanCheck];
    if (self.menuPanel && !self.menuPanel.hidden) {
        [self refreshUI];
    }
}

- (void)refreshUI {
    uintptr_t base = 0x100000000ULL + getSlide();
    DiagBool0Fn isMaster = (DiagBool0Fn)(base + RVA_IS_MASTER);
    bool master = isMaster ? isMaster(NULL) : false;

    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);

    if (count == 0 || !items) {
        g_selected_peer = 0;
        self.playerLabel.text = @"المحدد: لا يوجد لاعبين معك حالياً";
    } else {
        if (g_selected_peer >= count) g_selected_peer = 0;
        int32_t actorID = 0;
        bool isPeerHost = false;
        NSString *pName = OGSGetPlayerIdentity(items[g_selected_peer], NULL, &actorID, &isPeerHost);
        self.playerLabel.text = [NSString stringWithFormat:@"(%u/%u) %@%@",
                                 g_selected_peer + 1, count, pName, isPeerHost ? @" 👑" : @""];
    }

    self.statusLabel.text = [NSString stringWithFormat:@"الهوست: %@ | بالروم: %u | المحظورين: %lu",
                             master ? @"أنت 👑" : @"غيرك",
                             count,
                             (unsigned long)self.bannedNames.count];
    [self.unbanButton setTitle:[NSString stringWithFormat:@"فك حظر الكل (%lu)", (unsigned long)self.bannedNames.count] forState:UIControlStateNormal];
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

- (void)takeHostForMe:(UIButton *)s {
    void *myPlayer = OGSFindLocalPlayerObject();
    if (!myPlayer) {
        self.statusLabel.text = @"تأكد أنك داخل غرفة أولاً";
        return;
    }
    OGSSetRoomMasterObject(myPlayer);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshUI];
        self.statusLabel.text = @"تم سحب الهوست لحسابك 👑";
    });
}

- (void)giveHostToSelected:(UIButton *)s {
    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);
    if (count == 0 || !items) return;
    if (g_selected_peer >= count) g_selected_peer = 0;
    NSString *pName = OGSGetPlayerIdentity(items[g_selected_peer], NULL, NULL, NULL);
    OGSSetRoomMasterObject(items[g_selected_peer]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshUI];
        self.statusLabel.text = [NSString stringWithFormat:@"تم نقل الهوست إلى: %@", pName];
    });
}

- (void)kickSelected:(UIButton *)s {
    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);
    if (count == 0 || !items) return;
    if (g_selected_peer >= count) g_selected_peer = 0;
    NSString *pName = OGSGetPlayerIdentity(items[g_selected_peer], NULL, NULL, NULL);
    OGSKickPeerGuaranteed(items[g_selected_peer]);
    self.statusLabel.text = [NSString stringWithFormat:@"تم طرد: %@", pName];
}

- (void)banSelected:(UIButton *)s {
    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);
    if (count == 0 || !items) return;
    if (g_selected_peer >= count) g_selected_peer = 0;

    NSString *banKey = nil;
    NSString *pName = OGSGetPlayerIdentity(items[g_selected_peer], &banKey, NULL, NULL);
    NSString *normName = OGSNormalizeKey(pName);

    if (normName.length > 0) [self.bannedNames addObject:normName];
    if (banKey.length > 0)   [self.bannedNames addObject:banKey];

    OGSKickPeerGuaranteed(items[g_selected_peer]);
    [self refreshUI];
    self.statusLabel.text = [NSString stringWithFormat:@"تم طرد وحظر: %@", pName];
}

- (void)toggleRoomLock:(UIButton *)s {
    self.roomLockActive = !self.roomLockActive;
    [self.allowedNamesWhenLocked removeAllObjects];

    if (self.roomLockActive) {
        void **items = NULL;
        uint32_t count = OGSGetPeerCount(&items);
        for (uint32_t i = 0; i < count; i++) {
            if (items && items[i]) {
                NSString *pName = OGSGetPlayerIdentity(items[i], NULL, NULL, NULL);
                [self.allowedNamesWhenLocked addObject:OGSNormalizeKey(pName)];
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
    [self.bannedNames removeAllObjects];
    [self refreshUI];
    self.statusLabel.text = @"تم مسح قائمة المحظورين بالكامل";
}

- (void)applySpeed:(float)newSpeed {
    if (newSpeed < 0.0f) newSpeed = 0.0f;
    if (newSpeed > 20.0f) newSpeed = 20.0f;
    g_custom_speed = newSpeed;
    g_speed_dirty = 1;
    if (RVA_SET_TIMESCALE > 0) {
        ((SetTime1Fn)(0x100000000ULL + getSlide() + RVA_SET_TIMESCALE))(g_custom_speed, NULL);
    }
    [self.speedSetButton setTitle:[NSString stringWithFormat:@"السرعة: %.1fx (اضغط للكتابة)", g_custom_speed] forState:UIControlStateNormal];
}

- (void)speedDown:(UIButton *)s {
    [self applySpeed:g_custom_speed - 0.5f];
}

- (void)speedUp:(UIButton *)s {
    [self applySpeed:g_custom_speed + 0.5f];
}

- (void)promptCustomSpeed:(UIButton *)s {
    UIWindow *gw = [self gameMainWindow];
    UIViewController *rootVC = gw.rootViewController;
    if (!rootVC) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تحديد السرعة"
                                                                   message:@"اكتب رقم السرعة المطلوبة (مثلاً 0.5 للبطيء، 1.0 للطبيعي، 3.0 للسريع):"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"1.0";
        tf.text = [NSString stringWithFormat:@"%.1f", g_custom_speed];
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"تطبيق" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *txt = alert.textFields.firstObject.text;
        float val = [txt floatValue];
        if (val >= 0.0f && val <= 20.0f) {
            [self applySpeed:val];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)toggleSuperWeapon:(UIButton *)s {
    g_super_weapon_on = !g_super_weapon_on;
    if (g_super_weapon_on) {
        [s setTitle:@"سلاح خارق (دمج 999 + ذخيرة): مفعّل ⚡" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    } else {
        [s setTitle:@"سلاح خارق (دمج 999 + ذخيرة): متوقف" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
}
@end

__attribute__((constructor)) static void ogs_init() {
    installAllHooks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[OGSModMenu sharedInstance] setupMenu];
    });
}
