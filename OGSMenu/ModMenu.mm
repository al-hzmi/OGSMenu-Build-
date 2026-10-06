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
// MARK: - 1. Corrected Engine Offsets (Falcon_Clean_v9 Verified)
// ============================================================
static const uintptr_t RVA_PHOTON_NET_TYPEINFO = 0x0281B1C8;

typedef struct {
    uintptr_t tblCashUpdate;            // Type4640::Update
    uintptr_t tblChatUpdate;            // Type4635::Update (Corrected: 0x238FCE8)
    uintptr_t tblSendChatRemote;        // Type4635::SendChatRemote (Corrected: 0x238FD00)
    uintptr_t tblOnEvent;               // Type4870::OnEvent (0x2390048)
    uintptr_t tblDisconnect;            // Type4870::Disconnect (0x238FF48)
    uintptr_t tblLeaveRoom;             // Type4884::LeaveRoom (0x2390A10)
    uintptr_t tblType4995LeaveRoom;     // Type4995::LeaveRoom (0x238E518)
    uintptr_t tblOnMasterSwitched1;     // Type4821::OnMasterClientSwitched (0x2392628)
    uintptr_t tblOnMasterSwitched2;     // Type4894::OnMasterClientSwitched (0x2391000)
    uintptr_t tblOnMasterSwitched3;     // Type4935::OnMasterClientSwitched (0x238F228)
    uintptr_t tblOnMasterSwitched4;     // Type4967::OnMasterClientSwitched (0x23903E0)
    uintptr_t tblOnMasterSwitched5;     // Type4968::OnMasterClientSwitched (0x238E730)
    uintptr_t tblPeerSync;              // PhotonNetwork::CloseConnection (0x2390A98)
    uintptr_t tblSetMaster;             // PhotonNetwork::SetMasterClient (0x2390AA0)
    uintptr_t tblOnDisconnect;          // OnPhotonPlayerDisconnected (0x2391930)

    uintptr_t rvaSetTimescale;          // Time::set_timeScale (0x198AC4C)
    uintptr_t rvaInRoom;                // PhotonNetwork::get_inRoom (0x013CC38C)
    uintptr_t rvaIsMaster;              // PhotonNetwork::get_isMasterClient (0x013CC2BC)
    uintptr_t rvaGetMasterPeer;         // PhotonNetwork::get_masterClient (0x013CACA4)
    uintptr_t rvaGetLocalPlayer;        // PhotonNetwork::get_player (0x013CABF0)
    uintptr_t rvaGetRoom;               // PhotonNetwork::get_room (0x013CAB28)
    uintptr_t rvaAllPlayers;            // PhotonNetwork::get_playerList (0x013CAEC4)
    uintptr_t rvaGetPeers;              // PhotonNetwork::get_otherPlayers (0x013CAF78)
    uintptr_t rvaPlayerGetName;         // PhotonPlayer::get_name (0x013D7534)
    uintptr_t rvaPlayerGetID;           // PhotonPlayer::get_ID (0x013CC384)
    uintptr_t rvaNetPeerGetMMasterId;   // 0x013AB2A4
    uintptr_t rvaNetPeerSetMMasterId;   // Corrected: 0x013AB384
    uintptr_t rvaArabicFix;             // Type4294::Fix (0x0130F538)
    uintptr_t rvaFastAllocateString;    // System.String::FastAllocateString (0x01B33DB8)
} OGSOffsetsConfig;

static OGSOffsetsConfig gOffsets = {
    .tblCashUpdate          = 0x23918B8,
    .tblChatUpdate          = 0x238FCE8,
    .tblSendChatRemote      = 0x238FD00,
    .tblOnEvent             = 0x2390048,
    .tblDisconnect          = 0x238FF48,
    .tblLeaveRoom           = 0x2390A10,
    .tblType4995LeaveRoom   = 0x238E518,
    .tblOnMasterSwitched1   = 0x2392628,
    .tblOnMasterSwitched2   = 0x2391000,
    .tblOnMasterSwitched3   = 0x238F228,
    .tblOnMasterSwitched4   = 0x23903E0,
    .tblOnMasterSwitched5   = 0x238E730,
    .tblPeerSync            = 0x2390A98,
    .tblSetMaster           = 0x2390AA0,
    .tblOnDisconnect        = 0x2391930,

    .rvaSetTimescale        = 0x198AC4C,
    .rvaInRoom              = 0x013CC38C,
    .rvaIsMaster            = 0x013CC2BC,
    .rvaGetMasterPeer       = 0x013CACA4,
    .rvaGetLocalPlayer      = 0x013CABF0,
    .rvaGetRoom             = 0x013CAB28,
    .rvaAllPlayers          = 0x013CAEC4,
    .rvaGetPeers            = 0x013CAF78,
    .rvaPlayerGetName       = 0x013D7534,
    .rvaPlayerGetID         = 0x013CC384,
    .rvaNetPeerGetMMasterId = 0x013AB2A4,
    .rvaNetPeerSetMMasterId = 0x013AB384,
    .rvaArabicFix           = 0x0130F538,
    .rvaFastAllocateString  = 0x01B33DB8
};

// ============================================================
// MARK: - 2. Corrected Function Signatures (ARM64 ABI Safe)
// ============================================================
typedef void    (*Update0Fn)(void *, void *);
typedef void    (*SetTime1Fn)(float, void *);
typedef void    (*SendChatRemoteFn)(
    void *self,
    void *senderName,       // Il2CppString*
    void *text,             // Il2CppString*
    int32_t senderTeam,
    bool isTeamChat,
    const void *method
);
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
typedef void*   (*FastAllocateStringFn)(int32_t length, const void *method);
typedef void    (*OnDisconnectFn)(void *, void *, void *);

static Update0Fn        orig_CashUpdate      = NULL;
static Update0Fn        orig_ChatUpdate      = NULL;
static SendChatRemoteFn orig_SendChatRemote  = NULL;
static OnDisconnectFn   orig_OnDisconnect    = NULL;
static OnEventFn        orig_OnEvent         = NULL;
static LeaveRoomFn      orig_LeaveRoom       = NULL;
static Type4995LeaveFn  orig_Type4995Leave   = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch1 = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch2 = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch3 = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch4 = NULL;
static OnMasterSwitchFn orig_OnMasterSwitch5 = NULL;

// ============================================================
// MARK: - Runtime State
// ============================================================
typedef struct {
    volatile bool     inRoom;
    volatile bool     isMaster;
    volatile bool     heldMasterStably;
    volatile uint32_t selectedPeer;
    volatile float    gameSpeed;
    volatile bool     speedDirty;
    volatile uint64_t readFailures;
    volatile int32_t  autoHostOn;        // 1 = حماية الهوست التلقائية وصيد السارق
    volatile int32_t  antiKickHardLock;  // 0 افتراضياً لعدم تعطيل دخول الرومات
    volatile int32_t  chatMode;          // 0 = مفتوح | 1 = كتم | 2 = طرد من يكتب
    volatile int32_t  kickMsgArmed;
    volatile int32_t  forceHostReq;
    volatile int32_t  kickTargetID;
    volatile int32_t  kickRetries;
    volatile int32_t  insideNetworkEvent;
    volatile uint32_t blockedKicksCount;
    void * volatile   capturedNetPeer;
    double            roomEnterTime;
    double            masterAcquiredTime;
    double            lastMasterClaimTime;
    double            lastKickPacketTime;
    char              kickTargetName[OGS_MAX_NAME_BYTES];
    char              lastHijackerName[OGS_MAX_NAME_BYTES];
    char              customKickPhrase[OGS_MAX_NAME_BYTES];
} OGSRuntimeState;

static OGSRuntimeState gOGS = {
    .inRoom              = false,
    .isMaster            = false,
    .heldMasterStably    = false,
    .selectedPeer        = 0,
    .gameSpeed           = 1.0f,
    .speedDirty          = false,
    .readFailures        = 0,
    .autoHostOn          = 1,
    .antiKickHardLock    = 0,
    .chatMode            = 0,
    .kickMsgArmed        = 0,
    .forceHostReq        = 0,
    .kickTargetID        = -1,
    .kickRetries         = 0,
    .insideNetworkEvent  = 0,
    .blockedKicksCount   = 0,
    .capturedNetPeer     = NULL,
    .roomEnterTime       = 0.0,
    .masterAcquiredTime  = 0.0,
    .lastMasterClaimTime = 0.0,
    .lastKickPacketTime  = 0.0,
    .kickTargetName      = {0},
    .lastHijackerName    = {0},
    .customKickPhrase    = " تم طرده من الغرفة "
};

// ============================================================
// MARK: - 6. Safe Memory Layer & Fail-Closed Image Resolver
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

        uintptr_t base = 0x100000000ULL + (uintptr_t)_dyld_get_image_vmaddr_slide(i);
        __atomic_store_n(&gImageBase, base, __ATOMIC_RELEASE);
        return base;
    }
    // Fail closed: لا نستخدم image 0 أبداً لتجنب ضرب مكتبات النظام
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
// MARK: - 5. Safe IL2CPP Strings & FastAllocateString Allocator
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
    NSString *phrase = [NSString stringWithUTF8String:gOGS.customKickPhrase];
    if (!phrase.length) {
        phrase = @" تم طرده من الغرفة ";
    }
    if (phrase.length > 90) {
        phrase = [phrase substringToIndex:90];
    }

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
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.lowercaseString;
}

// ============================================================
// MARK: - 9. Lock-Protected Snapshot Model (os_unfair_lock)
// ============================================================
typedef struct {
    int32_t actorID;
    bool    isHost;
    char    name[OGS_MAX_NAME_BYTES];
} OGSPeerSnapshot;

typedef struct {
    bool            inRoom;
    bool            isMaster;
    uint32_t        count;
    OGSPeerSnapshot peers[OGS_MAX_PEERS];
} OGSRoomSnapshot;

static os_unfair_lock  gSnapshotLock = OS_UNFAIR_LOCK_INIT;
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

// ============================================================
// MARK: - Safe Peer & Array Extraction
// ============================================================
static bool OGSReadPeer(void *peer, void *master, OGSPeerSnapshot *output) {
    if (!peer || !output) return false;
    memset(output, 0, sizeof(*output));
    output->isHost = (peer == master);

    uintptr_t idAddress   = OGSResolveRVA(gOffsets.rvaPlayerGetID);
    uintptr_t nameAddress = OGSResolveRVA(gOffsets.rvaPlayerGetName);
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

    uintptr_t inRoomAddress = OGSResolveRVA(gOffsets.rvaInRoom);
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
// MARK: - 3. Validated NetworkingPeer Resolver & Host/Kick Engine
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
    return ((PlayerGetIDFn)idAddr)(myPlayer, NULL);
}

// التحقق من NetworkingPeer عبر الحقلين المؤكدين +0x160 (localPlayer) و +0x158 (currentRoom) فقط
static void *OGSGetNetworkingPeerSafe(void) {
    uintptr_t typeInfoSlot = OGSResolveRVA(RVA_PHOTON_NET_TYPEINFO);
    if (!typeInfoSlot) return NULL;

    void *typeInfo = NULL;
    if (!OGSReadPointer(typeInfoSlot, &typeInfo)) return NULL;

    void *staticFields = NULL;
    if (!OGSReadPointer((uintptr_t)typeInfo + 0xB8, &staticFields)) return NULL;

    void *netPeer = NULL;
    if (!OGSReadPointer((uintptr_t)staticFields + 0x10, &netPeer)) return NULL;

    void *localPlayer = NULL;
    void *currentRoom = NULL;
    OGSReadPointer((uintptr_t)netPeer + 0x160, &localPlayer);
    OGSReadPointer((uintptr_t)netPeer + 0x158, &currentRoom);
    if (!localPlayer && !currentRoom) return NULL;

    __atomic_store_n((uintptr_t *)&gOGS.capturedNetPeer, (uintptr_t)netPeer, __ATOMIC_RELEASE);
    return netPeer;
}

// سحب الهوست الآمن دون إفساد الذاكرة أو طردك من رومك
static bool OGSClaimMasterClean(bool bypassCooldown) {
    uintptr_t inRoomAddr   = OGSResolveRVA(gOffsets.rvaInRoom);
    uintptr_t isMasterAddr = OGSResolveRVA(gOffsets.rvaIsMaster);
    if (!inRoomAddr || !isMasterAddr) return false;

    if (!((Bool0Fn)inRoomAddr)(NULL)) return false;

    // إذا كنت أنت الهوست بالفعل، لا نرسل طلبات مكررة للسيرفر حتى لا يفصلك!
    if (((Bool0Fn)isMasterAddr)(NULL) && !bypassCooldown) {
        return true;
    }

    double now = CFAbsoluteTimeGetCurrent();
    if (!bypassCooldown && (now - gOGS.lastMasterClaimTime) < 0.55) {
        return false;
    }

    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);
    if (!myPlayer || myID <= 0) return false;

    gOGS.lastMasterClaimTime = now;

    void *netPeer = OGSGetNetworkingPeerSafe();
    uintptr_t setMasterIdAddr = OGSResolveRVA(gOffsets.rvaNetPeerSetMMasterId);
    if (netPeer && setMasterIdAddr) {
        ((SetMasterIdFn)setMasterIdAddr)(netPeer, myID, NULL);
    }

    uintptr_t slotAddr = OGSResolveRVA(gOffsets.tblSetMaster);
    void *fnPtr = NULL;
    if (OGSReadPointer(slotAddr, &fnPtr) && fnPtr) {
        ((PeerAction1Fn)fnPtr)(myPlayer, NULL);
        return true;
    }
    return false;
}

// طرد اللاعب مع فتح صلاحية Master عبر الدالة المصححة 0x013AB384
static bool OGSKickPeerClean(void *peerObj, bool bypassCooldown) {
    if (!peerObj || (uintptr_t)peerObj < 0x100000000ULL) return false;
    double now = CFAbsoluteTimeGetCurrent();
    if (!bypassCooldown && (now - gOGS.lastKickPacketTime) < 0.28) {
        return false;
    }
    gOGS.lastKickPacketTime = now;
    gOGS.kickMsgArmed = 1;

    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);

    void *netPeer = OGSGetNetworkingPeerSafe();
    uintptr_t getMasterIdAddr = OGSResolveRVA(gOffsets.rvaNetPeerGetMMasterId);
    uintptr_t setMasterIdAddr = OGSResolveRVA(gOffsets.rvaNetPeerSetMMasterId);

    int32_t origMasterID = 0;
    bool patched = false;

    if (netPeer && myID > 0 && getMasterIdAddr && setMasterIdAddr) {
        origMasterID = ((GetMasterIdFn)getMasterIdAddr)(netPeer, NULL);
        if (origMasterID != myID) {
            ((SetMasterIdFn)setMasterIdAddr)(netPeer, myID, NULL);
            patched = true;
        }
    }

    bool result = false;
    uintptr_t slotAddr = OGSResolveRVA(gOffsets.tblPeerSync);
    void *fnPtr = NULL;
    if (OGSReadPointer(slotAddr, &fnPtr) && fnPtr) {
        result = ((PeerAction1Fn)fnPtr)(peerObj, NULL);
    }

    if (patched && !gOGS.autoHostOn && netPeer && setMasterIdAddr && origMasterID > 0) {
        ((SetMasterIdFn)setMasterIdAddr)(netPeer, origMasterID, NULL);
    }
    return result;
}

// ============================================================
// MARK: - 7. Single-Point Speed Control
// ============================================================
static void OGSApplyTimescaleNow(float speed) {
    uintptr_t address = OGSResolveRVA(gOffsets.rvaSetTimescale);
    if (!address) return;
    SetTime1Fn setTime = (SetTime1Fn)address;
    setTime(speed, NULL);
}

static void OGSRequestSpeed(float speed) {
    if (!isfinite(speed)) return;
    speed = fmaxf(0.1f, fminf(speed, 20.0f));
    gOGS.gameSpeed = speed;
    __atomic_store_n(&gOGS.speedDirty, true, __ATOMIC_RELEASE);
    OGSApplyTimescaleNow(speed);
}

static void OGSProcessSpeed(void) {
    bool dirty = __atomic_exchange_n(&gOGS.speedDirty, false, __ATOMIC_ACQ_REL);
    float speed = gOGS.gameSpeed;
    if (dirty || fabsf(speed - 1.0f) > 0.01f) {
        OGSApplyTimescaleNow(speed);
    }
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
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) UILabel *playerLabel;
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UIButton *syncCloudButton;
@property (strong, nonatomic) UIButton *unbanButton;
@property (strong, nonatomic) UIButton *lockButton;
@property (strong, nonatomic) UIButton *hostLockButton;
@property (strong, nonatomic) UIButton *antiKickLockButton;
@property (strong, nonatomic) UIButton *muteChatButton;
@property (strong, nonatomic) UIButton *speedSetButton;
@property (strong, nonatomic) NSMutableSet<NSString *> *bannedNames;
@property (strong, nonatomic) NSMutableSet<NSNumber *> *bannedActorIDs;
@property (strong, nonatomic) NSMutableSet<NSString *> *allowedNamesWhenLocked;
@property (assign, nonatomic) BOOL roomLockActive;
@property (strong, nonatomic) NSTimer *masterTimer;
+ (instancetype)sharedInstance;
- (void)setupMenu;
- (void)ensureMenuVisible;
- (void)recordHijackerName:(NSString *)normName actorID:(int32_t)actID;
- (void)fetchGitHubCloudConfigWithFeedback:(BOOL)showFeedback;
- (BOOL)shouldAutoKickPeerWithName:(NSString *)normName actorID:(int32_t)actID;
@end

// ============================================================
// MARK: - Single-Source Room Snapshot & Anti-Hijack Engine
// ============================================================
static volatile bool s_inSnapshotUpdate = false;

static void OGSUpdateRoomSnapshot(void) {
    if (__atomic_exchange_n(&s_inSnapshotUpdate, true, __ATOMIC_ACQ_REL)) return;

    uintptr_t inRoomAddress       = OGSResolveRVA(gOffsets.rvaInRoom);
    uintptr_t masterStateAddress  = OGSResolveRVA(gOffsets.rvaIsMaster);
    uintptr_t masterPlayerAddress = OGSResolveRVA(gOffsets.rvaGetMasterPeer);

    if (!inRoomAddress || !masterStateAddress || !masterPlayerAddress) {
        __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
        return;
    }

    Bool0Fn inRoomFn   = (Bool0Fn)inRoomAddress;
    Bool0Fn isMasterFn = (Bool0Fn)masterStateAddress;
    Object0Fn masterFn = (Object0Fn)masterPlayerAddress;

    bool inRoom = inRoomFn(NULL);
    OGSRoomSnapshot snapshot = {0};
    snapshot.inRoom = inRoom;

    double now = CFAbsoluteTimeGetCurrent();
    bool wasInRoom = __atomic_load_n(&gOGS.inRoom, __ATOMIC_ACQUIRE);
    __atomic_store_n(&gOGS.inRoom, inRoom, __ATOMIC_RELEASE);

    if (!inRoom) {
        __atomic_store_n(&gOGS.isMaster, false, __ATOMIC_RELEASE);
        gOGS.heldMasterStably = false;
        gOGS.roomEnterTime = 0.0;
        gOGS.masterAcquiredTime = 0.0;
        gOGS.kickRetries = 0;
        OGSPublishSnapshotValue(&snapshot);
        __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
        return;
    }

    if (!wasInRoom || gOGS.roomEnterTime == 0.0) {
        gOGS.roomEnterTime = now;
        gOGS.heldMasterStably = false;
        gOGS.masterAcquiredTime = 0.0;
    }

    bool master = isMasterFn(NULL);
    void *masterPlayer = masterFn(NULL);
    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);
    OGSModMenu *menu = [OGSModMenu sharedInstance];

    // مهلة 2.0 ثانية بعد دخول الروم حتى يستقر اتصال الغرفة ولا يخرجك السيرفر
    bool roomSettled = ((now - gOGS.roomEnterTime) >= 2.0);

    if (master) {
        if (gOGS.masterAcquiredTime == 0.0) {
            gOGS.masterAcquiredTime = now;
        } else if ((now - gOGS.masterAcquiredTime) >= 1.0) {
            gOGS.heldMasterStably = true;
        }
    } else {
        gOGS.masterAcquiredTime = 0.0;

        if (roomSettled && (gOGS.autoHostOn || gOGS.forceHostReq > 0 || gOGS.kickRetries > 0)) {
            bool manualForce = (gOGS.forceHostReq > 0);
            gOGS.forceHostReq = 0;

            if (gOGS.autoHostOn && gOGS.heldMasterStably && masterPlayer && masterPlayer != myPlayer) {
                OGSPeerSnapshot thiefSnap;
                if (OGSReadPeer(masterPlayer, masterPlayer, &thiefSnap) && thiefSnap.actorID != myID) {
                    NSString *thiefName = [NSString stringWithUTF8String:thiefSnap.name];
                    NSString *normThief = OGSNormalizeKey(thiefName);
                    [menu recordHijackerName:normThief actorID:thiefSnap.actorID];

                    gOGS.kickTargetID = thiefSnap.actorID;
                    if (normThief.UTF8String) {
                        snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", normThief.UTF8String);
                        snprintf(gOGS.lastHijackerName, sizeof(gOGS.lastHijackerName), "%s", thiefSnap.name);
                    }
                    gOGS.kickRetries = 20;
                    OGSKickPeerClean(masterPlayer, true);
                }
            }

            OGSClaimMasterClean(manualForce);
        }
    }

    snapshot.isMaster = master;
    __atomic_store_n(&gOGS.isMaster, master, __ATOMIC_RELEASE);

    void *players[OGS_MAX_PEERS];
    uint32_t count = OGSReadPlayerArray(gOffsets.rvaGetPeers, players);
    bool targetStillInRoom = false;

    for (uint32_t i = 0; i < count; i++) {
        OGSPeerSnapshot peerSnap;
        if (!OGSReadPeer(players[i], masterPlayer, &peerSnap)) continue;

        snapshot.peers[snapshot.count++] = peerSnap;

        NSString *pName = [NSString stringWithUTF8String:peerSnap.name];
        NSString *normName = OGSNormalizeKey(pName);

        if (roomSettled && gOGS.kickRetries > 0) {
            bool matchID = (gOGS.kickTargetID > 0 && peerSnap.actorID == gOGS.kickTargetID);
            bool matchName = (gOGS.kickTargetName[0] != '\0' && strcmp(normName.UTF8String, gOGS.kickTargetName) == 0);
            if (matchID || matchName) {
                targetStillInRoom = true;
                if (!master) OGSClaimMasterClean(false);
                OGSKickPeerClean(players[i], false);
            }
        }

        if (roomSettled && [menu shouldAutoKickPeerWithName:normName actorID:peerSnap.actorID]) {
            if (!master) OGSClaimMasterClean(false);
            OGSKickPeerClean(players[i], false);
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

    OGSPublishSnapshotValue(&snapshot);
    __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
}

// ============================================================
// MARK: - 4 & 8. Clean Network, Chat & Lifecycle Hooks
// ============================================================
static void hook_OnEvent(void *self, void *eventData, void *method) {
    if (self && (uintptr_t)self >= 0x100000000ULL) {
        gOGS.capturedNetPeer = self;
    }
    __atomic_fetch_add(&gOGS.insideNetworkEvent, 1, __ATOMIC_ACQ_REL);
    if (orig_OnEvent) {
        orig_OnEvent(self, eventData, method);
    }
    __atomic_fetch_sub(&gOGS.insideNetworkEvent, 1, __ATOMIC_ACQ_REL);
}

// منع أوامر المغادرة القسرية القادمة من داخل حدث شبكي (OnEvent) أو من Type4995::LeaveRoom بعد استقرارك بالروم
static bool hook_LeaveRoom(int32_t becomeInactive, void *method) {
    double now = CFAbsoluteTimeGetCurrent();
    bool settled = (gOGS.inRoom && gOGS.roomEnterTime > 0.0 && (now - gOGS.roomEnterTime) > 2.0);
    if (settled && (gOGS.antiKickHardLock || (gOGS.autoHostOn && __atomic_load_n(&gOGS.insideNetworkEvent, __ATOMIC_ACQUIRE) > 0))) {
        __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
        return false;
    }
    return orig_LeaveRoom ? orig_LeaveRoom(becomeInactive, method) : false;
}

static void hook_Type4995LeaveRoom(void *self, void *method) {
    double now = CFAbsoluteTimeGetCurrent();
    bool settled = (gOGS.inRoom && gOGS.roomEnterTime > 0.0 && (now - gOGS.roomEnterTime) > 2.0);
    if (settled && (gOGS.antiKickHardLock || (gOGS.autoHostOn && __atomic_load_n(&gOGS.insideNetworkEvent, __ATOMIC_ACQUIRE) > 0))) {
        __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
        return;
    }
    if (orig_Type4995Leave) orig_Type4995Leave(self, method);
}

static void OGSHandleMasterSwitchIntercept(void *newMasterPlayer) {
    double now = CFAbsoluteTimeGetCurrent();
    bool settled = (gOGS.inRoom && gOGS.roomEnterTime > 0.0 && (now - gOGS.roomEnterTime) > 2.0);
    if (!settled || !gOGS.autoHostOn || !gOGS.heldMasterStably || !newMasterPlayer || (uintptr_t)newMasterPlayer < 0x100000000ULL) return;

    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);
    if (!myPlayer || newMasterPlayer == myPlayer) return;

    OGSPeerSnapshot thiefSnap;
    if (OGSReadPeer(newMasterPlayer, newMasterPlayer, &thiefSnap) && thiefSnap.actorID != myID) {
        NSString *thiefName = [NSString stringWithUTF8String:thiefSnap.name];
        NSString *normThief = OGSNormalizeKey(thiefName);
        [[OGSModMenu sharedInstance] recordHijackerName:normThief actorID:thiefSnap.actorID];

        gOGS.kickTargetID = thiefSnap.actorID;
        if (normThief.UTF8String) {
            snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", normThief.UTF8String);
            snprintf(gOGS.lastHijackerName, sizeof(gOGS.lastHijackerName), "%s", thiefSnap.name);
        }
        gOGS.kickRetries = 20;
    }
}

static void hook_OnMasterSwitched1(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch1) orig_OnMasterSwitch1(self, p, m); }
static void hook_OnMasterSwitched2(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch2) orig_OnMasterSwitch2(self, p, m); }
static void hook_OnMasterSwitched3(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch3) orig_OnMasterSwitch3(self, p, m); }
static void hook_OnMasterSwitched4(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch4) orig_OnMasterSwitch4(self, p, m); }
static void hook_OnMasterSwitched5(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch5) orig_OnMasterSwitch5(self, p, m); }

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

static void hook_SendChatRemote(
    void *self,
    void *senderStr,
    void *msgStr,
    int32_t senderTeam,
    bool isTeamChat,
    const void *method
) {
    int32_t mode = __atomic_load_n(&gOGS.chatMode, __ATOMIC_ACQUIRE);
    if (mode == 1) {
        return;
    } else if (mode == 2) {
        NSString *senderName = OGSReadIl2CppString(senderStr);
        if (senderName.length > 0) {
            NSString *normSender = OGSNormalizeKey(senderName);
            const char *utf8 = normSender.UTF8String;
            if (utf8) {
                snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", utf8);
                gOGS.kickTargetID = -1;
                gOGS.kickRetries = 18;
            }
        }
        return;
    }
    if (orig_SendChatRemote) {
        orig_SendChatRemote(self, senderStr, msgStr, senderTeam, isTeamChat, method);
    }
}

static void hook_ChatUpdate(void *self, void *method) {
    if (orig_ChatUpdate) {
        orig_ChatUpdate(self, method);
    }
}

static void hook_CashUpdate(void *self, void *method) {
    if (orig_CashUpdate) {
        orig_CashUpdate(self, method);
    }
}

static void OGSInstallHooks(void) {
    uintptr_t base = OGSFindGameImage();
    if (!base) return;
    if (gOffsets.tblCashUpdate)        { void **sl = (void **)(base + gOffsets.tblCashUpdate);        if (*sl != (void *)&hook_CashUpdate)                { orig_CashUpdate      = (Update0Fn)*sl;        *sl = (void *)&hook_CashUpdate; } }
    if (gOffsets.tblChatUpdate)        { void **sl = (void **)(base + gOffsets.tblChatUpdate);        if (*sl != (void *)&hook_ChatUpdate)                { orig_ChatUpdate      = (Update0Fn)*sl;        *sl = (void *)&hook_ChatUpdate; } }
    if (gOffsets.tblSendChatRemote)    { void **sl = (void **)(base + gOffsets.tblSendChatRemote);    if (*sl != (void *)&hook_SendChatRemote)            { orig_SendChatRemote  = (SendChatRemoteFn)*sl; *sl = (void *)&hook_SendChatRemote; } }
    if (gOffsets.tblOnDisconnect)      { void **sl = (void **)(base + gOffsets.tblOnDisconnect);      if (*sl != (void *)&hook_OnPhotonPlayerDisconnected){ orig_OnDisconnect    = (OnDisconnectFn)*sl;   *sl = (void *)&hook_OnPhotonPlayerDisconnected; } }
    if (gOffsets.tblOnEvent)           { void **sl = (void **)(base + gOffsets.tblOnEvent);           if (*sl != (void *)&hook_OnEvent)                   { orig_OnEvent         = (OnEventFn)*sl;        *sl = (void *)&hook_OnEvent; } }
    if (gOffsets.tblLeaveRoom)         { void **sl = (void **)(base + gOffsets.tblLeaveRoom);         if (*sl != (void *)&hook_LeaveRoom)                 { orig_LeaveRoom       = (LeaveRoomFn)*sl;      *sl = (void *)&hook_LeaveRoom; } }
    if (gOffsets.tblType4995LeaveRoom) { void **sl = (void **)(base + gOffsets.tblType4995LeaveRoom); if (*sl != (void *)&hook_Type4995LeaveRoom)         { orig_Type4995Leave   = (Type4995LeaveFn)*sl;  *sl = (void *)&hook_Type4995LeaveRoom; } }
    if (gOffsets.tblOnMasterSwitched1) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched1); if (*sl != (void *)&hook_OnMasterSwitched1)         { orig_OnMasterSwitch1 = (OnMasterSwitchFn)*sl; *sl = (void *)&hook_OnMasterSwitched1; } }
    if (gOffsets.tblOnMasterSwitched2) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched2); if (*sl != (void *)&hook_OnMasterSwitched2)         { orig_OnMasterSwitch2 = (OnMasterSwitchFn)*sl; *sl = (void *)&hook_OnMasterSwitched2; } }
    if (gOffsets.tblOnMasterSwitched3) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched3); if (*sl != (void *)&hook_OnMasterSwitched3)         { orig_OnMasterSwitch3 = (OnMasterSwitchFn)*sl; *sl = (void *)&hook_OnMasterSwitched3; } }
    if (gOffsets.tblOnMasterSwitched4) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched4); if (*sl != (void *)&hook_OnMasterSwitched4)         { orig_OnMasterSwitch4 = (OnMasterSwitchFn)*sl; *sl = (void *)&hook_OnMasterSwitched4; } }
    if (gOffsets.tblOnMasterSwitched5) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched5); if (*sl != (void *)&hook_OnMasterSwitched5)         { orig_OnMasterSwitch5 = (OnMasterSwitchFn)*sl; *sl = (void *)&hook_OnMasterSwitched5; } }
}

// ============================================================
// MARK: - ModMenu UI & Live Cloud Config Implementation
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
        NSArray *savedBans = [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"OGS_SavedBannedNames"];
        if (savedBans) [inst.bannedNames addObjectsFromArray:savedBans];
    });
    return inst;
}

- (void)saveLocalBans {
    [[NSUserDefaults standardUserDefaults] setObject:self.bannedNames.allObjects forKey:@"OGS_SavedBannedNames"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)recordHijackerName:(NSString *)normName actorID:(int32_t)actID {
    if (normName.length > 0) [self.bannedNames addObject:normName];
    if (actID > 0) [self.bannedActorIDs addObject:@(actID)];
    [self saveLocalBans];
}

- (BOOL)shouldAutoKickPeerWithName:(NSString *)normName actorID:(int32_t)actID {
    if (normName.length > 0 && [self.bannedNames containsObject:normName]) return YES;
    if (actID > 0 && [self.bannedActorIDs containsObject:@(actID)]) return YES;
    if (self.roomLockActive && normName.length > 0 && ![self.allowedNamesWhenLocked containsObject:normName]) return YES;
    return NO;
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

        self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(75, 18, 315, 252)];
        self.menuPanel.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.11 alpha:0.96];
        self.menuPanel.layer.cornerRadius = 14.0;
        self.menuPanel.layer.borderWidth = 2.0f;
        self.menuPanel.layer.borderColor = [UIColor systemRedColor].CGColor;
        self.menuPanel.hidden = YES;

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 260, 18)];
        self.titleLabel.text = @"OGS v12.1: النسخة المصححة الكاملة 🛡️👑";
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
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

        self.hostLockButton = [self makeBtn:CGRectMake(155, 142, 150, 32) title:@"حماية الهوست: مفعّل 👑" bg:wpnGreen action:@selector(toggleAutoHost:)];
        [self.menuPanel addSubview:self.hostLockButton];

        self.antiKickLockButton = [self makeBtn:CGRectMake(10, 142, 140, 32) title:@"قفل البقاء: تلقائي 🛡️" bg:darkGray action:@selector(toggleAntiKickHardLock:)];
        [self.menuPanel addSubview:self.antiKickLockButton];

        self.lockButton = [self makeBtn:CGRectMake(205, 179, 100, 30) title:@"قفل الروم: مفتوح" bg:darkGray action:@selector(toggleRoomLock:)];
        [self.menuPanel addSubview:self.lockButton];

        self.muteChatButton = [self makeBtn:CGRectMake(105, 179, 95, 30) title:@"الشات: مفتوح" bg:darkGray action:@selector(cycleChatMode:)];
        [self.menuPanel addSubview:self.muteChatButton];

        self.unbanButton = [self makeBtn:CGRectMake(10, 179, 90, 30) title:@"فك الحظر (0)" bg:darkGray action:@selector(clearBanList:)];
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

        // نقطة التحديث الوحيدة للسرعة والـ Snapshot (كل 0.20 ثانية) لمنع التداخل
        self.masterTimer = [NSTimer scheduledTimerWithTimeInterval:0.20 target:self selector:@selector(onMasterTick) userInfo:nil repeats:YES];
        self.masterTimer.tolerance = 0.03;

        [self fetchGitHubCloudConfigWithFeedback:NO];
    });
}

// ============================================================
// MARK: - GitHub Live Cloud Sync
// ============================================================
- (void)syncCloudTapped:(UIButton *)sender {
    [self fetchGitHubCloudConfigWithFeedback:YES];
}

- (void)tryFetchFromCandidateURLs:(NSArray<NSString *> *)candidates index:(NSUInteger)idx showFeedback:(BOOL)showFeedback {
    if (idx >= candidates.count) {
        if (showFeedback) {
            self.statusLabel.text = @"تأكد أن المستودع Public وملف JSON موجود";
        }
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
            if (showFeedback) {
                self.statusLabel.text = @"تم التحديث من GitHub بنجاح ✅";
            }
        });
    }] resume];
}

- (void)fetchGitHubCloudConfigWithFeedback:(BOOL)showFeedback {
    if (showFeedback) {
        self.statusLabel.text = @"جاري التحديث من GitHub...";
    }
    NSString *savedCustom = [[NSUserDefaults standardUserDefaults] stringForKey:@"OGS_GitHubConfigURL"];
    NSArray<NSString *> *candidates = OGSCandidateCloudURLs(savedCustom ?: kDefaultGitHubConfigURL);
    [self tryFetchFromCandidateURLs:candidates index:0 showFeedback:showFeedback];
}

- (void)applyCloudConfigDictionary:(NSDictionary *)json {
    if ([json[@"kick_message"] isKindOfClass:[NSString class]]) {
        const char *utf8 = [json[@"kick_message"] UTF8String];
        if (utf8) snprintf(gOGS.customKickPhrase, sizeof(gOGS.customKickPhrase), "%s", utf8);
    }
    if ([json[@"default_speed"] isKindOfClass:[NSNumber class]]) {
        [self applySpeed:[json[@"default_speed"] floatValue]];
    }
    if ([json[@"banned_names"] isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)json[@"banned_names"]) {
            if ([item isKindOfClass:[NSString class]]) {
                NSString *norm = OGSNormalizeKey(item);
                if (norm.length > 0) [self.bannedNames addObject:norm];
            }
        }
        [self saveLocalBans];
    }
    if ([json[@"banned_ids"] isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)json[@"banned_ids"]) {
            if ([item isKindOfClass:[NSNumber class]]) {
                [self.bannedActorIDs addObject:item];
            }
        }
    }
    [self refreshUI];
}

// ============================================================
// MARK: - UI Controls
// ============================================================
- (void)onMasterTick {
    [self ensureMenuVisible];
    OGSProcessSpeed();
    OGSUpdateRoomSnapshot();
    if (!self.menuPanel || self.menuPanel.hidden) return;
    [self refreshUI];
}

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

    uint32_t blocked = __atomic_load_n(&gOGS.blockedKicksCount, __ATOMIC_RELAXED);
    if (gOGS.kickRetries > 0) {
        self.statusLabel.text = @"جاري تأكيد طرد الهدف من الروم...";
    } else if (gOGS.lastHijackerName[0] != '\0') {
        NSString *hj = [NSString stringWithUTF8String:gOGS.lastHijackerName];
        self.statusLabel.text = [NSString stringWithFormat:@"طُرد السارق: %@ | صد طرد: %u 🛡️", hj ?: @"", blocked];
    } else {
        self.statusLabel.text = [NSString stringWithFormat:@"%@ | بالروم: %u | صد طرد: %u 🛡️",
                                 snapshot.inRoom ? (snapshot.isMaster ? @"الهوست: أنت 👑" : @"متصل (حماية نشطة)") : @"غير متصل",
                                 count,
                                 blocked];
    }
    [self.unbanButton setTitle:[NSString stringWithFormat:@"فك الحظر (%lu)", (unsigned long)self.bannedNames.count] forState:UIControlStateNormal];
}

- (void)toggleMenu {
    self.menuPanel.hidden = !self.menuPanel.hidden;
    if (!self.menuPanel.hidden) {
        OGSInstallHooks();
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

- (void)claimHostNow:(UIButton *)sender {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    if (!snapshot.inRoom) {
        self.statusLabel.text = @"ادخل داخل روم أولاً لسحب الهوست!";
        return;
    }
    if (snapshot.isMaster) {
        self.statusLabel.text = @"أنت الهوست بالفعل حالياً 👑";
        return;
    }
    gOGS.forceHostReq = 1;
    bool ok = OGSClaimMasterClean(true);
    OGSUpdateRoomSnapshot();
    [self refreshUI];
    self.statusLabel.text = ok ? @"تم إرسال طلب سحب الهوست بنجاح 👑" : @"تعذر إرسال الطلب حالياً";
}

- (void)toggleAutoHost:(UIButton *)s {
    gOGS.autoHostOn = !gOGS.autoHostOn;
    if (gOGS.autoHostOn) {
        gOGS.forceHostReq = 1;
        [s setTitle:@"حماية الهوست: مفعّل 👑" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    } else {
        [s setTitle:@"حماية الهوست: متوقف" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
    [self refreshUI];
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
    gOGS.chatMode = (gOGS.chatMode + 1) % 3;
    if (gOGS.chatMode == 1) {
        [s setTitle:@"الشات: كتم 🔇" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.80 green:0.35 blue:0.10 alpha:1.0];
    } else if (gOGS.chatMode == 2) {
        [s setTitle:@"الشات: طرد 🚫" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.70 green:0.12 blue:0.15 alpha:1.0];
    } else {
        [s setTitle:@"الشات: مفتوح" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
}

- (void)triggerImmediateKick:(OGSPeerSnapshot)peer {
    gOGS.kickTargetID = peer.actorID;
    NSString *pName = [NSString stringWithUTF8String:peer.name];
    NSString *normName = OGSNormalizeKey(pName);
    const char *utf8 = normName.UTF8String;
    if (utf8) {
        snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", utf8);
    }
    gOGS.kickRetries = 20;

    void *players[OGS_MAX_PEERS];
    uint32_t count = OGSReadPlayerArray(gOffsets.rvaGetPeers, players);
    uintptr_t idAddr = OGSResolveRVA(gOffsets.rvaPlayerGetID);
    PlayerGetIDFn getID = (PlayerGetIDFn)idAddr;

    for (uint32_t i = 0; i < count; i++) {
        if (getID && getID(players[i], NULL) == peer.actorID) {
            OGSKickPeerClean(players[i], true);
            break;
        }
    }
}

- (void)kickSelected:(UIButton *)s {
    OGSRoomSnapshot snapshot = OGSCurrentSnapshot();
    if (!snapshot.count) return;
    uint32_t selected = __atomic_load_n(&gOGS.selectedPeer, __ATOMIC_ACQUIRE);
    if (selected >= snapshot.count) selected = 0;

    OGSPeerSnapshot peer = snapshot.peers[selected];
    NSString *pName = [NSString stringWithUTF8String:peer.name];
    [self triggerImmediateKick:peer];
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
    [self saveLocalBans];

    [self triggerImmediateKick:peer];
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
    gOGS.lastHijackerName[0] = '\0';
    [self saveLocalBans];
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
