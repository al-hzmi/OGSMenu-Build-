#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

// عناوين PhotonNetwork و PhotonPlayer المؤكدة من الفحص
static const uintptr_t RVA_IN_ROOM           = 0x013CC38C; // PhotonNetwork::get_inRoom()
static const uintptr_t RVA_IS_MASTER         = 0x013CC2BC; // PhotonNetwork::get_isMasterClient()
static const uintptr_t RVA_ALL_PLAYERS       = 0x013CAEC4; // PhotonNetwork::get_playerList()
static const uintptr_t RVA_GET_PEERS         = 0x013CAF78; // PhotonNetwork::get_otherPlayers()

static const uintptr_t RVA_PLAYER_GET_NAME   = 0x013D7534; // PhotonPlayer::get_name()
static const uintptr_t RVA_PLAYER_GET_ID     = 0x013CC384; // PhotonPlayer::get_ID()
static const uintptr_t RVA_PLAYER_IS_MASTER  = 0x013D305C; // PhotonPlayer::get_IsMasterClient()
static const uintptr_t RVA_ARABIC_FIX        = 0x0130F538; // Type4294::Fix(Il2CppString*)

// جداول الدوال القابلة للربط والتنفيذ (__DATA)
static const uintptr_t TBL_PEER_SYNC         = 0x2390a98;  // PhotonNetwork::CloseConnection(PhotonPlayer)
static const uintptr_t TBL_SET_MASTER        = 0x2390aa0;  // PhotonNetwork::SetMasterClient(PhotonPlayer)
static const uintptr_t TBL_ON_DISCONNECT     = 0x2391930;  // Type4640::OnPhotonPlayerDisconnected(PhotonPlayer)

typedef bool    (*DiagBool0Fn)(void *);
typedef void*   (*DiagGetPeers0Fn)(void *);
typedef bool    (*DiagPeerSync1Fn)(void *, void *);
typedef void*   (*PlayerGetNameFn)(void *, void *);
typedef int32_t (*PlayerGetIDFn)(void *, void *);
typedef bool    (*PlayerIsMasterFn)(void *, void *);
typedef void*   (*ArabicFixFn)(void *, void *);
typedef void    (*OnDisconnectFn)(void *, void *, void *);

static OnDisconnectFn orig_OnDisconnect = NULL;
static volatile uint32_t g_selected_peer = 0;
static volatile int32_t  g_kick_msg_armed = 0;
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

// تحويل Il2CppString إلى NSString
static NSString *OGSReadIl2CppString(void *strPtr) {
    if (!strPtr || (uintptr_t)strPtr < 0x100000000ULL) return nil;
    int32_t strLen = 0;
    if (!safeReadMem((uintptr_t)strPtr + 0x10, &strLen, sizeof(int32_t))) return nil;
    if (strLen <= 0 || strLen > 64) return nil;

    uint16_t chars[68] = {0};
    if (!safeReadMem((uintptr_t)strPtr + 0x14, chars, (size_t)strLen * sizeof(uint16_t))) return nil;
    return [NSString stringWithCharacters:chars length:(NSUInteger)strLen];
}

// جلب اسم اللاعب الحقيقي ورقمه وحالة الهوست مباشرة من دوال PhotonPlayer الرسمية
static NSString *OGSGetPlayerNameAndID(void *peerObj, int32_t *outActorID, bool *outIsHost) {
    if (outActorID) *outActorID = 0;
    if (outIsHost)  *outIsHost = false;
    if (!peerObj) return @"غير معروف";

    uintptr_t base = 0x100000000ULL + getSlide();
    PlayerGetIDFn getID = (PlayerGetIDFn)(base + RVA_PLAYER_GET_ID);
    PlayerGetNameFn getName = (PlayerGetNameFn)(base + RVA_PLAYER_GET_NAME);
    PlayerIsMasterFn getMaster = (PlayerIsMasterFn)(base + RVA_PLAYER_IS_MASTER);

    int32_t actorID = getID ? getID(peerObj, NULL) : 0;
    if (outActorID) *outActorID = actorID;
    if (outIsHost && getMaster) *outIsHost = getMaster(peerObj, NULL);

    if (getName) {
        void *il2cppName = getName(peerObj, NULL);
        NSString *realName = OGSReadIl2CppString(il2cppName);
        if (realName && realName.length > 0) {
            return realName;
        }
    }
    return [NSString stringWithFormat:@"ID:%d", actorID];
}

// بناء Il2CppString مطابق لنسق اللعبة لعبارة " تم طرده من الغرفة "
static void *OGSBuildKickLeaveString(void *templateIl2CppStr) {
    if (g_customKickIl2CppStr) return g_customKickIl2CppStr;
    if (!templateIl2CppStr || (uintptr_t)templateIl2CppStr < 0x100000000ULL) return NULL;

    uint8_t header[16] = {0};
    if (!safeReadMem((uintptr_t)templateIl2CppStr, header, 16)) return NULL;

    // نفحص هل النص الأصلي في [X21 + 0x238] معالج مسبقاً بدالة Fix أم نص عربي خام
    bool origIsPreFixed = false;
    NSString *origText = OGSReadIl2CppString(templateIl2CppStr);
    if (origText) {
        for (NSUInteger i = 0; i < origText.length; i++) {
            unichar c = [origText characterAtIndex:i];
            if (c >= 0xFE70 && c <= 0xFEFF) {
                origIsPreFixed = true;
                break;
            }
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
            if (fixed) {
                g_customKickIl2CppStr = fixed;
                return g_customKickIl2CppStr;
            }
        }
    }

    g_customKickIl2CppStr = rawObj;
    return g_customKickIl2CppStr;
}

// خطاف OnPhotonPlayerDisconnected لتحويل "خرج من الغرفة" إلى "تم طرده من الغرفة"
static void hook_OnPhotonPlayerDisconnected(void *self, void *player, void *method) {
    if (!self || !orig_OnDisconnect) {
        if (orig_OnDisconnect) orig_OnDisconnect(self, player, method);
        return;
    }

    uintptr_t locManager = 0;
    void *origLeaveStr = NULL;
    void **leaveStrSlot = NULL;

    if (g_kick_msg_armed > 0 && safeReadMem((uintptr_t)self + 0x2F8, &locManager, sizeof(uintptr_t)) && locManager > 0x100000000ULL) {
        if (safeReadMem(locManager + 0x238, &origLeaveStr, sizeof(void *)) && origLeaveStr != NULL) {
            void *kickStr = OGSBuildKickLeaveString(origLeaveStr);
            if (kickStr) {
                leaveStrSlot = (void **)(locManager + 0x238);
                *leaveStrSlot = kickStr;
            }
        }
    }

    orig_OnDisconnect(self, player, method);

    // استعادة النص الأصلي بعد طباعة رسالة الطرد
    if (leaveStrSlot && origLeaveStr) {
        *leaveStrSlot = origLeaveStr;
    }
}

static void installRoomHooks() {
    uintptr_t base = 0x100000000ULL + getSlide();
    if (TBL_ON_DISCONNECT) {
        void **slot = (void **)(base + TBL_ON_DISCONNECT);
        orig_OnDisconnect = (OnDisconnectFn)*slot;
        *slot = (void *)&hook_OnPhotonPlayerDisconnected;
    }
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
        OGSGetPlayerNameAndID(cand, &candID, NULL);

        bool isOther = false;
        for (uint32_t j = 0; j < otherCount; j++) {
            if (otherItems[j] == cand) { isOther = true; break; }
            int32_t otherID = 0;
            OGSGetPlayerNameAndID(otherItems[j], &otherID, NULL);
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
    g_kick_msg_armed = 1; // تفعيل رسالة "تم طرده من الغرفة"
    uintptr_t base = 0x100000000ULL + getSlide();
    void *fnPtr = *(void **)(base + TBL_PEER_SYNC);
    if (!fnPtr) return false;
    return ((DiagPeerSync1Fn)fnPtr)(peerObj, NULL);
}

// طرد مضمون: إذا لم تكن الهوست، يسحب الهوست لنفسك تلقائياً ثم يطرد اللاعب
static void OGSKickPeerGuaranteed(void *peerObj) {
    if (!peerObj) return;
    g_kick_msg_armed = 1;

    uintptr_t base = 0x100000000ULL + getSlide();
    DiagBool0Fn isMaster = (DiagBool0Fn)(base + RVA_IS_MASTER);
    bool masterNow = isMaster ? isMaster(NULL) : false;

    if (masterNow) {
        OGSDisconnectPeerRaw(peerObj);
    } else {
        void *myPlayer = OGSFindLocalPlayerObject();
        if (myPlayer) {
            OGSSetRoomMasterObject(myPlayer);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            OGSDisconnectPeerRaw(peerObj);
        });
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
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
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

        // لوحة مدمجة وواضحة بالكامل في الوضع العرضي (الارتفاع 258 فقط)
        self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(85, 20, 305, 258)];
        self.menuPanel.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:0.96];
        self.menuPanel.layer.cornerRadius = 14.0;
        self.menuPanel.layer.borderWidth = 2.0f;
        self.menuPanel.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.menuPanel.hidden = YES;

        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(12, 6, 281, 20)];
        tl.text = @"إدارة الروم: الهوست والطرد والحظر";
        tl.textColor = [UIColor whiteColor];
        tl.textAlignment = NSTextAlignmentCenter;
        tl.font = [UIFont boldSystemFontOfSize:13.5];
        [self.menuPanel addSubview:tl];

        UIView *infoBox = [[UIView alloc] initWithFrame:CGRectMake(12, 30, 281, 46)];
        infoBox.backgroundColor = [UIColor colorWithRed:0.16 green:0.17 blue:0.20 alpha:1.0];
        infoBox.layer.cornerRadius = 8.0;

        self.playerLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, 265, 20)];
        self.playerLabel.text = @"المحدد: لا يوجد لاعبين";
        self.playerLabel.textColor = [UIColor systemYellowColor];
        self.playerLabel.textAlignment = NSTextAlignmentCenter;
        self.playerLabel.font = [UIFont boldSystemFontOfSize:13.0];
        [infoBox addSubview:self.playerLabel];

        self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 24, 265, 18)];
        self.statusLabel.text = @"الغرفة: غير متصل";
        self.statusLabel.textColor = [UIColor systemGreenColor];
        self.statusLabel.textAlignment = NSTextAlignmentCenter;
        self.statusLabel.font = [UIFont systemFontOfSize:11];
        [infoBox addSubview:self.statusLabel];
        [self.menuPanel addSubview:infoBox];

        UIColor *darkGray   = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
        UIColor *kickOrange = [UIColor colorWithRed:0.80 green:0.35 blue:0.10 alpha:1.0];
        UIColor *banRed     = [UIColor colorWithRed:0.70 green:0.12 blue:0.15 alpha:1.0];
        UIColor *hostBlue   = [UIColor colorWithRed:0.14 green:0.42 blue:0.72 alpha:1.0];
        UIColor *hostPurple = [UIColor colorWithRed:0.42 green:0.22 blue:0.65 alpha:1.0];

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(12, 82, 136, 34) title:@"▶ اللاعب السابق" bg:darkGray action:@selector(prevPlayer:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(157, 82, 136, 34) title:@"اللاعب التالي ◀" bg:darkGray action:@selector(nextPlayer:)]];

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(157, 122, 136, 36) title:@"طرد المحدد فقط" bg:kickOrange action:@selector(kickSelected:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(12, 122, 136, 36) title:@"طرد وحظر (Ban)" bg:banRed action:@selector(banSelected:)]];

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(157, 164, 136, 36) title:@"سحب الهوست لنفسي 👑" bg:hostBlue action:@selector(takeHostForMe:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(12, 164, 136, 36) title:@"منح الهوست للمحدد" bg:hostPurple action:@selector(giveHostToSelected:)]];

        self.lockButton = [self makeBtn:CGRectMake(157, 206, 136, 34) title:@"قفل الروم: مفتوح" bg:darkGray action:@selector(toggleRoomLock:)];
        [self.menuPanel addSubview:self.lockButton];

        self.unbanButton = [self makeBtn:CGRectMake(12, 206, 136, 34) title:@"فك حظر الكل (0)" bg:darkGray action:@selector(clearBanList:)];
        [self.menuPanel addSubview:self.unbanButton];

        [self.containerView addSubview:self.menuPanel];
        self.containerView.floatingButton = self.floatingButton;
        self.containerView.menuPanel = self.menuPanel;
        [gw addSubview:self.containerView];
        [gw bringSubviewToFront:self.containerView];

        self.guardTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(onGuardTick) userInfo:nil repeats:YES];
    });
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
        NSString *pName = OGSGetPlayerNameAndID(items[g_selected_peer], &actorID, &isPeerHost);
        self.playerLabel.text = [NSString stringWithFormat:@"(%u/%u) %@%@",
                                 g_selected_peer + 1, count, pName, isPeerHost ? @" 👑" : @""];
    }

    self.statusLabel.text = [NSString stringWithFormat:@"الهوست: %@ | بالروم: %u | المحظورين: %lu",
                             master ? @"أنت 👑" : @"غيرك",
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
            NSString *pName = OGSGetPlayerNameAndID(peer, NULL, NULL);

            if ([self.bannedKeys containsObject:pName]) {
                OGSKickPeerGuaranteed(peer);
                continue;
            }
            if (self.roomLockActive && ![self.allowedKeysWhenLocked containsObject:pName]) {
                OGSKickPeerGuaranteed(peer);
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
    if (count == 0 || !items) {
        self.statusLabel.text = @"لا يوجد لاعب لمنحه الهوست";
        return;
    }
    if (g_selected_peer >= count) g_selected_peer = 0;
    NSString *pName = OGSGetPlayerNameAndID(items[g_selected_peer], NULL, NULL);
    OGSSetRoomMasterObject(items[g_selected_peer]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshUI];
        self.statusLabel.text = [NSString stringWithFormat:@"تم نقل الهوست إلى: %@", pName];
    });
}

- (void)kickSelected:(UIButton *)s {
    void **items = NULL;
    uint32_t count = OGSGetPeerCount(&items);
    if (count == 0 || !items) {
        self.statusLabel.text = @"لا يوجد لاعب لطرده حالياً";
        return;
    }
    if (g_selected_peer >= count) g_selected_peer = 0;
    NSString *pName = OGSGetPlayerNameAndID(items[g_selected_peer], NULL, NULL);
    OGSKickPeerGuaranteed(items[g_selected_peer]);
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
    NSString *pName = OGSGetPlayerNameAndID(items[g_selected_peer], NULL, NULL);
    [self.bannedKeys addObject:pName];
    OGSKickPeerGuaranteed(items[g_selected_peer]);
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
                NSString *pName = OGSGetPlayerNameAndID(items[i], NULL, NULL);
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
    installRoomHooks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[OGSModMenu sharedInstance] setupMenu];
    });
}
