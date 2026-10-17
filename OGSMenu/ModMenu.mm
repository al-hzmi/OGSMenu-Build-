#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <mach/vm_region.h>

#define OGS_MAX_PEERS       64
#define OGS_MAX_NAME_BYTES  128
#define OGS_MAX_STRING_LEN  256

static NSString * const kDefaultGitHubConfigURL = @"https://raw.githubusercontent.com/al-hzmi/OGSMenu-Build-/main/ogs_config.json";

static NSArray<NSString *> *OGSCandidateCloudURLs(NSString *customURL) {
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    if (customURL.length > 8) [urls addObject:customURL];
    [urls addObject:@"https://raw.githubusercontent.com/al-hzmi/OGSMenu-Build-/main/ogs_config.json"];
    [urls addObject:@"https://raw.githubusercontent.com/al-hzmi/OGSMenu-Build-/main/OGSMenu/ogs_config.json"];
    [urls addObject:@"https://raw.githubusercontent.com/Al-hzmi/ogsmenu/main/ogs_config.json"];
    return urls;
}

// ============================================================
// MARK: - Verified Engine Offsets
// ============================================================
static const uintptr_t RVA_PHOTON_NET_TYPEINFO = 0x0281B1C8;

typedef struct {
    uintptr_t tblCashUpdate;
    uintptr_t tblChatUpdate;
    uintptr_t tblSendChatRemote;
    uintptr_t tblOnEvent;
    uintptr_t tblLeaveRoom;
    uintptr_t tblType4995LeaveRoom;
    uintptr_t tblOnMasterSwitched1;
    uintptr_t tblOnMasterSwitched2;
    uintptr_t tblOnMasterSwitched3;
    uintptr_t tblOnMasterSwitched4;
    uintptr_t tblOnMasterSwitched5;
    uintptr_t tblPeerSync;
    uintptr_t tblSetMaster;
    uintptr_t tblOnDisconnect;

    uintptr_t rvaSetTimescale;
    uintptr_t rvaInRoom;
    uintptr_t rvaIsMaster;
    uintptr_t rvaGetMasterPeer;
    uintptr_t rvaGetLocalPlayer;
    uintptr_t rvaGetRoom;
    uintptr_t rvaAllPlayers;
    uintptr_t rvaGetPeers;
    uintptr_t rvaPlayerGetName;
    uintptr_t rvaPlayerGetID;
    uintptr_t rvaNetPeerGetMMasterId;
    uintptr_t rvaNetPeerSetMMasterId;
    uintptr_t rvaNetPeerSetMasterProp;
    uintptr_t rvaIsLocalClientInside;
    uintptr_t rvaArabicFix;
    uintptr_t rvaFastAllocateString;

    // Aimbot & Unity RVAs
    uintptr_t rvaCameraGetMain;
    uintptr_t rvaComponentGetTransform;
    uintptr_t rvaTransformGetPosition;
    uintptr_t rvaTransformLookAtVec3;

    // Damage & Magic Bullet RVAs
    uintptr_t rvaApplyDamage;
    uintptr_t rvaDamageRemote;
} OGSOffsetsConfig;

static OGSOffsetsConfig gOffsets = {
    0x23918B8, // tblCashUpdate
    0x238FD68, // tblChatUpdate
    0x238FD80, // tblSendChatRemote
    0x2390048, // tblOnEvent
    0x2390A10, // tblLeaveRoom
    0x238E518, // tblType4995LeaveRoom
    0x2392628, // tblOnMasterSwitched1
    0x2391000, // tblOnMasterSwitched2
    0x238F228, // tblOnMasterSwitched3
    0x23903E0, // tblOnMasterSwitched4
    0x238E730, // tblOnMasterSwitched5
    0x2390A98, // tblPeerSync
    0x2390AA0, // tblSetMaster
    0x2391930, // tblOnDisconnect

    0x198AC4C, // rvaSetTimescale
    0x013CC38C, // rvaInRoom
    0x013CC2BC, // rvaIsMaster
    0x013CACA4, // rvaGetMasterPeer
    0x013CABF0, // rvaGetLocalPlayer
    0x013CAB28, // rvaGetRoom
    0x013CAEC4, // rvaAllPlayers
    0x013CAF78, // rvaGetPeers
    0x013D7534, // rvaPlayerGetName
    0x013CC384, // rvaPlayerGetID
    0x013AB2A4, // rvaNetPeerGetMMasterId
    0x013AB2AC, // rvaNetPeerSetMMasterId
    0x013B0C54, // rvaNetPeerSetMasterProp
    0x013FD758, // rvaIsLocalClientInside
    0x0130F538, // rvaArabicFix
    0x01B33DB8, // rvaFastAllocateString

    0x19655A4, // rvaCameraGetMain
    0x1966984, // rvaComponentGetTransform
    0x198B948, // rvaTransformGetPosition
    0x198CCFC, // rvaTransformLookAtVec3

    0x13E7360, // rvaApplyDamage
    0x13E7588  // rvaDamageRemote
};

// ============================================================
// MARK: - Function Signatures & Math Structs
// ============================================================
struct Vector3 {
    float x, y, z;
};

typedef void    (*Update0Fn)(void *, void *);
typedef void    (*SetTime1Fn)(float, void *);
typedef void    (*SendChatRemoteFn)(void *, void *, void *, int32_t, bool, const void *);
typedef void    (*OnEventFn)(void *, void *, void *);
typedef bool    (*LeaveRoomFn)(int32_t, void *);
typedef void    (*Type4995LeaveFn)(void *, void *);
typedef void    (*OnMasterSwitchFn)(void *, void *, void *);
typedef bool    (*Bool0Fn)(void *);
typedef void*   (*Object0Fn)(void *);
typedef bool    (*PeerAction1Fn)(void *, void *);
typedef void*   (*PlayerGetNameFn)(void *, void *);
typedef int32_t (*PlayerGetIDFn)(void *, void *);
typedef int32_t (*GetMasterIdFn)(void *, void *);
typedef void    (*SetMasterIdFn)(void *, int32_t, void *);
typedef void*   (*ArabicFixFn)(void *, void *);
typedef void*   (*FastAllocateStringFn)(int32_t length, const void *);
typedef void    (*OnDisconnectFn)(void *, void *, void *);

// IL2CPP fps 3.4.0: values points to Int32[3], not an ARM64 float register.
typedef void (*ApplyDamageFn)(void *, void *, const void *);
typedef void (*DamageRemoteFn)(void *, void *, int32_t, const void *);

// Unity Engine Signatures
typedef void*   (*Camera_GetMain_Fn)();
typedef void*   (*Component_GetTransform_Fn)(void *component, const void *method);
typedef Vector3 (*Transform_GetPosition_Fn)(void *transform, const void *method);
typedef void    (*Transform_LookAt_Vec3_Fn)(void *transform, Vector3 worldPosition, const void *method);

static Update0Fn        orig_CashUpdate      = NULL;
static Update0Fn        orig_ChatUpdate      = NULL;
static SendChatRemoteFn orig_SendChatRemote  = NULL;
static OnDisconnectFn   orig_OnDisconnect    = NULL;
static OnEventFn        orig_OnEvent         = NULL;
static OnEventFn        orig_OnOperationResponse = NULL;
static Update0Fn        orig_PhotonHandlerUpdate = NULL;
static LeaveRoomFn      orig_LeaveRoom       = NULL;
static Type4995LeaveFn  orig_Type4995Leave   = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch1 = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch2 = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch3 = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch4 = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch5 = NULL;
// MD31058: GameLogic.OnMasterClientSwitched() has NO PhotonPlayer argument.
static void (*orig_GameLogicMasterSwitch)(void *, void *) = NULL;
static Update0Fn orig_WorkerInGameDisconnected = NULL;

static ApplyDamageFn  orig_ApplyDamage = NULL;
static DamageRemoteFn orig_DamageRemote = NULL;

// ============================================================
// MARK: - Thread-Safe Runtime State & Locks
// ============================================================
static os_unfair_lock gBanSetLock   = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock gStateLock    = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock gSnapshotLock = OS_UNFAIR_LOCK_INIT;
static os_unfair_lock gHookInstallLock = OS_UNFAIR_LOCK_INIT; // serialize installer only

typedef struct {
    volatile bool     inRoom;
    volatile bool     isMaster;
    volatile bool     heldMasterStably;
    volatile uint32_t selectedPeer;
    volatile float    gameSpeed;
    volatile bool     speedDirty;
    volatile uint64_t readFailures;
    volatile int32_t  autoHostOn;
    volatile int32_t  aimbotOn;
    volatile int32_t  godModeOn;       // منع استلام الضرر
    volatile int32_t  magicBulletOn;   // مضاعفة الضرر
    volatile int32_t  antiKickHardLock;
    volatile int32_t  chatMode;
    volatile int32_t  kickMsgArmed;
    volatile int32_t  forceHostReq;
    volatile int32_t  kickTargetID;
    volatile int32_t  kickRetries;
    volatile int32_t  insideNetworkEvent;
    volatile int32_t  userInitiatedLeave;
    volatile uint32_t blockedKicksCount;
    volatile int32_t  cachedLocalActorID;
    void * volatile   capturedNetPeer;
    double            roomEnterTime;
    double            masterAcquiredTime;
    double            lastMasterClaimTime;
    double            lastKickPacketTime;
    double            lastUnityFrameTick;
    double            lastThreatTime;
    char              kickTargetName[OGS_MAX_NAME_BYTES];
    char              lastHijackerName[OGS_MAX_NAME_BYTES];
    char              customKickPhrase[OGS_MAX_NAME_BYTES];
} OGSRuntimeState;

static OGSRuntimeState gOGS = {
    false, // inRoom
    false, // isMaster
    false, // heldMasterStably
    0,     // selectedPeer
    1.0f,  // gameSpeed
    false, // speedDirty
    0,     // readFailures
    0,     // autoHostOn (legacy Unity tick path unused)
    0,     // aimbotOn
    0,     // godModeOn
    0,     // magicBulletOn
    0,     // antiKickHardLock
    0,     // chatMode
    0,     // kickMsgArmed
    0,     // forceHostReq
    -1,    // kickTargetID
    0,     // kickRetries
    0,     // insideNetworkEvent
    0,     // userInitiatedLeave
    0,     // blockedKicksCount
    0,     // cachedLocalActorID
    NULL,  // capturedNetPeer
    0.0,   // roomEnterTime
    0.0,   // masterAcquiredTime
    0.0,   // lastMasterClaimTime
    0.0,   // lastKickPacketTime
    0.0,   // lastUnityFrameTick
    0.0,   // lastThreatTime
    {0},   // kickTargetName
    {0},   // lastHijackerName
    " تم طرده من الغرفة " // customKickPhrase
};

// عداد ذكي لمنع الفيض الشبكي (Server Flood) ضد اللاعبين الذين لديهم مضاد طرد
typedef struct {
    int32_t actorID;
    int32_t attempts;
    double  lastAttemptTime;
} OGSAutoKickTracker;

static OGSAutoKickTracker gAutoKickTrackers[OGS_MAX_PEERS];

static void OGSResetAutoKickTrackers(void) {
    os_unfair_lock_lock(&gStateLock);
    memset(gAutoKickTrackers, 0, sizeof(gAutoKickTrackers));
    os_unfair_lock_unlock(&gStateLock);
}

static bool OGSIsAutoKickAllowedForActor(int32_t actorID, double now) {
    if (actorID <= 0) return true;
    bool allowed = false;
    os_unfair_lock_lock(&gStateLock);
    int emptySlot = -1;
    int foundSlot = -1;
    for (int i = 0; i < OGS_MAX_PEERS; i++) {
        if (gAutoKickTrackers[i].actorID == actorID) {
            foundSlot = i;
            break;
        }
        if (emptySlot == -1 && gAutoKickTrackers[i].actorID == 0) {
            emptySlot = i;
        }
    }
    if (foundSlot == -1) {
        int slot = (emptySlot != -1) ? emptySlot : 0;
        gAutoKickTrackers[slot].actorID = actorID;
        gAutoKickTrackers[slot].attempts = 1;
        gAutoKickTrackers[slot].lastAttemptTime = now;
        allowed = true;
    } else {
        // إذا تم إرسال 6 محاولات طرد ولم يخرج اللاعب (لديه مضاد)، نتوقف مؤقتاً لمنع السيرفر من طردنا
        if (gAutoKickTrackers[foundSlot].attempts < 6) {
            if ((now - gAutoKickTrackers[foundSlot].lastAttemptTime) >= 0.35) {
                gAutoKickTrackers[foundSlot].attempts++;
                gAutoKickTrackers[foundSlot].lastAttemptTime = now;
                allowed = true;
            }
        } else if ((now - gAutoKickTrackers[foundSlot].lastAttemptTime) >= 8.0) {
            // إعادة محاولة هادئة كل 8 ثوانٍ فقط دون التسبب في فيض للسيرفر
            gAutoKickTrackers[foundSlot].attempts = 1;
            gAutoKickTrackers[foundSlot].lastAttemptTime = now;
            allowed = true;
        }
    }
    os_unfair_lock_unlock(&gStateLock);
    return allowed;
}

static void OGSResetTrackerForActor(int32_t actorID) {
    if (actorID <= 0) return;
    os_unfair_lock_lock(&gStateLock);
    for (int i = 0; i < OGS_MAX_PEERS; i++) {
        if (gAutoKickTrackers[i].actorID == actorID) {
            gAutoKickTrackers[i].attempts = 0;
            gAutoKickTrackers[i].lastAttemptTime = 0.0;
            break;
        }
    }
    os_unfair_lock_unlock(&gStateLock);
}

// ============================================================
// MARK: - Safe Memory Layer & Image Resolver
// ============================================================
static volatile uintptr_t gImageBase = 0;

static uintptr_t OGSFindGameImage(void) {
    uintptr_t cached = __atomic_load_n(&gImageBase, __ATOMIC_ACQUIRE);
    if (cached) return cached;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        const char *last = strrchr(name, '/');
        const char *file = last ? last + 1 : name;
        if (strcmp(file, "fps") != 0) continue;

        const struct mach_header *header = _dyld_get_image_header(i);
        if (!header) continue;
        uintptr_t base = (uintptr_t)header;
        __atomic_store_n(&gImageBase, base, __ATOMIC_RELEASE);
        NSLog(@"[OGS] Found fps image: %s header=%p", name, header);
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

static bool OGSReadMemory(uintptr_t address, void *output, size_t size) {
    if (address < 0x100000000ULL || !output || size == 0) return false;
    vm_size_t copied = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)address, (vm_size_t)size, (vm_address_t)output, &copied);
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
    if (!OGSReadMemory(address + 0x14, buffer, bytes)) { free(buffer); return nil; }
    NSString *result = [[NSString alloc] initWithCharacters:buffer length:(NSUInteger)length];
    free(buffer);
    return result;
}

static void *OGSManagedStringFromNSString(NSString *text) {
    if (!text) return NULL;
    NSUInteger nsLen = text.length;
    if (nsLen == 0 || nsLen > INT32_MAX) return NULL;
    uintptr_t addr = OGSResolveRVA(gOffsets.rvaFastAllocateString);
    if (!addr) return NULL;
    FastAllocateStringFn allocString = (FastAllocateStringFn)addr;
    void *managed = allocString((int32_t)nsLen, NULL);
    if (!managed) return NULL;
    unichar *chars = (unichar *)((uintptr_t)managed + 0x14);
    [text getCharacters:chars range:NSMakeRange(0, nsLen)];
    return managed;
}

static void *OGSCreateFreshKickString(void *templateIl2CppStr) {
    char phraseBuf[OGS_MAX_NAME_BYTES];
    os_unfair_lock_lock(&gStateLock);
    memcpy(phraseBuf, gOGS.customKickPhrase, sizeof(phraseBuf));
    phraseBuf[OGS_MAX_NAME_BYTES - 1] = '\0';
    os_unfair_lock_unlock(&gStateLock);

    NSString *phrase = [NSString stringWithUTF8String:phraseBuf];
    if (!phrase.length) phrase = @" تم طرده من الغرفة ";
    if (phrase.length > 90) phrase = [phrase substringToIndex:90];

    void *managed = OGSManagedStringFromNSString(phrase);
    if (!managed) return NULL;

    bool origIsPreFixed = false;
    NSString *origText = OGSReadIl2CppString(templateIl2CppStr);
    if (origText) {
        for (NSUInteger i = 0; i < origText.length; i++) {
            unichar c = [origText characterAtIndex:i];
            if (c >= 0xFE70 && c <= 0xFEFF) { origIsPreFixed = true; break; }
        }
    }

    if (origIsPreFixed) {
        uintptr_t fixAddr = OGSResolveRVA(gOffsets.rvaArabicFix);
        if (fixAddr) {
            void *fixed = ((ArabicFixFn)fixAddr)(managed, NULL);
            if (fixed) return fixed;
        }
    }
    return managed;
}

static NSString *OGSNormalizeKey(NSString *value) {
    if (!value) return @"";
    return [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

// ============================================================
// MARK: - Snapshot Model & Peer Management
// ============================================================
typedef struct {
    int32_t actorID;
    bool    isHost;
    void    *playerObject; 
    char    name[OGS_MAX_NAME_BYTES];
} OGSPeerSnapshot;

typedef struct {
    bool            inRoom;
    bool            isMaster;
    uint32_t        count;
    OGSPeerSnapshot peers[OGS_MAX_PEERS];
} OGSRoomSnapshot;

static OGSRoomSnapshot gSnapshot;

static void OGSPublishSnapshotValue(const OGSRoomSnapshot *src) {
    if (!src) return;
    os_unfair_lock_lock(&gSnapshotLock);
    gSnapshot = *src;
    os_unfair_lock_unlock(&gSnapshotLock);
}

static OGSRoomSnapshot OGSCurrentSnapshot(void) {
    OGSRoomSnapshot out;
    os_unfair_lock_lock(&gSnapshotLock);
    out = gSnapshot;
    os_unfair_lock_unlock(&gSnapshotLock);
    return out;
}

static bool OGSReadPeer(void *peer, void *master, OGSPeerSnapshot *output) {
    if (!peer || (uintptr_t)peer < 0x100000000ULL || !output) return false;
    memset(output, 0, sizeof(*output));
    output->isHost = (peer == master);
    output->playerObject = peer;

    uintptr_t idAddress   = OGSResolveRVA(gOffsets.rvaPlayerGetID);
    uintptr_t nameAddress = OGSResolveRVA(gOffsets.rvaPlayerGetName);
    if (!idAddress || !nameAddress) return false;

    void *klassPtr = NULL;
    if (!OGSReadPointer((uintptr_t)peer, &klassPtr)) return false;

    output->actorID = ((PlayerGetIDFn)idAddress)(peer, NULL);
    void *nameObject = ((PlayerGetNameFn)nameAddress)(peer, NULL);
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

    uintptr_t inRoomAddress = OGSResolveRVA(gOffsets.rvaInRoom);
    uintptr_t listAddress   = OGSResolveRVA(listRVA);
    if (!inRoomAddress || !listAddress) return 0;

    if (!((Bool0Fn)inRoomAddress)(NULL)) return 0;

    void *array = ((Object0Fn)listAddress)(NULL);
    if (!array || (uintptr_t)array < 0x100000000ULL) return 0;

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
// MARK: - Aimbot Engine Implementation
// ============================================================
static void OGSExecuteAimbot(void) {
    if (!__atomic_load_n(&gOGS.aimbotOn, __ATOMIC_ACQUIRE)) return;
    if (!__atomic_load_n(&gOGS.inRoom, __ATOMIC_ACQUIRE)) return;

    uintptr_t camMainAddr = OGSResolveRVA(gOffsets.rvaCameraGetMain);
    if (!camMainAddr) return;
    void *mainCamera = ((Camera_GetMain_Fn)camMainAddr)();
    if (!mainCamera || (uintptr_t)mainCamera < 0x100000000ULL) return;

    uintptr_t getTransAddr = OGSResolveRVA(gOffsets.rvaComponentGetTransform);
    uintptr_t getPosAddr   = OGSResolveRVA(gOffsets.rvaTransformGetPosition);
    uintptr_t lookAtAddr   = OGSResolveRVA(gOffsets.rvaTransformLookAtVec3);
    if (!getTransAddr || !getPosAddr || !lookAtAddr) return;

    Component_GetTransform_Fn getTransform = (Component_GetTransform_Fn)getTransAddr;
    Transform_GetPosition_Fn getPosition   = (Transform_GetPosition_Fn)getPosAddr;
    Transform_LookAt_Vec3_Fn lookAt        = (Transform_LookAt_Vec3_Fn)lookAtAddr;

    // TODO: استبدل دالة OGSGetLocalPlayerID مستقبلاً بدالة دقيقة لجلب الـ PlayerNetwork الخاص بك
    // حالياً Aimbot معلق حتى نستخرج الـ LocalPlayer Network Object بدقة في التحديث القادم
}

// ============================================================
// MARK: - Real Server Host Claim & Gate-Bypass Kick
// ============================================================
static void *OGSFindLocalPlayer(void) {
    uintptr_t getLocalAddr = OGSResolveRVA(gOffsets.rvaGetLocalPlayer);
    if (getLocalAddr) {
        void *p = ((Object0Fn)getLocalAddr)(NULL);
        if (p && (uintptr_t)p > 0x100000000ULL) return p;
    }

    void *allPeers[OGS_MAX_PEERS];
    uint32_t allCount = OGSReadPlayerArray(gOffsets.rvaAllPlayers, allPeers);
    if (allCount == 0) return NULL;

    void *otherPeers[OGS_MAX_PEERS];
    uint32_t otherCount = OGSReadPlayerArray(gOffsets.rvaGetPeers, otherPeers);
    if (otherCount == 0) return allPeers[0];

    uintptr_t idAddress = OGSResolveRVA(gOffsets.rvaPlayerGetID);
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

static int32_t OGSGetLocalPlayerID(void **outPlayerObj) {
    void *myPlayer = OGSFindLocalPlayer();
    if (outPlayerObj) *outPlayerObj = myPlayer;
    if (!myPlayer) return 0;
    uintptr_t idAddr = OGSResolveRVA(gOffsets.rvaPlayerGetID);
    if (!idAddr) return 0;
    int32_t pid = ((PlayerGetIDFn)idAddr)(myPlayer, NULL);
    if (pid > 0) {
        __atomic_store_n(&gOGS.cachedLocalActorID, pid, __ATOMIC_RELEASE);
    }
    return pid;
}

static void *OGSGetNetworkingPeerSafe(void) {
    uintptr_t typeInfoSlot = OGSResolveRVA(RVA_PHOTON_NET_TYPEINFO);
    if (typeInfoSlot) {
        void *typeInfo = NULL;
        if (OGSReadPointer(typeInfoSlot, &typeInfo)) {
            void *staticFields = NULL;
            if (OGSReadPointer((uintptr_t)typeInfo + 0xB8, &staticFields)) {
                void *netPeer = NULL;
                if (OGSReadPointer((uintptr_t)staticFields + 0x10, &netPeer)) {
                    void *localPlayer = NULL;
                    void *currentRoom = NULL;
                    OGSReadPointer((uintptr_t)netPeer + 0x160, &localPlayer);
                    OGSReadPointer((uintptr_t)netPeer + 0x158, &currentRoom);
                    if (localPlayer || currentRoom) {
                        __atomic_store_n((uintptr_t *)&gOGS.capturedNetPeer, (uintptr_t)netPeer, __ATOMIC_RELEASE);
                        return netPeer;
                    }
                }
            }
        }
    }
    return nil;
}

// Defined below in the pre-sign bridge validation section.
static bool OGSIsExecutableGameAddress(uintptr_t addr);

static bool OGSClaimMasterReal(bool bypassCooldown) {
    uintptr_t inRoomAddr = OGSResolveRVA(gOffsets.rvaInRoom);
    if (!inRoomAddr || !((Bool0Fn)inRoomAddr)(NULL)) return false;

    double now = CFAbsoluteTimeGetCurrent();
    if (!bypassCooldown && (now - gOGS.lastMasterClaimTime) < 0.32) return false;
    if (bypassCooldown && (now - gOGS.lastMasterClaimTime) < 0.14) return false;

    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);
    if (!myPlayer || myID <= 0) return false;

    gOGS.lastMasterClaimTime = now;
    os_unfair_lock_lock(&gStateLock);
    gOGS.lastThreatTime = now;
    os_unfair_lock_unlock(&gStateLock);

    void *netPeer = OGSGetNetworkingPeerSafe();
    // rvaNetPeerSetMMasterId is not a verified callable function entry.
    // Do not call an instruction inside another function or rewrite Photon
    // MasterClient fields locally; request authorization through game APIs.

    bool sent = false;
    uintptr_t slotAddr = OGSResolveRVA(gOffsets.tblSetMaster);
    void *fnPtr = NULL;
    if (slotAddr && OGSReadPointer(slotAddr, &fnPtr) && fnPtr &&
        OGSIsExecutableGameAddress((uintptr_t)fnPtr)) {
        sent = ((PeerAction1Fn)fnPtr)(myPlayer, NULL);
    }

    if (netPeer) {
        void *currentRoom = NULL;
        if (OGSReadPointer((uintptr_t)netPeer + 0x158, &currentRoom) && currentRoom) {
            uintptr_t setPropMasterAddr = OGSResolveRVA(gOffsets.rvaNetPeerSetMasterProp);
            if (setPropMasterAddr && OGSIsExecutableGameAddress(setPropMasterAddr)) {
                ((SetMasterIdFn)setPropMasterAddr)(netPeer, myID, NULL);
                sent = true;
            }
        }
    }

    return sent;
}

// Stage 7: explicit, single-shot recovery experiment (OFF until user taps).
// Call only from the already-active Photon event-processing context,
// never the UIKit timer. Request the game API to ask Photon to restore the
// local actor; do not edit MasterClient fields or send duplicate requests.
static volatile uint32_t gOGSManualRecoveryPending = 0;
static volatile uint32_t gOGSManualRecoveryAttempts = 0;
static volatile uint32_t gOGSManualRecoveryAccepted = 0;
static volatile uint32_t gOGSManualRecoveryFailed = 0;
static volatile uint32_t gOGSRecoveryScopeRejected = 0; // local context mismatch, not server denial
static volatile uint32_t gOGSManualRecoverySkipped = 0;
// Stage 18: preserve a room-bound manual intent behind the shared limiter.
static uintptr_t gOGSManualRecoveryRoom = 0;        // gStateLock
static int32_t gOGSManualRecoveryActor = 0;         // gStateLock
static double gOGSManualRecoveryQueuedAt = 0.;     // gStateLock
static bool gOGSManualRecoveryDeferredCounted = false; // gStateLock
static volatile uint32_t gOGSManualRecoveryDeferred = 0;
static volatile uint32_t gOGSManualRecoveryExpired = 0;
static volatile uint32_t gOGSImmediateLocalMaster = 0;
static volatile uint32_t gOGSImmediateOtherMaster = 0;
static volatile uint32_t gOGSImmediateMasterReadFail = 0;
// Stage 11: defensive accounting only. A locally filtered event is not
// proof that Photon server-side disconnects or hostile clients were stopped.
// User-initiated, one-shot peer management request, scoped to current room.
static volatile uint32_t gOGSManualKickPending = 0;
static int32_t gOGSManualKickActor = 0; // gStateLock
static uintptr_t gOGSManualKickRoom = 0; // gStateLock
static double gOGSManualKickQueuedAt = 0.; // gStateLock
static volatile uint32_t gOGSManualKickSubmitted = 0;
static volatile uint32_t gOGSManualKickPreflightDenied = 0;
static volatile uint32_t gOGSManualKickRejected = 0;
static volatile uint32_t gOGSManualKickExpired = 0;
static volatile uint32_t gOGSFilteredEvent203 = 0;
static volatile uint32_t gOGSEvent203NearRecovery = 0;
static volatile uint32_t gOGSLastEvent203ProximityMs = 0;
static double gOGSLastRecoveryAttemptAt = 0.0; // guarded by gStateLock
static volatile uint32_t gOGSBanEvaluations = 0;
static volatile uint32_t gOGSBanMatches = 0;
static volatile uint32_t gOGSBanKickLocalAccepted = 0;
// Room-scoped automatic recovery; disabled until the room owner opts in.
static volatile uint32_t gOGSAutoEnabled = 0;
static uintptr_t gOGSAutoRoom = 0;             // gStateLock
static int32_t gOGSAutoOwner = 0;               // gStateLock
static double gOGSAutoLastRequestAt = 0.;      // gStateLock
static volatile uint32_t gOGSAutoAttempts = 0;
static volatile uint32_t gOGSAutoAccepted = 0;
static volatile uint32_t gOGSAutoFailed = 0;
static volatile uint32_t gOGSAutoCooldown = 0;
static volatile uint32_t gOGSAutoGuarded = 0;
static volatile uint32_t gOGSAutoDisarmed = 0;
static volatile uint32_t gOGSAutoRejoinApprovals = 0;
// Stage 14: Photon-event-driven fast recovery, bounded by a shared
// token bucket. Never patch local master fields or run engine APIs on UIKit.
// Manual and automatic recovery share one quota in the same room.
static volatile uint32_t gOGSAutoPendingLoss = 0;
static volatile uint32_t gOGSAutoDeferredQueued = 0;
static volatile uint32_t gOGSAutoDeferredExecuted = 0;
static volatile uint32_t gOGSAutoDeferredCancelled = 0;
static volatile uint32_t gOGSAutoRateLimitedWindows = 0;
static volatile uint32_t gOGSAutoRetriesWhileLost = 0;
static uint32_t gOGSAutoWindowAttempts = 0;      // gStateLock
static uintptr_t gOGSAutoWindowRoom = 0;          // gStateLock
static int32_t gOGSAutoWindowActor = 0;            // gStateLock
static double gOGSAutoWindowStartedAt = 0.;       // gStateLock
static bool gOGSAutoWindowPauseCounted = false;   // gStateLock
static bool gOGSAutoAttemptedPending = false;     // gStateLock
static bool gOGSAutoSawOwnedMaster = false;        // gStateLock
static const uint32_t kOGSAutoWindowAttemptLimit = 6;
static const double kOGSAutoWindowSeconds = 60.0;
static const double kOGSAutoCooldownSeconds = 0.65; // first counter after a confirmed loss can be immediate
static const double kOGSRecoveryTokenCapacity = 3.0;
static const double kOGSRecoveryTokenRefillSeconds = 10.0;
static double gOGSRecoveryTokens = 3.0;          // gStateLock
static double gOGSRecoveryTokenRefillAt = 0.0;  // gStateLock

// Stage 20: bounded, read-only, room-scoped local MasterClient chronology.
// The timeline records OBSERVED local state changes, not server approvals.
#define OGS_MASTER_TIMELINE_CAPACITY 32
typedef struct {
    double observedAt;
    int32_t localActor;
    int32_t fromActor;
    int32_t toActor;
    uint32_t eventCode;      // 0 for PhotonHandler.Update
    uint8_t viaUpdate;
    double locallyHeldMs;    // approximate observation gap, not server duration
} OGSHostTimelineEntry;
static OGSHostTimelineEntry gOGSHostTimeline[OGS_MASTER_TIMELINE_CAPACITY];
static uint64_t gOGSHostTimelineWrites = 0;  // gStateLock
static uintptr_t gOGSHostObservedRoom = 0;   // gStateLock
static int32_t gOGSHostObservedActor = 0;    // gStateLock
static int32_t gOGSHostObservedMaster = 0;   // gStateLock
static double gOGSHostLocalObservedSince = 0.; // gStateLock
static volatile uint32_t gOGSHostLossEvent208 = 0;
static volatile uint32_t gOGSHostLossEvent253 = 0;
static volatile uint32_t gOGSHostLossUpdate = 0;

// Verified room + local actor + master are read using Mach VM only.
static bool OGSReadAutoRoom(uintptr_t *roomOut, int32_t *localOut, int32_t *masterOut) {
    void *peer = OGSGetNetworkingPeerSafe();
    uintptr_t room = 0, localPtr = 0;
    int32_t localID = 0, masterID = 0;
    if (!peer ||
        !OGSReadMemory((uintptr_t)peer + 0x158, &room, sizeof(room)) ||
        !OGSReadMemory((uintptr_t)peer + 0x160, &localPtr, sizeof(localPtr)) ||
        room < 0x100000000ULL || localPtr < 0x100000000ULL ||
        !OGSReadMemory(localPtr + 0x10, &localID, sizeof(localID)) ||
        !OGSReadMemory(room + 0x48, &masterID, sizeof(masterID)) ||
        localID < 1 || localID >= 1000000 ||
        masterID < 1 || masterID >= 1000000) return false;
    if (roomOut) *roomOut = room;
    if (localOut) *localOut = localID;
    if (masterOut) *masterOut = masterID;
    return true;
}

// Never modify or synthesize a Photon event. Capture only cross-callback
// observations under one lock, resetting baseline whenever room/actor changes.
static void OGSRecordHostLocalObservation(uintptr_t room, int32_t actor,
                                          int32_t master, uint32_t code,
                                          bool viaUpdate) {
    if (!room || actor <= 0 || master <= 0) return;
    double observedAt = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&gStateLock);
    if (gOGSHostObservedRoom != room || gOGSHostObservedActor != actor ||
        gOGSHostObservedMaster <= 0) {
        gOGSHostObservedRoom = room;
        gOGSHostObservedActor = actor;
        gOGSHostObservedMaster = master;
        gOGSHostLocalObservedSince = master == actor ? observedAt : 0.;
    } else if (gOGSHostObservedMaster != master) {
        OGSHostTimelineEntry *entry =
            &gOGSHostTimeline[gOGSHostTimelineWrites % OGS_MASTER_TIMELINE_CAPACITY];
        entry->observedAt = observedAt;
        entry->localActor = actor;
        entry->fromActor = gOGSHostObservedMaster;
        entry->toActor = master;
        entry->eventCode = code;
        entry->viaUpdate = viaUpdate ? 1u : 0u;
        entry->locallyHeldMs =
            (gOGSHostObservedMaster == actor && gOGSHostLocalObservedSince > 0.) ?
            fmax(0., (observedAt - gOGSHostLocalObservedSince) * 1000.) : 0.;
        ++gOGSHostTimelineWrites;
        if (entry->fromActor == actor && master != actor) {
            if (viaUpdate)
                __atomic_fetch_add(&gOGSHostLossUpdate, 1u, __ATOMIC_RELAXED);
            else if (code == 208)
                __atomic_fetch_add(&gOGSHostLossEvent208, 1u, __ATOMIC_RELAXED);
            else if (code == 253)
                __atomic_fetch_add(&gOGSHostLossEvent253, 1u, __ATOMIC_RELAXED);
        }
        gOGSHostObservedMaster = master;
        gOGSHostLocalObservedSince = master == actor ? observedAt : 0.;
    }
    os_unfair_lock_unlock(&gStateLock);
}

static void OGSDisarmAutoRoom(void) {
    os_unfair_lock_lock(&gStateLock);
    if (__atomic_exchange_n(&gOGSAutoEnabled, 0u, __ATOMIC_ACQ_REL))
        __atomic_fetch_add(&gOGSAutoDisarmed, 1u, __ATOMIC_RELAXED);
    gOGSAutoRoom = 0;
    gOGSAutoOwner = 0;
    // Do not reset cooldown/rate budget here: disabling and immediately
    // re-enabling within the same room must not bypass the rate limiter.
    if (__atomic_exchange_n(&gOGSAutoPendingLoss, 0u, __ATOMIC_ACQ_REL))
        __atomic_fetch_add(&gOGSAutoDeferredCancelled, 1u, __ATOMIC_RELAXED);
    gOGSAutoAttemptedPending = false;
    gOGSAutoSawOwnedMaster = false;
    os_unfair_lock_unlock(&gStateLock);
}

// Invoked after the player explicitly enables recovery for the current room.
// Re-arming the same room preserves its rate limit and last request time.
static void OGSArmAutoRoomBounded(uintptr_t room, int32_t actor, int32_t master) {
    if (!room || actor <= 0 || master <= 0) return;
    os_unfair_lock_lock(&gStateLock);
    if (gOGSAutoWindowRoom != room || gOGSAutoWindowActor != actor) {
        gOGSAutoWindowRoom = room;
        gOGSAutoWindowActor = actor;
        gOGSAutoWindowAttempts = 0;
        gOGSAutoWindowStartedAt = 0.;
        gOGSAutoWindowPauseCounted = false;
        gOGSAutoLastRequestAt = 0.;
        gOGSRecoveryTokens = kOGSRecoveryTokenCapacity;
        gOGSRecoveryTokenRefillAt = 0.;
    }
    gOGSAutoRoom = room;
    gOGSAutoOwner = actor;
    gOGSAutoAttemptedPending = false;
    gOGSAutoSawOwnedMaster = (master == actor);
    __atomic_store_n(&gOGSAutoPendingLoss, master != actor ? 1u : 0u,
                     __ATOMIC_RELEASE);
    __atomic_store_n(&gOGSAutoEnabled, 1u, __ATOMIC_RELEASE);
    os_unfair_lock_unlock(&gStateLock);
}


/*
 * Atomic reservation for BOTH manual and automatic SetMasterClient requests.
 * Requires gStateLock. No Photon/IL2CPP methods are invoked here.
 * - maximum 3 immediately available requests, 650ms apart;
 * - one token refills every 10 seconds, up to 3;
 * - strict ceiling of 6 submissions in each 60-second window.
 * This constrains client traffic; the server may still reject any request.
 */
static bool OGSReserveMasterRequestLocked(uintptr_t room, int32_t actor, double now) {
    if (!room || actor <= 0) return false;
    if (gOGSAutoWindowRoom != room || gOGSAutoWindowActor != actor) {
        gOGSAutoWindowRoom = room;
        gOGSAutoWindowActor = actor;
        gOGSAutoWindowAttempts = 0;
        gOGSAutoWindowStartedAt = 0.;
        gOGSAutoWindowPauseCounted = false;
        gOGSAutoLastRequestAt = 0.;
        gOGSRecoveryTokens = kOGSRecoveryTokenCapacity;
        gOGSRecoveryTokenRefillAt = now;
    }
    if (gOGSRecoveryTokenRefillAt <= 0.) gOGSRecoveryTokenRefillAt = now;
    if (now > gOGSRecoveryTokenRefillAt) {
        gOGSRecoveryTokens = fmin(kOGSRecoveryTokenCapacity,
            gOGSRecoveryTokens + (now - gOGSRecoveryTokenRefillAt) /
                                 kOGSRecoveryTokenRefillSeconds);
        gOGSRecoveryTokenRefillAt = now;
    }
    if (gOGSAutoWindowStartedAt <= 0. ||
        now - gOGSAutoWindowStartedAt >= kOGSAutoWindowSeconds) {
        gOGSAutoWindowStartedAt = now;
        gOGSAutoWindowAttempts = 0;
        gOGSAutoWindowPauseCounted = false;
    }
    if (gOGSAutoLastRequestAt > 0. &&
        now - gOGSAutoLastRequestAt < kOGSAutoCooldownSeconds)
        return false;
    if (gOGSAutoWindowAttempts >= kOGSAutoWindowAttemptLimit) {
        if (!gOGSAutoWindowPauseCounted) {
            gOGSAutoWindowPauseCounted = true;
            __atomic_fetch_add(&gOGSAutoRateLimitedWindows, 1u, __ATOMIC_RELAXED);
        }
        return false;
    }
    if (gOGSRecoveryTokens < 1.0) return false;
    --gOGSRecoveryTokens;
    ++gOGSAutoWindowAttempts;
    gOGSAutoLastRequestAt = now;
    return true;
}

// Verified for fps 3.4.0 (IL2CPP metadata Room.set_IsOpen / Room.set_IsVisible).
// Both are PUN Room property setters; invoke only on the game's Photon callback,
// never from the UIKit timer. Slot pointers have been checked against ARM64.
static const uintptr_t kOGSRoomSetOpenSlot = 0x02391758;
static const uintptr_t kOGSRoomSetVisibleSlot = 0x02391768;
// 0=no action, 1=hidden & joinable, 2=hidden & closed, 3=public & joinable.
static volatile uint32_t gOGSPrivacyPending = 0;
static uintptr_t gOGSPrivacyRequestedRoom = 0; // gStateLock
static int32_t gOGSPrivacyRequestedActor = 0; // gStateLock
static volatile uint32_t gOGSPrivacyApplied = 0;
static volatile uint32_t gOGSPrivacyRejected = 0;
// Stage26: explicit, room/actor-bound entry guard. Only enforces the user's
// existing "closed and hidden" room setting. Never writes MasterClient.
static volatile uint32_t gOGSClosedGuardEnabled = 0;
static uintptr_t gOGSClosedGuardRoom = 0; // gStateLock
static int32_t gOGSClosedGuardActor = 0;   // gStateLock
static double gOGSClosedGuardLastScan = 0.;  // gStateLock
static double gOGSClosedGuardLastRequest = 0.; // gStateLock
static double gOGSClosedGuardWindowStart = 0.; // gStateLock
static uint32_t gOGSClosedGuardWindowRequests = 0; // gStateLock
static const double kOGSClosedGuardScanSeconds = 1.0;
static const double kOGSClosedGuardRetrySeconds = 5.0;
static const uint32_t kOGSClosedGuardWindowLimit = 6;
static volatile uint32_t gOGSClosedGuardQueued = 0;
static volatile uint32_t gOGSClosedGuardClosedObserved = 0;
static volatile uint32_t gOGSClosedGuardNoAuthority = 0;
static volatile uint32_t gOGSClosedGuardRateLimited = 0;
static volatile uint32_t gOGSClosedGuardDisarmed = 0;
// Independent Unity/PUN frame callback handles queued actions even when
// a private room has no incoming Photon OnEvent callbacks.
static volatile uint64_t gOGSPhotonHandlerUpdateCalls = 0;
// Recovery fallback is throttled separately from the unchanged Photon request quota.
static double gOGSRecoveryLastUpdateProbeAt = 0.; // gStateLock
static volatile uint32_t gOGSRecoveryUpdateProbes = 0;
static volatile uint32_t gOGSRecoveryEventProbes = 0;
static const uintptr_t kOGSPhotonHandlerUpdateSlot = 0x023905F0;
// Stage23 isolated repair: cached Unity Update MethodInfo only.
// Status: 0 pending, 1 already hooked, 2 repaired, 3 cache unavailable,
// 4 identity mismatch, 5 unsafe memory, 6 original pointer mismatch.
static volatile uint32_t gOGSCachedUpdateStatus = 0;
static volatile uint32_t gOGSCachedUpdateAttempts = 0;
static volatile uint32_t gOGSCachedUpdateEntryMatched = 0;
static volatile uintptr_t gOGSCachedUpdateObservedEntry = 0;
// Verified MD31284 / MI28551: NetworkingPeer.OnOperationResponse(OperationResponse).
// 0x02358400 + MI*8 = 0x02390038 in fps 3.4.0 ARM64 metadata table.
static const uintptr_t kOGSOnOperationResponseSlot = 0x02390038;
static const uintptr_t kOGSOnOperationResponseEntry = 0x013B0F3C;
static volatile uint32_t gOGSResponseHookStatus = 0; // 0 pending, 1 installed, 2 slot mismatch, 3 unavailable
static volatile uint64_t gOGSResponseEntryCalls = 0;
static volatile uint64_t gOGSResponseExitCalls = 0;
static volatile uint64_t gOGSSetProps252Replies = 0;
static volatile uint64_t gOGSSetProps252ZeroReturn = 0;
static volatile uint64_t gOGSSetProps252NonzeroReturn = 0;
static volatile uint32_t gOGSSetProps252ParseErrors = 0;
static volatile int32_t gOGSSetProps252LastReturnCode = 2147483647;
static volatile uint32_t gOGSOnEventInstallFailures = 0;
static volatile uint32_t gOGSPhotonUpdateInstallFailures = 0;
static volatile uint64_t gOGSPhotonHandlerUpdateExitCalls = 0;
// Verified against fps 3.4.0 IL2CPP metadata: PhotonHandler.Update method
// index 28734 maps to the ARM64 entry at RVA 0x013C8400 via this slot.

static bool OGSReadRoomPrivacy(uintptr_t room, bool *isOpen, bool *isVisible) {
    uint8_t o = 0, v = 0;
    if (room < 0x100000000ULL ||
        !OGSReadMemory(room + 0x38, &o, sizeof(o)) ||
        !OGSReadMemory(room + 0x39, &v, sizeof(v)) ||
        o > 1 || v > 1) return false;
    if (isOpen) *isOpen = (o != 0);
    if (isVisible) *isVisible = (v != 0);
    return true;
}

typedef void (*OGSRoomBoolSetterFn)(void *room, bool value, void *methodInfo);

// Process a user-requested room privacy mode from a Photon callback. A room
// and local-master check prevents applying a stale request after rejoin/transfer.
// Property setter updates locally and queues Photon room properties; server
// acceptance is not assumed by this local action.
static void OGSProcessRoomPrivacyOnEvent(void) {
    uint32_t mode = __atomic_exchange_n(&gOGSPrivacyPending, 0u, __ATOMIC_ACQ_REL);
    if (mode < 1 || mode > 3) return;

    uintptr_t wantedRoom = 0;
    int32_t wantedActor = 0;
    os_unfair_lock_lock(&gStateLock);
    wantedRoom = gOGSPrivacyRequestedRoom;
    wantedActor = gOGSPrivacyRequestedActor;
    os_unfair_lock_unlock(&gStateLock);

    uintptr_t room = 0;
    int32_t localActor = 0, masterActor = 0;
    bool isOpen = true, isVisible = true;
    uintptr_t openSlot = OGSResolveRVA(kOGSRoomSetOpenSlot);
    uintptr_t visibleSlot = OGSResolveRVA(kOGSRoomSetVisibleSlot);
    void *openSetter = NULL, *visibleSetter = NULL;
    if (!OGSReadAutoRoom(&room, &localActor, &masterActor) ||
        room != wantedRoom || localActor != wantedActor ||
        localActor != masterActor ||
        !OGSReadRoomPrivacy(room, &isOpen, &isVisible) ||
        !openSlot || !visibleSlot ||
        !OGSReadPointer(openSlot, &openSetter) ||
        !OGSReadPointer(visibleSlot, &visibleSetter) ||
        !OGSIsExecutableGameAddress((uintptr_t)openSetter) ||
        !OGSIsExecutableGameAddress((uintptr_t)visibleSetter)) {
        __atomic_fetch_add(&gOGSPrivacyRejected, 1u, __ATOMIC_RELAXED);
        return;
    }

    bool targetOpen = mode != 2;
    bool targetVisible = mode == 3;
    // Hide first when closing. Open first when publishing. Both changes
    // use the verified PUN Room property API, never direct memory writes.
    if (!targetVisible && isVisible)
        ((OGSRoomBoolSetterFn)visibleSetter)((void *)room, false, NULL);
    if (isOpen != targetOpen)
        ((OGSRoomBoolSetterFn)openSetter)((void *)room, targetOpen, NULL);
    if (targetVisible && !isVisible)
        ((OGSRoomBoolSetterFn)visibleSetter)((void *)room, true, NULL);
    __atomic_fetch_add(&gOGSPrivacyApplied, 1u, __ATOMIC_RELAXED);
}

// Poll at most once per second from PhotonHandler.Update only.
// A fresh snapshot must match the explicitly guarded room AND actor.
// Never submit room settings while another player is MasterClient.
// "Closed" is observed locally; an independent join test is needed for
// server-side confirmation.
static void OGSProcessClosedGuardOnPhotonCallback(void) {
    if (!__atomic_load_n(&gOGSClosedGuardEnabled, __ATOMIC_ACQUIRE)) return;
    double now = CFAbsoluteTimeGetCurrent();
    uintptr_t wantedRoom = 0;
    int32_t wantedActor = 0;
    os_unfair_lock_lock(&gStateLock);
    if (!__atomic_load_n(&gOGSClosedGuardEnabled, __ATOMIC_ACQUIRE) ||
        (gOGSClosedGuardLastScan > 0. &&
         now - gOGSClosedGuardLastScan < kOGSClosedGuardScanSeconds)) {
        os_unfair_lock_unlock(&gStateLock);
        return;
    }
    gOGSClosedGuardLastScan = now;
    wantedRoom = gOGSClosedGuardRoom;
    wantedActor = gOGSClosedGuardActor;
    os_unfair_lock_unlock(&gStateLock);

    uintptr_t liveRoom = 0;
    int32_t liveActor = 0, liveMaster = 0;
    if (!OGSReadAutoRoom(&liveRoom, &liveActor, &liveMaster)) return;
    if (liveRoom != wantedRoom || liveActor != wantedActor) {
        os_unfair_lock_lock(&gStateLock);
        if (gOGSClosedGuardRoom == wantedRoom &&
            gOGSClosedGuardActor == wantedActor &&
            __atomic_exchange_n(&gOGSClosedGuardEnabled, 0u,
                                __ATOMIC_ACQ_REL))
            __atomic_fetch_add(&gOGSClosedGuardDisarmed, 1u,
                               __ATOMIC_RELAXED);
        os_unfair_lock_unlock(&gStateLock);
        return;
    }
    if (liveMaster != liveActor) {
        __atomic_fetch_add(&gOGSClosedGuardNoAuthority, 1u,
                           __ATOMIC_RELAXED);
        return;
    }
    bool open = true, visible = true;
    if (!OGSReadRoomPrivacy(liveRoom, &open, &visible)) return;
    if (!open && !visible) {
        __atomic_fetch_add(&gOGSClosedGuardClosedObserved, 1u,
                           __ATOMIC_RELAXED);
        return;
    }
    // A queued explicit user privacy action always takes precedence.
    if (__atomic_load_n(&gOGSPrivacyPending, __ATOMIC_ACQUIRE)) return;

    os_unfair_lock_lock(&gStateLock);
    if (__atomic_load_n(&gOGSClosedGuardEnabled, __ATOMIC_ACQUIRE) &&
        gOGSClosedGuardRoom == liveRoom &&
        gOGSClosedGuardActor == liveActor &&
        !__atomic_load_n(&gOGSPrivacyPending, __ATOMIC_ACQUIRE)) {
        if (gOGSClosedGuardWindowStart <= 0. ||
            now - gOGSClosedGuardWindowStart >= 60.0) {
            gOGSClosedGuardWindowStart = now;
            gOGSClosedGuardWindowRequests = 0;
        }
        if (gOGSClosedGuardWindowRequests >= kOGSClosedGuardWindowLimit) {
            __atomic_fetch_add(&gOGSClosedGuardRateLimited, 1u,
                               __ATOMIC_RELAXED);
        } else if (gOGSClosedGuardLastRequest <= 0. ||
                   now - gOGSClosedGuardLastRequest >= kOGSClosedGuardRetrySeconds) {
            gOGSPrivacyRequestedRoom = liveRoom;
            gOGSPrivacyRequestedActor = liveActor;
            __atomic_store_n(&gOGSPrivacyPending, 2u, __ATOMIC_RELEASE);
            gOGSClosedGuardLastRequest = now;
            ++gOGSClosedGuardWindowRequests;
            __atomic_fetch_add(&gOGSClosedGuardQueued, 1u, __ATOMIC_RELAXED);
        }
    }
    os_unfair_lock_unlock(&gStateLock);
}

static bool OGSRequestLocalMasterOnceOnEvent(uintptr_t expectedRoom, int32_t expectedActor) {
    void *netPeer = OGSGetNetworkingPeerSafe();
    if (!netPeer) return false;
    uintptr_t room = 0, localPlayer = 0;
    int32_t localActor = 0, roomMaster = 0;
    if (!OGSReadMemory((uintptr_t)netPeer + 0x158, &room, sizeof(room)) ||
        !OGSReadMemory((uintptr_t)netPeer + 0x160, &localPlayer, sizeof(localPlayer)) ||
        room < 0x100000000ULL || localPlayer < 0x100000000ULL ||
        !OGSReadMemory(localPlayer + 0x10, &localActor, sizeof(localActor)) ||
        !OGSReadMemory(room + 0x48, &roomMaster, sizeof(roomMaster)) ||
        localActor <= 0 || localActor >= 1000000 ||
        roomMaster <= 0 || roomMaster >= 1000000 ||
        localActor == roomMaster) return false;
    // A reservation in room A must not be submitted from room B after a rejoin.
    if (room != expectedRoom || localActor != expectedActor) {
        __atomic_fetch_add(&gOGSRecoveryScopeRejected, 1u, __ATOMIC_RELAXED);
        return false;
    }

    uintptr_t slot = OGSResolveRVA(gOffsets.tblSetMaster);
    void *candidate = NULL;
    if (!slot || !OGSReadPointer(slot, &candidate) || !candidate ||
        !OGSIsExecutableGameAddress((uintptr_t)candidate)) return false;
    // Capture the moment before submission so a rapid incoming 203 cannot
    // outrun the telemetry. Timestamp means attempted, not accepted/authorized.
    os_unfair_lock_lock(&gStateLock);
    gOGSLastRecoveryAttemptAt = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_unlock(&gStateLock);
    // A true return means the local API accepted the request for submission.
    // Local room reads may be optimistic; server confirmation needs other evidence.
    bool submitted = ((PeerAction1Fn)candidate)((void *)localPlayer, NULL);
    // Read-only telemetry: PUN Classic may optimistically change the local
    // MasterClient prior to any server acknowledgement.
    int32_t immediate = 0;
    if (OGSReadMemory(room + 0x48, &immediate, sizeof(immediate))) {
        if (immediate == localActor)
            __atomic_fetch_add(&gOGSImmediateLocalMaster, 1u, __ATOMIC_RELAXED);
        else
            __atomic_fetch_add(&gOGSImmediateOtherMaster, 1u, __ATOMIC_RELAXED);
    } else {
        __atomic_fetch_add(&gOGSImmediateMasterReadFail, 1u, __ATOMIC_RELAXED);
    }
    return submitted;
}

static bool OGSKickPeerReal(void *peerObj, bool bypassCooldown) {
    if (!peerObj || (uintptr_t)peerObj < 0x100000000ULL) return false;

    void *klassPtr = NULL;
    if (!OGSReadPointer((uintptr_t)peerObj, &klassPtr)) return false;

    double now = CFAbsoluteTimeGetCurrent();
    if (!bypassCooldown && (now - gOGS.lastKickPacketTime) < 0.25) return false;

    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);
    if (!myPlayer || myID <= 0 || peerObj == myPlayer) return false;

    gOGS.lastKickPacketTime = now;
    gOGS.kickMsgArmed = 1;

    uintptr_t isMasterAddr = OGSResolveRVA(gOffsets.rvaIsMaster);
    bool currentlyMaster = isMasterAddr ? ((Bool0Fn)isMasterAddr)(NULL) : false;
    if (!currentlyMaster) {
        OGSClaimMasterReal(false);
    }

    // No temporary MasterClient spoofing. Photon ownership has to be
    // confirmed by the game before invoking peer-management operations.
    if (!currentlyMaster) return false;

    bool result = false;
    uintptr_t slotAddr = OGSResolveRVA(gOffsets.tblPeerSync);
    void *fnPtr = NULL;
    if (slotAddr && OGSReadPointer(slotAddr, &fnPtr) && fnPtr &&
        OGSIsExecutableGameAddress((uintptr_t)fnPtr)) {
        result = ((PeerAction1Fn)fnPtr)(peerObj, NULL);
    }

    return result;
}

// ============================================================
// MARK: - Speed Control
// ============================================================
static void OGSApplyTimescaleNow(float speed) {
    uintptr_t address = OGSResolveRVA(gOffsets.rvaSetTimescale);
    if (!address) return;
    ((SetTime1Fn)address)(speed, NULL);
}

static void OGSRequestSpeed(float speed) {
    if (!isfinite(speed)) return;
    speed = fmaxf(0.1f, fminf(speed, 20.0f));
    os_unfair_lock_lock(&gStateLock);
    gOGS.gameSpeed = speed;
    os_unfair_lock_unlock(&gStateLock);
    __atomic_store_n(&gOGS.speedDirty, true, __ATOMIC_RELEASE);
}
static volatile uint32_t gOGSSpeedApplied = 0;
static volatile uint32_t gOGSSpeedDeferred = 0;
static void OGSProcessSpeed(void) {
    // Only when a new speed value is requested; no every-frame updates.
    if (!__atomic_exchange_n(&gOGS.speedDirty, false, __ATOMIC_ACQ_REL)) return;
    float speed = 1.0f;
    os_unfair_lock_lock(&gStateLock);
    speed = gOGS.gameSpeed;
    os_unfair_lock_unlock(&gStateLock);
    uintptr_t setter = OGSResolveRVA(gOffsets.rvaSetTimescale);
    if (!setter || !OGSIsExecutableGameAddress(setter)) {
        __atomic_store_n(&gOGS.speedDirty, true, __ATOMIC_RELEASE);
        __atomic_fetch_add(&gOGSSpeedDeferred, 1u, __ATOMIC_RELAXED);
        return;
    }
    ((SetTime1Fn)setter)(speed, NULL);
    __atomic_fetch_add(&gOGSSpeedApplied, 1u, __ATOMIC_RELAXED);
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
@property (strong, nonatomic) UIScrollView *menuPanel;
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) UILabel *playerLabel;
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UIButton *syncCloudButton;
@property (strong, nonatomic) UIButton *unbanButton;
@property (strong, nonatomic) UIButton *lockButton;
@property (strong, nonatomic) UIButton *hostLockButton;
@property (strong, nonatomic) UIButton *privacyHiddenButton;
@property (strong, nonatomic) UIButton *privacyClosedButton;
@property (strong, nonatomic) UIButton *godModeButton;     // درع الحماية
@property (strong, nonatomic) UIButton *magicBulletButton; // رصاصة سحرية
@property (strong, nonatomic) UIButton *antiKickLockButton;
@property (strong, nonatomic) UIButton *muteChatButton;
@property (strong, nonatomic) UIButton *speedSetButton;
@property (strong, nonatomic) NSMutableSet<NSString *> *bannedNames;
@property (strong, nonatomic) NSMutableSet<NSNumber *> *bannedActorIDs;
@property (strong, nonatomic) NSMutableSet<NSString *> *allowedNamesWhenLocked;
@property (assign, nonatomic) BOOL roomLockActive;
@property (strong, nonatomic) NSTimer *masterTimer;
// Names observed for the same actor *in this room session only*.
// Actor numbers can change after rejoining and are not user identities.
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, NSMutableArray<NSString *> *> *sessionNameHistory;
@property (assign, nonatomic) uintptr_t sessionNameRoom;
+ (instancetype)sharedInstance;
- (void)setupMenu;
- (void)ensureMenuVisible;
- (void)recordHijackerName:(NSString *)normName actorID:(int32_t)actID;
- (void)fetchGitHubCloudConfigWithFeedback:(BOOL)showFeedback;
- (BOOL)shouldAutoKickPeerWithName:(NSString *)normName actorID:(int32_t)actID;
- (NSUInteger)bannedCountSafe;
@end

// ============================================================
// MARK: - Room Snapshot & Engine Tick (Unity Thread)
// ============================================================
static volatile bool s_inSnapshotUpdate = false;

static void OGSUpdateRoomSnapshot(bool passive = false) {
    if (__atomic_exchange_n(&s_inSnapshotUpdate, true, __ATOMIC_ACQ_REL)) return;

    uintptr_t inRoomAddress       = OGSResolveRVA(gOffsets.rvaInRoom);
    uintptr_t masterStateAddress  = OGSResolveRVA(gOffsets.rvaIsMaster);
    uintptr_t masterPlayerAddress = OGSResolveRVA(gOffsets.rvaGetMasterPeer);

    if (!inRoomAddress || !masterStateAddress || !masterPlayerAddress) {
        __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
        return;
    }

    bool inRoom = ((Bool0Fn)inRoomAddress)(NULL);
    OGSRoomSnapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    snapshot.inRoom = inRoom;

    double now = CFAbsoluteTimeGetCurrent();
    bool wasInRoom = __atomic_load_n(&gOGS.inRoom, __ATOMIC_ACQUIRE);
    __atomic_store_n(&gOGS.inRoom, inRoom, __ATOMIC_RELEASE);

    if (!inRoom) {
        __atomic_store_n(&gOGS.isMaster, false, __ATOMIC_RELEASE);
        __atomic_store_n(&gOGS.heldMasterStably, false, __ATOMIC_RELEASE);
        os_unfair_lock_lock(&gStateLock);
        gOGS.roomEnterTime = 0.0;
        gOGS.masterAcquiredTime = 0.0;
        gOGS.kickRetries = 0;
        os_unfair_lock_unlock(&gStateLock);
        OGSResetAutoKickTrackers();
        OGSPublishSnapshotValue(&snapshot);
        __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
        return;
    }

    os_unfair_lock_lock(&gStateLock);
    if (!wasInRoom || gOGS.roomEnterTime == 0.0) {
        gOGS.roomEnterTime = now;
        gOGS.masterAcquiredTime = 0.0;
        __atomic_store_n(&gOGS.heldMasterStably, false, __ATOMIC_RELEASE);
    }
    double enterTime = gOGS.roomEnterTime;
    os_unfair_lock_unlock(&gStateLock);

    bool master = ((Bool0Fn)masterStateAddress)(NULL);
    void *masterPlayer = ((Object0Fn)masterPlayerAddress)(NULL);
    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);
    OGSModMenu *menu = [OGSModMenu sharedInstance];

    bool roomSettled = ((now - enterTime) >= 0.8 && myPlayer != NULL && myID > 0);
    int32_t forceReq = passive ? 0 : __atomic_exchange_n(&gOGS.forceHostReq, 0, __ATOMIC_ACQ_REL);

    if (master) {
        os_unfair_lock_lock(&gStateLock);
        if (gOGS.masterAcquiredTime == 0.0) {
            gOGS.masterAcquiredTime = now;
        } else if ((now - gOGS.masterAcquiredTime) >= 0.30) {
            __atomic_store_n(&gOGS.heldMasterStably, true, __ATOMIC_RELEASE);
        }
        os_unfair_lock_unlock(&gStateLock);
    } else {
        os_unfair_lock_lock(&gStateLock);
        gOGS.masterAcquiredTime = 0.0;
        int32_t curRetries = gOGS.kickRetries;
        os_unfair_lock_unlock(&gStateLock);

        if (!passive && roomSettled && (gOGS.autoHostOn || forceReq > 0 || curRetries > 0)) {
            bool heldStably = __atomic_load_n(&gOGS.heldMasterStably, __ATOMIC_ACQUIRE);

            if (gOGS.autoHostOn && heldStably && masterPlayer && masterPlayer != myPlayer) {
                OGSPeerSnapshot thiefSnap;
                if (OGSReadPeer(masterPlayer, masterPlayer, &thiefSnap) && thiefSnap.actorID != myID && thiefSnap.actorID > 0) {
                    NSString *thiefName = [NSString stringWithUTF8String:thiefSnap.name];
                    NSString *normThief = OGSNormalizeKey(thiefName);

                    os_unfair_lock_lock(&gStateLock);
                    gOGS.lastThreatTime = now;
                    gOGS.kickTargetID = thiefSnap.actorID;
                    if (normThief.UTF8String) {
                        snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", normThief.UTF8String);
                        snprintf(gOGS.lastHijackerName, sizeof(gOGS.lastHijackerName), "%s", thiefSnap.name);
                    }
                    // تحديد محاولات طرد السارق بـ 6 محاولات فقط بعد استرجاع الهوست لمنع السيرفر من طردنا إذا كان لديه مضاد
                    if (gOGS.kickRetries <= 0) {
                        gOGS.kickRetries = 6;
                    }
                    os_unfair_lock_unlock(&gStateLock);
                }
            }

            // الأولوية القصوى: استرجاع الهوست أولاً وعدم إرسال حزم طرد أثناء فقدان الصلاحية
            OGSClaimMasterReal(forceReq > 0);
        }
    }

    snapshot.isMaster = master;
    __atomic_store_n(&gOGS.isMaster, master, __ATOMIC_RELEASE);

    void *players[OGS_MAX_PEERS];
    uint32_t count = OGSReadPlayerArray(gOffsets.rvaGetPeers, players);
    bool targetStillInRoom = false;

    int32_t curKickID = -1;
    int32_t curRetries = 0;
    char curKickName[OGS_MAX_NAME_BYTES];
    memset(curKickName, 0, sizeof(curKickName));

    os_unfair_lock_lock(&gStateLock);
    curKickID = gOGS.kickTargetID;
    curRetries = gOGS.kickRetries;
    memcpy(curKickName, gOGS.kickTargetName, sizeof(curKickName));
    os_unfair_lock_unlock(&gStateLock);

    for (uint32_t i = 0; i < count; i++) {
        OGSPeerSnapshot peerSnap;
        if (!OGSReadPeer(players[i], masterPlayer, &peerSnap)) continue;

        snapshot.peers[snapshot.count++] = peerSnap;

        NSString *pName = [NSString stringWithUTF8String:peerSnap.name];
        NSString *normName = OGSNormalizeKey(pName);

        // لا يتم إرسال حزم الطرد إلا بعد تأكيد استلامنا للهوست (master == true) لمنع تفعيل مضاد الخصم أو طردنا من السيرفر
        if (!passive && roomSettled && master && curRetries > 0) {
            bool matchID = (curKickID > 0 && peerSnap.actorID == curKickID);
            bool matchName = (curKickName[0] != '\0' && normName.UTF8String && strcmp(normName.UTF8String, curKickName) == 0);
            if (matchID || matchName) {
                targetStillInRoom = true;
                OGSKickPeerReal(players[i], false);
            }
        }

        if (!passive && roomSettled && master && [menu shouldAutoKickPeerWithName:normName actorID:peerSnap.actorID]) {
            if (OGSIsAutoKickAllowedForActor(peerSnap.actorID, now)) {
                if (OGSKickPeerReal(players[i], false))
                    __atomic_fetch_add(&gOGSBanKickLocalAccepted, 1u, __ATOMIC_RELAXED);
            }
        }
    }

    if (!passive && master && curRetries > 0) {
        os_unfair_lock_lock(&gStateLock);
        if (!targetStillInRoom) {
            gOGS.kickRetries = 0;
            gOGS.kickTargetID = -1;
            gOGS.kickTargetName[0] = '\0';
        } else if (gOGS.kickRetries > 0) {
            gOGS.kickRetries--;
        }
        os_unfair_lock_unlock(&gStateLock);
    }

    OGSPublishSnapshotValue(&snapshot);
    __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
}

static void OGSUnityThreadTick(void) {
    double now = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&gStateLock);
    gOGS.lastUnityFrameTick = now;
    os_unfair_lock_unlock(&gStateLock);

    OGSProcessSpeed();

    int32_t forceReq = __atomic_load_n(&gOGS.forceHostReq, __ATOMIC_ACQUIRE);
    static double s_lastSnapTime = 0.0;

    if (forceReq > 0 || (now - s_lastSnapTime) >= 0.16) {
        s_lastSnapTime = now;
        OGSUpdateRoomSnapshot(false);
    }
}

// ============================================================
// MARK: - Damage, Network, Chat & Lifecycle Hooks
// ============================================================

// Executable trampolines are installed OFFLINE into the unsigned IPA, before
// the device signs it. Runtime changes only writable callback pointers.
static bool OGSIsWritableMappedSlot(uintptr_t address);
static const uintptr_t OGS_MAGIC_STUB = 0x3000;
static const uintptr_t OGS_GOD_STUB = 0x3040;
static const uintptr_t OGS_MAGIC_SLOT = 0x2813EF0;
static const uintptr_t OGS_GOD_SLOT = 0x2813EF8;
static const uintptr_t OGS_MAGIC_ORIGINAL = 0x3014;
static const uintptr_t OGS_GOD_ORIGINAL = 0x3054;

// Safe, runtime-only diagnostics for the pre-sign bridge.
// Counts let us distinguish a working bridge from an unused game call path.
static volatile uint32_t gMagicCallbacks = 0;
static volatile uint32_t gMagicArrayReads = 0;
static volatile uint32_t gMagicMutations = 0;
static volatile int32_t gMagicLastOriginalDamage = 0;
static volatile uintptr_t gMagicLastArrayCount = 0;
static volatile uint32_t gGodCallbacks = 0;
static volatile uint32_t gGodLocalBypasses = 0;
static volatile uint32_t gGodOtherPlayerPasses = 0;
static volatile uint32_t gGodUnverifiedPasses = 0;

// Verified in the original fps 3.4.0 ARM64 executable:
// PlayerNetwork.GetPhotonView RVA 0x13A9964 (self -> PhotonView),
// PhotonView.ownerId at +0x20,
// PhotonNetwork.get_player RVA 0x13CABF0 (PhotonPlayer),
// PhotonPlayer.ID at +0x10.
static bool OGSIsDamageToLocalPlayer(void *playerNetwork, bool *verified) {
    if (verified) *verified = false;
    if (!playerNetwork || (uintptr_t)playerNetwork < 0x100000000ULL) return false;
    void *klass = NULL;
    if (!OGSReadPointer((uintptr_t)playerNetwork, &klass)) return false;

    uintptr_t localGetter = OGSResolveRVA(gOffsets.rvaGetLocalPlayer);
    uintptr_t viewGetter = OGSResolveRVA(0x13A9964);
    if (!localGetter || !viewGetter) return false;

    void *localPhotonPlayer = ((Object0Fn)localGetter)(NULL);
    if (!localPhotonPlayer) return false;
    int32_t localActorID = 0;
    if (!OGSReadMemory((uintptr_t)localPhotonPlayer + 0x10, &localActorID, sizeof(localActorID)) ||
        localActorID <= 0) return false;

    // Use the same cached/getter PhotonView that DamageRemote itself uses.
    void *photonView = ((void *(*)(void *, const void *))viewGetter)(playerNetwork, NULL);
    if (!photonView) return false;
    int32_t ownerActorID = 0;
    if (!OGSReadMemory((uintptr_t)photonView + 0x20, &ownerActorID, sizeof(ownerActorID)) ||
        ownerActorID <= 0) return false;
    if (verified) *verified = true;
    return localActorID == ownerActorID;
}

// RVA 0x137CF70 constructs an Int32[3] with damage at +0x20.
// DamageRemote calls Abs(int32) on negative incoming damage values.
static void OGSBridgeOutgoingDamage(void *self, void *values, const void *method) {
    __atomic_fetch_add(&gMagicCallbacks, 1u, __ATOMIC_RELAXED);
    if (values && __atomic_load_n(&gOGS.magicBulletOn, __ATOMIC_ACQUIRE)) {
        uintptr_t a = (uintptr_t)values;
        uintptr_t n = 0;
        int32_t damage = 0;
        bool hasCount = OGSReadMemory(a + 0x18, &n, sizeof(n));
        if (hasCount) __atomic_store_n(&gMagicLastArrayCount, n, __ATOMIC_RELAXED);
        if (hasCount && n == 3 &&
            OGSReadMemory(a + 0x20, &damage, sizeof(damage))) {
            __atomic_fetch_add(&gMagicArrayReads, 1u, __ATOMIC_RELAXED);
            __atomic_store_n(&gMagicLastOriginalDamage, damage, __ATOMIC_RELAXED);
            if (damage < 0 && damage > -10000 &&
                OGSIsWritableMappedSlot(a + 0x20)) {
                __atomic_store_n((int32_t *)(a + 0x20), -50000, __ATOMIC_RELEASE);
                __atomic_fetch_add(&gMagicMutations, 1u, __ATOMIC_RELAXED);
            }
        }
    }
    if (orig_ApplyDamage) orig_ApplyDamage(self, values, method);
}

static void OGSBridgeIncomingDamage(void *self, void *values, int32_t killerID, const void *method) {
    __atomic_fetch_add(&gGodCallbacks, 1u, __ATOMIC_RELAXED);
    if (self && __atomic_load_n(&gOGS.godModeOn, __ATOMIC_ACQUIRE)) {
        bool verified = false;
        bool isLocalOwner = OGSIsDamageToLocalPlayer(self, &verified);
        if (verified && isLocalOwner) {
            __atomic_fetch_add(&gGodLocalBypasses, 1u, __ATOMIC_RELAXED);
            return;
        }
        if (verified) __atomic_fetch_add(&gGodOtherPlayerPasses, 1u, __ATOMIC_RELAXED);
        else __atomic_fetch_add(&gGodUnverifiedPasses, 1u, __ATOMIC_RELAXED);
    }
    if (orig_DamageRemote) orig_DamageRemote(self, values, killerID, method);
}

static volatile uint64_t gOGSCashHookCalls = 0;
static volatile uint64_t gOGSChatHookCalls = 0;
static volatile uint64_t gOGSNetworkEvents = 0;
static volatile uint64_t gOGSMasterSwitchEvents = 0;
// Stage27: distinguish local LeaveRoom attempts, suppressed attempts,
// and separate Unity OnDisconnectedFromPhoton notifications.
static volatile uint32_t gOGSLeaveRoomHookEntries = 0;
static volatile uint32_t gOGSLeaveRoomBlocked = 0;
static volatile uint32_t gOGSLeaveRoomForwarded = 0;
static volatile uint32_t gOGSDemoLeaveEntries = 0;
static volatile uint32_t gOGSDemoLeaveBlocked = 0;
static volatile uint32_t gOGSDemoLeaveForwarded = 0;
static volatile uint32_t gOGSWorkerPhotonDisconnectNotices = 0;
static volatile uint32_t gOGSObservedRoomDisappearances = 0;
// Stage24: callback entries are NOT unique transfers. Index 5 = GameLogic.
static volatile uint64_t gOGSMasterReceiverEntries[6] = {0};
// Index 6 = PhotonNetwork.LeaveRoom, 7 = WorkerInGame.OnDisconnectedFromPhoton.
static volatile uint32_t gOGSMasterCacheStatus[8] = {0};
static volatile uint32_t gOGSMasterCacheRounds = 0;
static volatile uint64_t gOGSMasterRepairFrameTicks = 0;
static volatile int32_t gOGSHostMonitorOn = 1;
// Photon network event diagnostics. Defined before hook_OnEvent uses them.
static volatile uint32_t gOGSEventCodes[256] = {0};
static volatile uint32_t gOGSEventCodeReadFailures = 0;
static volatile uint32_t gOGSLastEventCode = 0;
// Observations inside the already-active Photon event callback.
// These are not proof that an incoming packet requested the switch.
static volatile uint32_t gOGSInlineMasterObservations = 0;
static volatile uint32_t gOGSInlineMasterReadFailures = 0;
static volatile uint32_t gOGSInlineMasterTransitions = 0;
static volatile uint32_t gOGSInlineMasterChangeCode = 0;
static volatile int32_t gOGSInlineMasterFrom = 0;
static volatile int32_t gOGSInlineMasterTo = 0;
// Diagnostic-only bounded timeline of incoming codes (no packet payloads).
#define OGS_NET_TRAIL_CAPACITY 16
static uint8_t gOGSNetTrailCodes[OGS_NET_TRAIL_CAPACITY] = {0};
static double gOGSNetTrailTimes[OGS_NET_TRAIL_CAPACITY] = {0};
static uint64_t gOGSNetTrailWrites = 0;
static char gOGSLastTransitionEventTrail[192] = {0}; // guarded by gStateLock

// Stage 6: non-invasive pre/post callback snapshot. Pure Mach VM reads:
// no Photon methods, memory writes, or actor/room enumeration.
static int32_t OGSReadMasterForEventObservation(void) {
    uintptr_t typeSlot = OGSResolveRVA(RVA_PHOTON_NET_TYPEINFO);
    void *typeInfo = NULL, *fields = NULL, *netPeer = NULL;
    uintptr_t room = 0;
    int32_t actor = 0;
    if (!typeSlot ||
        !OGSReadPointer(typeSlot, &typeInfo) ||
        !OGSReadPointer((uintptr_t)typeInfo + 0xB8, &fields) ||
        !OGSReadPointer((uintptr_t)fields + 0x10, &netPeer) ||
        !OGSReadMemory((uintptr_t)netPeer + 0x158, &room, sizeof(room)) ||
        room < 0x100000000ULL ||
        !OGSReadMemory(room + 0x48, &actor, sizeof(actor)) ||
        actor <= 0 || actor >= 1000000) {
        return 0;
    }
    return actor;
}


/* Stage 13: one manual request, consumed on Photon callback.
 * Never reuse managed player pointers previously observed by UIKit. */
static void OGSProcessManualKickOnEvent(void) {
    if (!__atomic_load_n(&gOGSManualKickPending, __ATOMIC_ACQUIRE)) return;
    uintptr_t wantedRoom = 0;
    int32_t wantedActor = 0;
    double queuedAt = 0.;
    os_unfair_lock_lock(&gStateLock);
    if (__atomic_exchange_n(&gOGSManualKickPending, 0u, __ATOMIC_ACQ_REL)) {
        wantedRoom = gOGSManualKickRoom;
        wantedActor = gOGSManualKickActor;
        queuedAt = gOGSManualKickQueuedAt;
    }
    os_unfair_lock_unlock(&gStateLock);
    if (wantedRoom == 0 || wantedActor <= 0) return;
    if (CFAbsoluteTimeGetCurrent() - queuedAt > 12.) {
        __atomic_fetch_add(&gOGSManualKickExpired, 1u, __ATOMIC_RELAXED);
        return;
    }
    void *netPeer = OGSGetNetworkingPeerSafe();
    uintptr_t room = 0, others = 0, local = 0;
    int32_t me = 0, master = 0;
    if (!netPeer ||
        !OGSReadMemory((uintptr_t)netPeer + 0x158, &room, sizeof(room)) ||
        !OGSReadMemory((uintptr_t)netPeer + 0x160, &local, sizeof(local)) ||
        !OGSReadMemory((uintptr_t)netPeer + 0x1B0, &others, sizeof(others)) ||
        room != wantedRoom || others < 0x100000000ULL ||
        local < 0x100000000ULL ||
        !OGSReadMemory(local + 0x10, &me, sizeof(me)) ||
        !OGSReadMemory(room + 0x48, &master, sizeof(master)) ||
        master != me || me <= 0 || wantedActor == me) {
        __atomic_fetch_add(&gOGSManualKickRejected, 1u, __ATOMIC_RELAXED);
        return;
    }
    uintptr_t count = 0;
    if (!OGSReadMemory(others + 0x18, &count, sizeof(count)) ||
        count > OGS_MAX_PEERS) {
        __atomic_fetch_add(&gOGSManualKickRejected, 1u, __ATOMIC_RELAXED);
        return;
    }
    for (uintptr_t i = 0; i < count; ++i) {
        void *player = NULL;
        int32_t id = 0;
        if (!OGSReadPointer(others + 0x20 + i * sizeof(void *), &player) ||
            !OGSReadMemory((uintptr_t)player + 0x10, &id, sizeof(id)) ||
            id != wantedActor) continue;
        if (OGSKickPeerReal(player, false))
            __atomic_fetch_add(&gOGSManualKickSubmitted, 1u, __ATOMIC_RELAXED);
        else
            __atomic_fetch_add(&gOGSManualKickRejected, 1u, __ATOMIC_RELAXED);
        return;
    }
    __atomic_fetch_add(&gOGSManualKickRejected, 1u, __ATOMIC_RELAXED);
}

// Stage 19: reusable Unity/PUN-thread recovery state machine. A room read or
// local API result is NOT a confirmation of server-side MasterClient ownership.
// The existing shared token bucket remains the only authority for sending.
static void OGSProcessRecoveryOnPhotonCallback(uint32_t observedEventCode,
                                               int32_t masterBefore,
                                               int32_t masterAfter,
                                               bool viaUpdate) {
    // Sample BEFORE this dispatcher submits a new local recovery request.
    // This distinction is essential: the SDK may change local ownership
    // optimistically before the Photon server has accepted any transfer.
    uintptr_t observedRoom = 0;
    int32_t observedActor = 0, observedMaster = 0;
    bool snapshotOK = OGSReadAutoRoom(&observedRoom, &observedActor, &observedMaster);
    if (snapshotOK)
        OGSRecordHostLocalObservation(observedRoom, observedActor, observedMaster,
                                      observedEventCode, viaUpdate);
    // Auto recovery remains strictly opt-in, bound to the original room/actor.
    // Evaluate ownership with a fresh room-bound snapshot on every selected
    // Photon callback, including bounded Update probes during quiet periods.
    if (__atomic_load_n(&gOGSAutoEnabled, __ATOMIC_ACQUIRE)) {
        uintptr_t liveRoom = observedRoom;
        int32_t localID = observedActor, liveMaster = observedMaster;
        if (snapshotOK) {
            bool ready = false, wrongRoom = false;
            double currentTime = CFAbsoluteTimeGetCurrent();
            os_unfair_lock_lock(&gStateLock);
            if (__atomic_load_n(&gOGSAutoEnabled, __ATOMIC_ACQUIRE)) {
                wrongRoom = gOGSAutoRoom != liveRoom ||
                            gOGSAutoOwner != localID;
                if (!wrongRoom) {
                    // Verified ARM64 fps 3.4.0 NetworkingPeer.SetMasterClient
                    // invokes RaiseEvent(208) for master assignment. 253 is
                    // separately retained for room property update correlation.
                    bool masterChangeCode = observedEventCode == 208 ||
                                            observedEventCode == 253;
                    bool lostThisEvent = masterBefore == localID &&
                        masterAfter == liveMaster && masterAfter != localID &&
                        masterBefore != masterAfter && masterChangeCode;
                    // Stage 17: do not miss host loss if the exact 253
                    // transition fell outside our hooked callback. A later
                    // validated room-state read can still detect the loss.
                    bool lostSinceOwned = gOGSAutoSawOwnedMaster && liveMaster != localID;
                    if ((lostThisEvent || lostSinceOwned) &&
                        !__atomic_load_n(&gOGSAutoPendingLoss, __ATOMIC_RELAXED)) {
                        __atomic_store_n(&gOGSAutoPendingLoss, 1u, __ATOMIC_RELEASE);
                        gOGSAutoAttemptedPending = false;
                        if (gOGSAutoLastRequestAt > 0. &&
                            currentTime - gOGSAutoLastRequestAt < kOGSAutoCooldownSeconds) {
                            __atomic_fetch_add(&gOGSAutoCooldown, 1u, __ATOMIC_RELAXED);
                            __atomic_fetch_add(&gOGSAutoDeferredQueued, 1u, __ATOMIC_RELAXED);
                        }
                    }
                    if (liveMaster == localID) {
                        gOGSAutoSawOwnedMaster = true;
                        if (__atomic_exchange_n(&gOGSAutoPendingLoss, 0u, __ATOMIC_ACQ_REL))
                            __atomic_fetch_add(&gOGSAutoDeferredCancelled, 1u, __ATOMIC_RELAXED);
                        gOGSAutoAttemptedPending = false;
                    } else if (__atomic_load_n(&gOGSAutoPendingLoss, __ATOMIC_ACQUIRE)) {
                        // A confirmed local loss can trigger a response in
                        // this same Photon callback; only the shared bounded
                        // limiter decides when another request is permitted.
                        // The pending loss stays queued during token refill.
                        // An explicit manual request takes precedence on
                        // this callback, using the SAME bounded quota.
                        // Do not consume its slot and discard the tap.
                        if (!__atomic_load_n(&gOGSManualRecoveryPending, __ATOMIC_ACQUIRE) &&
                            OGSReserveMasterRequestLocked(liveRoom, localID, currentTime)) {
                            ready = true;
                            if (gOGSAutoAttemptedPending)
                                __atomic_fetch_add(&gOGSAutoRetriesWhileLost, 1u,
                                                   __ATOMIC_RELAXED);
                            gOGSAutoAttemptedPending = true;
                            if (!lostThisEvent)
                                __atomic_fetch_add(&gOGSAutoDeferredExecuted, 1u,
                                                   __ATOMIC_RELAXED);
                        }
                    }
                }
            }
            os_unfair_lock_unlock(&gStateLock);
            if (wrongRoom) OGSDisarmAutoRoom();
            if (ready && __atomic_load_n(&gOGSAutoEnabled, __ATOMIC_ACQUIRE)) {
                __atomic_fetch_add(&gOGSAutoAttempts, 1u, __ATOMIC_RELAXED);
                if (OGSRequestLocalMasterOnceOnEvent(liveRoom, localID))
                    __atomic_fetch_add(&gOGSAutoAccepted, 1u, __ATOMIC_RELAXED);
                else
                    __atomic_fetch_add(&gOGSAutoFailed, 1u, __ATOMIC_RELAXED);
            }
        } else {
            __atomic_fetch_add(&gOGSAutoGuarded, 1u, __ATOMIC_RELAXED);
        }
    }
    // One manual request uses the same bounded quota as auto.
    // A user tap takes precedence over auto in this callback, but cannot
    // override any cooldown, room validity check or request budget.
    if (__atomic_load_n(&gOGSManualRecoveryPending, __ATOMIC_ACQUIRE)) {
        uintptr_t liveRoom = observedRoom;
        int32_t localID = observedActor, liveMaster = observedMaster;
        bool readable = snapshotOK;
        bool permitted = false;
        double checkedAt = CFAbsoluteTimeGetCurrent();
        os_unfair_lock_lock(&gStateLock);
        if (__atomic_load_n(&gOGSManualRecoveryPending, __ATOMIC_ACQUIRE)) {
            double age = checkedAt - gOGSManualRecoveryQueuedAt;
            if (gOGSManualRecoveryQueuedAt <= 0. || age > 12.0) {
                __atomic_store_n(&gOGSManualRecoveryPending, 0u, __ATOMIC_RELEASE);
                __atomic_fetch_add(&gOGSManualRecoveryExpired, 1u, __ATOMIC_RELAXED);
            } else if (readable &&
                       (liveRoom != gOGSManualRecoveryRoom ||
                        localID != gOGSManualRecoveryActor ||
                        liveMaster == localID)) {
                // Do not reuse a tap after switching rooms or actor IDs.
                // Local ownership is only an observation, not server proof.
                __atomic_store_n(&gOGSManualRecoveryPending, 0u, __ATOMIC_RELEASE);
                __atomic_fetch_add(&gOGSManualRecoverySkipped, 1u, __ATOMIC_RELAXED);
            } else if (readable &&
                       OGSReserveMasterRequestLocked(liveRoom, localID, checkedAt)) {
                __atomic_store_n(&gOGSManualRecoveryPending, 0u, __ATOMIC_RELEASE);
                permitted = true;
            } else if (!gOGSManualRecoveryDeferredCounted) {
                gOGSManualRecoveryDeferredCounted = true;
                __atomic_fetch_add(&gOGSManualRecoveryDeferred, 1u, __ATOMIC_RELAXED);
            }
        }
        os_unfair_lock_unlock(&gStateLock);
        if (permitted) {
            __atomic_fetch_add(&gOGSManualRecoveryAttempts, 1u, __ATOMIC_RELAXED);
            if (OGSRequestLocalMasterOnceOnEvent(liveRoom, localID))
                __atomic_fetch_add(&gOGSManualRecoveryAccepted, 1u, __ATOMIC_RELAXED);
            else
                __atomic_fetch_add(&gOGSManualRecoveryFailed, 1u, __ATOMIC_RELAXED);
        }
    }
}

static void OGSRepairMasterReceiverCaches(void);

// Executed on the game's Unity/PUN Update thread, never from the UIKit
// menu timer. Makes standalone room privacy possible with zero other players.
static void hook_PhotonHandlerUpdate(void *self, void *method) {
    // Count entry before the original to distinguish hook reachability
    // from a non-returning/exceptional original managed call.
    __atomic_fetch_add(&gOGSPhotonHandlerUpdateCalls, 1ULL, __ATOMIC_RELAXED);
    if (orig_PhotonHandlerUpdate)
        orig_PhotonHandlerUpdate(self, method);
    __atomic_fetch_add(&gOGSPhotonHandlerUpdateExitCalls, 1ULL, __ATOMIC_RELAXED);
    // Late-loaded scene classes may not exist during the first installation.
    // Repair only once per ~120 reached Update frames, never on each frame.
    uint64_t repairFrame = __atomic_add_fetch(&gOGSMasterRepairFrameTicks,
                                               1ULL, __ATOMIC_RELAXED);
    if (repairFrame == 1ULL || repairFrame % 120ULL == 0ULL)
        OGSRepairMasterReceiverCaches();
    // Both callbacks may run on the same frame. Pending actions are atomically
    // consumed only once; kick executes before optional room close.
    if (__atomic_load_n(&gOGSManualKickPending, __ATOMIC_ACQUIRE))
        OGSProcessManualKickOnEvent();
    OGSProcessClosedGuardOnPhotonCallback();
    if (__atomic_load_n(&gOGSPrivacyPending, __ATOMIC_ACQUIRE))
        OGSProcessRoomPrivacyOnEvent();

    // Still service pending intents when the room has no incoming events
    // or when event 203 is deliberately filtered by this client.
    if (__atomic_load_n(&gOGSAutoEnabled, __ATOMIC_ACQUIRE) ||
        __atomic_load_n(&gOGSManualRecoveryPending, __ATOMIC_ACQUIRE)) {
        bool due = false;
        double tick = CFAbsoluteTimeGetCurrent();
        os_unfair_lock_lock(&gStateLock);
        if (gOGSRecoveryLastUpdateProbeAt <= 0. ||
            tick - gOGSRecoveryLastUpdateProbeAt >= 0.12) {
            gOGSRecoveryLastUpdateProbeAt = tick;
            due = true;
        }
        os_unfair_lock_unlock(&gStateLock);
        if (due) {
            __atomic_fetch_add(&gOGSRecoveryUpdateProbes, 1u, __ATOMIC_RELAXED);
            OGSProcessRecoveryOnPhotonCallback(0u, 0, 0, true);
        }
    }
}

// Read-only response telemetry. OpCode 252 can represent MANY room-property
// updates; it must NOT be attributed to a SetMasterClient request on its own.
static void hook_OnOperationResponse(void *self, void *response, void *method) {
    __atomic_fetch_add(&gOGSResponseEntryCalls, 1ULL, __ATOMIC_RELAXED);
    if (response) {
        uint8_t opCode = 0;
        if (OGSReadMemory((uintptr_t)response + 0x10, &opCode, sizeof(opCode)) &&
            opCode == 252) {
            int16_t returnCode = 0;
            __atomic_fetch_add(&gOGSSetProps252Replies, 1ULL, __ATOMIC_RELAXED);
            if (OGSReadMemory((uintptr_t)response + 0x12, &returnCode, sizeof(returnCode))) {
                __atomic_store_n(&gOGSSetProps252LastReturnCode, (int32_t)returnCode,
                                 __ATOMIC_RELEASE);
                if (returnCode == 0)
                    __atomic_fetch_add(&gOGSSetProps252ZeroReturn, 1ULL, __ATOMIC_RELAXED);
                else
                    __atomic_fetch_add(&gOGSSetProps252NonzeroReturn, 1ULL, __ATOMIC_RELAXED);
            } else {
                __atomic_fetch_add(&gOGSSetProps252ParseErrors, 1u, __ATOMIC_RELAXED);
            }
        }
    }
    OnEventFn original = __atomic_load_n(&orig_OnOperationResponse, __ATOMIC_ACQUIRE);
    if (original) original(self, response, method);
    __atomic_fetch_add(&gOGSResponseExitCalls, 1ULL, __ATOMIC_RELAXED);
}

static void hook_OnEvent(void *self, void *eventData, void *method) {
    __atomic_fetch_add(&gOGSNetworkEvents, 1ULL, __ATOMIC_RELAXED);
    double now = CFAbsoluteTimeGetCurrent();
    uint32_t observedEventCode = 0; // zero = unknown / unreadable
    // No original Unity/Photon calls from the UIKit timer.

    // حماية مطلقة 100%: حظر حزمة الطرد (203 CloseConnection) فوراً ودائماً تحت أي ظرف
    if (eventData && (uintptr_t)eventData >= 0x100000000ULL) {
        uint8_t eventCode = 0;
        if (OGSReadMemory((uintptr_t)eventData + 0x10, &eventCode, sizeof(uint8_t))) {
            // Diagnostics only: never mutate packets or call Unity from here.
            __atomic_fetch_add(&gOGSEventCodes[eventCode], 1u, __ATOMIC_RELAXED);
            __atomic_store_n(&gOGSLastEventCode, (uint32_t)eventCode, __ATOMIC_RELEASE);
            observedEventCode = (uint32_t)eventCode;
            os_unfair_lock_lock(&gStateLock);
            size_t ringSlot = (size_t)(gOGSNetTrailWrites % OGS_NET_TRAIL_CAPACITY);
            gOGSNetTrailCodes[ringSlot] = eventCode;
            gOGSNetTrailTimes[ringSlot] = now;
            ++gOGSNetTrailWrites;
            os_unfair_lock_unlock(&gStateLock);
            if (eventCode == 203) {
                double lastRecoveryAt = 0.0;
                os_unfair_lock_lock(&gStateLock);
                gOGS.lastThreatTime = now;
                lastRecoveryAt = gOGSLastRecoveryAttemptAt;
                os_unfair_lock_unlock(&gStateLock);
                __atomic_fetch_add(&gOGSFilteredEvent203, 1u, __ATOMIC_RELAXED);
                if (lastRecoveryAt > 0.0 && now >= lastRecoveryAt &&
                    now - lastRecoveryAt <= 5.0) {
                    __atomic_fetch_add(&gOGSEvent203NearRecovery, 1u, __ATOMIC_RELAXED);
                    __atomic_store_n(&gOGSLastEvent203ProximityMs,
                                     (uint32_t)((now - lastRecoveryAt) * 1000.0),
                                     __ATOMIC_RELEASE);
                }
                // Existing local filter retained, with explicit telemetry.
                // It cannot override Photon server-side removal.
                __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
                return;
            }
            if (eventCode == 208 || eventCode == 253) {
                os_unfair_lock_lock(&gStateLock);
                gOGS.lastThreatTime = now;
                os_unfair_lock_unlock(&gStateLock);
            }
        } else {
            __atomic_fetch_add(&gOGSEventCodeReadFailures, 1u, __ATOMIC_RELAXED);
        }
    }

    // Compare room MasterClient only across original dispatch execution.
    // This never tries to restore master or suppress the event.
    int32_t masterBefore = OGSReadMasterForEventObservation();
    __atomic_fetch_add(&gOGS.insideNetworkEvent, 1, __ATOMIC_ACQ_REL);
    if (orig_OnEvent) {
        orig_OnEvent(self, eventData, method);
    }
    __atomic_fetch_sub(&gOGS.insideNetworkEvent, 1, __ATOMIC_ACQ_REL);
    int32_t masterAfter = OGSReadMasterForEventObservation();
    if (masterBefore > 0 && masterAfter > 0) {
        __atomic_fetch_add(&gOGSInlineMasterObservations, 1u, __ATOMIC_RELAXED);
        if (masterBefore != masterAfter) {
            __atomic_store_n(&gOGSInlineMasterFrom, masterBefore, __ATOMIC_RELEASE);
            __atomic_store_n(&gOGSInlineMasterTo, masterAfter, __ATOMIC_RELEASE);
            __atomic_store_n(&gOGSInlineMasterChangeCode, observedEventCode, __ATOMIC_RELEASE);
            __atomic_fetch_add(&gOGSInlineMasterTransitions, 1u, __ATOMIC_RELAXED);
        }
    } else {
        __atomic_fetch_add(&gOGSInlineMasterReadFailures, 1u, __ATOMIC_RELAXED);
    }

    // Stage 19: a single rate-limited recovery dispatcher for both Photon
    // event dispatch and PhotonHandler.Update (main-thread, non-UIKit).
    // This also survives locally filtered event 203 and quiet rooms.
    __atomic_fetch_add(&gOGSRecoveryEventProbes, 1u, __ATOMIC_RELAXED);
    OGSProcessRecoveryOnPhotonCallback(observedEventCode, masterBefore, masterAfter, false);

    // Execute queued room actions after the original Photon callback.
    OGSProcessManualKickOnEvent();
    OGSProcessRoomPrivacyOnEvent();
    if (__atomic_load_n(&gOGS.speedDirty, __ATOMIC_ACQUIRE))
        OGSProcessSpeed();


}

static bool hook_LeaveRoom(int32_t becomeInactive, void *method) {
    __atomic_fetch_add(&gOGSLeaveRoomHookEntries, 1u, __ATOMIC_RELAXED);
    double now = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&gStateLock);
    double enterTime = gOGS.roomEnterTime;
    double threatTime = gOGS.lastThreatTime;
    os_unfair_lock_unlock(&gStateLock);

    bool inRoomNow = __atomic_load_n(&gOGS.inRoom, __ATOMIC_ACQUIRE);
    bool settled = (inRoomNow && enterTime > 0.0 && (now - enterTime) > 0.3);
    bool insideNet = (__atomic_load_n(&gOGS.insideNetworkEvent, __ATOMIC_ACQUIRE) > 0);
    bool recentThreat = (threatTime > 0.0 && (now - threatTime) < 3.5);

    if (inRoomNow && (gOGS.antiKickHardLock || insideNet || (settled && recentThreat))) {
        __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
        __atomic_fetch_add(&gOGSLeaveRoomBlocked, 1u, __ATOMIC_RELAXED);
        return false;
    }
    __atomic_fetch_add(&gOGSLeaveRoomForwarded, 1u, __ATOMIC_RELAXED);
    return orig_LeaveRoom ? orig_LeaveRoom(becomeInactive, method) : false;
}

static void hook_Type4995LeaveRoom(void *self, void *method) {
    // Verified in fps 3.4.0: DemoAnimator.GameManager.LeaveRoom(), not
    // PhotonNetwork.LeaveRoom. Its entry count is only contextual.
    __atomic_fetch_add(&gOGSDemoLeaveEntries, 1u, __ATOMIC_RELAXED);
    double now = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&gStateLock);
    double enterTime = gOGS.roomEnterTime;
    double threatTime = gOGS.lastThreatTime;
    os_unfair_lock_unlock(&gStateLock);

    bool inRoomNow = __atomic_load_n(&gOGS.inRoom, __ATOMIC_ACQUIRE);
    bool settled = (inRoomNow && enterTime > 0.0 && (now - enterTime) > 0.3);
    bool insideNet = (__atomic_load_n(&gOGS.insideNetworkEvent, __ATOMIC_ACQUIRE) > 0);
    bool recentThreat = (threatTime > 0.0 && (now - threatTime) < 3.5);

    // This is a game demo helper, not evidence of any Photon server kick.
    if (inRoomNow && (gOGS.antiKickHardLock || insideNet || (settled && recentThreat))) {
        __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
        __atomic_fetch_add(&gOGSDemoLeaveBlocked, 1u, __ATOMIC_RELAXED);
        return;
    }
    __atomic_fetch_add(&gOGSDemoLeaveForwarded, 1u, __ATOMIC_RELAXED);
    if (orig_Type4995Leave) orig_Type4995Leave(self, method);
}

// Stage 1: do not dereference a peer after the original Photon callback.
// Its managed lifetime may end inside the original callback. The verified
// Unity update path already identifies current ownership from a fresh snapshot.
static void OGSHandleMasterSwitchIntercept(void *newMasterPlayer) {
    (void)newMasterPlayer;
    __atomic_fetch_add(&gOGSMasterSwitchEvents, 1ULL, __ATOMIC_RELAXED);
    double now = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&gStateLock);
    gOGS.lastThreatTime = now;
    double entered = gOGS.roomEnterTime;
    os_unfair_lock_unlock(&gStateLock);
    bool active = __atomic_load_n(&gOGS.inRoom, __ATOMIC_ACQUIRE);
    if (active && entered > 0.0 && (now - entered) > 0.5 &&
        __atomic_load_n(&gOGS.autoHostOn, __ATOMIC_ACQUIRE)) {
        __atomic_store_n(&gOGS.forceHostReq, 1, __ATOMIC_RELEASE);
    }
}

// Count BEFORE the original method; Unity SendMessage receivers can be
// independent, and one property update can invoke multiple receivers.
static void hook_OnMasterSwitched1(void *self, void *p, void *m) {
    __atomic_fetch_add(&gOGSMasterReceiverEntries[0], 1ULL, __ATOMIC_RELAXED);
    auto original = __atomic_load_n(&orig_OnMasterSwitch1, __ATOMIC_ACQUIRE);
    if (original) original(self, p, m);
    OGSHandleMasterSwitchIntercept(p);
}
static void hook_OnMasterSwitched2(void *self, void *p, void *m) {
    __atomic_fetch_add(&gOGSMasterReceiverEntries[1], 1ULL, __ATOMIC_RELAXED);
    auto original = __atomic_load_n(&orig_OnMasterSwitch2, __ATOMIC_ACQUIRE);
    if (original) original(self, p, m);
    OGSHandleMasterSwitchIntercept(p);
}
static void hook_OnMasterSwitched3(void *self, void *p, void *m) {
    __atomic_fetch_add(&gOGSMasterReceiverEntries[2], 1ULL, __ATOMIC_RELAXED);
    auto original = __atomic_load_n(&orig_OnMasterSwitch3, __ATOMIC_ACQUIRE);
    if (original) original(self, p, m);
    OGSHandleMasterSwitchIntercept(p);
}
static void hook_OnMasterSwitched4(void *self, void *p, void *m) {
    __atomic_fetch_add(&gOGSMasterReceiverEntries[3], 1ULL, __ATOMIC_RELAXED);
    auto original = __atomic_load_n(&orig_OnMasterSwitch4, __ATOMIC_ACQUIRE);
    if (original) original(self, p, m);
    OGSHandleMasterSwitchIntercept(p);
}
static void hook_OnMasterSwitched5(void *self, void *p, void *m) {
    __atomic_fetch_add(&gOGSMasterReceiverEntries[4], 1ULL, __ATOMIC_RELAXED);
    auto original = __atomic_load_n(&orig_OnMasterSwitch5, __ATOMIC_ACQUIRE);
    if (original) original(self, p, m);
    OGSHandleMasterSwitchIntercept(p);
}
static void hook_GameLogicMasterSwitch(void *self, void *method) {
    __atomic_fetch_add(&gOGSMasterReceiverEntries[5], 1ULL, __ATOMIC_RELAXED);
    auto original = __atomic_load_n(&orig_GameLogicMasterSwitch, __ATOMIC_ACQUIRE);
    if (original) original(self, method);
    OGSHandleMasterSwitchIntercept(NULL);
}

static void hook_OnPhotonPlayerDisconnected(void *self, void *player, void *method) {
    // This slot is RoomController.OnPhotonPlayerDisconnected, i.e. a REMOTE
    // player's departure, not the local client's disconnected callback.
    if (orig_OnDisconnect) orig_OnDisconnect(self, player, method);
}
static void hook_WorkerInGameDisconnected(void *self, void *method) {
    // Unity notification that THIS client disconnected from Photon.
    // Observation only: forward to original before any room is destroyed.
    __atomic_fetch_add(&gOGSWorkerPhotonDisconnectNotices, 1u,
                       __ATOMIC_RELAXED);
    if (orig_WorkerInGameDisconnected)
        orig_WorkerInGameDisconnected(self, method);
}

static void hook_SendChatRemote(void *self, void *senderStr, void *msgStr, int32_t senderTeam, bool isTeamChat, const void *method) {
    int32_t mode = __atomic_load_n(&gOGS.chatMode, __ATOMIC_ACQUIRE);
    if (mode == 1) return;
    else if (mode == 2) {
        NSString *senderName = OGSReadIl2CppString(senderStr);
        if (senderName.length > 0) {
            NSString *normSender = OGSNormalizeKey(senderName);
            const char *utf8 = normSender.UTF8String;
            if (utf8) {
                os_unfair_lock_lock(&gStateLock);
                snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", utf8);
                gOGS.kickTargetID = -1;
                gOGS.kickRetries = 8;
                os_unfair_lock_unlock(&gStateLock);
                __atomic_store_n(&gOGS.forceHostReq, 1, __ATOMIC_RELEASE);
            }
        }
        return;
    }
    if (orig_SendChatRemote) orig_SendChatRemote(self, senderStr, msgStr, senderTeam, isTeamChat, method);
}

static void hook_ChatUpdate(void *self, void *method) {
    __atomic_fetch_add(&gOGSChatHookCalls, 1ULL, __ATOMIC_RELAXED);
    if (orig_ChatUpdate) orig_ChatUpdate(self, method);
    OGSUnityThreadTick();
}

static void hook_CashUpdate(void *self, void *method) {
    __atomic_fetch_add(&gOGSCashHookCalls, 1ULL, __ATOMIC_RELAXED);
    if (orig_CashUpdate) orig_CashUpdate(self, method);
    OGSUnityThreadTick();
}

// PRE-SIGN bridge only. No DobbyHook, DobbyInstrument or vm_protect.
static bool gOGSDamageHookInstalled[2] = {false, false};
static bool OGSIsExecutableGameAddress(uintptr_t addr) {
    if (addr < 0x100000000ULL || (addr & 3)) return false;
    vm_address_t start = (vm_address_t)addr;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info = {};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(mach_task_self(), &start, &size,
                                    VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info,
                                    &count, &object);
    if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
    return kr == KERN_SUCCESS && start <= (vm_address_t)addr &&
           (uintptr_t)size >= sizeof(uint32_t) &&
           addr-(uintptr_t)start <= (uintptr_t)size-sizeof(uint32_t) &&
           (info.protection & (VM_PROT_READ | VM_PROT_EXECUTE)) ==
           (VM_PROT_READ | VM_PROT_EXECUTE);
}

static bool OGSInstallDamageHookOnDemand(bool godMode) {
    int index = godMode ? 1 : 0;
    if (gOGSDamageHookInstalled[index]) return true;
    uintptr_t base = OGSFindGameImage();
    if (!base) return false;
    uintptr_t entryRVA = godMode ? gOffsets.rvaDamageRemote : gOffsets.rvaApplyDamage;
    uintptr_t stubRVA = godMode ? OGS_GOD_STUB : OGS_MAGIC_STUB;
    uintptr_t slotRVA = godMode ? OGS_GOD_SLOT : OGS_MAGIC_SLOT;
    uintptr_t originalRVA = godMode ? OGS_GOD_ORIGINAL : OGS_MAGIC_ORIGINAL;
    uintptr_t entry = base + entryRVA, stub = base + stubRVA;
    uintptr_t slot = base + slotRVA, trampoline = base + originalRVA;
    if (!OGSIsExecutableGameAddress(entry) ||
        !OGSIsExecutableGameAddress(stub) ||
        !OGSIsWritableMappedSlot(slot)) return false;
    int64_t distance = (int64_t)stubRVA - (int64_t)entryRVA;
    if ((distance & 3) || distance <= -(1LL << 27) || distance >= (1LL << 27)) return false;
    uint32_t expectBranch = 0x14000000u | (uint32_t)((distance / 4) & 0x03ffffffu);
    uint32_t branch = 0, adrp = 0, ldr = 0, br = 0, prolog = 0;
    if (!OGSReadMemory(entry, &branch, 4) ||
        !OGSReadMemory(stub, &adrp, 4) ||
        !OGSReadMemory(stub + 8, &ldr, 4) ||
        !OGSReadMemory(stub + 16, &br, 4) ||
        !OGSReadMemory(trampoline, &prolog, 4) ||
        branch != expectBranch || adrp != 0x90014090u ||
        ldr != 0xF9400210u || br != 0xD61F0200u ||
        prolog != (godMode ? 0xD10183FFu : 0xD10103FFu)) {
        NSLog(@"[OGS] IPA not prepared with verified fps 3.4.0 bridge (%d)", index);
        return false;
    }
    uintptr_t old = 0;
    if (!OGSReadMemory(slot, &old, sizeof(old))) return false;
    uintptr_t callback = godMode ? (uintptr_t)&OGSBridgeIncomingDamage :
                                    (uintptr_t)&OGSBridgeOutgoingDamage;
    if (old && old != callback) return false;
    if (godMode) orig_DamageRemote = (DamageRemoteFn)trampoline;
    else orig_ApplyDamage = (ApplyDamageFn)trampoline;
    __atomic_store_n((uintptr_t *)slot, callback, __ATOMIC_RELEASE);
    gOGSDamageHookInstalled[index] = true;
    NSLog(@"[OGS] Offline-prepared bridge registered safely: %d", index);
    return true;
}

static bool OGSIsWritableMappedSlot(uintptr_t address) {
    if (address < 0x100000000ULL || (address & (sizeof(void *) - 1))) return false;
    vm_address_t regionAddress = (vm_address_t)address;
    vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info = {};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(mach_task_self(), &regionAddress, &regionSize,
                                    VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &count, &objectName);
    if (objectName != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), objectName);
    if (kr != KERN_SUCCESS || regionAddress > (vm_address_t)address) return false;
    if ((uintptr_t)regionSize < sizeof(void *) ||
        address - (uintptr_t)regionAddress > (uintptr_t)regionSize - sizeof(void *)) return false;
    return (info.protection & (VM_PROT_READ | VM_PROT_WRITE)) ==
           (VM_PROT_READ | VM_PROT_WRITE);
}

static bool OGSInstallPointerSlotHook(uintptr_t rva, void *replacement, void **outOriginal) {
    // Synchronize re-entrant installer calls (UIKit retry and delayed setup).
    // Crucially publish the original callback BEFORE the replacement pointer
    // becomes callable by another thread.
    os_unfair_lock_lock(&gHookInstallLock);
    bool installed = false;
    do {
        uintptr_t addr = OGSResolveRVA(rva);
        if (!addr || !replacement || !outOriginal || !OGSIsWritableMappedSlot(addr))
            break;
        void *prior = NULL;
        if (!OGSReadPointer(addr, &prior)) break;
        void *storedOriginal = __atomic_load_n(outOriginal, __ATOMIC_ACQUIRE);
        if (prior == replacement) {
            installed = storedOriginal != NULL &&
                        OGSIsExecutableGameAddress((uintptr_t)storedOriginal);
            break;
        }
        if (!OGSIsExecutableGameAddress((uintptr_t)prior)) break;
        // Never overwrite a previously captured original with another hook
        // or an unrelated target; fail safely instead.
        if (storedOriginal && storedOriginal != prior) break;
        __atomic_store_n(outOriginal, prior, __ATOMIC_RELEASE);
        uintptr_t expected = (uintptr_t)prior;
        installed = __atomic_compare_exchange_n((uintptr_t *)addr, &expected,
            (uintptr_t)replacement, false, __ATOMIC_RELEASE, __ATOMIC_RELAXED);
    } while (false);
    os_unfair_lock_unlock(&gHookInstallLock);
    return installed;
}

// Stage23: repair only PhotonHandler.Update MethodInfo methodPointer after
// matching type, declaration address, token, ABI arity and expected original.
// Unity's cached MethodInfo may bypass edits to global methodPointers.
// Repeated calls are idempotent; no Unity methods are invoked from this helper.
static void OGSRepairPhotonHandlerUpdateCache(void) {
    __atomic_fetch_add(&gOGSCachedUpdateAttempts, 1u, __ATOMIC_RELAXED);
    static const uint32_t kTypeIndex = 4880u, kDefinitionIndex = 31414u;
    static const uint32_t kExpectedToken = 0x06000460u;
    static const uintptr_t kEntryRVA = 0x013C8400u;
    uintptr_t cache = 0, klass = 0, methods = 0, metadata = 0, header = 0;
    uint32_t methodsOffset = 0;
    uint16_t count = 0;
    if (!OGSReadMemory(OGSResolveRVA(0x02813CE8), &cache, sizeof(cache)) || !cache ||
        !OGSReadMemory(cache + (uintptr_t)kTypeIndex * sizeof(void *),
                       &klass, sizeof(klass)) || !klass ||
        !OGSReadMemory(klass + 0x98, &methods, sizeof(methods)) || !methods ||
        !OGSReadMemory(klass + 0x110, &count, sizeof(count)) ||
        count == 0 || count > 1024 ||
        !OGSReadMemory(OGSResolveRVA(0x02813CD0), &metadata, sizeof(metadata)) || !metadata ||
        !OGSReadMemory(OGSResolveRVA(0x02813CD8), &header, sizeof(header)) || !header ||
        !OGSReadMemory(header + 0x30, &methodsOffset, sizeof(methodsOffset))) {
        __atomic_store_n(&gOGSCachedUpdateStatus, 3u, __ATOMIC_RELEASE);
        return;
    }
    uintptr_t expectedDefinition = metadata + methodsOffset +
        (uintptr_t)kDefinitionIndex * 52u;
    uintptr_t expectedEntry = OGSResolveRVA(kEntryRVA);
    if (!expectedEntry) {
        __atomic_store_n(&gOGSCachedUpdateStatus, 5u, __ATOMIC_RELEASE);
        return;
    }
    for (uint16_t i = 0; i < count; ++i) {
        uintptr_t info = 0, owner = 0, definition = 0;
        uint32_t token = 0;
        uint8_t arity = 255;
        if (!OGSReadMemory(methods + (uintptr_t)i * sizeof(void *), &info, sizeof(info)) ||
            !info ||
            !OGSReadMemory(info + 0x18, &owner, sizeof(owner)) ||
            !OGSReadMemory(info + 0x30, &definition, sizeof(definition)) ||
            !OGSReadMemory(info + 0x40, &token, sizeof(token)) ||
            !OGSReadMemory(info + 0x4A, &arity, sizeof(arity)) ||
            owner != klass || definition != expectedDefinition ||
            token != kExpectedToken || arity != 0) continue;
        __atomic_fetch_add(&gOGSCachedUpdateEntryMatched, 1u, __ATOMIC_RELAXED);
        if (!OGSIsWritableMappedSlot(info)) {
            __atomic_store_n(&gOGSCachedUpdateStatus, 5u, __ATOMIC_RELEASE);
            return;
        }
        os_unfair_lock_lock(&gHookInstallLock);
        void *prior = __atomic_load_n((void **)info, __ATOMIC_ACQUIRE);
        __atomic_store_n(&gOGSCachedUpdateObservedEntry, (uintptr_t)prior,
                         __ATOMIC_RELEASE);
        void *original = __atomic_load_n((void **)&orig_PhotonHandlerUpdate,
                                         __ATOMIC_ACQUIRE);
        if (prior == (void *)&hook_PhotonHandlerUpdate &&
            original == (void *)expectedEntry) {
            __atomic_store_n(&gOGSCachedUpdateStatus, 1u, __ATOMIC_RELEASE);
        } else if (prior == (void *)expectedEntry &&
                   original == (void *)expectedEntry) {
            void *expected = prior;
            bool ok = __atomic_compare_exchange_n((void **)info, &expected,
                  (void *)&hook_PhotonHandlerUpdate, false,
                  __ATOMIC_RELEASE, __ATOMIC_RELAXED);
            __atomic_store_n(&gOGSCachedUpdateStatus,
                             ok ? 2u : 6u, __ATOMIC_RELEASE);
        } else {
            __atomic_store_n(&gOGSCachedUpdateStatus, 6u, __ATOMIC_RELEASE);
        }
        os_unfair_lock_unlock(&gHookInstallLock);
        return;
    }
    __atomic_store_n(&gOGSCachedUpdateStatus, 4u, __ATOMIC_RELEASE);
}

// Stage24: six verified OnMasterClientSwitched receivers; five have a
// PhotonPlayer argument, GameLogic has none. Class.methods may be lazily
// instantiated, so Update retries bounded scans. Never invoke a Unity API
// or change Room.MasterClient fields here.
static void OGSRepairMasterReceiverCacheOne(uint32_t index, uint32_t typeIndex,
        uint32_t definitionIndex, uint32_t token, uint8_t parameterCount,
        uintptr_t entryRVA, void *replacement, void **outOriginal) {
    uint32_t status = 3u; // cache unavailable / class not yet initialized
    uintptr_t cache = 0, klass = 0, methods = 0, metadata = 0, header = 0;
    uint16_t count = 0;
    uint32_t methodsOffset = 0;
    if (!OGSReadMemory(OGSResolveRVA(0x02813CE8), &cache, sizeof(cache)) ||
        !cache ||
        !OGSReadMemory(cache + (uintptr_t)typeIndex * sizeof(void *),
                       &klass, sizeof(klass)) || !klass ||
        !OGSReadMemory(klass + 0x98, &methods, sizeof(methods)) || !methods ||
        !OGSReadMemory(klass + 0x110, &count, sizeof(count)) ||
        count == 0 || count > 1024 ||
        !OGSReadMemory(OGSResolveRVA(0x02813CD0), &metadata, sizeof(metadata)) ||
        !metadata ||
        !OGSReadMemory(OGSResolveRVA(0x02813CD8), &header, sizeof(header)) ||
        !header ||
        !OGSReadMemory(header + 0x30, &methodsOffset, sizeof(methodsOffset))) {
        __atomic_store_n(&gOGSMasterCacheStatus[index], status, __ATOMIC_RELEASE);
        return;
    }
    uintptr_t expectedEntry = OGSResolveRVA(entryRVA);
    uintptr_t expectedDefinition = metadata + methodsOffset +
                                   (uintptr_t)definitionIndex * 52u;
    if (!expectedEntry) {
        status = 5u;
    } else {
        status = 4u; // initialized, matching MethodInfo not found
        for (uint16_t i = 0; i < count; ++i) {
            uintptr_t info = 0, owner = 0, definition = 0;
            uint32_t foundToken = 0;
            uint8_t foundCount = 255;
            if (!OGSReadMemory(methods + (uintptr_t)i * sizeof(void *),
                               &info, sizeof(info)) || !info ||
                !OGSReadMemory(info + 0x18, &owner, sizeof(owner)) ||
                !OGSReadMemory(info + 0x30, &definition, sizeof(definition)) ||
                !OGSReadMemory(info + 0x40, &foundToken, sizeof(foundToken)) ||
                !OGSReadMemory(info + 0x4A, &foundCount, sizeof(foundCount)) ||
                owner != klass || definition != expectedDefinition ||
                foundToken != token || foundCount != parameterCount) continue;
            status = 5u; // matched identity, check writable mapping
            if (!OGSIsWritableMappedSlot(info)) break;
            os_unfair_lock_lock(&gHookInstallLock);
            void *prior = __atomic_load_n((void **)info, __ATOMIC_ACQUIRE);
            void *original = __atomic_load_n(outOriginal, __ATOMIC_ACQUIRE);
            if (original == (void *)expectedEntry && prior == replacement) {
                status = 1u; // already hooked
            } else if (original == (void *)expectedEntry &&
                       prior == (void *)expectedEntry) {
                void *expected = prior;
                bool ok = __atomic_compare_exchange_n((void **)info, &expected,
                    replacement, false, __ATOMIC_RELEASE, __ATOMIC_RELAXED);
                status = ok ? 2u : 6u; // repaired or unsafe competing change
            } else {
                status = 6u; // foreign pointer / original mismatch
            }
            os_unfair_lock_unlock(&gHookInstallLock);
            break;
        }
    }
    __atomic_store_n(&gOGSMasterCacheStatus[index], status, __ATOMIC_RELEASE);
}

static void OGSRepairMasterReceiverCaches(void) {
    __atomic_fetch_add(&gOGSMasterCacheRounds, 1u, __ATOMIC_RELAXED);
    OGSRepairMasterReceiverCacheOne(0, 4821, 31022, 0x060002DAu, 1,
        0x0142800Cu, (void *)&hook_OnMasterSwitched1, (void **)&orig_OnMasterSwitch1);
    OGSRepairMasterReceiverCacheOne(1, 4894, 31665, 0x0600054Bu, 1,
        0x013DCE14u, (void *)&hook_OnMasterSwitched2, (void **)&orig_OnMasterSwitch2);
    OGSRepairMasterReceiverCacheOne(2, 4935, 31901, 0x06000623u, 1,
        0x0138E214u, (void *)&hook_OnMasterSwitched3, (void **)&orig_OnMasterSwitch3);
    OGSRepairMasterReceiverCacheOne(3, 4967, 32043, 0x060006ABu, 1,
        0x013C5ADCu, (void *)&hook_OnMasterSwitched4, (void **)&orig_OnMasterSwitch4);
    OGSRepairMasterReceiverCacheOne(4, 4968, 32078, 0x060006CEu, 1,
        0x013795F0u, (void *)&hook_OnMasterSwitched5, (void **)&orig_OnMasterSwitch5);
    OGSRepairMasterReceiverCacheOne(5, 4825, 31058, 0x060002FEu, 0,
        0x0138881Cu, (void *)&hook_GameLogicMasterSwitch,
        (void **)&orig_GameLogicMasterSwitch);
    // Metadata and native methodPointers verified from the actual fps IPA:
    // PhotonNetwork.LeaveRoom(bool) MD31543, MI28866, Type4884.
    OGSRepairMasterReceiverCacheOne(6, 4884, 31543, 0x060004D8u, 1,
        0x013D0604u, (void *)&hook_LeaveRoom, (void **)&orig_LeaveRoom);
    // WorkerInGame.OnDisconnectedFromPhoton() MD31024 MI29767 Type4821.
    OGSRepairMasterReceiverCacheOne(7, 4821, 31024, 0x060002DCu, 0,
        0x01428224u, (void *)&hook_WorkerInGameDisconnected,
        (void **)&orig_WorkerInGameDisconnected);
}

// Stage 2: read-only Photon presence. No IL2CPP/Photon function calls
// from the UIKit timer. Verified fps 3.4.0 offsets:
// typeInfo->staticFields +0xB8 -> networkPeer +0x10;
// peer->currentRoom +0x158, peer->localPlayer +0x160;
// player->actorID +0x10. This is NOT proof of host authority.
static volatile uint32_t gOGSPresenceProbeCalls = 0;
static volatile uint32_t gOGSPresenceReadFailures = 0;
static volatile int32_t gOGSPresenceReadOnly = 0; // 0 unknown, 1 room seen, 2 room absent
static volatile int32_t gOGSPresenceActorID = 0;
// fps 3.4.0: currentRoom->masterActorID +0x48 (ARM64 game RVA 0x13F1FF4).
// Read-only Photon local state. Not confirmation of server-side authority.
static volatile int32_t gOGSLocalMasterActorID = 0; // zero means unknown
static volatile uint32_t gOGSLocalMasterSamples = 0;
static volatile uint32_t gOGSLocalMasterReadFailures = 0;
static volatile uint32_t gOGSLocalMasterChanges = 0;
// The last trustworthy room/master sample survives transient VM read errors;
// the displayed current MasterClient remains UNKNOWN during those errors.
static uintptr_t gOGSLastReliableRoomAddress = 0; // UIKit timer thread only
static int32_t gOGSLastReliableMasterActor = 0;    // UIKit timer thread only
static volatile int32_t gOGSLastMasterFromActor = 0;
static volatile int32_t gOGSLastMasterToActor = 0;
static uint32_t gOGSPresenceNoRoomStreak = 0;

/*
 * Stage 13: read-only roster for Photon PUN classic fps 3.4.0.
 * The following RVAs/offsets are confirmed from the actual iOS ARM64 fps:
 *   PhotonNetwork.get_otherPlayers RVA 0x13CAF78 loads peer + 0x1B0;
 *   PhotonPlayer.get_ID RVA 0x13CC384 reads + 0x10;
 *   PhotonPlayer.get_NickName RVA 0x13D7534 loads string + 0x18;
 *   room + 0x48 is the observed MasterClient actor.
 * This is strictly Mach VM reading. No managed/Unity call on UIKit timer.
 * Read failures publish an empty roster instead of reusing stale peer ptrs.
 */
static volatile uint32_t gOGSRosterReadOK = 0;
static volatile uint32_t gOGSRosterReadFail = 0;
static volatile uint32_t gOGSRosterLastCount = 0;
static uintptr_t gOGSRosterLastRoom = 0; // UIKit timer only
static void OGSRefreshReadOnlyRoster(void) {
    OGSRoomSnapshot roster = {};
    uintptr_t typeSlot = OGSResolveRVA(RVA_PHOTON_NET_TYPEINFO);
    void *typeInfo = NULL, *fields = NULL, *netPeer = NULL;
    uintptr_t room = 0, others = 0;
    int32_t master = 0;
    if (!typeSlot ||
        !OGSReadPointer(typeSlot, &typeInfo) ||
        !OGSReadPointer((uintptr_t)typeInfo + 0xB8, &fields) ||
        !OGSReadPointer((uintptr_t)fields + 0x10, &netPeer) ||
        !OGSReadMemory((uintptr_t)netPeer + 0x158, &room, sizeof(room)) ||
        room < 0x100000000ULL ||
        !OGSReadMemory(room + 0x48, &master, sizeof(master)) ||
        master <= 0 || master >= 1000000 ||
        !OGSReadMemory((uintptr_t)netPeer + 0x1B0, &others, sizeof(others))) {
        gOGSRosterLastRoom = 0;
        OGSPublishSnapshotValue(&roster);
        __atomic_fetch_add(&gOGSRosterReadFail, 1u, __ATOMIC_RELAXED);
        return;
    }
    roster.inRoom = true;
    int32_t me = __atomic_load_n(&gOGSPresenceActorID, __ATOMIC_ACQUIRE);
    roster.isMaster = me > 0 && master == me;
    if (others == 0) {
        gOGSRosterLastRoom = room;
        OGSPublishSnapshotValue(&roster);
        __atomic_store_n(&gOGSRosterLastCount, 0u, __ATOMIC_RELEASE);
        __atomic_fetch_add(&gOGSRosterReadOK, 1u, __ATOMIC_RELAXED);
        return;
    }
    uintptr_t count = 0;
    if (others < 0x100000000ULL ||
        !OGSReadMemory(others + 0x18, &count, sizeof(count)) ||
        count > OGS_MAX_PEERS) {
        OGSPublishSnapshotValue(&roster);
        __atomic_fetch_add(&gOGSRosterReadFail, 1u, __ATOMIC_RELAXED);
        return;
    }
    for (uintptr_t i = 0; i < count; ++i) {
        void *player = NULL, *nameObject = NULL;
        int32_t id = 0;
        if (!OGSReadPointer(others + 0x20 + i * sizeof(void *), &player) ||
            !OGSReadMemory((uintptr_t)player + 0x10, &id, sizeof(id)) ||
            id <= 0 || id >= 1000000 || id == me ||
            !OGSReadPointer((uintptr_t)player + 0x18, &nameObject)) continue;
        NSString *name = OGSReadIl2CppString(nameObject);
        if (!name.length) continue;
        OGSPeerSnapshot *p = &roster.peers[roster.count++];
        p->actorID = id;
        p->isHost = id == master;
        p->playerObject = NULL; // no managed pointers survive into UI snapshot
        snprintf(p->name, sizeof(p->name), "%s", name.UTF8String ?: "");
    }
    uintptr_t roomAfter = 0;
    if (!OGSReadMemory((uintptr_t)netPeer + 0x158, &roomAfter, sizeof(roomAfter)) ||
        roomAfter != room) {
        OGSRoomSnapshot emptyRoster = {};
        OGSPublishSnapshotValue(&emptyRoster);
        __atomic_fetch_add(&gOGSRosterReadFail, 1u, __ATOMIC_RELAXED);
        return;
    }
    gOGSRosterLastRoom = room;
    __atomic_store_n(&gOGSRosterLastCount, roster.count, __ATOMIC_RELEASE);
    __atomic_fetch_add(&gOGSRosterReadOK, 1u, __ATOMIC_RELAXED);
    OGSPublishSnapshotValue(&roster);
}



static void OGSRefreshReadOnlyPresence(void) {
    __atomic_fetch_add(&gOGSPresenceProbeCalls, 1u, __ATOMIC_RELAXED);
    uintptr_t slot = OGSResolveRVA(RVA_PHOTON_NET_TYPEINFO);
    void *typeInfo = NULL, *fields = NULL, *netPeer = NULL;
    if (!slot || !OGSReadPointer(slot, &typeInfo) ||
        !OGSReadPointer((uintptr_t)typeInfo + 0xB8, &fields) ||
        !OGSReadPointer((uintptr_t)fields + 0x10, &netPeer)) {
        __atomic_store_n(&gOGSPresenceReadOnly, 0, __ATOMIC_RELEASE);
        __atomic_store_n(&gOGSLocalMasterActorID, 0, __ATOMIC_RELEASE);
        __atomic_fetch_add(&gOGSPresenceReadFailures, 1u, __ATOMIC_RELAXED);
        gOGSPresenceNoRoomStreak = 0;
        return;
    }
    uintptr_t room = 0, local = 0;
    if (!OGSReadMemory((uintptr_t)netPeer + 0x158, &room, sizeof(room)) ||
        !OGSReadMemory((uintptr_t)netPeer + 0x160, &local, sizeof(local))) {
        __atomic_store_n(&gOGSPresenceReadOnly, 0, __ATOMIC_RELEASE);
        __atomic_store_n(&gOGSLocalMasterActorID, 0, __ATOMIC_RELEASE);
        __atomic_fetch_add(&gOGSPresenceReadFailures, 1u, __ATOMIC_RELAXED);
        gOGSPresenceNoRoomStreak = 0;
        return;
    }
    int32_t actor = 0;
    bool localValid = local > 0x100000000ULL &&
        OGSReadMemory(local + 0x10, &actor, sizeof(actor)) &&
        actor > 0 && actor < 1000000;
    if (room > 0x100000000ULL && localValid) {
        __atomic_store_n(&gOGSPresenceReadOnly, 1, __ATOMIC_RELEASE);
        __atomic_store_n(&gOGSPresenceActorID, actor, __ATOMIC_RELEASE);
        if (__atomic_load_n(&gOGSAutoEnabled, __ATOMIC_ACQUIRE)) {
            bool mismatch = false;
            os_unfair_lock_lock(&gStateLock);
            mismatch = gOGSAutoRoom != room || gOGSAutoOwner != actor;
            os_unfair_lock_unlock(&gStateLock);
            if (mismatch) OGSDisarmAutoRoom();
        }
        // Pure VM read: safe even when Cash/Chat update callbacks do not run.
        // No invocation of a Photon getter or setter on the UIKit thread.
        int32_t observedMaster = 0;
        bool validMaster = OGSReadMemory(room + 0x48, &observedMaster, sizeof(observedMaster)) &&
            observedMaster > 0 && observedMaster < 1000000;
        if (gOGSLastReliableRoomAddress != room) {
            gOGSLastReliableRoomAddress = room;
            gOGSLastReliableMasterActor = 0;
        }
        if (validMaster) {
            int32_t previous = gOGSLastReliableMasterActor;
            gOGSLastReliableMasterActor = observedMaster;
            __atomic_store_n(&gOGSLocalMasterActorID, observedMaster, __ATOMIC_RELEASE);
            if (previous > 0 && previous != observedMaster) {
                __atomic_store_n(&gOGSLastMasterFromActor, previous, __ATOMIC_RELEASE);
                __atomic_store_n(&gOGSLastMasterToActor, observedMaster, __ATOMIC_RELEASE);
                // Events preceding detection are correlation clues, not
                // proof of which client or packet caused the transfer.
                double observedAt = CFAbsoluteTimeGetCurrent();
                os_unfair_lock_lock(&gStateLock);
                gOGSLastTransitionEventTrail[0] = '\0';
                for (uint64_t i = 0; i < 6 && i < gOGSNetTrailWrites; ++i) {
                    size_t slotIndex = (size_t)((gOGSNetTrailWrites - 1 - i) % OGS_NET_TRAIL_CAPACITY);
                    double millis = (observedAt - gOGSNetTrailTimes[slotIndex]) * 1000.0;
                    if (millis < 0.0 || millis > 5000.0) continue;
                    size_t used = strlen(gOGSLastTransitionEventTrail);
                    if (used + 24 >= sizeof(gOGSLastTransitionEventTrail)) break;
                    snprintf(gOGSLastTransitionEventTrail + used,
                             sizeof(gOGSLastTransitionEventTrail) - used,
                             "%s%u@%.0fms", used ? ", " : "",
                             (unsigned)gOGSNetTrailCodes[slotIndex], millis);
                }
                os_unfair_lock_unlock(&gStateLock);
                __atomic_fetch_add(&gOGSLocalMasterChanges, 1u, __ATOMIC_RELAXED);
            }
            __atomic_fetch_add(&gOGSLocalMasterSamples, 1u, __ATOMIC_RELAXED);
        } else {
            __atomic_store_n(&gOGSLocalMasterActorID, 0, __ATOMIC_RELEASE);
            __atomic_fetch_add(&gOGSLocalMasterReadFailures, 1u, __ATOMIC_RELAXED);
        }
        __atomic_store_n(&gOGS.inRoom, true, __ATOMIC_RELEASE);
        gOGSPresenceNoRoomStreak = 0;
        os_unfair_lock_lock(&gStateLock);
        if (gOGS.roomEnterTime <= 0.0)
            gOGS.roomEnterTime = CFAbsoluteTimeGetCurrent();
        os_unfair_lock_unlock(&gStateLock);
    } else if (room == 0 && ++gOGSPresenceNoRoomStreak >= 4) {
        if (__atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE) == 1)
            __atomic_fetch_add(&gOGSObservedRoomDisappearances, 1u,
                               __ATOMIC_RELAXED);
        OGSDisarmAutoRoom();
        __atomic_store_n(&gOGSPresenceReadOnly, 2, __ATOMIC_RELEASE);
        gOGSLastReliableRoomAddress = 0;
        gOGSLastReliableMasterActor = 0;
        __atomic_store_n(&gOGSPresenceActorID, 0, __ATOMIC_RELEASE);
        __atomic_store_n(&gOGSLocalMasterActorID, 0, __ATOMIC_RELEASE);
        __atomic_store_n(&gOGS.inRoom, false, __ATOMIC_RELEASE);
        __atomic_store_n(&gOGS.isMaster, false, __ATOMIC_RELEASE);
        __atomic_store_n(&gOGS.heldMasterStably, false, __ATOMIC_RELEASE);
        os_unfair_lock_lock(&gStateLock);
        gOGS.roomEnterTime = 0.0;
        gOGS.masterAcquiredTime = 0.0;
        os_unfair_lock_unlock(&gStateLock);
    } else {
        __atomic_store_n(&gOGSPresenceReadOnly, 0, __ATOMIC_RELEASE);
        __atomic_store_n(&gOGSLocalMasterActorID, 0, __ATOMIC_RELEASE);
        if (room != 0) gOGSPresenceNoRoomStreak = 0;
    }
}

static void OGSInstallHooks(void) {
    if (!OGSFindGameImage()) return;
    OGSInstallPointerSlotHook(gOffsets.tblCashUpdate, (void *)&hook_CashUpdate, (void **)&orig_CashUpdate);
    // Stage 22: DO NOT hook the former "chat" slots! For this exact iOS
    // executable they are NamePickGui..ctor() and NetworkCharacter..ctor(),
    // NOT Chat.Update / SendChatRemote. No unverified replacement offset.
    __atomic_store_n(&gOGS.chatMode, 0, __ATOMIC_RELEASE);
    OGSInstallPointerSlotHook(gOffsets.tblOnDisconnect, (void *)&hook_OnPhotonPlayerDisconnected, (void **)&orig_OnDisconnect);
    if (!OGSInstallPointerSlotHook(gOffsets.tblOnEvent, (void *)&hook_OnEvent,
                                    (void **)&orig_OnEvent))
        __atomic_fetch_add(&gOGSOnEventInstallFailures, 1u, __ATOMIC_RELAXED);
    if (!OGSInstallPointerSlotHook(kOGSPhotonHandlerUpdateSlot,
                                    (void *)&hook_PhotonHandlerUpdate,
                                    (void **)&orig_PhotonHandlerUpdate))
        __atomic_fetch_add(&gOGSPhotonUpdateInstallFailures, 1u, __ATOMIC_RELAXED);
    else
        OGSRepairPhotonHandlerUpdateCache();

    // Strictly identify the original method ENTRY before hooking its slot.
    // A mismatch must leave the game's dispatch table untouched.
    uintptr_t responseSlot = OGSResolveRVA(kOGSOnOperationResponseSlot);
    uintptr_t responseEntry = OGSResolveRVA(kOGSOnOperationResponseEntry);
    void *actual = NULL;
    if (responseSlot && responseEntry &&
        OGSReadPointer(responseSlot, &actual) &&
        (actual == (void *)responseEntry || actual == (void *)&hook_OnOperationResponse)) {
        bool ok = OGSInstallPointerSlotHook(kOGSOnOperationResponseSlot,
                                            (void *)&hook_OnOperationResponse,
                                            (void **)&orig_OnOperationResponse);
        __atomic_store_n(&gOGSResponseHookStatus, ok ? 1u : 3u, __ATOMIC_RELEASE);
    } else {
        __atomic_store_n(&gOGSResponseHookStatus,
                          actual ? 2u : 3u, __ATOMIC_RELEASE);
    }
    OGSInstallPointerSlotHook(gOffsets.tblLeaveRoom, (void *)&hook_LeaveRoom, (void **)&orig_LeaveRoom);
    // Verified Unity callback entry: WorkerInGame.OnDisconnectedFromPhoton.
    // Never suppress or mutate network disconnect handling.
    OGSInstallPointerSlotHook(0x02392638u,
        (void *)&hook_WorkerInGameDisconnected,
        (void **)&orig_WorkerInGameDisconnected);
    OGSInstallPointerSlotHook(gOffsets.tblType4995LeaveRoom, (void *)&hook_Type4995LeaveRoom, (void **)&orig_Type4995Leave);
    OGSInstallPointerSlotHook(gOffsets.tblOnMasterSwitched1, (void *)&hook_OnMasterSwitched1, (void **)&orig_OnMasterSwitch1);
    OGSInstallPointerSlotHook(gOffsets.tblOnMasterSwitched2, (void *)&hook_OnMasterSwitched2, (void **)&orig_OnMasterSwitch2);
    OGSInstallPointerSlotHook(gOffsets.tblOnMasterSwitched3, (void *)&hook_OnMasterSwitched3, (void **)&orig_OnMasterSwitch3);
    OGSInstallPointerSlotHook(gOffsets.tblOnMasterSwitched4, (void *)&hook_OnMasterSwitched4, (void **)&orig_OnMasterSwitch4);
    OGSInstallPointerSlotHook(gOffsets.tblOnMasterSwitched5, (void *)&hook_OnMasterSwitched5, (void **)&orig_OnMasterSwitch5);
    // Sixth receiver has ABI (self, MethodInfo*), without PhotonPlayer*.
    OGSInstallPointerSlotHook(0x0238EEA8u, (void *)&hook_GameLogicMasterSwitch,
                              (void **)&orig_GameLogicMasterSwitch);
    // Stage23 already repaired cached PhotonHandler.Update. Repair only the
    // six MasterClient notification receivers without touching Event203.
    OGSRepairMasterReceiverCaches();
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
        inst.sessionNameHistory = [NSMutableDictionary dictionary];
        NSArray *savedBans = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"OGS_SavedBannedNames"];
        if (savedBans) [inst.bannedNames addObjectsFromArray:savedBans];
    });
    return inst;
}

- (void)saveLocalBans {
    os_unfair_lock_lock(&gBanSetLock);
    NSArray *all = [self.bannedNames.allObjects copy];
    os_unfair_lock_unlock(&gBanSetLock);
    if (all) {
        [[NSUserDefaults standardUserDefaults] setObject:all forKey:@"OGS_SavedBannedNames"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (NSUInteger)bannedCountSafe {
    os_unfair_lock_lock(&gBanSetLock);
    NSUInteger c = self.bannedNames.count;
    os_unfair_lock_unlock(&gBanSetLock);
    return c;
}

- (void)recordHijackerName:(NSString *)normName actorID:(int32_t)actID {
    os_unfair_lock_lock(&gBanSetLock);
    if (normName.length > 0) [self.bannedNames addObject:normName];
    if (actID > 0) [self.bannedActorIDs addObject:@(actID)];
    os_unfair_lock_unlock(&gBanSetLock);
    OGSResetTrackerForActor(actID);
    [self saveLocalBans];
}

- (BOOL)shouldAutoKickPeerWithName:(NSString *)normName actorID:(int32_t)actID {
    __atomic_fetch_add(&gOGSBanEvaluations, 1u, __ATOMIC_RELAXED);
    BOOL res = NO;
    os_unfair_lock_lock(&gBanSetLock);
    if (normName.length > 0 && [self.bannedNames containsObject:normName]) res = YES;
    else if (actID > 0 && [self.bannedActorIDs containsObject:@(actID)]) res = YES;
    else if (self.roomLockActive && normName.length > 0 && ![self.allowedNamesWhenLocked containsObject:normName]) res = YES;
    os_unfair_lock_unlock(&gBanSetLock);
    if (res) __atomic_fetch_add(&gOGSBanMatches, 1u, __ATOMIC_RELAXED);
    return res;
}

- (UIWindow *)gameMainWindow {
    UIWindow *bestWindow = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.isKeyWindow) return w;
                if (!w.hidden && w.alpha > 0.01f) bestWindow = w;
            }
        }
    }
    if (bestWindow) return bestWindow;
    return [UIApplication sharedApplication].windows.firstObject;
}

- (UIButton *)makeBtn:(CGRect)f title:(NSString *)t bg:(UIColor *)bg action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    b.backgroundColor = bg;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    b.layer.cornerRadius = 7.0;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)ensureMenuVisible {
    UIWindow *gw = [self gameMainWindow];
    if (!gw || !self.containerView) return;

    if (self.containerView.superview != gw) {
        [gw addSubview:self.containerView];
    }
    if (!CGRectEqualToRect(self.containerView.frame, gw.bounds)) {
        self.containerView.frame = gw.bounds;
    }
    // Resize without increasing panel content height; scrolling preserves
    // access to the final row on iPhone landscape and compact screens.
    if (self.menuPanel) {
        CGFloat vh = MIN(358.0, MAX(160.0, CGRectGetHeight(gw.bounds) - 26.0));
        CGFloat vx = MAX(8.0, MIN(75.0, CGRectGetWidth(gw.bounds) - 323.0));
        CGRect box = self.menuPanel.frame;
        if (box.size.height != vh || box.origin.x != vx) {
            box.size.height = vh;
            box.origin.x = vx;
            self.menuPanel.frame = box;
        }
    }
    self.containerView.hidden = NO;
    self.floatingButton.hidden = NO;
    [gw bringSubviewToFront:self.containerView];
}

- (void)setupMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.containerView) {
            [self ensureMenuVisible];
            return;
        }
        UIWindow *gw = [self gameMainWindow];
        if (!gw) return;

        self.containerView = [[OGSPassthroughContainer alloc] initWithFrame:gw.bounds];
        self.containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

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

        CGFloat menuViewportHeight = MIN(358.0, MAX(160.0, CGRectGetHeight(gw.bounds) - 26.0));
        CGFloat menuX = MAX(8.0, MIN(75.0, CGRectGetWidth(gw.bounds) - 323.0));
        self.menuPanel = [[UIScrollView alloc] initWithFrame:CGRectMake(menuX, 18, 315, menuViewportHeight)];
        self.menuPanel.contentSize = CGSizeMake(315, 358);
        self.menuPanel.alwaysBounceVertical = NO;
        self.menuPanel.showsVerticalScrollIndicator = YES;
        self.menuPanel.clipsToBounds = YES;
        self.menuPanel.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:0.96];
        self.menuPanel.layer.cornerRadius = 14.0;
        self.menuPanel.layer.borderWidth = 2.0f;
        self.menuPanel.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.menuPanel.hidden = YES;

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 260, 18)];
        self.titleLabel.text = @"OGS Stage 27 LAB | إدارة الروم";
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
        self.titleLabel.userInteractionEnabled = YES;
        [self.titleLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showHookDiagnostics:)]];
        [self.menuPanel addSubview:self.titleLabel];

        self.syncCloudButton = [self makeBtn:CGRectMake(273, 3, 32, 21)
                                       title:@"🔄"
                                          bg:[UIColor colorWithRed:0.18 green:0.45 blue:0.75 alpha:1.0]
                                      action:@selector(syncCloudTapped:)];
        [self.menuPanel addSubview:self.syncCloudButton];

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

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 70, 95, 30) title:@"▶ السابق" bg:darkGray action:@selector(prevPlayer:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(110, 70, 95, 30) title:@"سحب الهوست 👑" bg:hostBlue action:@selector(claimHostNow:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(210, 70, 95, 30) title:@"التالي ◀" bg:darkGray action:@selector(nextPlayer:)]];

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(161, 105, 144, 32) title:@"طرد المحدد فقط" bg:kickOrange action:@selector(kickSelected:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 105, 144, 32) title:@"طرد وحظر (Ban)" bg:banRed action:@selector(banSelected:)]];

        self.hostLockButton = [self makeBtn:CGRectMake(155, 142, 150, 32) title:@"استعادة تلقائية: إيقاف" bg:darkGray action:@selector(toggleAutoHost:)];
        [self.menuPanel addSubview:self.hostLockButton];

        self.antiKickLockButton = [self makeBtn:CGRectMake(10, 142, 140, 32) title:@"قفل البقاء: تلقائي 🛡️" bg:darkGray action:@selector(toggleAntiKickHardLock:)];
        [self.menuPanel addSubview:self.antiKickLockButton];

        self.godModeButton = [self makeBtn:CGRectMake(155, 179, 150, 30) title:@"درع الحماية: متوقف 🛡️" bg:darkGray action:@selector(toggleGodMode:)];
        [self.menuPanel addSubview:self.godModeButton];

        self.magicBulletButton = [self makeBtn:CGRectMake(10, 179, 140, 30) title:@"طلقة سحرية: متوقف 🔫" bg:darkGray action:@selector(toggleMagicBullet:)];
        [self.menuPanel addSubview:self.magicBulletButton];

        self.muteChatButton = [self makeBtn:CGRectMake(105, 214, 95, 30) title:@"الشات: معطل مؤقتًا" bg:darkGray action:@selector(cycleChatMode:)];
        [self.menuPanel addSubview:self.muteChatButton];

        self.unbanButton = [self makeBtn:CGRectMake(10, 214, 90, 30) title:@"فك الحظر (0)" bg:darkGray action:@selector(clearBanList:)];
        [self.menuPanel addSubview:self.unbanButton];

        self.lockButton = [self makeBtn:CGRectMake(205, 214, 100, 30) title:@"حظر محلي: إيقاف" bg:darkGray action:@selector(toggleRoomLock:)];
        [self.menuPanel addSubview:self.lockButton];

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 249, 55, 30) title:@"سرعة -" bg:darkGray action:@selector(speedDown:)]];
        self.speedSetButton = [self makeBtn:CGRectMake(70, 249, 175, 30) title:@"السرعة: 1.0x (اضغط للكتابة)" bg:hostBlue action:@selector(promptCustomSpeed:)];
        [self.menuPanel addSubview:self.speedSetButton];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(250, 249, 55, 30) title:@"سرعة +" bg:darkGray action:@selector(speedUp:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 284, 144, 30)
            title:@"نسخ اسم المحدد 📋" bg:hostBlue action:@selector(copySelectedName:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(161, 284, 144, 30)
            title:@"أسماء نفس الجلسة" bg:darkGray action:@selector(showSelectedNameHistory:)]];

        // Exactly two optional privacy choices; tapping the active choice
        // again restores the public and joinable default.
        self.privacyHiddenButton = [self makeBtn:CGRectMake(10, 319, 144, 30)
            title:@"مخفي: إيقاف" bg:darkGray action:@selector(togglePrivacyHidden:)];
        [self.menuPanel addSubview:self.privacyHiddenButton];
        self.privacyClosedButton = [self makeBtn:CGRectMake(161, 319, 144, 30)
            title:@"خاص ومغلق: إيقاف" bg:darkGray action:@selector(togglePrivacyClosed:)];
        [self.menuPanel addSubview:self.privacyClosedButton];

        [self.containerView addSubview:self.menuPanel];
        self.containerView.floatingButton = self.floatingButton;
        self.containerView.menuPanel = self.menuPanel;
        [gw addSubview:self.containerView];
        [gw bringSubviewToFront:self.containerView];

        self.masterTimer = [NSTimer scheduledTimerWithTimeInterval:0.18 target:self selector:@selector(onMasterTick) userInfo:nil repeats:YES];
        self.masterTimer.tolerance = 0.03;

        [self fetchGitHubCloudConfigWithFeedback:NO];
    });
}

- (void)syncCloudTapped:(UIButton *)sender {
    [self fetchGitHubCloudConfigWithFeedback:YES];
}

- (void)tryFetchFromCandidateURLs:(NSArray<NSString *> *)candidates index:(NSUInteger)idx showFeedback:(BOOL)showFeedback {
    if (idx >= candidates.count) {
        if (showFeedback) self.statusLabel.text = @"تأكد أن المستودع Public وملف JSON موجود";
        return;
    }

    NSString *baseUrl = candidates[idx];
    NSString *sep = [baseUrl containsString:@"?"] ? @"&" : @"?";
    NSString *bustUrl = [NSString stringWithFormat:@"%@%@t=%lld", baseUrl, sep, (long long)([[NSDate date] timeIntervalSince1970] * 1000)];
    NSURL *url = [NSURL URLWithString:bustUrl];
    if (!url) {
        [self tryFetchFromCandidateURLs:candidates index:idx + 1 showFeedback:showFeedback];
        return;
    }

    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:6.0];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResp = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        if (error || !data || (httpResp && httpResp.statusCode != 200)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self tryFetchFromCandidateURLs:candidates index:idx + 1 showFeedback:showFeedback];
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self tryFetchFromCandidateURLs:candidates index:idx + 1 showFeedback:showFeedback];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyCloudConfigDictionary:json];
            if (showFeedback) self.statusLabel.text = @"تم التحديث من GitHub بنجاح ✅";
        });
    }] resume];
}

- (void)fetchGitHubCloudConfigWithFeedback:(BOOL)showFeedback {
    if (showFeedback) self.statusLabel.text = @"جاري التحديث من GitHub...";
    NSString *savedCustom = [[NSUserDefaults standardUserDefaults] stringForKey:@"OGS_GitHubConfigURL"];
    NSArray<NSString *> *candidates = OGSCandidateCloudURLs(savedCustom ?: kDefaultGitHubConfigURL);
    [self tryFetchFromCandidateURLs:candidates index:0 showFeedback:showFeedback];
}

- (void)applyCloudConfigDictionary:(NSDictionary *)json {
    if ([json[@"kick_message"] isKindOfClass:[NSString class]]) {
        const char *utf8 = [json[@"kick_message"] UTF8String];
        if (utf8) {
            os_unfair_lock_lock(&gStateLock);
            snprintf(gOGS.customKickPhrase, sizeof(gOGS.customKickPhrase), "%s", utf8);
            os_unfair_lock_unlock(&gStateLock);
        }
    }
    if ([json[@"default_speed"] isKindOfClass:[NSNumber class]]) {
        [self applySpeed:[json[@"default_speed"] floatValue]];
    }
    os_unfair_lock_lock(&gBanSetLock);
    if ([json[@"banned_names"] isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)json[@"banned_names"]) {
            if ([item isKindOfClass:[NSString class]]) {
                NSString *norm = OGSNormalizeKey(item);
                if (norm.length > 0) [self.bannedNames addObject:norm];
            }
        }
    }
    if ([json[@"banned_ids"] isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)json[@"banned_ids"]) {
            if ([item isKindOfClass:[NSNumber class]]) [self.bannedActorIDs addObject:item];
        }
    }
    os_unfair_lock_unlock(&gBanSetLock);
    [self saveLocalBans];
    [self refreshUI];
}

- (void)onMasterTick {
    [self ensureMenuVisible];
    double now = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&gStateLock);
    double lastUnity = gOGS.lastUnityFrameTick;
    os_unfair_lock_unlock(&gStateLock);

    // إذا كانت هوكات التحديث في اللعبة متوقفة، ننفذ التحديث من المؤقت الاحتياطي بأمان
    if ((now - lastUnity) > 0.35) {
        static double s_lastHookRetry = 0.0;
        if ((now - s_lastHookRetry) >= 2.0) {
            s_lastHookRetry = now;
            OGSInstallHooks();
        }
        // Crash 7567FE79: Calling OGSUpdateRoomSnapshot from this UIKit
        // NSTimer entered IL2CPP object/peer code on an unsupported call path.
        // Read-only Mach VM reads only. No managed calls from UIKit timer.
        OGSRefreshReadOnlyPresence();
        @autoreleasepool { OGSRefreshReadOnlyRoster(); }
    }
    [self updateSessionNameHistory];

    if (!self.menuPanel || self.menuPanel.hidden) return;
    [self refreshUI];
}

- (void)updateSessionNameHistory {
    // Observations only; never infer an identity across different actor IDs or rooms.
    uintptr_t room = gOGSRosterLastRoom;
    if (room != self.sessionNameRoom) {
        self.sessionNameRoom = room;
        [self.sessionNameHistory removeAllObjects];
    }
    if (!room) return;
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    if (!snapshot.inRoom) return;
    for (uint32_t i = 0; i < snapshot.count; ++i) {
        const OGSPeerSnapshot *peer = &snapshot.peers[i];
        if (peer->actorID <= 0) continue;
        NSString *name = [NSString stringWithUTF8String:peer->name];
        if (!name.length) continue;
        NSNumber *actorKey = @(peer->actorID);
        NSMutableArray<NSString *> *names = self.sessionNameHistory[actorKey];
        if (!names) {
            names = [NSMutableArray arrayWithObject:name];
            self.sessionNameHistory[actorKey] = names;
        } else if (![names.lastObject isEqualToString:name] &&
                   ![names containsObject:name]) {
            // Keep at most 8 distinct names for this one actor in this room.
            if (names.count >= 8) [names removeObjectAtIndex:0];
            [names addObject:name];
        }
    }
}
- (void)copySelectedName:(UIButton *)sender {
    (void)sender;
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    uint32_t index = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);
    if (!snapshot.inRoom || index >= snapshot.count) {
        self.statusLabel.text = @"القائمة خالية أو غير متاحة؛ لا يوجد اسم للنسخ";
        return;
    }
    NSString *name = [NSString stringWithUTF8String:snapshot.peers[index].name];
    if (!name.length) return;
    [UIPasteboard generalPasteboard].string = name;
    self.statusLabel.text = [NSString stringWithFormat:@"نُسخ الاسم: %@", name];
}
- (void)showSelectedNameHistory:(UIButton *)sender {
    (void)sender;
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    uint32_t index = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);
    if (!snapshot.inRoom || index >= snapshot.count) {
        self.statusLabel.text = @"اختر لاعبًا من القائمة أولًا";
        return;
    }
    OGSPeerSnapshot peer = snapshot.peers[index];
    NSArray<NSString *> *names = [self.sessionNameHistory[@(peer.actorID)] copy];
    NSString *last = [NSString stringWithUTF8String:peer.name] ?: @"غير معروف";
    NSString *message = names.count > 1 ?
        [NSString stringWithFormat:@"أسماء شوهدت لنفس Actor #%d في هذه الغرفة فقط:\n%@\n\nلا يمكن ربط أسماء أشخاص بعد الخروج والدخول أو عبر الأيام بهذه البيانات.",
             peer.actorID, [names componentsJoinedByString:@" ← "]] :
        [NSString stringWithFormat:@"Actor #%d: %@\nلم يُرصد تغيير اسم لهذا الرقم أثناء هذه الجلسة. رقم Actor ليس هوية حساب دائمة.",
             peer.actorID, last];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"سجل الأسماء المحلي"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"نسخ" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            (void)action;
            [UIPasteboard generalPasteboard].string =
                names.count ? [names componentsJoinedByString:@" ← "] : last;
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إغلاق"
        style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *root = [self gameMainWindow].rootViewController;
    if (root && !root.presentedViewController)
        [root presentViewController:alert animated:YES completion:nil];
}
- (void)refreshUI {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    uint32_t count = snapshot.count;
    double lastUpdate = 0.0;
    os_unfair_lock_lock(&gStateLock);
    lastUpdate = gOGS.lastUnityFrameTick;
    os_unfair_lock_unlock(&gStateLock);
    BOOL hookActive = lastUpdate > 0.0 && (CFAbsoluteTimeGetCurrent() - lastUpdate) <= 0.5;
    BOOL autoArmed = __atomic_load_n(&gOGSAutoEnabled, __ATOMIC_ACQUIRE) != 0;
    // Render privacy from fresh room memory, not a claimed local UI state.
    uintptr_t privacyRoom = 0;
    int32_t privacyLocal = 0, privacyMaster = 0;
    bool privacyOpen = true, privacyVisible = true;
    BOOL privacyReadable = OGSReadAutoRoom(&privacyRoom, &privacyLocal, &privacyMaster) &&
        OGSReadRoomPrivacy(privacyRoom, &privacyOpen, &privacyVisible);
    BOOL hiddenActive = privacyReadable && !privacyVisible && privacyOpen;
    BOOL closedActive = privacyReadable && !privacyVisible && !privacyOpen;
    UIColor *privacyGray = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    UIColor *privacyGreen = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    if (self.privacyHiddenButton) {
        [self.privacyHiddenButton setTitle:(hiddenActive ? @"مخفي: مفعّل" : @"مخفي: إيقاف") forState:UIControlStateNormal];
        self.privacyHiddenButton.backgroundColor = hiddenActive ? privacyGreen : privacyGray;
    }
    if (self.privacyClosedButton) {
        BOOL guardArmed = __atomic_load_n(&gOGSClosedGuardEnabled, __ATOMIC_ACQUIRE) != 0;
        NSString *guardTitle = guardArmed ? (closedActive ?
            @"حراسة الدخول: مفعلة" : @"حراسة الدخول: انتظار") :
            (closedActive ? @"خاص ومغلق: يدوي" : @"حراسة الدخول: إيقاف");
        [self.privacyClosedButton setTitle:guardTitle forState:UIControlStateNormal];
        self.privacyClosedButton.backgroundColor = closedActive ? privacyGreen : privacyGray;
    }
    NSString *autoTitle = autoArmed ? @"استعادة تلقائية: مفعلة 👑" : @"استعادة تلقائية: إيقاف";
    if (self.hostLockButton && ![self.hostLockButton.currentTitle isEqualToString:autoTitle]) {
        [self.hostLockButton setTitle:autoTitle forState:UIControlStateNormal];
        self.hostLockButton.backgroundColor = autoArmed ?
            [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0] :
            [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
    int32_t pending = __atomic_load_n(&gOGS.forceHostReq, __ATOMIC_ACQUIRE);
    // UNKNOWN is safer than falsely declaring room ownership with a stale tick.
    int32_t readPresence = __atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE);
    int32_t localActor = __atomic_load_n(&gOGSPresenceActorID, __ATOMIC_ACQUIRE);
    int32_t localMaster = __atomic_load_n(&gOGSLocalMasterActorID, __ATOMIC_ACQUIRE);
    NSString *masterStatus = hookActive ?
        (!snapshot.inRoom ? @"خارج" : (snapshot.isMaster ? @"أنت" : @"غيرك")) :
        (readPresence == 1 && localMaster > 0 && localActor > 0 ?
            (localActor == localMaster ? @"أنت (محليًا)" :
             [NSString stringWithFormat:@"#%d (محليًا)", localMaster]) :
            @"غير مؤكد");
    self.titleLabel.text = [NSString stringWithFormat:@"OGS | هوست:%@ | تحديث:%@ | طلب:%@", masterStatus, hookActive ? @"نشط" : @"متوقف", pending ? @"معلق" : @"لا"];
    uint32_t selected = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);

    if (count == 0) {
        __atomic_store_n(&gOGS.selectedPeer, 0, __ATOMIC_RELEASE);
        self.playerLabel.text = hookActive ? @"المحدد: لا يوجد لاعبين معك حالياً" :
            @"قائمة اللاعبين غير متاحة: تحديث اللعبة متوقف";
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

    uint32_t blocked = __atomic_load_n(&gOGS.blockedKicksCount, __ATOMIC_RELAXED);
    int32_t retries = 0;
    char hjBuf[OGS_MAX_NAME_BYTES];
    memset(hjBuf, 0, sizeof(hjBuf));

    os_unfair_lock_lock(&gStateLock);
    retries = gOGS.kickRetries;
    memcpy(hjBuf, gOGS.lastHijackerName, sizeof(hjBuf));
    os_unfair_lock_unlock(&gStateLock);

    if (!OGSFindGameImage()) {
        self.statusLabel.text = @"تعذر العثور على صورة اللعبة fps؛ البيانات والهوست غير متاحين";
    } else if (__atomic_load_n(&gOGS.magicBulletOn, __ATOMIC_ACQUIRE)) {
        uint32_t calls = __atomic_load_n(&gMagicCallbacks, __ATOMIC_RELAXED);
        uint32_t reads = __atomic_load_n(&gMagicArrayReads, __ATOMIC_RELAXED);
        uint32_t edits = __atomic_load_n(&gMagicMutations, __ATOMIC_RELAXED);
        self.statusLabel.text = [NSString stringWithFormat:@"السحري: مرور %u | مصفوفة %u | تعديل %u", calls, reads, edits];
    } else if (__atomic_load_n(&gOGS.godModeOn, __ATOMIC_ACQUIRE)) {
        uint32_t calls = __atomic_load_n(&gGodCallbacks, __ATOMIC_RELAXED);
        uint32_t blocks = __atomic_load_n(&gGodLocalBypasses, __ATOMIC_RELAXED);
        uint32_t unknown = __atomic_load_n(&gGodUnverifiedPasses, __ATOMIC_RELAXED);
        self.statusLabel.text = [NSString stringWithFormat:@"الدرع: ورود %u | منع %u | مجهول %u", calls, blocks, unknown];
    } else if (retries > 0) {
        self.statusLabel.text = @"جاري إرسال حزمة الطرد للسيرفر...";
    } else if (hjBuf[0] != '\0') {
        NSString *hj = [NSString stringWithUTF8String:hjBuf];
        self.statusLabel.text = [NSString stringWithFormat:@"آخر سارق: %@ | صد طرد: %u 🛡️", hj ?: @"", blocked];
    } else {
        int32_t presence = __atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE);
        NSString *roomLine = hookActive ?
            (snapshot.inRoom ? (snapshot.isMaster ? @"هوست: أنت 👑" : @"داخل الروم | الهوست لغيرك") : @"خارج الروم") :
            (presence == 1 && localMaster > 0 && localActor > 0 ?
                (localMaster == localActor ? @"داخل الروم | أنت الهوست محليًا" :
                 [NSString stringWithFormat:@"داخل الروم | الهوست محليًا #%d", localMaster]) :
             presence == 2 ? @"لا توجد غرفة في الذاكرة المحلية" : @"حالة الروم أو الهوست غير مؤكدة");
        self.statusLabel.text = [NSString stringWithFormat:@"%@ | صد طرد: %u 🛡️",
                                 roomLine, blocked];
    }
    [self.unbanButton setTitle:[NSString stringWithFormat:@"فك الحظر (%lu)", (unsigned long)[self bannedCountSafe]] forState:UIControlStateNormal];
}

- (void)showHookDiagnostics:(UITapGestureRecognizer *)gesture {
    (void)gesture;
    uintptr_t cashSlot = OGSResolveRVA(gOffsets.tblCashUpdate);
    uintptr_t chatSlot = OGSResolveRVA(gOffsets.tblChatUpdate);
    void *cashFn = NULL, *chatFn = NULL;
    BOOL cashReadable = cashSlot && OGSReadPointer(cashSlot, &cashFn);
    BOOL chatReadable = chatSlot && OGSReadPointer(chatSlot, &chatFn);
    BOOL cashHook = cashReadable && cashFn == (void *)&hook_CashUpdate;
    BOOL chatHook = chatReadable && chatFn == (void *)&hook_ChatUpdate;
    BOOL cashWritable = cashSlot && OGSIsWritableMappedSlot(cashSlot);
    BOOL chatWritable = chatSlot && OGSIsWritableMappedSlot(chatSlot);
    double lastTick = 0.0;
    os_unfair_lock_lock(&gStateLock);
    lastTick = gOGS.lastUnityFrameTick;
    os_unfair_lock_unlock(&gStateLock);
    double age = lastTick > 0.0 ? CFAbsoluteTimeGetCurrent() - lastTick : -1.0;
    OGSRoomSnapshot snap = OGSCurrentSnapshot();
    int32_t queued = __atomic_load_n(&gOGS.forceHostReq, __ATOMIC_ACQUIRE);
    NSString *details = [NSString stringWithFormat:
        @"غرفة: %@ | المالك حسب اللعبة: %@\n"
         "تحديث اللعبة: %@\n"
         "آخر تحديث منذ: %@\n"
         "Cash hook: %@ | خانة قابلة للكتابة: %@\n"
         "Chat hook: %@ | خانة قابلة للكتابة: %@\n"
         "طلب في الانتظار: %@\n"
         "تغير صلاحية المالك لا يثبت إلا من حالة Photon.",
        age >= 0.0 && age <= 0.5 ? (snap.inRoom ? @"داخل" : @"خارج") :
            (__atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE) == 1 ? @"مرصودة من الذاكرة" :
             __atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE) == 2 ? @"لا توجد غرفة محلياً" : @"غير مؤكدة"),
        age >= 0.0 && age <= 0.5 ? (snap.isMaster ? @"أنت" : @"لاعب آخر") :
            (__atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE) == 1 &&
             __atomic_load_n(&gOGSLocalMasterActorID, __ATOMIC_ACQUIRE) > 0 &&
             __atomic_load_n(&gOGSPresenceActorID, __ATOMIC_ACQUIRE) > 0 ?
                (__atomic_load_n(&gOGSLocalMasterActorID, __ATOMIC_ACQUIRE) ==
                 __atomic_load_n(&gOGSPresenceActorID, __ATOMIC_ACQUIRE) ?
                 @"أنت (محليًا)" :
                 [NSString stringWithFormat:@"لاعب %d (محليًا)",
                    __atomic_load_n(&gOGSLocalMasterActorID, __ATOMIC_ACQUIRE)]) :
                @"غير مؤكد"),
        age >= 0.0 && age <= 0.5 ? @"نشط" : @"متوقف",
        age >= 0.0 ? [NSString stringWithFormat:@"%.1f ثانية", age] : @"لا يوجد",
        cashHook ? @"مركب" : (cashReadable ? @"غير مركب" : @"غير قابل للقراءة"),
        cashWritable ? @"نعم" : @"لا",
        chatHook ? @"مركب" : (chatReadable ? @"غير مركب" : @"غير قابل للقراءة"),
        chatWritable ? @"نعم" : @"لا",
        queued ? @"نعم" : @"لا"];
    details = [details stringByAppendingFormat:
        @"\nStage22: legacy chat hooks DISABLED (wrong constructor slots)"
         "\nOnEvent install failures=%u | Update install failures=%u"
         "\nPhoton responses hook status=%u (1=installed,2=bad slot,3=unavailable)"
         "\nOpResponse entry=%llu exit=%llu | Op252 replies=%llu"
         "\nOp252 return 0=%llu nonzero=%llu parsefail=%u lastReturn=%d"
         "\nOp252 includes ALL room properties; not proof of Master authority.",
        __atomic_load_n(&gOGSOnEventInstallFailures, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSPhotonUpdateInstallFailures, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSResponseHookStatus, __ATOMIC_ACQUIRE),
        (unsigned long long)__atomic_load_n(&gOGSResponseEntryCalls, __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSResponseExitCalls, __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSSetProps252Replies, __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSSetProps252ZeroReturn, __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSSetProps252NonzeroReturn, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSSetProps252ParseErrors, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSSetProps252LastReturnCode, __ATOMIC_ACQUIRE)];
    details = [details stringByAppendingFormat:
        @"\nStage23 cached Update: status=%u (1=already,2=repaired,3=not ready,4=identity,5=memory,6=mismatch)"
         "\nCache repair attempts=%u | matched=%u | last pointer=0x%llx"
         "\nDoes NOT change Event203, host rate limits, or other method caches.",
        __atomic_load_n(&gOGSCachedUpdateStatus, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSCachedUpdateAttempts, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSCachedUpdateEntryMatched, __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSCachedUpdateObservedEntry,
                                              __ATOMIC_ACQUIRE)];
    details = [details stringByAppendingFormat:
        @"\nStage24 Master receiver cache status W/P/T/PB/I/G=%u/%u/%u/%u/%u/%u"
         "\nStatus: 1=already,2=repaired,3=not ready,4=identity,5=memory,6=mismatch"
         "\nMaster receiver entries W/P/T/PB/I/G=%llu/%llu/%llu/%llu/%llu/%llu"
         "\nRepair scans=%u | receiver entries are NOT unique host transfers."
         "\nEvent203 and host request quotas are unchanged.",
        __atomic_load_n(&gOGSMasterCacheStatus[0], __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSMasterCacheStatus[1], __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSMasterCacheStatus[2], __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSMasterCacheStatus[3], __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSMasterCacheStatus[4], __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSMasterCacheStatus[5], __ATOMIC_ACQUIRE),
        (unsigned long long)__atomic_load_n(&gOGSMasterReceiverEntries[0], __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSMasterReceiverEntries[1], __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSMasterReceiverEntries[2], __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSMasterReceiverEntries[3], __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSMasterReceiverEntries[4], __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSMasterReceiverEntries[5], __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSMasterCacheRounds, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nStage26 EntryGuard armed=%u | reclose queued=%u | local closed samples=%u"
         "\nEntryGuard no-master=%u | rate-limited=%u | changed-room disarms=%u"
         "\nRoom close only blocks NEW joins when server accepts it; not an anti-host takeover guarantee.",
        __atomic_load_n(&gOGSClosedGuardEnabled, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSClosedGuardQueued, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSClosedGuardClosedObserved, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSClosedGuardNoAuthority, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSClosedGuardRateLimited, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSClosedGuardDisarmed, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nStage27 LeaveRoom cache=%u | local disconnect cache=%u | strict lock=%u"
         "\nLeaveRoom entry=%u blocked=%u forwarded=%u | DemoLeave entry=%u blocked=%u forwarded=%u"
         "\nLocal OnDisconnectedFromPhoton=%u | room vanished=%u"
         "\nNo Event203 + local disconnect means different Photon exit path, not confirmed attacker action.",
        __atomic_load_n(&gOGSMasterCacheStatus[6], __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSMasterCacheStatus[7], __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGS.antiKickHardLock, __ATOMIC_ACQUIRE) ? 1u : 0u,
        __atomic_load_n(&gOGSLeaveRoomHookEntries, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSLeaveRoomBlocked, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSLeaveRoomForwarded, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSDemoLeaveEntries, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSDemoLeaveBlocked, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSDemoLeaveForwarded, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSWorkerPhotonDisconnectNotices, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSObservedRoomDisappearances, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nPhotonHandler.Update entry=%llu exit=%llu | privacy pending=%u | applied=%u | rejected=%u",
        (unsigned long long)__atomic_load_n(&gOGSPhotonHandlerUpdateCalls, __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSPhotonHandlerUpdateExitCalls, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSPrivacyPending, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSPrivacyApplied, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSPrivacyRejected, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:@"\nCash calls: %llu | Chat calls: %llu\nNetwork events: %llu | Host switches: %llu",
        (unsigned long long)__atomic_load_n(&gOGSCashHookCalls, __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSChatHookCalls, __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSNetworkEvents, __ATOMIC_RELAXED),
        (unsigned long long)__atomic_load_n(&gOGSMasterSwitchEvents, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nManual kick: pending=%u | local API accepted=%u | rejected=%u | expired=%u"
         "\nStage25 kick UI denied=%u | wrong room/actor=%u"
         "\nSpeed setter: applied=%u | pending=%u | deferred=%u",
        __atomic_load_n(&gOGSManualKickPending, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSManualKickSubmitted, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSManualKickRejected, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSManualKickExpired, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSManualKickPreflightDenied, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSRecoveryScopeRejected, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSSpeedApplied, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGS.speedDirty, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSSpeedDeferred, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nRead-only roster: active=%u | list=%u | failures=%u | names tracked=%lu",
        __atomic_load_n(&gOGSRosterReadOK, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSRosterLastCount, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSRosterReadFail, __ATOMIC_RELAXED),
        (unsigned long)self.sessionNameHistory.count];
    details = [details stringByAppendingFormat:
        @"\nRead-only presence: %@ | polls: %u | read failures: %u | local actor: %d",
        __atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE) == 1 ? @"IN" :
          (__atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE) == 2 ? @"OUT" : @"UNKNOWN"),
        __atomic_load_n(&gOGSPresenceProbeCalls, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSPresenceReadFailures, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSPresenceActorID, __ATOMIC_ACQUIRE)];
    int32_t observedMaster = __atomic_load_n(&gOGSLocalMasterActorID, __ATOMIC_ACQUIRE);
    int32_t myActor = __atomic_load_n(&gOGSPresenceActorID, __ATOMIC_ACQUIRE);
    int32_t presence = __atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE);
    NSString *matchText = presence == 1 && observedMaster > 0 && myActor > 0 ?
        (observedMaster == myActor ? @"YOU (local)" : @"OTHER (local)") : @"UNKNOWN";
    details = [details stringByAppendingFormat:
        @"\nPhoton local master actor: %d | local actor: %d | match: %@\nMaster reads: %u | failures: %u | changes: %u",
        observedMaster, myActor, matchText,
        __atomic_load_n(&gOGSLocalMasterSamples, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSLocalMasterReadFailures, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSLocalMasterChanges, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nLast local master transition: %d -> %d | changes: %u"
         "\nNetwork code samples: 203=%u, 208=%u, 253=%u, 254=%u, 255=%u | last=%u | unreadable=%u",
        __atomic_load_n(&gOGSLastMasterFromActor, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSLastMasterToActor, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSLocalMasterChanges, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSEventCodes[203], __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSEventCodes[208], __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSEventCodes[253], __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSEventCodes[254], __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSEventCodes[255], __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSLastEventCode, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSEventCodeReadFailures, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nEvent callback master observations: %u | incomplete: %u"
         "\nMaster changed during callback: %u | code: %u | %d -> %d"
         "\nCallback correlation is not proof of server-side authorization.",
        __atomic_load_n(&gOGSInlineMasterObservations, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSInlineMasterReadFailures, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSInlineMasterTransitions, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSInlineMasterChangeCode, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSInlineMasterFrom, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSInlineMasterTo, __ATOMIC_ACQUIRE)];
    details = [details stringByAppendingFormat:
        @"\nManual host restore: queued=%u | attempts=%u | API accepted=%u | failed=%u | skipped=%u"
         "\nAPI returned true indicates local submission, NOT server confirmation.",
        __atomic_load_n(&gOGSManualRecoveryPending, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSManualRecoveryAttempts, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSManualRecoveryAccepted, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSManualRecoveryFailed, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSManualRecoverySkipped, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nStage 20 recovery probes: Photon Update=%u | OnEvent=%u"
         "\nUpdate fallback runs at most ~8 times/s (not network sends)."
         "\nServer-confirmed MasterClient: not measurable by these local-only counters.",
        __atomic_load_n(&gOGSRecoveryUpdateProbes, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSRecoveryEventProbes, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nObserved local host loss: event208=%u | event253=%u | update=%u"
         "\n208 is confirmed from fps ARM64 RaiseEvent; still not server proof.",
        __atomic_load_n(&gOGSHostLossEvent208, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSHostLossEvent253, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSHostLossUpdate, __ATOMIC_RELAXED)];
    OGSHostTimelineEntry trace[12] = {};
    uint32_t traceCount = 0;
    os_unfair_lock_lock(&gStateLock);
    traceCount = (uint32_t)fmin((double)gOGSHostTimelineWrites, 12.);
    for (uint32_t i = 0; i < traceCount; ++i)
        trace[i] = gOGSHostTimeline[(gOGSHostTimelineWrites - 1u - i) %
                                    OGS_MASTER_TIMELINE_CAPACITY];
    os_unfair_lock_unlock(&gStateLock);
    details = [details stringByAppendingString:@"\nRecent local master transitions (newest first):"];
    for (uint32_t i = 0; i < traceCount; ++i) {
        const OGSHostTimelineEntry *e = &trace[i];
        details = [details stringByAppendingFormat:
            @"\n- %.0fms ago | %d -> %d | %@%u | yours~%.1fms",
            fmax(0., (CFAbsoluteTimeGetCurrent() - e->observedAt) * 1000.),
            e->fromActor, e->toActor, e->viaUpdate ? @"Update" : @"Event",
            e->eventCode, e->locallyHeldMs];
    }
    details = [details stringByAppendingFormat:
        @"\nManual deferred=%u | expired=%u | room+actor bound | TTL=12s"
         "\nImmediate local read after API: mine=%u | other=%u | read fail=%u"
         "\nThese immediate samples are local, NOT server acknowledgments.",
        __atomic_load_n(&gOGSManualRecoveryDeferred, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSManualRecoveryExpired, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSImmediateLocalMaster, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSImmediateOtherMaster, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSImmediateMasterReadFail, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nAuto recovery: %@ | attempts=%u | API accepted=%u | failed=%u"
         "\nCooldown skips=%u | guard skips=%u | disarms=%u",
        __atomic_load_n(&gOGSAutoEnabled, __ATOMIC_ACQUIRE) ? @"ARMED" : @"OFF",
        __atomic_load_n(&gOGSAutoAttempts, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSAutoAccepted, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSAutoFailed, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSAutoCooldown, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSAutoGuarded, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSAutoDisarmed, __ATOMIC_RELAXED)];
    uint32_t budgetUsed = 0;
    double rateWindowLeft = 0.0;
    os_unfair_lock_lock(&gStateLock);
    budgetUsed = gOGSAutoWindowAttempts;
    if (gOGSAutoWindowStartedAt > 0.)
        rateWindowLeft = fmax(0.0, kOGSAutoWindowSeconds -
                             (CFAbsoluteTimeGetCurrent() - gOGSAutoWindowStartedAt));
    os_unfair_lock_unlock(&gStateLock);
    double availableTokens = 0.;
    os_unfair_lock_lock(&gStateLock);
    availableTokens = gOGSRecoveryTokens;
    os_unfair_lock_unlock(&gStateLock);
    details = [details stringByAppendingFormat:
        @"\nRecovery tokens=%.2f/3 | shared manual+auto | min interval=650ms",
        availableTokens];
    details = [details stringByAppendingFormat:
        @"\nAuto pending loss=%u | deferred queued=%u | deferred executed=%u | cancelled=%u"
         "\nRolling rate limit=%u/%u in 60s | window resets in %.1fs"
         "\nRate-limited windows=%u | retries while still not host=%u"
         "\nStay ARMED when limited; requests continue on the next Photon Update/Event after cooldown/window reset.",
        __atomic_load_n(&gOGSAutoPendingLoss, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSAutoDeferredQueued, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSAutoDeferredExecuted, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSAutoDeferredCancelled, __ATOMIC_RELAXED),
        budgetUsed, kOGSAutoWindowAttemptLimit, rateWindowLeft,
        __atomic_load_n(&gOGSAutoRateLimitedWindows, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSAutoRetriesWhileLost, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nRejoin approvals=%u | local actor may differ from first entrant"
         "\nA rejoin request must be explicitly approved; it does not prove server ownership.",
        __atomic_load_n(&gOGSAutoRejoinApprovals, __ATOMIC_RELAXED)];
    details = [details stringByAppendingFormat:
        @"\nKick event 203: locally filtered=%u | within 5s of host request=%u | last proximity=%ums"
         "\nBan processing: evaluations=%u | matched=%u | local kick API accepted=%u"
         "\nBan enforcement engine tick: %@. Local filters cannot provide server-wide account bans.",
        __atomic_load_n(&gOGSFilteredEvent203, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSEvent203NearRecovery, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSLastEvent203ProximityMs, __ATOMIC_ACQUIRE),
        __atomic_load_n(&gOGSBanEvaluations, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSBanMatches, __ATOMIC_RELAXED),
        __atomic_load_n(&gOGSBanKickLocalAccepted, __ATOMIC_RELAXED),
        age >= 0.0 && age <= 0.5 ? @"ACTIVE" : @"INACTIVE"];
    char eventTrailCopy[sizeof(gOGSLastTransitionEventTrail)] = {0};
    os_unfair_lock_lock(&gStateLock);
    memcpy(eventTrailCopy, gOGSLastTransitionEventTrail, sizeof(eventTrailCopy));
    os_unfair_lock_unlock(&gStateLock);
    details = [details stringByAppendingFormat:
        @"\nNetwork event 201 count: %u"
         "\nEvents before observed master transfer (newest first): %s"
         "\nTiming indicates proximity only, not causation.",
        __atomic_load_n(&gOGSEventCodes[201], __ATOMIC_RELAXED),
        eventTrailCopy[0] ? eventTrailCopy : "none within 5s"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تشخيص تحديث OGS"
                             message:details preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"نسخ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        [UIPasteboard generalPasteboard].string = details;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إغلاق" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *root = [self gameMainWindow].rootViewController;
    if (root && !root.presentedViewController)
        [root presentViewController:alert animated:YES completion:nil];
}

- (void)toggleMenu {
    self.menuPanel.hidden = !self.menuPanel.hidden;
    if (!self.menuPanel.hidden) {
        OGSInstallHooks();
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

// UI only queues an intent. The managed Room setters execute on OnEvent.
- (void)requestPrivacyMode:(uint32_t)mode forced:(BOOL)forced {
    uintptr_t room = 0;
    int32_t actor = 0, master = 0;
    bool open = true, visible = true;
    if (!OGSReadAutoRoom(&room, &actor, &master) ||
        !OGSReadRoomPrivacy(room, &open, &visible)) {
        self.statusLabel.text = @"لا يمكن قراءة حالة الروم؛ ادخل رومًا مستقرًا";
        return;
    }
    if (actor != master) {
        self.statusLabel.text = @"تغيير خصوصية الروم متاح عندما تكون الهوست فقط";
        return;
    }
    bool alreadyActive = (mode == 1 && !visible && open) ||
                         (mode == 2 && !visible && !open);
    uint32_t targetMode = (!forced && alreadyActive) ? 3u : mode;
    os_unfair_lock_lock(&gStateLock);
    gOGSPrivacyRequestedRoom = room;
    gOGSPrivacyRequestedActor = actor;
    __atomic_store_n(&gOGSPrivacyPending, targetMode, __ATOMIC_RELEASE);
    os_unfair_lock_unlock(&gStateLock);
    self.statusLabel.text = targetMode == 3 ? @"طلب إظهار الروم وفتحه في انتظار تحديث اللعبة" :
        targetMode == 1 ? @"طلب إخفاء الروم مع السماح بالدخول باسمه" :
                          @"طلب إخفاء الروم وإغلاق الانضمام";
}
- (void)requestPrivacyMode:(uint32_t)mode {
    [self requestPrivacyMode:mode forced:NO];
}
- (void)togglePrivacyHidden:(UIButton *)sender {
    (void)sender;
    // Explicitly choosing hidden-but-open disables closed-room enforcement.
    os_unfair_lock_lock(&gStateLock);
    __atomic_store_n(&gOGSClosedGuardEnabled, 0u, __ATOMIC_RELEASE);
    os_unfair_lock_unlock(&gStateLock);
    [self requestPrivacyMode:1u];
}
- (void)togglePrivacyClosed:(UIButton *)sender {
    (void)sender;
    uintptr_t room = 0;
    int32_t actor = 0, master = 0;
    bool open = true, visible = true;
    bool valid = OGSReadAutoRoom(&room, &actor, &master) &&
                 OGSReadRoomPrivacy(room, &open, &visible);
    os_unfair_lock_lock(&gStateLock);
    bool sameArmed = __atomic_load_n(&gOGSClosedGuardEnabled, __ATOMIC_ACQUIRE) &&
                     (!valid ||
                      (gOGSClosedGuardRoom == room && gOGSClosedGuardActor == actor));
    if (sameArmed)
        __atomic_store_n(&gOGSClosedGuardEnabled, 0u, __ATOMIC_RELEASE);
    os_unfair_lock_unlock(&gStateLock);
    if (sameArmed) {
        // Never reopen another room or after losing local MasterClient.
        if (valid && actor == master)
            [self requestPrivacyMode:3u forced:YES];
        else
            self.statusLabel.text = @"توقفت الحراسة؛ لم يتم فتح الروم بسبب غياب صلاحية الهوست";
        return;
    }
    if (!valid || actor != master) {
        self.statusLabel.text = @"الحراسة تحتاج غرفة ثابتة وأن تكون أنت الهوست محليًا";
        return;
    }
    os_unfair_lock_lock(&gStateLock);
    gOGSClosedGuardRoom = room;
    gOGSClosedGuardActor = actor;
    gOGSClosedGuardLastScan = 0.;
    gOGSClosedGuardLastRequest = 0.;
    gOGSClosedGuardWindowStart = 0.;
    gOGSClosedGuardWindowRequests = 0;
    __atomic_store_n(&gOGSClosedGuardEnabled, 1u, __ATOMIC_RELEASE);
    os_unfair_lock_unlock(&gStateLock);
    [self requestPrivacyMode:2u forced:YES];
    self.statusLabel.text = @"حراسة الدخول مفعلة لهذه الغرفة؛ لا تمنع الموجودين من تبديل الهوست";
}

- (void)claimHostNow:(UIButton *)sender {
    (void)sender;
    int32_t presence = __atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE);
    int32_t localActor = __atomic_load_n(&gOGSPresenceActorID, __ATOMIC_ACQUIRE);
    int32_t masterActor = __atomic_load_n(&gOGSLocalMasterActorID, __ATOMIC_ACQUIRE);
    if (presence != 1 || localActor <= 0 || masterActor <= 0) {
        self.statusLabel.text = @"حالة الغرفة أو الهوست غير مؤكدة؛ افتح التشخيص أولًا";
        return;
    }
    if (localActor == masterActor) {
        self.statusLabel.text = @"أنت الهوست بالفعل بحسب بيانات Photon المحلية";
        return;
    }
    static double lastManualClick = 0.0; // UIKit thread only
    double now = CFAbsoluteTimeGetCurrent();
    if (now - lastManualClick < kOGSAutoCooldownSeconds) {
        self.statusLabel.text = @"انتظر قليلًا قبل الطلب التالي؛ السحب اليدوي والتلقائي يشتركان في الحماية";
        return;
    }
    uintptr_t requestedRoom = 0;
    int32_t verifiedActor = 0, verifiedMaster = 0;
    if (!OGSReadAutoRoom(&requestedRoom, &verifiedActor, &verifiedMaster) ||
        verifiedActor != localActor || verifiedMaster == verifiedActor) {
        self.statusLabel.text = @"تغيرت حالة الغرفة أثناء الضغط؛ أعد المحاولة";
        return;
    }
    lastManualClick = now;
    os_unfair_lock_lock(&gStateLock);
    gOGSManualRecoveryRoom = requestedRoom;
    gOGSManualRecoveryActor = verifiedActor;
    gOGSManualRecoveryQueuedAt = now;
    gOGSManualRecoveryDeferredCounted = false;
    __atomic_store_n(&gOGSManualRecoveryPending, 1u, __ATOMIC_RELEASE);
    os_unfair_lock_unlock(&gStateLock);
    self.statusLabel.text = @"طلب يدوي معلّق حتى 12 ثانية؛ ضمن نفس الحد المشترك، وليس إثبات استعادة";
}

- (void)toggleAutoHost:(UIButton *)s {
    // Disable the legacy path (Unity update hooks never fire in this build).
    __atomic_store_n(&gOGS.autoHostOn, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&gOGSHostMonitorOn, 0, __ATOMIC_RELEASE);
    if (__atomic_load_n(&gOGSAutoEnabled, __ATOMIC_ACQUIRE)) {
        OGSDisarmAutoRoom();
        [s setTitle:@"استعادة تلقائية: إيقاف" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
        self.statusLabel.text = @"تم إيقاف الاستعادة التلقائية";
        return;
    }
    uintptr_t room = 0;
    int32_t localActor = 0, master = 0;
    if (!OGSReadAutoRoom(&room, &localActor, &master)) {
        self.statusLabel.text = @"ادخل رومًا مستقرًا أولًا؛ لا توجد بيانات موثوقة لتفعيل الاستعادة";
        return;
    }
    // No actor==1 requirement: a returning creator may be actor 3, 4, ...
    // If MasterClient is someone else, get an explicit affirmative choice
    // before allowing the first recovery request. This prevents accidentally
    // arming auto-claim while browsing unrelated rooms.
    if (master != localActor) {
        int32_t proposedActor = localActor;
        uintptr_t proposedRoom = room;
        UIAlertController *confirm = [UIAlertController
            alertControllerWithTitle:@"استعادة هوست رومك بعد العودة"
            message:@"رقمك تغير أو الهوست مع لاعب آخر. لا يمكن للعميل إثبات أنك منشئ هذه الغرفة بعد إعادة الدخول. استخدم هذا الخيار فقط في رومك الذي أنشأته. هل تريد تفعيل محاولة استعادة للروم الحالي؟"
            preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"إلغاء"
            style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"نعم، هذا رومي"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                (void)action;
                uintptr_t verifiedRoom = 0;
                int32_t verifiedLocal = 0, verifiedMaster = 0;
                if (!OGSReadAutoRoom(&verifiedRoom, &verifiedLocal, &verifiedMaster) ||
                    verifiedRoom != proposedRoom || verifiedLocal != proposedActor) {
                    self.statusLabel.text = @"تغيرت الغرفة أو هويتك أثناء التأكيد؛ أعد التفعيل";
                    return;
                }
                OGSArmAutoRoomBounded(verifiedRoom, verifiedLocal, verifiedMaster);
                __atomic_fetch_add(&gOGSAutoRejoinApprovals, 1u, __ATOMIC_RELAXED);
                [s setTitle:@"استعادة تلقائية: مفعلة 👑" forState:UIControlStateNormal];
                s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
                self.statusLabel.text = verifiedLocal == verifiedMaster ?
                    @"أنت الهوست الآن؛ تمت حماية الروم الحالي" :
                    @"الاستعادة التفاعلية مفعلة؛ 3 طلبات سريعة كحد أقصى، و6 بكل دقيقة";
            }]];
        UIViewController *root = [self gameMainWindow].rootViewController;
        if (root && !root.presentedViewController) {
            [root presentViewController:confirm animated:YES completion:nil];
        } else {
            self.statusLabel.text = @"أغلق أي نافذة أخرى وحاول تفعيل الاستعادة من جديد";
        }
        return;
    }
    // Re-arming the same room does not reset cooldown or its 60s quota.
    OGSArmAutoRoomBounded(room, localActor, master);
    [s setTitle:@"استعادة تلقائية: مفعلة 👑" forState:UIControlStateNormal];
    s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    self.statusLabel.text = master != localActor ?
        @"الاستعادة التفاعلية تنتظر حدث Photon؛ 3 طلبات سريعة، و6 بكل دقيقة" :
        @"الاستعادة التفاعلية مستمرة؛ تشترك اليدوية والتلقائية في الحد";
}

- (void)toggleGodMode:(UIButton *)s {
    int32_t current = __atomic_load_n(&gOGS.godModeOn, __ATOMIC_ACQUIRE);
    int32_t next = current ? 0 : 1;
    if (next && !OGSInstallDamageHookOnDemand(true)) {
        self.statusLabel.text = @"نسخة IPA الحالية لا تحتوي جسر الضرر المجهز قبل التوقيع";
        UIAlertController *warning = [UIAlertController alertControllerWithTitle:@"حماية من الكراش"
            message:@"الميزات تتطلب تجهيز ملف fps 3.4.0 قبل توقيع التطبيق وإعادة حقن OGSMenu. النسخة الأصلية لا تحتوي جسر الضرر."
            preferredStyle:UIAlertControllerStyleAlert];
        [warning addAction:[UIAlertAction actionWithTitle:@"فهمت" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *root = [self gameMainWindow].rootViewController;
        if (root && !root.presentedViewController) [root presentViewController:warning animated:YES completion:nil];
        return;
    }
    __atomic_store_n(&gOGS.godModeOn, next, __ATOMIC_RELEASE);
    if (next) {
        __atomic_store_n(&gGodCallbacks, 0u, __ATOMIC_RELAXED);
        __atomic_store_n(&gGodLocalBypasses, 0u, __ATOMIC_RELAXED);
        __atomic_store_n(&gGodOtherPlayerPasses, 0u, __ATOMIC_RELAXED);
        __atomic_store_n(&gGodUnverifiedPasses, 0u, __ATOMIC_RELAXED);
        [s setTitle:@"درع الحماية: مسلّح 🛡️" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
        self.statusLabel.text = @"الدرع جاهز للاختبار؛ تحقق من عدّاد المنع عند وصول ضرر";
    } else {
        [s setTitle:@"درع الحماية: متوقف 🛡️" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
}

- (void)toggleMagicBullet:(UIButton *)s {
    int32_t current = __atomic_load_n(&gOGS.magicBulletOn, __ATOMIC_ACQUIRE);
    int32_t next = current ? 0 : 1;
    if (next && (!__atomic_load_n(&gOGS.inRoom, __ATOMIC_ACQUIRE) || !OGSInstallDamageHookOnDemand(false))) {
        self.statusLabel.text = @"نسخة IPA الحالية لا تحتوي جسر الضرر المجهز قبل التوقيع";
        UIAlertController *warning = [UIAlertController alertControllerWithTitle:@"حماية من الكراش"
            message:@"الميزات تتطلب تجهيز ملف fps 3.4.0 قبل توقيع التطبيق وإعادة حقن OGSMenu. النسخة الأصلية لا تحتوي جسر الضرر."
            preferredStyle:UIAlertControllerStyleAlert];
        [warning addAction:[UIAlertAction actionWithTitle:@"فهمت" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *root = [self gameMainWindow].rootViewController;
        if (root && !root.presentedViewController) [root presentViewController:warning animated:YES completion:nil];
        return;
    }
    __atomic_store_n(&gOGS.magicBulletOn, next, __ATOMIC_RELEASE);
    if (next) {
        __atomic_store_n(&gMagicCallbacks, 0u, __ATOMIC_RELAXED);
        __atomic_store_n(&gMagicArrayReads, 0u, __ATOMIC_RELAXED);
        __atomic_store_n(&gMagicMutations, 0u, __ATOMIC_RELAXED);
        __atomic_store_n(&gMagicLastOriginalDamage, 0, __ATOMIC_RELAXED);
        __atomic_store_n(&gMagicLastArrayCount, (uintptr_t)0, __ATOMIC_RELAXED);
        [s setTitle:@"طلقة سحرية: قيد الاختبار 🔫" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.80 green:0.35 blue:0.10 alpha:1.0];
        self.statusLabel.text = @"اختبر إصابة فعلية: مرور / مصفوفة / تعديل";
    } else {
        [s setTitle:@"طلقة سحرية: متوقف 🔫" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
}

- (void)toggleAntiKickHardLock:(UIButton *)s {
    gOGS.antiKickHardLock = !gOGS.antiKickHardLock;
    if (gOGS.antiKickHardLock) {
        [s setTitle:@"قفل البقاء: صارم 🔒" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
        self.statusLabel.text = @"قفل البقاء الصارم مفعّل (أوقفه قبل الخروج)";
    } else {
        [s setTitle:@"قفل البقاء: تلقائي 🛡️" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
        self.statusLabel.text = @"الحماية التلقائية ضد الطرد الشبكي نشطة";
    }
}

- (void)cycleChatMode:(UIButton *)s {
    // The legacy chat hooks targeted two unrelated constructors.
    // Leave the feature unavailable until the exact iOS method indices are verified.
    __atomic_store_n(&gOGS.chatMode, 0, __ATOMIC_RELEASE);
    [s setTitle:@"الشات: معطل مؤقتًا" forState:UIControlStateNormal];
    self.statusLabel.text = @"Stage22: تم تعطيل Hooks الشات الخاطئة لحماية الاستقرار";
}

- (BOOL)triggerImmediateKick:(OGSPeerSnapshot)peer {
    int32_t local = __atomic_load_n(&gOGSPresenceActorID, __ATOMIC_ACQUIRE);
    int32_t master = __atomic_load_n(&gOGSLocalMasterActorID, __ATOMIC_ACQUIRE);
    if (gOGSRosterLastRoom == 0 ||
        __atomic_load_n(&gOGSPresenceReadOnly, __ATOMIC_ACQUIRE) != 1 ||
        local <= 0 || master <= 0 || local != master ||
        peer.actorID <= 0 || peer.actorID == local) {
        __atomic_fetch_add(&gOGSManualKickPreflightDenied, 1u, __ATOMIC_RELAXED);
        self.statusLabel.text = local > 0 && master > 0 && local != master ?
            [NSString stringWithFormat:@"لم يُرسل الطرد: الهوست المحلي هو اللاعب %d", master] :
            @"لم يُرسل الطرد: الغرفة أو اللاعب غير مؤكد";
        return NO;
    }
    NSString *pName = [NSString stringWithUTF8String:peer.name];
    NSString *normName = OGSNormalizeKey(pName);
    const char *utf8 = normName.UTF8String;

    OGSResetTrackerForActor(peer.actorID);

    os_unfair_lock_lock(&gStateLock);
    gOGS.lastThreatTime = CFAbsoluteTimeGetCurrent();
    gOGS.kickTargetID = peer.actorID;
    if (utf8) {
        snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", utf8);
    }
    gOGSManualKickRoom = gOGSRosterLastRoom;
    gOGSManualKickActor = peer.actorID;
    gOGSManualKickQueuedAt = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_unlock(&gStateLock);
    __atomic_store_n(&gOGSManualKickPending, 1u, __ATOMIC_RELEASE);
    return YES;
}

- (void)kickSelected:(UIButton *)s {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    if (!snapshot.count) {
        self.statusLabel.text = @"لم يُرسل الطرد: لا يوجد لاعب محدد بالقائمة";
        return;
    }
    uint32_t selected = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);
    if (selected >= snapshot.count) selected = 0;

    OGSPeerSnapshot peer = snapshot.peers[selected];
    NSString *pName = [NSString stringWithUTF8String:peer.name];
    BOOL queued = [self triggerImmediateKick:peer];
    if (queued)
        self.statusLabel.text = [NSString stringWithFormat:
            @"طرد %@: الطلب مجهّز محليًا ولم يؤكده الخادم", pName ?: @"اللاعب"];
    // When the caller is not Master, retain the precise preflight failure.
}

- (void)banSelected:(UIButton *)s {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    if (!snapshot.count) return;
    uint32_t selected = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);
    if (selected >= snapshot.count) selected = 0;

    OGSPeerSnapshot peer = snapshot.peers[selected];
    NSString *pName = [NSString stringWithUTF8String:peer.name];
    NSString *normName = OGSNormalizeKey(pName);

    [self recordHijackerName:normName actorID:peer.actorID];
    BOOL queued = [self triggerImmediateKick:peer];
    [self refreshUI];
    self.statusLabel.text = queued ?
        [NSString stringWithFormat:@"حُفظ الاسم محليًا؛ طلب طرد %@ مجهّز فقط", pName ?: @"اللاعب"] :
        [NSString stringWithFormat:@"حُفظ الاسم محليًا؛ لم يُرسل طرد %@", pName ?: @"اللاعب"];
}

- (void)toggleRoomLock:(UIButton *)s {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    os_unfair_lock_lock(&gBanSetLock);
    self.roomLockActive = !self.roomLockActive;
    [self.allowedNamesWhenLocked removeAllObjects];

    if (self.roomLockActive) {
        for (uint32_t i = 0; i < snapshot.count; i++) {
            NSString *pName = [NSString stringWithUTF8String:snapshot.peers[i].name];
            NSString *norm = OGSNormalizeKey(pName);
            if (norm.length > 0) [self.allowedNamesWhenLocked addObject:norm];
        }
    }
    BOOL isLocked = self.roomLockActive;
    os_unfair_lock_unlock(&gBanSetLock);

    OGSResetAutoKickTrackers();

    if (isLocked) {
        __atomic_store_n(&gOGS.forceHostReq, 1, __ATOMIC_RELEASE);
        [s setTitle:@"حظر محلي: مفعّل" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    } else {
        [s setTitle:@"حظر محلي: إيقاف" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
    [self refreshUI];
    self.statusLabel.text = isLocked ?
        @"الحظر محلي ويعتمد على تحديث Unity؛ ليس قفل دخول على الخادم" :
        @"تم إيقاف الحظر المحلي";
}

- (void)clearBanList:(UIButton *)s {
    os_unfair_lock_lock(&gBanSetLock);
    [self.bannedNames removeAllObjects];
    [self.bannedActorIDs removeAllObjects];
    os_unfair_lock_unlock(&gBanSetLock);

    os_unfair_lock_lock(&gStateLock);
    gOGS.lastHijackerName[0] = '\0';
    gOGS.kickRetries = 0;
    gOGS.kickTargetID = -1;
    os_unfair_lock_unlock(&gStateLock);

    OGSResetAutoKickTrackers();
    [self saveLocalBans];
    [self refreshUI];
    self.statusLabel.text = @"تم مسح قائمة المحظورين بالكامل";
}

- (void)applySpeed:(float)value {
    OGSRequestSpeed(value);
    // Defer managed setter; UIKit only stores the request.
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
        if (val >= 0.1f && val <= 20.0f) [self applySpeed:val];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [rootVC presentViewController:alert animated:YES completion:nil];
}
@end

__attribute__((constructor))
static void ogs_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OGSInstallHooks();
        [[OGSModMenu sharedInstance] setupMenu];
    });
}
