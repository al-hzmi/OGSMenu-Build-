#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

// جداول وعناوين اللعب الأساسية
static const uintptr_t TBL_CASH_UPDATE       = 0x23918b8; // Type4640::Update
static const uintptr_t TBL_GET_DMG           = 0x2391388; // الدمج 999
static const uintptr_t TBL_WPN_HOOK          = 0x238ea10; // السلاح
static const uintptr_t RVA_REFILL_AMMO       = 0x1382c10; // الذخيرة
static const uintptr_t RVA_SET_TIMESCALE     = 0x198ac4c; // السرعة

// جداول الشات (Type 4635) - تعمل باستمرار داخل الروم على خيط UnityMain
static const uintptr_t TBL_CHAT_UPDATE       = 0x238fd68; // Type4635::Update
static const uintptr_t TBL_SEND_CHAT_REMOTE  = 0x238fd80; // Type4635::SendChatRemote

// عناوين PhotonNetwork (تُستدعى حصرياً من خيط UnityMain لمنع الكراش)
static const uintptr_t RVA_IN_ROOM           = 0x013CC38C; // PhotonNetwork::get_inRoom()
static const uintptr_t RVA_IS_MASTER         = 0x013CC2BC; // PhotonNetwork::get_isMasterClient()
static const uintptr_t RVA_GET_MASTER_PEER   = 0x013CACA4; // PhotonNetwork::get_masterClient()
static const uintptr_t RVA_ALL_PLAYERS       = 0x013CAEC4; // PhotonNetwork::get_playerList()
static const uintptr_t RVA_GET_PEERS         = 0x013CAF78; // PhotonNetwork::get_otherPlayers()
static const uintptr_t RVA_PLAYER_GET_NAME   = 0x013D7534; // PhotonPlayer::get_name()
static const uintptr_t RVA_ARABIC_FIX        = 0x0130F538; // Type4294::Fix

static const uintptr_t TBL_PEER_SYNC         = 0x2390a98;  // CloseConnection(PhotonPlayer)
static const uintptr_t TBL_SET_MASTER        = 0x2390aa0;  // SetMasterClient(PhotonPlayer)
static const uintptr_t TBL_ON_DISCONNECT     = 0x2391930;  // OnPhotonPlayerDisconnected(PhotonPlayer)

typedef void    (*Update0Fn)(void *, void *);
typedef void    (*Refill0Fn)(void *, void *);
typedef int32_t (*GetDMG2Fn)(void *, uintptr_t, uintptr_t, void *, double, double, double);
typedef void    (*WpnHookFn)(void *, uintptr_t, uintptr_t, uintptr_t, void *, double, double, double, double);
typedef void    (*SetTime1Fn)(float, void *);
typedef void    (*SendChatRemoteFn)(void *, void *, void *, int32_t, int32_t, void *);

typedef bool    (*DiagBool0Fn)(void *);
typedef void*   (*DiagGetPeers0Fn)(void *);
typedef bool    (*DiagPeerSync1Fn)(void *, void *);
typedef void*   (*ArabicFixFn)(void *, void *);
typedef void    (*OnDisconnectFn)(void *, void *, void *);

static Update0Fn        orig_CashUpdate     = NULL;
static Update0Fn        orig_ChatUpdate     = NULL;
static SendChatRemoteFn orig_SendChatRemote = NULL;
static GetDMG2Fn        orig_GetDMG         = NULL;
static WpnHookFn        orig_WpnHook        = NULL;
static OnDisconnectFn   orig_OnDisconnect   = NULL;

// ذاكرة وسيطة آمنة (Thread-Safe Cache) تفصل واجهة الأزرار عن خيط اللعبة تماماً
typedef struct {
    void *peerPtr;
    int32_t actorID;
    bool isHost;
    char nameUTF8[128];
} OGSPeerEntry;

static OGSPeerEntry      g_peerCache[64];
static volatile uint32_t g_cached_count    = 0;
static volatile int32_t  g_cached_in_room  = 0;
static volatile int32_t  g_cached_is_host  = 0;
static volatile uint32_t g_selected_peer   = 0;

// أوامر تُرسل من الواجهة وتُنفذ بأمان داخل خيط UnityMain
// 1 = طرد المحدد | 2 = سحب الهوست لنفسي
static volatile int32_t  g_pending_cmd     = 0;
static void * volatile   g_pending_target  = NULL;

static volatile int32_t  g_auto_host_on    = 1; // حماية الهوست وطرد السارق
static volatile int32_t  g_chat_mode       = 0; // 0 = مفتوح | 1 = كتم الشات | 2 = طرد من يكتب
static volatile int32_t  g_super_weapon_on = 1; // دمج 999 + ذخيرة لا نهائية
static volatile float    g_custom_speed    = 1.0f;
static volatile int32_t  g_speed_dirty     = 0;
static volatile int32_t  g_kick_msg_armed  = 0;
static volatile int32_t  g_unity_tick      = 0;
static void *g_customKickIl2CppStr         = NULL;

static uintptr_t getSlide() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "/fps.app/fps")) return _dyld_get_image_vmaddr_slide(i);
    }
    return _dyld_get_image_vmaddr_slide(0);
}

// قراءة محمية عبر النواة: مستحيل أن تسبب كراش حتى لو كان المؤشر تالفاً
static bool safeReadMem(uintptr_t addr, void *buf, size_t len) {
    if (addr < 0x100000000ULL) return false;
    vm_size_t outSize = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr, (vm_size_t)len, (vm_address_t)buf, &outSize);
    return (kr == KERN_SUCCESS && outSize == len);
}

static NSString *OGSReadIl2CppStringSafe(void *strPtr) {
    if (!strPtr || (uintptr_t)strPtr < 0x100000000ULL) return nil;
    uintptr_t klassPtr = 0;
    if (!safeReadMem((uintptr_t)strPtr, &klassPtr, sizeof(uintptr_t)) || klassPtr < 0x100000000ULL) return nil;

    int32_t strLen = 0;
    if (!safeReadMem((uintptr_t)strPtr + 0x10, &strLen, sizeof(int32_t))) return nil;
    if (strLen <= 0 || strLen > 48) return nil;

    uint16_t chars[52] = {0};
    if (!safeReadMem((uintptr_t)strPtr + 0x14, chars, (size_t)(strLen + 1) * sizeof(uint16_t))) return nil;
    if (chars[strLen] != 0) return nil;

    for (int32_t i = 0; i < strLen; i++) {
        if (chars[i] < 0x20 || chars[i] == 0xFFFE || chars[i] == 0xFFFF) return nil;
    }
    return [NSString stringWithCharacters:chars length:(NSUInteger)strLen];
}

// استخراج اسم اللاعب ورقمه من الذاكرة مباشرة بدون استدعاء أي دالة قد تسبب كراش
static void OGSExtractPeerInfoSafe(void *peerObj, void *masterPeerObj, char *outNameUTF8, size_t maxLen, int32_t *outActorID, bool *outIsHost) {
    if (outActorID) *outActorID = 0;
    if (outIsHost)  *outIsHost = (peerObj && peerObj == masterPeerObj);
    if (outNameUTF8 && maxLen > 0) strncpy(outNameUTF8, "لاعب", maxLen - 1);
    if (!peerObj || (uintptr_t)peerObj < 0x100000000ULL) return;

    uintptr_t baseObj = (uintptr_t)peerObj;
    int32_t actorID = 0;
    if (safeReadMem(baseObj + 0x10, &actorID, sizeof(int32_t))) {
        if (actorID > 0 && actorID < 10000 && outActorID) {
            *outActorID = actorID;
        }
    }

    // معرفة إزاحة الاسم من تعليمة LDR داخل PhotonPlayer::get_name إن وجدت
    uintptr_t base = 0x100000000ULL + getSlide();
    uint32_t insn = 0;
    uintptr_t dynamicOff = 0x18;
    if (safeReadMem(base + RVA_PLAYER_GET_NAME, &insn, sizeof(uint32_t))) {
        if ((insn & 0xFFC003FF) == 0xF9400000) {
            uint32_t off = ((insn >> 10) & 0xFFF) * 8;
            if (off >= 0x10 && off <= 0x50) dynamicOff = off;
        }
    }

    const uintptr_t offsets[] = {dynamicOff, 0x18, 0x20, 0x28, 0x30, 0x38, 0x10};
    for (size_t i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++) {
        uintptr_t strPtr = 0;
        if (!safeReadMem(baseObj + offsets[i], &strPtr, sizeof(uintptr_t))) continue;
        NSString *s = OGSReadIl2CppStringSafe((void *)strPtr);
        if (s && s.length > 0) {
            const char *utf8 = [s UTF8String];
            if (utf8 && outNameUTF8) {
                strncpy(outNameUTF8, utf8, maxLen - 1);
                outNameUTF8[maxLen - 1] = '\0';
                return;
            }
        }
    }

    if (actorID > 0 && actorID < 10000 && outNameUTF8) {
        snprintf(outNameUTF8, maxLen, "ID:%d", actorID);
    }
}

static NSString *OGSNormalizeKey(NSString *raw) {
    if (!raw) return @"";
    return [[raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

// دوال Photon تُستدعى حصرياً من داخل خيط UnityMain
static uint32_t OGSUnityGetPeers(uintptr_t rvaListFn, void *outPeers[64]) {
    uintptr_t base = 0x100000000ULL + getSlide();
    DiagBool0Fn inRoom = (DiagBool0Fn)(base + RVA_IN_ROOM);
    DiagGetPeers0Fn getList = (DiagGetPeers0Fn)(base + rvaListFn);
    if (!inRoom || !inRoom(NULL) || !getList) return 0;

    void *arr = getList(NULL);
    if (!arr || (uintptr_t)arr < 0x100000000ULL) return 0;

    uintptr_t n = 0;
    if (!safeReadMem((uintptr_t)arr + 0x18, &n, sizeof(uintptr_t))) return 0;
    if (n == 0 || n > 64) return 0;

    uint32_t validCount = 0;
    for (uint32_t i = 0; i < (uint32_t)n; i++) {
        void *p = NULL;
        if (safeReadMem((uintptr_t)arr + 0x20 + i * sizeof(void *), &p, sizeof(void *)) && p && (uintptr_t)p > 0x100000000ULL) {
            if (outPeers) outPeers[validCount] = p;
            validCount++;
        }
    }
    return validCount;
}

static void *OGSUnityFindLocalPlayer(void) {
    void *allPeers[64] = {0};
    uint32_t allCount = OGSUnityGetPeers(RVA_ALL_PLAYERS, allPeers);
    if (allCount == 0) return NULL;

    void *otherPeers[64] = {0};
    uint32_t otherCount = OGSUnityGetPeers(RVA_GET_PEERS, otherPeers);
    if (otherCount == 0) return allPeers[0];

    for (uint32_t i = 0; i < allCount; i++) {
        void *cand = allPeers[i];
        bool isOther = false;
        for (uint32_t j = 0; j < otherCount; j++) {
            if (otherPeers[j] == cand) { isOther = true; break; }
        }
        if (!isOther) return cand;
    }
    return NULL;
}

static void OGSUnitySetMaster(void *playerObj) {
    if (!playerObj || (uintptr_t)playerObj < 0x100000000ULL) return;
    uintptr_t base = 0x100000000ULL + getSlide();
    void *fnPtr = NULL;
    if (safeReadMem(base + TBL_SET_MASTER, &fnPtr, sizeof(void *)) && fnPtr) {
        ((DiagPeerSync1Fn)fnPtr)(playerObj, NULL);
    }
}

static void OGSUnityKickPeer(void *peerObj) {
    if (!peerObj || (uintptr_t)peerObj < 0x100000000ULL) return;
    g_kick_msg_armed = 1;

    uintptr_t base = 0x100000000ULL + getSlide();
    DiagBool0Fn isMaster = (DiagBool0Fn)(base + RVA_IS_MASTER);
    if (!isMaster || !isMaster(NULL)) {
        void *myPlayer = OGSUnityFindLocalPlayer();
        if (myPlayer) OGSUnitySetMaster(myPlayer);
    }

    void *fnPtr = NULL;
    if (safeReadMem(base + TBL_PEER_SYNC, &fnPtr, sizeof(void *)) && fnPtr) {
        ((DiagPeerSync1Fn)fnPtr)(peerObj, NULL);
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
@property (strong, nonatomic) UIButton *hostLockButton;
@property (strong, nonatomic) UIButton *muteChatButton;
@property (strong, nonatomic) UIButton *weaponButton;
@property (strong, nonatomic) UIButton *speedSetButton;
@property (strong, nonatomic) NSMutableSet<NSString *> *bannedNames;
@property (strong, nonatomic) NSMutableSet<NSString *> *allowedNamesWhenLocked;
@property (assign, nonatomic) BOOL roomLockActive;
@property (strong, nonatomic) NSTimer *uiTimer;
+ (instancetype)sharedInstance;
- (void)setupMenu;
- (BOOL)isNameBannedOrLockedOut:(NSString *)normName;
@end

// الدالة المركزية التي تعمل داخل خيط UnityMain فقط (آمنة 100% ولا تسبب كراش)
static void OGSRunUnityMainThreadLogic(void) {
    uintptr_t base = 0x100000000ULL + getSlide();

    if (g_speed_dirty && RVA_SET_TIMESCALE > 0) {
        g_speed_dirty = 0;
        ((SetTime1Fn)(base + RVA_SET_TIMESCALE))(g_custom_speed, NULL);
    }

    // تنفيذ أي أمر ضغطت عليه في الواجهة فوراً داخل خيط Unity
    int32_t cmd = g_pending_cmd;
    if (cmd != 0) {
        void *target = g_pending_target;
        g_pending_cmd = 0;
        g_pending_target = NULL;
        if (cmd == 1 && target) {
            OGSUnityKickPeer(target);
        } else if (cmd == 2) {
            void *me = OGSUnityFindLocalPlayer();
            if (me) OGSUnitySetMaster(me);
        }
    }

    if (++g_unity_tick < 10) return;
    g_unity_tick = 0;

    DiagBool0Fn inRoomFn = (DiagBool0Fn)(base + RVA_IN_ROOM);
    bool inRoom = inRoomFn ? inRoomFn(NULL) : false;
    g_cached_in_room = inRoom ? 1 : 0;

    if (!inRoom) {
        g_cached_count = 0;
        g_cached_is_host = 0;
        return;
    }

    DiagBool0Fn isMasterFn = (DiagBool0Fn)(base + RVA_IS_MASTER);
    DiagGetPeers0Fn getMasterPeerFn = (DiagGetPeers0Fn)(base + RVA_GET_MASTER_PEER);
    bool isMaster = isMasterFn ? isMasterFn(NULL) : false;
    void *masterPeer = getMasterPeerFn ? getMasterPeerFn(NULL) : NULL;

    // 1. حماية الهوست المضادة للهكر: استعادة الهوست فوراً + طرد الهكر السارق
    if (g_auto_host_on && !isMaster) {
        void *myPlayer = OGSUnityFindLocalPlayer();
        if (myPlayer) {
            OGSUnitySetMaster(myPlayer);
            isMaster = true;
        }
        if (masterPeer && masterPeer != myPlayer) {
            OGSUnityKickPeer(masterPeer);
        }
    }
    g_cached_is_host = isMaster ? 1 : 0;

    // 2. تحديث قائمة اللاعبين في الذاكرة الوسيطة وتطبيق الحظر التلقائي
    void *peers[64] = {0};
    uint32_t count = OGSUnityGetPeers(RVA_GET_PEERS, peers);
    OGSModMenu *menu = [OGSModMenu sharedInstance];

    for (uint32_t i = 0; i < count && i < 64; i++) {
        g_peerCache[i].peerPtr = peers[i];
        OGSExtractPeerInfoSafe(peers[i], masterPeer, g_peerCache[i].nameUTF8, sizeof(g_peerCache[i].nameUTF8), &g_peerCache[i].actorID, &g_peerCache[i].isHost);

        NSString *pName = [NSString stringWithUTF8String:g_peerCache[i].nameUTF8];
        NSString *normName = OGSNormalizeKey(pName);
        if ([menu isNameBannedOrLockedOut:normName]) {
            OGSUnityKickPeer(peers[i]);
        }
    }
    g_cached_count = count;
}

static void *OGSBuildKickLeaveString(void *templateIl2CppStr) {
    if (g_customKickIl2CppStr) return g_customKickIl2CppStr;
    if (!templateIl2CppStr || (uintptr_t)templateIl2CppStr < 0x100000000ULL) return NULL;

    uint8_t header[16] = {0};
    if (!safeReadMem((uintptr_t)templateIl2CppStr, header, 16)) return NULL;

    bool origIsPreFixed = false;
    NSString *origText = OGSReadIl2CppStringSafe(templateIl2CppStr);
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

static void hook_SendChatRemote(void *self, void *senderStr, void *msgStr, int32_t p3, int32_t p4, void *method) {
    if (g_chat_mode == 1) {
        return; // كتم رسائل اللاعبين
    } else if (g_chat_mode == 2) {
        // طرد تلقائي لأي لاعب يرسل رسالة في الشات
        NSString *senderName = OGSReadIl2CppStringSafe(senderStr);
        if (senderName && senderName.length > 0) {
            NSString *normSender = OGSNormalizeKey(senderName);
            uint32_t count = g_cached_count;
            for (uint32_t i = 0; i < count && i < 64; i++) {
                NSString *peerName = [NSString stringWithUTF8String:g_peerCache[i].nameUTF8];
                if ([OGSNormalizeKey(peerName) isEqualToString:normSender]) {
                    OGSUnityKickPeer(g_peerCache[i].peerPtr);
                    return;
                }
            }
        }
        return;
    }
    if (orig_SendChatRemote) orig_SendChatRemote(self, senderStr, msgStr, p3, p4, method);
}

static void hook_ChatUpdate(void *self, void *method) {
    if (orig_ChatUpdate) orig_ChatUpdate(self, method);
    OGSRunUnityMainThreadLogic();
}

static void hook_CashUpdate(void *s, void *m) {
    if (orig_CashUpdate) orig_CashUpdate(s, m);
    OGSRunUnityMainThreadLogic();
}

static int32_t hook_GetDMG(void *s, uintptr_t p1, uintptr_t p2, void *m, double d0, double d1, double d2) {
    if (g_super_weapon_on) return 999;
    return orig_GetDMG ? orig_GetDMG(s, p1, p2, m, d0, d1, d2) : 0;
}

static void hook_Wpn(void *s, uintptr_t p1, uintptr_t p2, uintptr_t p3, void *m, double d0, double d1, double d2, double d3) {
    if (orig_WpnHook) orig_WpnHook(s, p1, p2, p3, m, d0, d1, d2, d3);
    if (s && g_super_weapon_on && RVA_REFILL_AMMO > 0) {
        ((Refill0Fn)(0x100000000ULL + getSlide() + RVA_REFILL_AMMO))(s, NULL);
    }
}

static void installAllHooks() {
    uintptr_t base = 0x100000000ULL + getSlide();
    if (TBL_CASH_UPDATE)      { void **sl = (void **)(base + TBL_CASH_UPDATE);      orig_CashUpdate     = (Update0Fn)*sl;        *sl = (void *)&hook_CashUpdate; }
    if (TBL_CHAT_UPDATE)      { void **sl = (void **)(base + TBL_CHAT_UPDATE);      orig_ChatUpdate     = (Update0Fn)*sl;        *sl = (void *)&hook_ChatUpdate; }
    if (TBL_SEND_CHAT_REMOTE) { void **sl = (void **)(base + TBL_SEND_CHAT_REMOTE); orig_SendChatRemote = (SendChatRemoteFn)*sl; *sl = (void *)&hook_SendChatRemote; }
    if (TBL_GET_DMG)          { void **sl = (void **)(base + TBL_GET_DMG);          orig_GetDMG         = (GetDMG2Fn)*sl;        *sl = (void *)&hook_GetDMG; }
    if (TBL_WPN_HOOK)         { void **sl = (void **)(base + TBL_WPN_HOOK);         orig_WpnHook        = (WpnHookFn)*sl;        *sl = (void *)&hook_Wpn; }
    if (TBL_ON_DISCONNECT)    { void **sl = (void **)(base + TBL_ON_DISCONNECT);    orig_OnDisconnect   = (OnDisconnectFn)*sl;   *sl = (void *)&hook_OnPhotonPlayerDisconnected; }
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

- (BOOL)isNameBannedOrLockedOut:(NSString *)normName {
    if (!normName || normName.length == 0) return NO;
    if ([self.bannedNames containsObject:normName]) return YES;
    if (self.roomLockActive && ![self.allowedNamesWhenLocked containsObject:normName]) return YES;
    return NO;
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
    b.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
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
        self.floatingButton.frame = CGRectMake(18, 95, 48, 48);
        self.floatingButton.backgroundColor = [UIColor blackColor];
        self.floatingButton.opaque = YES;
        [self.floatingButton setTitle:@"OGS" forState:UIControlStateNormal];
        self.floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        self.floatingButton.layer.cornerRadius = 24.0;
        self.floatingButton.layer.borderWidth = 2.0f;
        self.floatingButton.layer.borderColor = [UIColor systemRedColor].CGColor;
        [self.floatingButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [self.floatingButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)]];
        [self.containerView addSubview:self.floatingButton];

        self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(75, 12, 315, 292)];
        self.menuPanel.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:0.96];
        self.menuPanel.layer.cornerRadius = 14.0;
        self.menuPanel.layer.borderWidth = 2.0f;
        self.menuPanel.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.menuPanel.hidden = YES;

        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, 295, 18)];
        tl.text = @"OGS v6: الهوست + الطرد + الشات + السرعة + 999";
        tl.textColor = [UIColor whiteColor];
        tl.textAlignment = NSTextAlignmentCenter;
        tl.font = [UIFont boldSystemFontOfSize:11.5];
        [self.menuPanel addSubview:tl];

        UIView *infoBox = [[UIView alloc] initWithFrame:CGRectMake(10, 24, 295, 40)];
        infoBox.backgroundColor = [UIColor colorWithRed:0.16 green:0.17 blue:0.20 alpha:1.0];
        infoBox.layer.cornerRadius = 8.0;

        self.playerLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 2, 283, 18)];
        self.playerLabel.text = @"المحدد: لا يوجد لاعبين";
        self.playerLabel.textColor = [UIColor systemYellowColor];
        self.playerLabel.textAlignment = NSTextAlignmentCenter;
        self.playerLabel.font = [UIFont boldSystemFontOfSize:12.0];
        [infoBox addSubview:self.playerLabel];

        self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 20, 283, 17)];
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
        UIColor *wpnGreen   = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];

        // صف 1: التنقل بين اللاعبين
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 68, 144, 30) title:@"▶ اللاعب السابق" bg:darkGray action:@selector(prevPlayer:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(161, 68, 144, 30) title:@"اللاعب التالي ◀" bg:darkGray action:@selector(nextPlayer:)]];

        // صف 2: طرد أو حظر
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(161, 103, 144, 32) title:@"طرد المحدد فقط" bg:kickOrange action:@selector(kickSelected:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 103, 144, 32) title:@"طرد وحظر (Ban)" bg:banRed action:@selector(banSelected:)]];

        // صف 3: حماية الهوست المضادة للهكر + كتم الشات
        self.hostLockButton = [self makeBtn:CGRectMake(155, 140, 150, 32) title:@"حماية الهوست: مفعّل 👑" bg:wpnGreen action:@selector(toggleAutoHost:)];
        [self.menuPanel addSubview:self.hostLockButton];

        self.muteChatButton = [self makeBtn:CGRectMake(10, 140, 140, 32) title:@"الشات: مفتوح" bg:darkGray action:@selector(cycleChatMode:)];
        [self.menuPanel addSubview:self.muteChatButton];

        // صف 4: قفل الروم + فك الحظر
        self.lockButton = [self makeBtn:CGRectMake(161, 177, 144, 30) title:@"قفل الروم: مفتوح" bg:darkGray action:@selector(toggleRoomLock:)];
        [self.menuPanel addSubview:self.lockButton];

        self.unbanButton = [self makeBtn:CGRectMake(10, 177, 144, 30) title:@"فك حظر الكل (0)" bg:darkGray action:@selector(clearBanList:)];
        [self.menuPanel addSubview:self.unbanButton];

        // صف 5: التحكم بالسرعة (- / كتابة رقم / +)
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 212, 55, 30) title:@"سرعة -" bg:darkGray action:@selector(speedDown:)]];
        self.speedSetButton = [self makeBtn:CGRectMake(70, 212, 175, 30) title:@"السرعة: 1.0x (اضغط للكتابة)" bg:hostBlue action:@selector(promptCustomSpeed:)];
        [self.menuPanel addSubview:self.speedSetButton];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(250, 212, 55, 30) title:@"سرعة +" bg:darkGray action:@selector(speedUp:)]];

        // صف 6: السلاح الخارق (دمج 999 + ذخيرة بدون تعشيق)
        self.weaponButton = [self makeBtn:CGRectMake(10, 247, 295, 34) title:@"سلاح خارق (دمج 999 + ذخيرة): مفعّل ⚡" bg:wpnGreen action:@selector(toggleSuperWeapon:)];
        [self.menuPanel addSubview:self.weaponButton];

        [self.containerView addSubview:self.menuPanel];
        self.containerView.floatingButton = self.floatingButton;
        self.containerView.menuPanel = self.menuPanel;
        [gw addSubview:self.containerView];
        [gw bringSubviewToFront:self.containerView];

        self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(onUITick) userInfo:nil repeats:YES];
    });
}

// تحديث الواجهة يقرأ فقط من الذاكرة الوسيطة (لا يستدعي أي دالة في اللعبة، فلا يمكن أن يسبب كراش)
- (void)refreshUI {
    uint32_t count = g_cached_count;
    bool master = (g_cached_is_host != 0);

    if (count == 0) {
        g_selected_peer = 0;
        self.playerLabel.text = @"المحدد: لا يوجد لاعبين معك حالياً";
    } else {
        if (g_selected_peer >= count) g_selected_peer = 0;
        NSString *pName = [NSString stringWithUTF8String:g_peerCache[g_selected_peer].nameUTF8];
        bool isPeerHost = g_peerCache[g_selected_peer].isHost;
        self.playerLabel.text = [NSString stringWithFormat:@"(%u/%u) %@%@",
                                 g_selected_peer + 1, count, pName, isPeerHost ? @" 👑" : @""];
    }

    self.statusLabel.text = [NSString stringWithFormat:@"الهوست: %@ | بالروم: %u | المحظورين: %lu",
                             master ? @"أنت 👑" : (g_auto_host_on ? @"حماية نشطة" : @"غيرك"),
                             count,
                             (unsigned long)self.bannedNames.count];
    [self.unbanButton setTitle:[NSString stringWithFormat:@"فك حظر الكل (%lu)", (unsigned long)self.bannedNames.count] forState:UIControlStateNormal];
}

- (void)onUITick {
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
    uint32_t n = g_cached_count;
    if (n > 0) g_selected_peer = (g_selected_peer + 1) % n;
    else g_selected_peer = 0;
    [self refreshUI];
}

- (void)prevPlayer:(UIButton *)s {
    uint32_t n = g_cached_count;
    if (n > 0) g_selected_peer = (g_selected_peer + n - 1) % n;
    else g_selected_peer = 0;
    [self refreshUI];
}

- (void)toggleAutoHost:(UIButton *)s {
    g_auto_host_on = !g_auto_host_on;
    if (g_auto_host_on) {
        g_pending_cmd = 2; // يطلب من خيط Unity سحب الهوست فوراً
        [s setTitle:@"حماية الهوست: مفعّل 👑" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    } else {
        [s setTitle:@"حماية الهوست: متوقف" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
    [self refreshUI];
}

- (void)cycleChatMode:(UIButton *)s {
    g_chat_mode = (g_chat_mode + 1) % 3;
    if (g_chat_mode == 1) {
        [s setTitle:@"الشات: كتم عندي 🔇" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.80 green:0.35 blue:0.10 alpha:1.0];
    } else if (g_chat_mode == 2) {
        [s setTitle:@"الشات: طرد من يكتب 🚫" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.70 green:0.12 blue:0.15 alpha:1.0];
    } else {
        [s setTitle:@"الشات: مفتوح" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
}

- (void)kickSelected:(UIButton *)s {
    uint32_t count = g_cached_count;
    if (count == 0) return;
    if (g_selected_peer >= count) g_selected_peer = 0;

    NSString *pName = [NSString stringWithUTF8String:g_peerCache[g_selected_peer].nameUTF8];
    g_pending_target = g_peerCache[g_selected_peer].peerPtr;
    g_pending_cmd = 1; // ينفذ الطرد في خيط UnityMain
    self.statusLabel.text = [NSString stringWithFormat:@"تم طرد: %@", pName];
}

- (void)banSelected:(UIButton *)s {
    uint32_t count = g_cached_count;
    if (count == 0) return;
    if (g_selected_peer >= count) g_selected_peer = 0;

    NSString *pName = [NSString stringWithUTF8String:g_peerCache[g_selected_peer].nameUTF8];
    NSString *normName = OGSNormalizeKey(pName);
    if (normName.length > 0) [self.bannedNames addObject:normName];

    g_pending_target = g_peerCache[g_selected_peer].peerPtr;
    g_pending_cmd = 1; // ينفذ الطرد والحظر في خيط UnityMain
    [self refreshUI];
    self.statusLabel.text = [NSString stringWithFormat:@"تم طرد وحظر: %@", pName];
}

- (void)toggleRoomLock:(UIButton *)s {
    self.roomLockActive = !self.roomLockActive;
    [self.allowedNamesWhenLocked removeAllObjects];

    if (self.roomLockActive) {
        uint32_t count = g_cached_count;
        for (uint32_t i = 0; i < count && i < 64; i++) {
            NSString *pName = [NSString stringWithUTF8String:g_peerCache[i].nameUTF8];
            [self.allowedNamesWhenLocked addObject:OGSNormalizeKey(pName)];
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
    g_speed_dirty = 1; // يُطبق بأمان داخل خيط UnityMain
    [self.speedSetButton setTitle:[NSString stringWithFormat:@"السرعة: %.1fx (اضغط للكتابة)", g_custom_speed] forState:UIControlStateNormal];
}

- (void)speedDown:(UIButton *)s { [self applySpeed:g_custom_speed - 0.5f]; }
- (void)speedUp:(UIButton *)s   { [self applySpeed:g_custom_speed + 0.5f]; }

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
        float val = [alert.textFields.firstObject.text floatValue];
        if (val >= 0.0f && val <= 20.0f) [self applySpeed:val];
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
