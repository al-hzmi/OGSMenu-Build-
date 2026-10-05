#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#define OGS_MAX_PEERS       64
#define OGS_MAX_NAME_BYTES  128
#define OGS_MAX_STRING_LEN  256

// ============================================================
// MARK: - Engine Addresses
// ============================================================
static const uintptr_t TBL_CASH_UPDATE      = 0x23918b8; // Type4640::Update
static const uintptr_t TBL_CHAT_UPDATE      = 0x238fd68; // Type4635::Update
static const uintptr_t TBL_SEND_CHAT_REMOTE = 0x238fd80; // Type4635::SendChatRemote
static const uintptr_t RVA_SET_TIMESCALE    = 0x198ac4c; // Time::set_timeScale

static const uintptr_t RVA_IN_ROOM          = 0x013CC38C; // PhotonNetwork::get_inRoom()
static const uintptr_t RVA_IS_MASTER        = 0x013CC2BC; // PhotonNetwork::get_isMasterClient()
static const uintptr_t RVA_GET_MASTER_PEER  = 0x013CACA4; // PhotonNetwork::get_masterClient()
static const uintptr_t RVA_ALL_PLAYERS      = 0x013CAEC4; // PhotonNetwork::get_playerList()
static const uintptr_t RVA_GET_PEERS        = 0x013CAF78; // PhotonNetwork::get_otherPlayers()

static const uintptr_t RVA_PLAYER_GET_NAME  = 0x013D7534; // PhotonPlayer::get_name()
static const uintptr_t RVA_PLAYER_GET_ID    = 0x013CC384; // PhotonPlayer::get_ID()
static const uintptr_t RVA_ARABIC_FIX       = 0x0130F538; // Type4294::Fix

static const uintptr_t TBL_PEER_SYNC        = 0x2390a98;  // CloseConnection(PhotonPlayer)
static const uintptr_t TBL_SET_MASTER       = 0x2390aa0;  // SetMasterClient(PhotonPlayer)
static const uintptr_t TBL_ON_DISCONNECT    = 0x2391930;  // OnPhotonPlayerDisconnected(PhotonPlayer)

// ============================================================
// MARK: - Function Signatures
// ============================================================
typedef void    (*Update0Fn)(void *, void *);
typedef void    (*SetTime1Fn)(float, void *);
typedef void    (*SendChatRemoteFn)(void *, void *, void *, int32_t, int32_t, void *);
typedef bool    (*Bool0Fn)(void *);
typedef void*   (*Object0Fn)(void *);
typedef bool    (*PeerAction1Fn)(void *, void *);
typedef void*   (*PlayerGetNameFn)(void *, void *);
typedef int32_t (*PlayerGetIDFn)(void *, void *);
typedef void*   (*ArabicFixFn)(void *, void *);
typedef void    (*OnDisconnectFn)(void *, void *, void *);

static Update0Fn        orig_CashUpdate     = NULL;
static Update0Fn        orig_ChatUpdate     = NULL;
static SendChatRemoteFn orig_SendChatRemote = NULL;
static OnDisconnectFn   orig_OnDisconnect   = NULL;

// ============================================================
// MARK: - Atomic Runtime State (C++ Safe)
// ============================================================
typedef NS_ENUM(uint8_t, OGSRuntimePhase) {
    OGSRuntimePhaseBoot = 0,
    OGSRuntimePhaseWaitingImage,
    OGSRuntimePhaseResolving,
    OGSRuntimePhaseReady,
    OGSRuntimePhaseDegraded
};

typedef struct {
    volatile uint8_t  phase;
    volatile bool     inRoom;
    volatile bool     isMaster;
    volatile uint32_t selectedPeer;
    volatile float    gameSpeed;
    volatile bool     speedDirty;
    volatile uint64_t generation;
    volatile uint64_t readFailures;
    volatile int32_t  autoHostOn;
    volatile int32_t  chatMode;      // 0 = مفتوح | 1 = كتم | 2 = طرد من يكتب
    volatile int32_t  kickMsgArmed;
    volatile int32_t  forceHostReq;
    volatile int32_t  kickTargetID;
    volatile int32_t  kickRetries;
    char              kickTargetName[OGS_MAX_NAME_BYTES];
} OGSRuntimeState;

static OGSRuntimeState gOGS = {
    .phase          = OGSRuntimePhaseBoot,
    .inRoom         = false,
    .isMaster       = false,
    .selectedPeer   = 0,
    .gameSpeed      = 1.0f,
    .speedDirty     = false,
    .generation     = 0,
    .readFailures   = 0,
    .autoHostOn     = 1,
    .chatMode       = 0,
    .kickMsgArmed   = 0,
    .forceHostReq   = 0,
    .kickTargetID   = -1,
    .kickRetries    = 0,
    .kickTargetName = {0}
};

// ============================================================
// MARK: - Safe Memory Layer (iOS Mach VM)
// ============================================================
static bool OGSReadMemory(uintptr_t address, void *output, size_t size) {
    if (address < 0x100000000ULL || !output || size == 0) return false;
    vm_size_t copied = 0;
    kern_return_t kr = vm_read_overwrite(
        mach_task_self(),
        (vm_address_t)address,
        (vm_size_t)size,
        (vm_address_t)output,
        &copied
    );
    if (kr != KERN_SUCCESS || copied != (vm_size_t)size) {
        __atomic_fetch_add(&gOGS.readFailures, 1, __ATOMIC_RELAXED);
        return false;
    }
    return true;
}

static bool OGSReadPointer(uintptr_t address, void **output) {
    if (!output) return false;
    uintptr_t value = 0;
    if (!OGSReadMemory(address, &value, sizeof(value))) return false;
    if (value < 0x100000000ULL) return false;
    *output = (void *)value;
    return true;
}

// ============================================================
// MARK: - Mach-O Resolver
// ============================================================
static volatile uintptr_t gImageBase = 0;

static uintptr_t OGSFindGameImage(void) {
    uintptr_t cached = __atomic_load_n(&gImageBase, __ATOMIC_ACQUIRE);
    if (cached) return cached;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, "/fps.app/fps")) continue;
        const struct mach_header *header = _dyld_get_image_header(i);
        if (!header) continue;
        uintptr_t base = (uintptr_t)header;
        __atomic_store_n(&gImageBase, base, __ATOMIC_RELEASE);
        return base;
    }
    return 0;
}

static uintptr_t OGSResolveRVA(uintptr_t rva) {
    if (!rva) return 0;
    uintptr_t base = OGSFindGameImage();
    if (!base || (UINTPTR_MAX - base < rva)) return 0;
    return base + rva;
}

// ============================================================
// MARK: - Safe IL2CPP Strings
// ============================================================
static NSString *OGSReadIl2CppString(void *object) {
    if (!object || (uintptr_t)object < 0x100000000ULL) return nil;
    uintptr_t address = (uintptr_t)object;

    int32_t length = 0;
    if (!OGSReadMemory(address + 0x10, &length, sizeof(length))) return nil;
    if (length <= 0 || length > OGS_MAX_STRING_LEN) return nil;

    size_t bytes = (size_t)length * sizeof(unichar);
    unichar *buffer = (unichar *)calloc((size_t)length, sizeof(unichar));
    if (!buffer) return nil;

    if (!OGSReadMemory(address + 0x14, buffer, bytes)) {
        free(buffer);
        return nil;
    }

    NSString *result = [[NSString alloc] initWithCharacters:buffer length:(NSUInteger)length];
    free(buffer);
    return result;
}

static NSString *OGSNormalizeKey(NSString *value) {
    if (!value) return @"";
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.lowercaseString;
}

// ============================================================
// MARK: - Double-Buffered Snapshot Model
// ============================================================
typedef struct {
    int32_t actorID;
    bool    isHost;
    char    name[OGS_MAX_NAME_BYTES];
} OGSPeerSnapshot;

typedef struct {
    uint64_t        generation;
    bool            inRoom;
    bool            isMaster;
    uint32_t        count;
    OGSPeerSnapshot peers[OGS_MAX_PEERS];
} OGSRoomSnapshot;

static OGSRoomSnapshot   gSnapshots[2];
static volatile uint32_t gSnapshotIndex = 0;

static OGSRoomSnapshot *OGSBeginSnapshotWrite(void) {
    uint32_t current = __atomic_load_n(&gSnapshotIndex, __ATOMIC_ACQUIRE);
    uint32_t next = current ^ 1U;
    memset(&gSnapshots[next], 0, sizeof(OGSRoomSnapshot));
    return &gSnapshots[next];
}

static void OGSPublishSnapshot(OGSRoomSnapshot *snapshot) {
    if (!snapshot) return;
    snapshot->generation = __atomic_fetch_add(&gOGS.generation, 1, __ATOMIC_RELAXED) + 1;
    uint32_t index = (snapshot == &gSnapshots[0]) ? 0U : 1U;
    __atomic_store_n(&gSnapshotIndex, index, __ATOMIC_RELEASE);
}

static OGSRoomSnapshot OGSCurrentSnapshot(void) {
    uint32_t index = __atomic_load_n(&gSnapshotIndex, __ATOMIC_ACQUIRE);
    return gSnapshots[index];
}

// ============================================================
// MARK: - Safe Peer & Array Extraction
// ============================================================
static bool OGSReadPeer(void *peer, void *master, OGSPeerSnapshot *output) {
    if (!peer || !output) return false;
    memset(output, 0, sizeof(*output));
    output->isHost = (peer == master);

    uintptr_t idAddress   = OGSResolveRVA(RVA_PLAYER_GET_ID);
    uintptr_t nameAddress = OGSResolveRVA(RVA_PLAYER_GET_NAME);
    if (!idAddress || !nameAddress) return false;

    PlayerGetIDFn getID     = (PlayerGetIDFn)idAddress;
    PlayerGetNameFn getName = (PlayerGetNameFn)nameAddress;

    output->actorID = getID(peer, NULL);
    void *nameObject = getName(peer, NULL);
    NSString *name = OGSReadIl2CppString(nameObject);

    if (!name.length) {
        snprintf(output->name, sizeof(output->name), "ID:%d", output->actorID);
        return true;
    }

    const char *utf8 = name.UTF8String;
    if (!utf8) return false;
    snprintf(output->name, sizeof(output->name), "%s", utf8);
    return true;
}

static uint32_t OGSReadPlayerArray(uintptr_t listRVA, void *output[OGS_MAX_PEERS]) {
    if (!output) return 0;
    memset(output, 0, sizeof(void *) * OGS_MAX_PEERS);

    uintptr_t inRoomAddress = OGSResolveRVA(RVA_IN_ROOM);
    uintptr_t listAddress   = OGSResolveRVA(listRVA);
    if (!inRoomAddress || !listAddress) return 0;

    Bool0Fn inRoom    = (Bool0Fn)inRoomAddress;
    Object0Fn getList = (Object0Fn)listAddress;
    if (!inRoom(NULL)) return 0;

    void *array = getList(NULL);
    if (!array) return 0;

    uintptr_t arrayAddress = (uintptr_t)array;
    uintptr_t count = 0;
    if (!OGSReadMemory(arrayAddress + 0x18, &count, sizeof(count))) return 0;
    if (count == 0 || count > OGS_MAX_PEERS) return 0;

    uint32_t valid = 0;
    for (uint32_t i = 0; i < (uint32_t)count; i++) {
        void *peer = NULL;
        uintptr_t itemAddress = arrayAddress + 0x20 + ((uintptr_t)i * sizeof(void *));
        if (!OGSReadPointer(itemAddress, &peer)) continue;
        output[valid++] = peer;
    }
    return valid;
}

// ============================================================
// MARK: - Host & Connection Control Helpers
// ============================================================
static void *OGSFindLocalPlayer(void) {
    void *allPeers[OGS_MAX_PEERS];
    uint32_t allCount = OGSReadPlayerArray(RVA_ALL_PLAYERS, allPeers);
    if (allCount == 0) return NULL;

    void *otherPeers[OGS_MAX_PEERS];
    uint32_t otherCount = OGSReadPlayerArray(RVA_GET_PEERS, otherPeers);
    if (otherCount == 0) return allPeers[0];

    uintptr_t idAddress = OGSResolveRVA(RVA_PLAYER_GET_ID);
    PlayerGetIDFn getID = (PlayerGetIDFn)idAddress;

    for (uint32_t i = 0; i < allCount; i++) {
        void *cand = allPeers[i];
        int32_t candID = getID ? getID(cand, NULL) : 0;
        bool isOther = false;
        for (uint32_t j = 0; j < otherCount; j++) {
            if (otherPeers[j] == cand) { isOther = true; break; }
            if (candID > 0 && getID && getID(otherPeers[j], NULL) == candID) { isOther = true; break; }
        }
        if (!isOther) return cand;
    }
    return NULL;
}

static void OGSSetMaster(void *playerObj) {
    if (!playerObj) return;
    uintptr_t slotAddr = OGSResolveRVA(TBL_SET_MASTER);
    void *fnPtr = NULL;
    if (OGSReadPointer(slotAddr, &fnPtr) && fnPtr) {
        ((PeerAction1Fn)fnPtr)(playerObj, NULL);
    }
}

static void OGSCloseConnRaw(void *peerObj) {
    if (!peerObj) return;
    gOGS.kickMsgArmed = 1;
    uintptr_t slotAddr = OGSResolveRVA(TBL_PEER_SYNC);
    void *fnPtr = NULL;
    if (OGSReadPointer(slotAddr, &fnPtr) && fnPtr) {
        ((PeerAction1Fn)fnPtr)(peerObj, NULL);
    }
}

// ============================================================
// MARK: - Speed Control
// ============================================================
static void OGSRequestSpeed(float speed) {
    if (!isfinite(speed)) return;
    speed = fmaxf(0.0f, fminf(speed, 20.0f));
    gOGS.gameSpeed = speed;
    __atomic_store_n(&gOGS.speedDirty, true, __ATOMIC_RELEASE);
}

static void OGSProcessSpeed(void) {
    if (!__atomic_exchange_n(&gOGS.speedDirty, false, __ATOMIC_ACQ_REL)) return;
    uintptr_t address = OGSResolveRVA(RVA_SET_TIMESCALE);
    if (!address) return;
    float speed = gOGS.gameSpeed;
    SetTime1Fn setTime = (SetTime1Fn)address;
    setTime(speed, NULL);
}

// ============================================================
// MARK: - UI Forward Declarations
// ============================================================
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
@property (strong, nonatomic) UIButton *speedSetButton;
@property (strong, nonatomic) NSMutableSet<NSString *> *bannedNames;
@property (strong, nonatomic) NSMutableSet<NSNumber *> *bannedActorIDs;
@property (strong, nonatomic) NSMutableSet<NSString *> *allowedNamesWhenLocked;
@property (assign, nonatomic) BOOL roomLockActive;
@property (strong, nonatomic) NSTimer *masterTimer;
+ (instancetype)sharedInstance;
- (void)setupMenu;
- (BOOL)shouldAutoKickPeerWithName:(NSString *)normName actorID:(int32_t)actID;
@end

// ============================================================
// MARK: - Unified Room Snapshot & Protection Engine
// ============================================================
static volatile bool s_inSnapshotUpdate = false;

static void OGSUpdateRoomSnapshot(void) {
    if (__atomic_exchange_n(&s_inSnapshotUpdate, true, __ATOMIC_ACQ_REL)) return;

    uintptr_t inRoomAddress       = OGSResolveRVA(RVA_IN_ROOM);
    uintptr_t masterStateAddress  = OGSResolveRVA(RVA_IS_MASTER);
    uintptr_t masterPlayerAddress = OGSResolveRVA(RVA_GET_MASTER_PEER);

    if (!inRoomAddress || !masterStateAddress || !masterPlayerAddress) {
        __atomic_store_n(&gOGS.phase, OGSRuntimePhaseDegraded, __ATOMIC_RELEASE);
        __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
        return;
    }

    Bool0Fn inRoomFn     = (Bool0Fn)inRoomAddress;
    Bool0Fn isMasterFn   = (Bool0Fn)masterStateAddress;
    Object0Fn masterFn   = (Object0Fn)masterPlayerAddress;

    bool inRoom = inRoomFn(NULL);
    OGSRoomSnapshot *snapshot = OGSBeginSnapshotWrite();
    snapshot->inRoom = inRoom;
    __atomic_store_n(&gOGS.inRoom, inRoom, __ATOMIC_RELEASE);

    if (!inRoom) {
        __atomic_store_n(&gOGS.isMaster, false, __ATOMIC_RELEASE);
        gOGS.kickRetries = 0;
        OGSPublishSnapshot(snapshot);
        __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
        return;
    }

    bool master = isMasterFn(NULL);
    void *masterPlayer = masterFn(NULL);

    // 1. حماية الهوست التلقائية واستعادته فوراً عند الحاجة
    if ((gOGS.autoHostOn || gOGS.forceHostReq > 0 || gOGS.kickRetries > 0) && !master) {
        gOGS.forceHostReq = 0;
        void *myPlayer = OGSFindLocalPlayer();
        if (myPlayer) {
            OGSSetMaster(myPlayer);
        }
        if (gOGS.autoHostOn && masterPlayer && masterPlayer != myPlayer) {
            OGSCloseConnRaw(masterPlayer);
        }
    }

    snapshot->isMaster = master;
    __atomic_store_n(&gOGS.isMaster, master, __ATOMIC_RELEASE);

    // 2. قراءة اللاعبين وتحديث الـ Snapshot وتطبيق الطرد المتتبع والحظر
    void *players[OGS_MAX_PEERS];
    uint32_t count = OGSReadPlayerArray(RVA_GET_PEERS, players);
    OGSModMenu *menu = [OGSModMenu sharedInstance];
    bool targetStillInRoom = false;

    for (uint32_t i = 0; i < count; i++) {
        OGSPeerSnapshot peerSnap;
        if (!OGSReadPeer(players[i], masterPlayer, &peerSnap)) continue;

        snapshot->peers[snapshot->count++] = peerSnap;

        NSString *pName = [NSString stringWithUTF8String:peerSnap.name];
        NSString *normName = OGSNormalizeKey(pName);

        // أ) تنفيذ الطرد المتتبع المضمون
        if (gOGS.kickRetries > 0) {
            bool matchID = (gOGS.kickTargetID > 0 && peerSnap.actorID == gOGS.kickTargetID);
            bool matchName = (gOGS.kickTargetName[0] != '\0' && strcmp(normName.UTF8String, gOGS.kickTargetName) == 0);
            if (matchID || matchName) {
                targetStillInRoom = true;
                if (!master) {
                    void *me = OGSFindLocalPlayer();
                    if (me) OGSSetMaster(me);
                }
                OGSCloseConnRaw(players[i]);
            }
        }

        // ب) تنفيذ الحظر وقفل الروم
        if ([menu shouldAutoKickPeerWithName:normName actorID:peerSnap.actorID]) {
            if (!master) {
                void *me = OGSFindLocalPlayer();
                if (me) OGSSetMaster(me);
            }
            OGSCloseConnRaw(players[i]);
        }
    }

    if (gOGS.kickRetries > 0) {
        if (!targetStillInRoom) {
            gOGS.kickRetries = 0;
            gOGS.kickTargetID = -1;
            gOGS.kickTargetName[0] = '\0';
        } else {
            gOGS.kickRetries--;
        }
    }

    OGSPublishSnapshot(snapshot);
    __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
}

// ============================================================
// MARK: - Game Hooks (Single Update Point + Chat + Disconnect)
// ============================================================
static void *OGSCreateFreshKickString(void *templateIl2CppStr) {
    if (!templateIl2CppStr || (uintptr_t)templateIl2CppStr < 0x100000000ULL) return NULL;

    uint8_t header[16] = {0};
    if (!OGSReadMemory((uintptr_t)templateIl2CppStr, header, 16)) return NULL;

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
    static uint8_t s_rawStrBuf[256] = {0};
    memset(s_rawStrBuf, 0, sizeof(s_rawStrBuf));
    memcpy(s_rawStrBuf, header, 16);
    *(int32_t *)(s_rawStrBuf + 0x10) = (int32_t)len;
    [kickPhrase getCharacters:(unichar *)(s_rawStrBuf + 0x14) range:NSMakeRange(0, len)];

    if (origIsPreFixed) {
        uintptr_t fixAddr = OGSResolveRVA(RVA_ARABIC_FIX);
        if (fixAddr) {
            void *fixed = ((ArabicFixFn)fixAddr)(s_rawStrBuf, NULL);
            if (fixed) return fixed;
        }
    }
    return s_rawStrBuf;
}

static void hook_OnPhotonPlayerDisconnected(void *self, void *player, void *method) {
    uintptr_t locManager = 0;
    void *origLeaveStr = NULL;
    void **leaveStrSlot = NULL;

    if (self && gOGS.kickMsgArmed > 0 && OGSReadMemory((uintptr_t)self + 0x2F8, &locManager, sizeof(uintptr_t)) && locManager > 0x100000000ULL) {
        if (OGSReadPointer(locManager + 0x238, &origLeaveStr) && origLeaveStr != NULL) {
            void *kickStr = OGSCreateFreshKickString(origLeaveStr);
            if (kickStr) {
                leaveStrSlot = (void **)(locManager + 0x238);
                *leaveStrSlot = kickStr;
            }
        }
        gOGS.kickMsgArmed = 0;
    }

    if (orig_OnDisconnect) orig_OnDisconnect(self, player, method);
    if (leaveStrSlot && origLeaveStr) *leaveStrSlot = origLeaveStr;
}

static void hook_SendChatRemote(void *self, void *senderStr, void *msgStr, int32_t p3, int32_t p4, void *method) {
    if (gOGS.chatMode == 1) {
        return; // كتم رسائل اللاعبين
    } else if (gOGS.chatMode == 2) {
        // طرد تلقائي لأي لاعب يرسل رسالة في الشات
        NSString *senderName = OGSReadIl2CppString(senderStr);
        if (senderName.length > 0) {
            NSString *normSender = OGSNormalizeKey(senderName);
            const char *utf8 = normSender.UTF8String;
            if (utf8) {
                snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", utf8);
                gOGS.kickTargetID = -1;
                gOGS.kickRetries = 12;
            }
        }
        return;
    }
    if (orig_SendChatRemote) orig_SendChatRemote(self, senderStr, msgStr, p3, p4, method);
}

// نقطة التحديث الموحدة (Single Update Point)
static volatile int32_t s_chatFrameTick = 0;

static void hook_ChatUpdate(void *self, void *method) {
    if (orig_ChatUpdate) orig_ChatUpdate(self, method);
    OGSProcessSpeed();
    if (++s_chatFrameTick >= 15) {
        s_chatFrameTick = 0;
        OGSUpdateRoomSnapshot();
    }
}

static void hook_CashUpdate(void *self, void *method) {
    if (orig_CashUpdate) orig_CashUpdate(self, method);
}

static void OGSInstallHooks(void) {
    uintptr_t base = OGSFindGameImage();
    if (!base) return;
    if (TBL_CASH_UPDATE)      { void **sl = (void **)(base + TBL_CASH_UPDATE);      orig_CashUpdate     = (Update0Fn)*sl;        *sl = (void *)&hook_CashUpdate; }
    if (TBL_CHAT_UPDATE)      { void **sl = (void **)(base + TBL_CHAT_UPDATE);      orig_ChatUpdate     = (Update0Fn)*sl;        *sl = (void *)&hook_ChatUpdate; }
    if (TBL_SEND_CHAT_REMOTE) { void **sl = (void **)(base + TBL_SEND_CHAT_REMOTE); orig_SendChatRemote = (SendChatRemoteFn)*sl; *sl = (void *)&hook_SendChatRemote; }
    if (TBL_ON_DISCONNECT)    { void **sl = (void **)(base + TBL_ON_DISCONNECT);    orig_OnDisconnect   = (OnDisconnectFn)*sl;   *sl = (void *)&hook_OnPhotonPlayerDisconnected; }
}

// ============================================================
// MARK: - ModMenu UI Implementation
// ============================================================
@implementation OGSModMenu
+ (instancetype)sharedInstance {
    static OGSModMenu *inst = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        inst = [[OGSModMenu alloc] init];
        inst.bannedNames = [NSMutableSet set];
        inst.bannedActorIDs = [NSMutableSet set];
        inst.allowedNamesWhenLocked = [NSMutableSet set];
    });
    return inst;
}

- (BOOL)shouldAutoKickPeerWithName:(NSString *)normName actorID:(int32_t)actID {
    if (normName.length > 0 && [self.bannedNames containsObject:normName]) return YES;
    if (actID > 0 && [self.bannedActorIDs containsObject:@(actID)]) return YES;
    if (self.roomLockActive && normName.length > 0 && ![self.allowedNamesWhenLocked containsObject:normName]) return YES;
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

        self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(75, 18, 315, 252)];
        self.menuPanel.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:0.96];
        self.menuPanel.layer.cornerRadius = 14.0;
        self.menuPanel.layer.borderWidth = 2.0f;
        self.menuPanel.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.menuPanel.hidden = YES;

        UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 295, 18)];
        tl.text = @"OGS v8: الهوست + الطرد المؤكد + الشات + السرعة";
        tl.textColor = [UIColor whiteColor];
        tl.textAlignment = NSTextAlignmentCenter;
        tl.font = [UIFont boldSystemFontOfSize:11.5];
        [self.menuPanel addSubview:tl];

        UIView *infoBox = [[UIView alloc] initWithFrame:CGRectMake(10, 25, 295, 40)];
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

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 70, 144, 30) title:@"▶ اللاعب السابق" bg:darkGray action:@selector(prevPlayer:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(161, 70, 144, 30) title:@"اللاعب التالي ◀" bg:darkGray action:@selector(nextPlayer:)]];

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(161, 105, 144, 32) title:@"طرد المحدد فقط" bg:kickOrange action:@selector(kickSelected:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 105, 144, 32) title:@"طرد وحظر (Ban)" bg:banRed action:@selector(banSelected:)]];

        self.hostLockButton = [self makeBtn:CGRectMake(155, 142, 150, 32) title:@"حماية الهوست: مفعّل 👑" bg:wpnGreen action:@selector(toggleAutoHost:)];
        [self.menuPanel addSubview:self.hostLockButton];

        self.muteChatButton = [self makeBtn:CGRectMake(10, 142, 140, 32) title:@"الشات: مفتوح" bg:darkGray action:@selector(cycleChatMode:)];
        [self.menuPanel addSubview:self.muteChatButton];

        self.lockButton = [self makeBtn:CGRectMake(161, 179, 144, 30) title:@"قفل الروم: مفتوح" bg:darkGray action:@selector(toggleRoomLock:)];
        [self.menuPanel addSubview:self.lockButton];

        self.unbanButton = [self makeBtn:CGRectMake(10, 179, 144, 30) title:@"فك حظر الكل (0)" bg:darkGray action:@selector(clearBanList:)];
        [self.menuPanel addSubview:self.unbanButton];

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 214, 55, 30) title:@"سرعة -" bg:darkGray action:@selector(speedDown:)]];
        self.speedSetButton = [self makeBtn:CGRectMake(70, 214, 175, 30) title:@"السرعة: 1.0x (اضغط للكتابة)" bg:hostBlue action:@selector(promptCustomSpeed:)];
        [self.menuPanel addSubview:self.speedSetButton];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(250, 214, 55, 30) title:@"سرعة +" bg:darkGray action:@selector(speedUp:)]];

        [self.containerView addSubview:self.menuPanel];
        self.containerView.floatingButton = self.floatingButton;
        self.containerView.menuPanel = self.menuPanel;
        [gw addSubview:self.containerView];
        [gw bringSubviewToFront:self.containerView];

        self.masterTimer = [NSTimer scheduledTimerWithTimeInterval:0.40 target:self selector:@selector(onMasterTick) userInfo:nil repeats:YES];
        self.masterTimer.tolerance = 0.08;
    });
}

- (void)onMasterTick {
    OGSUpdateRoomSnapshot();
    if (!self.menuPanel || self.menuPanel.hidden) return;
    [self refreshUI];
}

// قراءة معتمدة 100% على الـ Snapshot المعزول (بدون لمس مؤشرات اللعبة)
- (void)refreshUI {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    uint32_t count = snapshot.count;
    uint32_t selected = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);

    if (count == 0) {
        __atomic_store_n(&gOGS.selectedPeer, 0, __ATOMIC_RELEASE);
        self.playerLabel.text = @"المحدد: لا يوجد لاعبين معك حالياً";
    } else {
        if (selected >= count) {
            selected = 0;
            __atomic_store_n(&gOGS.selectedPeer, 0, __ATOMIC_RELEASE);
        }
        OGSPeerSnapshot peer = snapshot.peers[selected];
        NSString *name = [NSString stringWithUTF8String:peer.name];
        if (!name.length) name = @"لاعب";
        self.playerLabel.text = [NSString stringWithFormat:@"(%u/%u) %@%@",
                                 selected + 1, count, name, peer.isHost ? @" 👑" : @""];
    }

    if (gOGS.kickRetries > 0) {
        self.statusLabel.text = @"جاري تأكيد طرد اللاعب من السيرفر...";
    } else {
        self.statusLabel.text = [NSString stringWithFormat:@"%@ | بالروم: %u | المحظورين: %lu",
                                 snapshot.inRoom ? (snapshot.isMaster ? @"الهوست: أنت 👑" : @"متصل (حماية نشطة)") : @"غير متصل",
                                 count,
                                 (unsigned long)self.bannedNames.count];
    }
    [self.unbanButton setTitle:[NSString stringWithFormat:@"فك حظر الكل (%lu)", (unsigned long)self.bannedNames.count] forState:UIControlStateNormal];
}

- (void)toggleMenu {
    self.menuPanel.hidden = !self.menuPanel.hidden;
    if (!self.menuPanel.hidden) {
        OGSUpdateRoomSnapshot();
        [self refreshUI];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.containerView];
    g.view.center = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.containerView];
}

- (void)nextPlayer:(UIButton *)sender {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    if (!snapshot.count) return;
    uint32_t current = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);
    __atomic_store_n(&gOGS.selectedPeer, (current + 1) % snapshot.count, __ATOMIC_RELEASE);
    [self refreshUI];
}

- (void)prevPlayer:(UIButton *)sender {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    if (!snapshot.count) return;
    uint32_t current = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);
    __atomic_store_n(&gOGS.selectedPeer, (current + snapshot.count - 1) % snapshot.count, __ATOMIC_RELEASE);
    [self refreshUI];
}

- (void)toggleAutoHost:(UIButton *)s {
    gOGS.autoHostOn = !gOGS.autoHostOn;
    if (gOGS.autoHostOn) {
        gOGS.forceHostReq = 1;
        OGSUpdateRoomSnapshot();
        [s setTitle:@"حماية الهوست: مفعّل 👑" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    } else {
        [s setTitle:@"حماية الهوست: متوقف" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
    [self refreshUI];
}

- (void)cycleChatMode:(UIButton *)s {
    gOGS.chatMode = (gOGS.chatMode + 1) % 3;
    if (gOGS.chatMode == 1) {
        [s setTitle:@"الشات: كتم عندي 🔇" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.80 green:0.35 blue:0.10 alpha:1.0];
    } else if (gOGS.chatMode == 2) {
        [s setTitle:@"الشات: طرد من يكتب 🚫" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.70 green:0.12 blue:0.15 alpha:1.0];
    } else {
        [s setTitle:@"الشات: مفتوح" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
}

- (void)triggerKickForPeer:(OGSPeerSnapshot)peer {
    gOGS.kickTargetID = peer.actorID;
    NSString *pName = [NSString stringWithUTF8String:peer.name];
    NSString *normName = OGSNormalizeKey(pName);
    const char *utf8 = normName.UTF8String;
    if (utf8) {
        snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", utf8);
    }
    gOGS.kickRetries = 15;
    OGSUpdateRoomSnapshot();
}

- (void)kickSelected:(UIButton *)s {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    if (!snapshot.count) return;
    uint32_t selected = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);
    if (selected >= snapshot.count) selected = 0;

    OGSPeerSnapshot peer = snapshot.peers[selected];
    NSString *pName = [NSString stringWithUTF8String:peer.name];
    [self triggerKickForPeer:peer];
    self.statusLabel.text = [NSString stringWithFormat:@"تم طرد: %@", pName ?: @"اللاعب"];
}

- (void)banSelected:(UIButton *)s {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    if (!snapshot.count) return;
    uint32_t selected = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);
    if (selected >= snapshot.count) selected = 0;

    OGSPeerSnapshot peer = snapshot.peers[selected];
    NSString *pName = [NSString stringWithUTF8String:peer.name];
    NSString *normName = OGSNormalizeKey(pName);

    if (normName.length > 0) [self.bannedNames addObject:normName];
    if (peer.actorID > 0)    [self.bannedActorIDs addObject:@(peer.actorID)];

    [self triggerKickForPeer:peer];
    [self refreshUI];
    self.statusLabel.text = [NSString stringWithFormat:@"تم طرد وحظر: %@", pName ?: @"اللاعب"];
}

- (void)toggleRoomLock:(UIButton *)s {
    OGSUpdateRoomSnapshot();
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    self.roomLockActive = !self.roomLockActive;
    [self.allowedNamesWhenLocked removeAllObjects];

    if (self.roomLockActive) {
        for (uint32_t i = 0; i < snapshot.count; i++) {
            NSString *pName = [NSString stringWithUTF8String:snapshot.peers[i].name];
            NSString *norm = OGSNormalizeKey(pName);
            if (norm.length > 0) [self.allowedNamesWhenLocked addObject:norm];
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
    [self.bannedActorIDs removeAllObjects];
    [self refreshUI];
    self.statusLabel.text = @"تم مسح قائمة المحظورين بالكامل";
}

- (void)applySpeed:(float)value {
    OGSRequestSpeed(value);
    float actual = gOGS.gameSpeed;
    [self.speedSetButton setTitle:[NSString stringWithFormat:@"السرعة: %.1fx (اضغط للكتابة)", actual]
                         forState:UIControlStateNormal];
}

- (void)speedDown:(UIButton *)sender {
    [self applySpeed:gOGS.gameSpeed - 0.5f];
}

- (void)speedUp:(UIButton *)sender {
    [self applySpeed:gOGS.gameSpeed + 0.5f];
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
        tf.text = [NSString stringWithFormat:@"%.1f", gOGS.gameSpeed];
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"تطبيق" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        float val = [alert.textFields.firstObject.text floatValue];
        if (val >= 0.0f && val <= 20.0f) [self applySpeed:val];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [rootVC presentViewController:alert animated:YES completion:nil];
}
@end

// ============================================================
// MARK: - Smart Runtime Bootstrap
// ============================================================
static void OGSWaitForRuntime(void) {
    __atomic_store_n(&gOGS.phase, OGSRuntimePhaseWaitingImage, __ATOMIC_RELEASE);
    __block void (^probe)(void);
    probe = ^{
        uintptr_t base = OGSFindGameImage();
        if (!base) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), probe);
            return;
        }
        __atomic_store_n(&gOGS.phase, OGSRuntimePhaseResolving, __ATOMIC_RELEASE);
        if (!OGSResolveRVA(RVA_IN_ROOM) ||
            !OGSResolveRVA(RVA_PLAYER_GET_ID) ||
            !OGSResolveRVA(RVA_PLAYER_GET_NAME)) {
            __atomic_store_n(&gOGS.phase, OGSRuntimePhaseDegraded, __ATOMIC_RELEASE);
            return;
        }
        OGSInstallHooks();
        __atomic_store_n(&gOGS.phase, OGSRuntimePhaseReady, __ATOMIC_RELEASE);
        [[OGSModMenu sharedInstance] setupMenu];
    };
    probe();
}

__attribute__((constructor))
static void ogs_init(void) {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            OGSWaitForRuntime();
        });
    }
}
