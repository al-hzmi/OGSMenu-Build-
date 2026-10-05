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
// MARK: - Exact Audited Engine Offsets & VTable Slots
// ============================================================
// Confirmed from binary ADRP+ADD @ 0x13d3090 & 0x1427fcc:
// PhotonNetwork_TypeInfo = 0x0281B1C8 -> +0xb8 (static_fields) -> +0x10 (networkingPeer)
static const uintptr_t RVA_PHOTON_NET_TYPEINFO   = 0x0281B1C8;

// Type4870 (NetworkingPeer) Exact VTable Offsets in Il2CppClass:
static const uintptr_t VTABLE_OFF_DISCONNECT     = 0x1A8; // Slot 8  -> 0x13aca38
static const uintptr_t VTABLE_OFF_OPLEAVE_VIRT   = 0x2A8; // Called by LeaveRoom @ 0x13d0808
static const uintptr_t VTABLE_OFF_OPRAISEEVENT   = 0x308; // Slot 30 -> 0x13ace98
static const uintptr_t VTABLE_OFF_ONEVENT        = 0x358; // Slot 35 -> 0x13b54ac

typedef struct {
    uintptr_t tblCashUpdate;            // 0x23918b8
    uintptr_t tblChatUpdate;            // 0x238fd68
    uintptr_t tblSendChatRemote;        // 0x238fd80
    uintptr_t tblOnEvent;               // 0x2390048
    uintptr_t tblDisconnect;            // 0x238ff48
    uintptr_t tblLeaveRoom;             // 0x2390a10
    uintptr_t tblType4995LeaveRoom;     // 0x238e518 (Type4995::LeaveRoom @ 0x1375150)
    uintptr_t tblNetPeerSetMaster2;     // 0x238ff50 (Type4870::SetMasterClient P=2 @ 0x13b0a20)
    uintptr_t tblNetPeerSetMaster1;     // 0x238ff58 (Type4870::SetMasterClient P=1 @ 0x13b0c54)
    uintptr_t tblOnMasterSwitched1;     // 0x2392628
    uintptr_t tblOnMasterSwitched2;     // 0x2391000
    uintptr_t tblOnMasterSwitched3;     // 0x238f228
    uintptr_t tblOnMasterSwitched4;     // 0x23903e0
    uintptr_t tblOnMasterSwitched5;     // 0x238e730
    uintptr_t tblPeerSync;              // 0x2390a98 (PhotonNetwork::CloseConnection @ 0x13d2e84)
    uintptr_t tblSetMaster;             // 0x2390aa0 (PhotonNetwork::SetMasterClient @ 0x13d30ec)
    uintptr_t tblOnDisconnect;          // 0x2391930

    uintptr_t rvaSetTimescale;          // 0x198ac4c
    uintptr_t rvaInRoom;                // 0x013CC38C
    uintptr_t rvaIsMaster;              // 0x013CC2BC
    uintptr_t rvaGetMasterPeer;         // 0x013CACA4
    uintptr_t rvaGetLocalPlayer;        // 0x013CABF0
    uintptr_t rvaGetRoom;               // 0x013CAB28
    uintptr_t rvaAllPlayers;            // 0x013CAEC4
    uintptr_t rvaGetPeers;              // 0x013CAF78
    uintptr_t rvaPlayerGetName;         // 0x013D7534
    uintptr_t rvaPlayerGetID;           // 0x013CC384
    uintptr_t rvaNetPeerGetMMasterId;   // 0x013AB2A4 (LDR W0, [X0, #0x1c0])
    uintptr_t rvaNetPeerSetMMasterId;   // 0x013AB2AC (STR W1, [X0, #0x1c0])
    uintptr_t rvaNetPeerSetMaster2;     // 0x013B0A20
    uintptr_t rvaNetPeerSetMaster1;     // 0x013B0C54
    uintptr_t rvaRoomSetMasterId;       // 0x013F1FFC (STR W1, [X0, #0x48])
    uintptr_t rvaIsLocalClientInside;   // 0x013FD758
    uintptr_t rvaArabicFix;             // 0x0130F538
} OGSOffsetsConfig;

static OGSOffsetsConfig gOffsets = {
    .tblCashUpdate          = 0x23918b8,
    .tblChatUpdate          = 0x238fd68,
    .tblSendChatRemote      = 0x238fd80,
    .tblOnEvent             = 0x2390048,
    .tblDisconnect          = 0x238ff48,
    .tblLeaveRoom           = 0x2390a10,
    .tblType4995LeaveRoom   = 0x238e518,
    .tblNetPeerSetMaster2   = 0x238ff50,
    .tblNetPeerSetMaster1   = 0x238ff58,
    .tblOnMasterSwitched1   = 0x2392628,
    .tblOnMasterSwitched2   = 0x2391000,
    .tblOnMasterSwitched3   = 0x238f228,
    .tblOnMasterSwitched4   = 0x23903e0,
    .tblOnMasterSwitched5   = 0x238e730,
    .tblPeerSync            = 0x2390a98,
    .tblSetMaster           = 0x2390aa0,
    .tblOnDisconnect        = 0x2391930,

    .rvaSetTimescale        = 0x198ac4c,
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
    .rvaNetPeerSetMMasterId = 0x013AB2AC,
    .rvaNetPeerSetMaster2   = 0x013B0A20,
    .rvaNetPeerSetMaster1   = 0x013B0C54,
    .rvaRoomSetMasterId     = 0x013F1FFC,
    .rvaIsLocalClientInside = 0x013FD758,
    .rvaArabicFix           = 0x0130F538
};

// ============================================================
// MARK: - Function Signatures
// ============================================================
typedef void    (*Update0Fn)(void *, void *);
typedef void    (*SetTime1Fn)(float, void *);
typedef void    (*SendChatRemoteFn)(void *, void *, void *, int32_t, int32_t, void *);
typedef void    (*OnEventFn)(void *, void *, void *);
typedef void    (*DisconnectFn)(void *, void *);
typedef bool    (*OpLeaveVirtFn)(void *, int32_t, void *);
typedef bool    (*LeaveRoomFn)(int32_t, void *);
typedef void    (*Type4995LeaveFn)(void *, void *);
typedef void    (*OnMasterSwitchFn)(void *, void *, void *);
typedef bool    (*Bool0Fn)(void *);
typedef bool    (*Bool1ObjFn)(void *, void *);
typedef void*   (*Object0Fn)(void *);
typedef bool    (*PeerAction1Fn)(void *, void *);
typedef void*   (*PlayerGetNameFn)(void *, void *);
typedef int32_t (*PlayerGetIDFn)(void *, void *);
typedef int32_t (*GetMasterIdFn)(void *, void *);
typedef void    (*SetMasterIdFn)(void *, int32_t, void *);
typedef bool    (*NetPeerSetMaster2Fn)(void *, int32_t, int32_t, void *);
typedef bool    (*NetPeerSetMaster1Fn)(void *, int32_t, void *);
typedef void*   (*ArabicFixFn)(void *, void *);
typedef void    (*OnDisconnectFn)(void *, void *, void *);

static Update0Fn           orig_CashUpdate        = NULL;
static Update0Fn           orig_ChatUpdate        = NULL;
static SendChatRemoteFn    orig_SendChatRemote    = NULL;
static OnDisconnectFn      orig_OnDisconnect      = NULL;
static OnEventFn           orig_OnEvent           = NULL;
static DisconnectFn        orig_Disconnect        = NULL;
static OpLeaveVirtFn       orig_OpLeaveVirt       = NULL;
static LeaveRoomFn         orig_LeaveRoom         = NULL;
static Type4995LeaveFn     orig_Type4995Leave     = NULL;
static NetPeerSetMaster2Fn orig_NetPeerSetMaster2 = NULL;
static NetPeerSetMaster1Fn orig_NetPeerSetMaster1 = NULL;
static OnMasterSwitchFn    orig_OnMasterSwitch1   = NULL;
static OnMasterSwitchFn    orig_OnMasterSwitch2   = NULL;
static OnMasterSwitchFn    orig_OnMasterSwitch3   = NULL;
static OnMasterSwitchFn    orig_OnMasterSwitch4   = NULL;
static OnMasterSwitchFn    orig_OnMasterSwitch5   = NULL;

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
    volatile uint64_t generation;
    volatile uint64_t readFailures;
    volatile int32_t  autoHostOn;        // 1 = درع الهوست + صيد السارق + منع الطرد الشبكي
    volatile int32_t  antiKickHardLock;  // 1 = منع الخروج من الروم نهائياً من أي مصدر حتى تفتحه
    volatile int32_t  chatMode;          // 0 = مفتوح | 1 = كتم | 2 = طرد من يكتب
    volatile int32_t  kickMsgArmed;
    volatile int32_t  forceHostReq;
    volatile int32_t  kickTargetID;
    volatile int32_t  kickRetries;
    volatile int32_t  insideNetworkEvent;
    volatile uint32_t blockedKicksCount;
    void * volatile   capturedNetPeer;   // يُلتقط مباشرة من OnEvent/VTable لضمان عدم رجوع NULL أبداً
    uintptr_t         patchedVTableKlass;
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
    .generation          = 0,
    .readFailures        = 0,
    .autoHostOn          = 1,
    .antiKickHardLock    = 1,
    .chatMode            = 0,
    .kickMsgArmed        = 0,
    .forceHostReq        = 0,
    .kickTargetID        = -1,
    .kickRetries         = 0,
    .insideNetworkEvent  = 0,
    .blockedKicksCount   = 0,
    .capturedNetPeer     = NULL,
    .patchedVTableKlass  = 0,
    .roomEnterTime       = 0.0,
    .masterAcquiredTime  = 0.0,
    .lastMasterClaimTime = 0.0,
    .lastKickPacketTime  = 0.0,
    .kickTargetName      = {0},
    .lastHijackerName    = {0},
    .customKickPhrase    = " تم طرده من الغرفة "
};

// ============================================================
// MARK: - Safe Memory Layer & Base Resolver
// ============================================================
static volatile uintptr_t gImageBase = 0;

static uintptr_t OGSFindGameImage(void) {
    uintptr_t cached = __atomic_load_n(&gImageBase, __ATOMIC_ACQUIRE);
    if (cached) return cached;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "/fps.app/fps")) {
            uintptr_t base = 0x100000000ULL + _dyld_get_image_vmaddr_slide(i);
            __atomic_store_n(&gImageBase, base, __ATOMIC_RELEASE);
            return base;
        }
    }
    uintptr_t fallback = 0x100000000ULL + _dyld_get_image_vmaddr_slide(0);
    __atomic_store_n(&gImageBase, fallback, __ATOMIC_RELEASE);
    return fallback;
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
// MARK: - Verified NetworkingPeer Resolver (0x0281B1C8 + Live Capture)
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

// يستخرج مؤشر networkingPeer من العنوان الصحيح 0x0281B1C8 أو من الالتقاط المباشر
static void *OGSGetNetworkingPeerSafe(void) {
    uintptr_t typeInfoSlot = OGSResolveRVA(RVA_PHOTON_NET_TYPEINFO);
    void *typeInfo = NULL;
    if (OGSReadPointer(typeInfoSlot, &typeInfo)) {
        void *staticFields = NULL;
        if (OGSReadPointer((uintptr_t)typeInfo + 0xb8, &staticFields)) {
            void *netPeer = NULL;
            if (OGSReadPointer((uintptr_t)staticFields + 0x10, &netPeer)) {
                int32_t testMaster = 0;
                if (OGSReadMemory((uintptr_t)netPeer + 0x1c0, &testMaster, sizeof(int32_t))) {
                    gOGS.capturedNetPeer = netPeer;
                    return netPeer;
                }
            }
        }
    }

    void *captured = gOGS.capturedNetPeer;
    if (captured && (uintptr_t)captured > 0x100000000ULL) {
        int32_t testMaster = 0;
        if (OGSReadMemory((uintptr_t)captured + 0x1c0, &testMaster, sizeof(int32_t))) {
            return captured;
        }
    }
    return NULL;
}

static bool OGSIsNetworkingPeerRoomReady(void *netPeer, void **outRoomObj) {
    if (outRoomObj) *outRoomObj = NULL;
    if (!netPeer || (uintptr_t)netPeer < 0x100000000ULL) return false;

    void *actorsDict = NULL;
    if (!OGSReadPointer((uintptr_t)netPeer + 0x1a8, &actorsDict) || !actorsDict) return false;

    void *currentRoom = NULL;
    if (!OGSReadPointer((uintptr_t)netPeer + 0x158, &currentRoom) || !currentRoom) return false;

    uintptr_t isInsideAddr = OGSResolveRVA(gOffsets.rvaIsLocalClientInside);
    if (isInsideAddr) {
        Bool1ObjFn isInsideFn = (Bool1ObjFn)isInsideAddr;
        if (!isInsideFn(currentRoom, NULL)) return false;
    }

    if (outRoomObj) *outRoomObj = currentRoom;
    return true;
}

static void OGSInstallLiveVTableHooksIfNeeded(void *netPeer);

// ============================================================
// MARK: - Unstoppable Host Claim & Gate-Bypass Kick Engine
// ============================================================
// لا تتوقف أبداً حتى لو كان netPeer غير جاهز، بل تنفذ كل الطبقات المتاحة وترجع true إذا نجحت
static bool OGSClaimMasterAllLayers(bool bypassCooldown) {
    double now = CFAbsoluteTimeGetCurrent();
    if (!bypassCooldown && (now - gOGS.lastMasterClaimTime) < 0.28) {
        return false;
    }

    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);
    if (!myPlayer || myID <= 0) return false;

    gOGS.lastMasterClaimTime = now;
    bool executedAny = false;

    void *netPeer = OGSGetNetworkingPeerSafe();
    void *roomObj = NULL;

    if (netPeer) {
        OGSInstallLiveVTableHooksIfNeeded(netPeer);

        // 1. فرض رقمك في [netPeer + 0x1c0] فوراً
        uintptr_t setMMasterAddr = OGSResolveRVA(gOffsets.rvaNetPeerSetMMasterId);
        if (setMMasterAddr) {
            ((SetMasterIdFn)setMMasterAddr)(netPeer, myID, NULL);
            executedAny = true;
        }

        if (OGSIsNetworkingPeerRoomReady(netPeer, &roomObj)) {
            // 2. إرسال خاصية الغرفة 248 للسيرفر مباشرة عبر 0x13b0c54
            uintptr_t setMaster1Addr = OGSResolveRVA(gOffsets.rvaNetPeerSetMaster1);
            if (setMaster1Addr) {
                if (orig_NetPeerSetMaster1) {
                    orig_NetPeerSetMaster1(netPeer, myID, NULL);
                } else {
                    ((NetPeerSetMaster1Fn)setMaster1Addr)(netPeer, myID, NULL);
                }
                executedAny = true;
            }

            // 3. إرسال الحدث 208 عبر 0x13b0a20
            uintptr_t setMaster2Addr = OGSResolveRVA(gOffsets.rvaNetPeerSetMaster2);
            if (setMaster2Addr) {
                if (orig_NetPeerSetMaster2) {
                    orig_NetPeerSetMaster2(netPeer, myID, 1, NULL);
                } else {
                    ((NetPeerSetMaster2Fn)setMaster2Addr)(netPeer, myID, 1, NULL);
                }
                executedAny = true;
            }
        }
    }

    // 4. تحديث [room + 0x48]
    if (!roomObj) {
        uintptr_t getRoomAddr = OGSResolveRVA(gOffsets.rvaGetRoom);
        if (getRoomAddr) roomObj = ((Object0Fn)getRoomAddr)(NULL);
    }
    uintptr_t setRoomMasterAddr = OGSResolveRVA(gOffsets.rvaRoomSetMasterId);
    if (roomObj && (uintptr_t)roomObj > 0x100000000ULL && setRoomMasterAddr) {
        ((SetMasterIdFn)setRoomMasterAddr)(roomObj, myID, NULL);
        executedAny = true;
    }

    // 5. استدعاء PhotonNetwork::SetMasterClient الرسمي دائماً بدون شروط تعجيزية
    uintptr_t slotAddr = OGSResolveRVA(gOffsets.tblSetMaster);
    void *fnPtr = NULL;
    if (OGSReadPointer(slotAddr, &fnPtr) && fnPtr) {
        ((PeerAction1Fn)fnPtr)(myPlayer, NULL);
        executedAny = true;
    }

    return executedAny;
}

// طرد قسري مضمون: يفتح بوابة [netPeer + 0x1c0] بالرقم الصحيح (0x0281B1C8) ويرسل CloseConnection فوراً
static bool OGSForceKickPeerBypassingGate(void *peerObj, bool bypassCooldown) {
    if (!peerObj || (uintptr_t)peerObj < 0x100000000ULL) return false;
    double now = CFAbsoluteTimeGetCurrent();
    if (!bypassCooldown && (now - gOGS.lastKickPacketTime) < 0.18) {
        return false;
    }
    gOGS.lastKickPacketTime = now;
    gOGS.kickMsgArmed = 1;

    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);

    void *netPeer = OGSGetNetworkingPeerSafe();
    uintptr_t getMMasterAddr = OGSResolveRVA(gOffsets.rvaNetPeerGetMMasterId);
    uintptr_t setMMasterAddr = OGSResolveRVA(gOffsets.rvaNetPeerSetMMasterId);
    uintptr_t getRoomAddr    = OGSResolveRVA(gOffsets.rvaGetRoom);
    uintptr_t setRoomMaster  = OGSResolveRVA(gOffsets.rvaRoomSetMasterId);

    int32_t origMasterID = 0;
    bool patchedGate = false;

    // 1. فتح البوابة المحلية +0x1c0 و +0x48 برقمك حتى لا ترفض دالة 0x13d2e84 إرسال حزمة الطرد أبداً!
    if (netPeer && myID > 0 && getMMasterAddr && setMMasterAddr) {
        origMasterID = ((GetMasterIdFn)getMMasterAddr)(netPeer, NULL);
        if (origMasterID != myID) {
            ((SetMasterIdFn)setMMasterAddr)(netPeer, myID, NULL);
            patchedGate = true;
        }
    }
    if (myID > 0 && getRoomAddr && setRoomMaster) {
        void *room = ((Object0Fn)getRoomAddr)(NULL);
        if (room && (uintptr_t)room > 0x100000000ULL) {
            ((SetMasterIdFn)setRoomMaster)(room, myID, NULL);
        }
    }

    // 2. إرسال حزمة الطرد عبر CloseConnection (التي أصبحت تمر الآن 100% بعد فتح +0x1c0)
    bool sent = false;
    uintptr_t slotAddr = OGSResolveRVA(gOffsets.tblPeerSync);
    void *fnPtr = NULL;
    if (OGSReadPointer(slotAddr, &fnPtr) && fnPtr) {
        sent = ((PeerAction1Fn)fnPtr)(peerObj, NULL);
    }

    if (patchedGate && !gOGS.autoHostOn && netPeer && setMMasterAddr && origMasterID > 0) {
        ((SetMasterIdFn)setMMasterAddr)(netPeer, origMasterID, NULL);
    }
    return sent;
}

// ============================================================
// MARK: - Speed Control
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
// MARK: - Room Snapshot & Anti-Hijack Engine
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
    OGSRoomSnapshot *snapshot = OGSBeginSnapshotWrite();
    snapshot->inRoom = inRoom;

    double now = CFAbsoluteTimeGetCurrent();
    bool wasInRoom = __atomic_load_n(&gOGS.inRoom, __ATOMIC_ACQUIRE);
    __atomic_store_n(&gOGS.inRoom, inRoom, __ATOMIC_RELEASE);

    if (!inRoom) {
        __atomic_store_n(&gOGS.isMaster, false, __ATOMIC_RELEASE);
        gOGS.heldMasterStably = false;
        gOGS.roomEnterTime = 0.0;
        gOGS.masterAcquiredTime = 0.0;
        gOGS.kickRetries = 0;
        OGSPublishSnapshot(snapshot);
        __atomic_store_n(&s_inSnapshotUpdate, false, __ATOMIC_RELEASE);
        return;
    }

    if (!wasInRoom || gOGS.roomEnterTime == 0.0) {
        gOGS.roomEnterTime = now;
        gOGS.heldMasterStably = false;
        gOGS.masterAcquiredTime = 0.0;
    }

    void *netPeer = OGSGetNetworkingPeerSafe();
    if (netPeer) {
        OGSInstallLiveVTableHooksIfNeeded(netPeer);
    }

    bool master = isMasterFn(NULL);
    void *masterPlayer = masterFn(NULL);
    void *myPlayer = NULL;
    int32_t myID = OGSGetLocalPlayerID(&myPlayer);
    OGSModMenu *menu = [OGSModMenu sharedInstance];

    if (master) {
        if (gOGS.masterAcquiredTime == 0.0) {
            gOGS.masterAcquiredTime = now;
        } else if ((now - gOGS.masterAcquiredTime) >= 0.6) {
            gOGS.heldMasterStably = true;
        }
    } else {
        gOGS.masterAcquiredTime = 0.0;
        bool roomSettled = ((now - gOGS.roomEnterTime) >= 1.0);

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
                    gOGS.kickRetries = 30;
                    OGSForceKickPeerBypassingGate(masterPlayer, true);
                }
            }

            OGSClaimMasterAllLayers(manualForce);
        }
    }

    snapshot->isMaster = master;
    __atomic_store_n(&gOGS.isMaster, master, __ATOMIC_RELEASE);

    void *players[OGS_MAX_PEERS];
    uint32_t count = OGSReadPlayerArray(gOffsets.rvaGetPeers, players);
    bool targetStillInRoom = false;

    for (uint32_t i = 0; i < count; i++) {
        OGSPeerSnapshot peerSnap;
        if (!OGSReadPeer(players[i], masterPlayer, &peerSnap)) continue;

        snapshot->peers[snapshot->count++] = peerSnap;

        NSString *pName = [NSString stringWithUTF8String:peerSnap.name];
        NSString *normName = OGSNormalizeKey(pName);

        if (gOGS.kickRetries > 0) {
            bool matchID = (gOGS.kickTargetID > 0 && peerSnap.actorID == gOGS.kickTargetID);
            bool matchName = (gOGS.kickTargetName[0] != '\0' && strcmp(normName.UTF8String, gOGS.kickTargetName) == 0);
            if (matchID || matchName) {
                targetStillInRoom = true;
                if (!master) OGSClaimMasterAllLayers(false);
                OGSForceKickPeerBypassingGate(players[i], false);
            }
        }

        if ([menu shouldAutoKickPeerWithName:normName actorID:peerSnap.actorID]) {
            if (!master) OGSClaimMasterAllLayers(false);
            OGSForceKickPeerBypassingGate(players[i], false);
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
// MARK: - VTable & Direct Anti-Kick / Anti-Hijack Hooks
// ============================================================

// 1. اعتراض البوابة الحقيقية للخروج من الروم في الرام (Klass + 0x2a8 التي يستدعيها LeaveRoom عند 0x13d0808)
static bool hook_OpLeaveVirt(void *self, int32_t becomeInactive, void *method) {
    if (self && (uintptr_t)self > 0x100000000ULL) gOGS.capturedNetPeer = self;
    // إذا كان الخروج قادماً من الشبكة (OnEvent) أو كان قفل البقاء الصارم مفعلاً، نرفض الخروج 100%!
    if (gOGS.antiKickHardLock || (gOGS.autoHostOn && __atomic_load_n(&gOGS.insideNetworkEvent, __ATOMIC_ACQUIRE) > 0)) {
        __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
        return false;
    }
    return orig_OpLeaveVirt ? orig_OpLeaveVirt(self, becomeInactive, method) : false;
}

// 2. اعتراض Disconnect (Slot 8 -> Klass + 0x1a8) لمنع فصل الاتصال القسري أثناء وجودك بالروم
static void hook_Disconnect(void *self, void *method) {
    if (self && (uintptr_t)self > 0x100000000ULL) gOGS.capturedNetPeer = self;
    if (gOGS.inRoom && (gOGS.antiKickHardLock || __atomic_load_n(&gOGS.insideNetworkEvent, __ATOMIC_ACQUIRE) > 0)) {
        __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
        return;
    }
    if (orig_Disconnect) orig_Disconnect(self, method);
}

// 3. اعتراض Type4995::LeaveRoom (0x1375150 / Tbl 0x238e518) التي يستغلها الهكر لطرد اللاعبين
static void hook_Type4995LeaveRoom(void *self, void *method) {
    if (gOGS.inRoom && (gOGS.antiKickHardLock || gOGS.autoHostOn)) {
        __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
        return;
    }
    if (orig_Type4995Leave) orig_Type4995Leave(self, method);
}

// 4. اعتراض PhotonNetwork::LeaveRoom (0x13d0604 / Tbl 0x2390a10)
static bool hook_LeaveRoom(int32_t becomeInactive, void *method) {
    if (gOGS.antiKickHardLock || (gOGS.autoHostOn && __atomic_load_n(&gOGS.insideNetworkEvent, __ATOMIC_ACQUIRE) > 0)) {
        __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
        return false;
    }
    return orig_LeaveRoom ? orig_LeaveRoom(becomeInactive, method) : false;
}

// 5. اعتراض Type4870::OnEvent (Slot 35 -> Klass + 0x358 @ 0x13b54ac)
static void hook_OnEvent(void *self, void *eventData, void *method) {
    if (self && (uintptr_t)self > 0x100000000ULL) {
        gOGS.capturedNetPeer = self;
    }

    if ((gOGS.autoHostOn || gOGS.antiKickHardLock) && eventData && (uintptr_t)eventData > 0x100000000ULL) {
        uint8_t evCode = 0;
        if (OGSReadMemory((uintptr_t)eventData + 0x10, &evCode, sizeof(uint8_t))) {
            // Event 203 (0xCB) = CloseConnection Kick
            if (evCode == 203) {
                __atomic_fetch_add(&gOGS.blockedKicksCount, 1, __ATOMIC_RELAXED);
                return;
            }
        }
    }

    __atomic_fetch_add(&gOGS.insideNetworkEvent, 1, __ATOMIC_ACQ_REL);
    if (orig_OnEvent) orig_OnEvent(self, eventData, method);
    __atomic_fetch_sub(&gOGS.insideNetworkEvent, 1, __ATOMIC_ACQ_REL);

    // بعد انتهاء OnEvent مباشرة: نفحص إذا غيّر الحدث قيمة [netPeer + 0x1c0] لغير رقمنا
    if (gOGS.autoHostOn && self && (uintptr_t)self > 0x100000000ULL && gOGS.heldMasterStably) {
        int32_t currentMasterID = 0;
        if (OGSReadMemory((uintptr_t)self + 0x1c0, &currentMasterID, sizeof(int32_t)) && currentMasterID > 0) {
            void *myPlayer = NULL;
            int32_t myID = OGSGetLocalPlayerID(&myPlayer);
            if (myID > 0 && currentMasterID != myID) {
                gOGS.kickTargetID = currentMasterID;
                gOGS.kickRetries = 30;
                OGSClaimMasterAllLayers(true);
            }
        }
    }
}

// 6. اعتراض دوال SetMasterClient الداخلية (0x13b0a20 و 0x13b0c54)
static bool hook_NetPeerSetMaster2(void *self, int32_t masterClientId, int32_t sync, void *method) {
    if (self && (uintptr_t)self > 0x100000000ULL) gOGS.capturedNetPeer = self;
    if (gOGS.autoHostOn && self && OGSIsNetworkingPeerRoomReady(self, NULL)) {
        void *myPlayer = NULL;
        int32_t myID = OGSGetLocalPlayerID(&myPlayer);
        if (myID > 0 && masterClientId > 0 && masterClientId != myID) {
            gOGS.kickTargetID = masterClientId;
            gOGS.kickRetries = 30;
            masterClientId = myID;
        }
    }
    return orig_NetPeerSetMaster2 ? orig_NetPeerSetMaster2(self, masterClientId, sync, method) : false;
}

static bool hook_NetPeerSetMaster1(void *self, int32_t nextMasterId, void *method) {
    if (self && (uintptr_t)self > 0x100000000ULL) gOGS.capturedNetPeer = self;
    if (gOGS.autoHostOn && self && OGSIsNetworkingPeerRoomReady(self, NULL)) {
        void *myPlayer = NULL;
        int32_t myID = OGSGetLocalPlayerID(&myPlayer);
        if (myID > 0 && nextMasterId > 0 && nextMasterId != myID) {
            gOGS.kickTargetID = nextMasterId;
            gOGS.kickRetries = 30;
            nextMasterId = myID;
        }
    }
    return orig_NetPeerSetMaster1 ? orig_NetPeerSetMaster1(self, nextMasterId, method) : false;
}

static void OGSHandleMasterSwitchIntercept(void *newMasterPlayer) {
    if (!gOGS.autoHostOn || !newMasterPlayer || (uintptr_t)newMasterPlayer < 0x100000000ULL) return;
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
        gOGS.kickRetries = 30;
        OGSForceKickPeerBypassingGate(newMasterPlayer, true);
        OGSClaimMasterAllLayers(true);
    }
}

static void hook_OnMasterSwitched1(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch1) orig_OnMasterSwitch1(self, p, m); }
static void hook_OnMasterSwitched2(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch2) orig_OnMasterSwitch2(self, p, m); }
static void hook_OnMasterSwitched3(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch3) orig_OnMasterSwitch3(self, p, m); }
static void hook_OnMasterSwitched4(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch4) orig_OnMasterSwitch4(self, p, m); }
static void hook_OnMasterSwitched5(void *self, void *p, void *m) { OGSHandleMasterSwitchIntercept(p); if (orig_OnMasterSwitch5) orig_OnMasterSwitch5(self, p, m); }

// ربط فتحات الـ VTable الدقيقة في الرام (+0x1a8, +0x2a8, +0x358) الخاصة بكائن NetworkingPeer
static void OGSInstallLiveVTableHooksIfNeeded(void *netPeer) {
    if (!netPeer || (uintptr_t)netPeer < 0x100000000ULL) return;
    uintptr_t klass = 0;
    if (!OGSReadMemory((uintptr_t)netPeer, &klass, sizeof(uintptr_t)) || klass < 0x100000000ULL) return;
    if (gOGS.patchedVTableKlass == klass) return;

    // 1. Slot +0x2a8 (البوابة الافتراضية التي يستدعيها LeaveRoom عند 0x13d0808)
    void **slotOpLeave = (void **)(klass + VTABLE_OFF_OPLEAVE_VIRT);
    void *curOpLeave = NULL;
    if (OGSReadPointer((uintptr_t)slotOpLeave, &curOpLeave) && curOpLeave != (void *)&hook_OpLeaveVirt) {
        orig_OpLeaveVirt = (OpLeaveVirtFn)curOpLeave;
        *slotOpLeave = (void *)&hook_OpLeaveVirt;
    }

    // 2. Slot +0x358 (Type4870::OnEvent - Slot 35)
    void **slotOnEvent = (void **)(klass + VTABLE_OFF_ONEVENT);
    void *curOnEvent = NULL;
    if (OGSReadPointer((uintptr_t)slotOnEvent, &curOnEvent) && curOnEvent != (void *)&hook_OnEvent) {
        orig_OnEvent = (OnEventFn)curOnEvent;
        *slotOnEvent = (void *)&hook_OnEvent;
    }

    // 3. Slot +0x1a8 (Type4870::Disconnect - Slot 8)
    void **slotDisconnect = (void **)(klass + VTABLE_OFF_DISCONNECT);
    void *curDisconnect = NULL;
    if (OGSReadPointer((uintptr_t)slotDisconnect, &curDisconnect) && curDisconnect != (void *)&hook_Disconnect) {
        orig_Disconnect = (DisconnectFn)curDisconnect;
        *slotDisconnect = (void *)&hook_Disconnect;
    }

    gOGS.patchedVTableKlass = klass;
}

// ============================================================
// MARK: - Chat & Disconnect Hooks
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

    NSString *kickPhrase = [NSString stringWithUTF8String:gOGS.customKickPhrase];
    if (!kickPhrase.length) kickPhrase = @" تم طرده من الغرفة ";
    NSUInteger len = kickPhrase.length;
    if (len > 90) len = 90;

    static uint8_t s_rawStrBuf[256] = {0};
    memset(s_rawStrBuf, 0, sizeof(s_rawStrBuf));
    memcpy(s_rawStrBuf, header, 16);
    *(int32_t *)(s_rawStrBuf + 0x10) = (int32_t)len;
    [kickPhrase getCharacters:(unichar *)(s_rawStrBuf + 0x14) range:NSMakeRange(0, len)];

    if (origIsPreFixed) {
        uintptr_t fixAddr = OGSResolveRVA(gOffsets.rvaArabicFix);
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
        return;
    } else if (gOGS.chatMode == 2) {
        NSString *senderName = OGSReadIl2CppString(senderStr);
        if (senderName.length > 0) {
            NSString *normSender = OGSNormalizeKey(senderName);
            const char *utf8 = normSender.UTF8String;
            if (utf8) {
                snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", utf8);
                gOGS.kickTargetID = -1;
                gOGS.kickRetries = 25;
                OGSUpdateRoomSnapshot();
            }
        }
        return;
    }
    if (orig_SendChatRemote) orig_SendChatRemote(self, senderStr, msgStr, p3, p4, method);
}

static volatile int32_t s_chatFrameDiv = 0;

static void hook_ChatUpdate(void *self, void *method) {
    if (orig_ChatUpdate) orig_ChatUpdate(self, method);
    OGSProcessSpeed();
    if (++s_chatFrameDiv >= 8) {
        s_chatFrameDiv = 0;
        OGSUpdateRoomSnapshot();
    }
}

static void hook_CashUpdate(void *self, void *method) {
    if (orig_CashUpdate) orig_CashUpdate(self, method);
    OGSProcessSpeed();
}

static void OGSInstallHooks(void) {
    uintptr_t base = OGSFindGameImage();
    if (!base) return;
    if (gOffsets.tblCashUpdate)        { void **sl = (void **)(base + gOffsets.tblCashUpdate);        if (*sl != (void *)&hook_CashUpdate)                { orig_CashUpdate        = (Update0Fn)*sl;           *sl = (void *)&hook_CashUpdate; } }
    if (gOffsets.tblChatUpdate)        { void **sl = (void **)(base + gOffsets.tblChatUpdate);        if (*sl != (void *)&hook_ChatUpdate)                { orig_ChatUpdate        = (Update0Fn)*sl;           *sl = (void *)&hook_ChatUpdate; } }
    if (gOffsets.tblSendChatRemote)    { void **sl = (void **)(base + gOffsets.tblSendChatRemote);    if (*sl != (void *)&hook_SendChatRemote)            { orig_SendChatRemote    = (SendChatRemoteFn)*sl;    *sl = (void *)&hook_SendChatRemote; } }
    if (gOffsets.tblOnDisconnect)      { void **sl = (void **)(base + gOffsets.tblOnDisconnect);      if (*sl != (void *)&hook_OnPhotonPlayerDisconnected){ orig_OnDisconnect      = (OnDisconnectFn)*sl;      *sl = (void *)&hook_OnPhotonPlayerDisconnected; } }
    if (gOffsets.tblOnEvent)           { void **sl = (void **)(base + gOffsets.tblOnEvent);           if (*sl != (void *)&hook_OnEvent)                   { orig_OnEvent           = (OnEventFn)*sl;           *sl = (void *)&hook_OnEvent; } }
    if (gOffsets.tblDisconnect)        { void **sl = (void **)(base + gOffsets.tblDisconnect);        if (*sl != (void *)&hook_Disconnect)                { orig_Disconnect        = (DisconnectFn)*sl;        *sl = (void *)&hook_Disconnect; } }
    if (gOffsets.tblLeaveRoom)         { void **sl = (void **)(base + gOffsets.tblLeaveRoom);         if (*sl != (void *)&hook_LeaveRoom)                 { orig_LeaveRoom         = (LeaveRoomFn)*sl;         *sl = (void *)&hook_LeaveRoom; } }
    if (gOffsets.tblType4995LeaveRoom) { void **sl = (void **)(base + gOffsets.tblType4995LeaveRoom); if (*sl != (void *)&hook_Type4995LeaveRoom)         { orig_Type4995Leave     = (Type4995LeaveFn)*sl;     *sl = (void *)&hook_Type4995LeaveRoom; } }
    if (gOffsets.tblNetPeerSetMaster2) { void **sl = (void **)(base + gOffsets.tblNetPeerSetMaster2); if (*sl != (void *)&hook_NetPeerSetMaster2)         { orig_NetPeerSetMaster2 = (NetPeerSetMaster2Fn)*sl; *sl = (void *)&hook_NetPeerSetMaster2; } }
    if (gOffsets.tblNetPeerSetMaster1) { void **sl = (void **)(base + gOffsets.tblNetPeerSetMaster1); if (*sl != (void *)&hook_NetPeerSetMaster1)         { orig_NetPeerSetMaster1 = (NetPeerSetMaster1Fn)*sl; *sl = (void *)&hook_NetPeerSetMaster1; } }
    if (gOffsets.tblOnMasterSwitched1) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched1); if (*sl != (void *)&hook_OnMasterSwitched1)         { orig_OnMasterSwitch1   = (OnMasterSwitchFn)*sl;    *sl = (void *)&hook_OnMasterSwitched1; } }
    if (gOffsets.tblOnMasterSwitched2) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched2); if (*sl != (void *)&hook_OnMasterSwitched2)         { orig_OnMasterSwitch2   = (OnMasterSwitchFn)*sl;    *sl = (void *)&hook_OnMasterSwitched2; } }
    if (gOffsets.tblOnMasterSwitched3) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched3); if (*sl != (void *)&hook_OnMasterSwitched3)         { orig_OnMasterSwitch3   = (OnMasterSwitchFn)*sl;    *sl = (void *)&hook_OnMasterSwitched3; } }
    if (gOffsets.tblOnMasterSwitched4) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched4); if (*sl != (void *)&hook_OnMasterSwitched4)         { orig_OnMasterSwitch4   = (OnMasterSwitchFn)*sl;    *sl = (void *)&hook_OnMasterSwitched4; } }
    if (gOffsets.tblOnMasterSwitched5) { void **sl = (void **)(base + gOffsets.tblOnMasterSwitched5); if (*sl != (void *)&hook_OnMasterSwitched5)         { orig_OnMasterSwitch5   = (OnMasterSwitchFn)*sl;    *sl = (void *)&hook_OnMasterSwitched5; } }
}

static uintptr_t OGSParseHexOffset(id val, uintptr_t fallback) {
    if ([val isKindOfClass:[NSNumber class]]) return (uintptr_t)[val unsignedLongLongValue];
    if ([val isKindOfClass:[NSString class]]) {
        unsigned long long outVal = 0;
        NSScanner *scanner = [NSScanner scannerWithString:(NSString *)val];
        if ([scanner scanHexLongLong:&outVal] && outVal > 0) return (uintptr_t)outVal;
    }
    return fallback;
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
        self.titleLabel.text = @"OGS v12: قفل الخروج (+0x2a8) + سيطرة الهوست";
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

        [self.menuPanel addSubview:[self makeBtn:CGRectMake(161, 105, 144, 32) title:@"طرد قسري (+0x1c0)" bg:kickOrange action:@selector(kickSelected:)]];
        [self.menuPanel addSubview:[self makeBtn:CGRectMake(10, 105, 144, 32) title:@"طرد وحظر (Ban)" bg:banRed action:@selector(banSelected:)]];

        self.hostLockButton = [self makeBtn:CGRectMake(155, 142, 150, 32) title:@"احتكار الهوست: مفعّل 👑" bg:wpnGreen action:@selector(toggleAutoHost:)];
        [self.menuPanel addSubview:self.hostLockButton];

        self.antiKickLockButton = [self makeBtn:CGRectMake(10, 142, 140, 32) title:@"ضد الطرد: مفعّل 🛡️" bg:wpnGreen action:@selector(toggleAntiKickHardLock:)];
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

        self.masterTimer = [NSTimer scheduledTimerWithTimeInterval:0.15 target:self selector:@selector(onMasterTick) userInfo:nil repeats:YES];
        self.masterTimer.tolerance = 0.02;

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
        self.statusLabel.text = @"هجوم قسري (0x0281B1C8): جاري طرد الهدف...";
    } else if (gOGS.lastHijackerName[0] != '\0') {
        NSString *hj = [NSString stringWithUTF8String:gOGS.lastHijackerName];
        self.statusLabel.text = [NSString stringWithFormat:@"طُرد السارق: %@ | صد طرد: %u 🛡️", hj ?: @"", blocked];
    } else {
        self.statusLabel.text = [NSString stringWithFormat:@"%@ | بالروم: %u | صد طرد: %u 🛡️",
                                 snapshot.inRoom ? (snapshot.isMaster ? @"الهوست: أنت 👑" : @"درع VTable نشط 🛡️") : @"غير متصل",
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
    gOGS.forceHostReq = 1;
    bool ok = OGSClaimMasterAllLayers(true);
    OGSUpdateRoomSnapshot();
    if (ok) {
        self.statusLabel.text = @"تم تنفيذ سحب الهوست الفعلي بنجاح (0x0281B1C8) 👑";
    } else {
        self.statusLabel.text = @"ادخل داخل روم أولاً لسحب الهوست!";
    }
}

- (void)toggleAutoHost:(UIButton *)s {
    gOGS.autoHostOn = !gOGS.autoHostOn;
    if (gOGS.autoHostOn) {
        gOGS.forceHostReq = 1;
        OGSClaimMasterAllLayers(true);
        [s setTitle:@"احتكار الهوست: مفعّل 👑" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
    } else {
        [s setTitle:@"احتكار الهوست: متوقف" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
    }
    [self refreshUI];
}

// زر مستقل لقفل عدم الخروج من الروم نهائياً (+0x2a8): يمنع طردك بأي طريقة، وعندما تريد أنت الخروج من الروم أوقفه مؤقتاً
- (void)toggleAntiKickHardLock:(UIButton *)s {
    gOGS.antiKickHardLock = !gOGS.antiKickHardLock;
    if (gOGS.antiKickHardLock) {
        [s setTitle:@"ضد الطرد: مفعّل 🛡️" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.25 alpha:1.0];
        self.statusLabel.text = @"قفل (+0x2a8) مفعّل: يستحيل إخراجك من الروم 🛡️";
    } else {
        [s setTitle:@"ضد الطرد: متوقف (للخروج)" forState:UIControlStateNormal];
        s.backgroundColor = [UIColor colorWithRed:0.22 green:0.23 blue:0.28 alpha:1.0];
        self.statusLabel.text = @"تم فتح القفل: يمكنك الخروج من الروم الآن";
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

- (void)triggerImmediateGateBypassKick:(OGSPeerSnapshot)peer {
    gOGS.kickTargetID = peer.actorID;
    NSString *pName = [NSString stringWithUTF8String:peer.name];
    NSString *normName = OGSNormalizeKey(pName);
    const char *utf8 = normName.UTF8String;
    if (utf8) {
        snprintf(gOGS.kickTargetName, sizeof(gOGS.kickTargetName), "%s", utf8);
    }
    gOGS.kickRetries = 25;

    OGSClaimMasterAllLayers(true);

    void *players[OGS_MAX_PEERS];
    uint32_t count = OGSReadPlayerArray(gOffsets.rvaGetPeers, players);
    uintptr_t idAddr = OGSResolveRVA(gOffsets.rvaPlayerGetID);
    PlayerGetIDFn getID = (PlayerGetIDFn)idAddr;

    for (uint32_t i = 0; i < count; i++) {
        if (getID && getID(players[i], NULL) == peer.actorID) {
            OGSForceKickPeerBypassingGate(players[i], true);
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
    [self triggerImmediateGateBypassKick:peer];
    self.statusLabel.text = [NSString stringWithFormat:@"تم إرسال طرد فعلي: %@", pName ?: @"اللاعب"];
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

    [self triggerImmediateGateBypassKick:peer];
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
    // تثبيت الخطافات مبكراً (0.5 ثانية) لالتقاط جدول الـ VTable وكائن الشبكة فور تشغيل المحرك
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OGSInstallHooks();
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OGSInstallHooks();
        [[OGSModMenu sharedInstance] setupMenu];
    });
}
