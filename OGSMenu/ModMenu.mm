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

static NSString * const kDefaultGitHubConfigURL =
@"https://raw.githubusercontent.com/al-hzmi/OGSMenu-Build-/main/ogs_config.json";

static NSArray<NSString *> *OGSCandidateCloudURLs(NSString *customURL)
{
    NSMutableArray<NSString *> *urls = [NSMutableArray array];

    if (customURL.length > 8)
        [urls addObject:customURL];

    [urls addObject:
     @"https://raw.githubusercontent.com/al-hzmi/OGSMenu-Build-/main/ogs_config.json"];

    [urls addObject:
     @"https://raw.githubusercontent.com/al-hzmi/OGSMenu-Build-/main/OGSMenu/ogs_config.json"];

    [urls addObject:
     @"https://raw.githubusercontent.com/Al-hzmi/ogsmenu/main/ogs_config.json"];

    return urls;
}

// ============================================================
// MARK: - Verified offsets for Falcon_Clean_v9
// ============================================================

static const uintptr_t RVA_PHOTON_NET_TYPEINFO = 0x0281B1C8;

typedef struct {
    uintptr_t tblCashUpdate;
    uintptr_t tblChatUpdate;
    uintptr_t tblSendChatRemote;
    uintptr_t tblOnEvent;
    uintptr_t tblDisconnect;
    uintptr_t tblOnDisconnect;

    uintptr_t tblPeerSync;
    uintptr_t tblSetMaster;

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
    uintptr_t rvaArabicFix;
    uintptr_t rvaFastAllocateString;
} OGSOffsetsConfig;

static const OGSOffsetsConfig gOffsets = {
    // VERIFIED method-pointer entries
    .tblCashUpdate         = 0x23918B8,
    .tblChatUpdate         = 0x238FCE8,
    .tblSendChatRemote     = 0x238FD00,

    .tblOnEvent            = 0x2390048,
    .tblDisconnect         = 0x238FF48,
    .tblOnDisconnect       = 0x2391930,

    .tblPeerSync           = 0x2390A98,
    .tblSetMaster          = 0x2390AA0,

    .rvaSetTimescale       = 0x0198AC4C,
    .rvaInRoom             = 0x013CC38C,
    .rvaIsMaster           = 0x013CC2BC,
    .rvaGetMasterPeer      = 0x013CACA4,
    .rvaGetLocalPlayer     = 0x013CABF0,
    .rvaGetRoom            = 0x013CAB28,
    .rvaAllPlayers         = 0x013CAEC4,
    .rvaGetPeers           = 0x013CAF78,
    .rvaPlayerGetName      = 0x013D7534,
    .rvaPlayerGetID        = 0x013CC384,
    .rvaArabicFix          = 0x0130F538,
    .rvaFastAllocateString = 0x01B33DB8
};

// ============================================================
// MARK: - Function signatures
// ============================================================

typedef void  (*Update0Fn)(void *, const void *);
typedef void  (*SetTime1Fn)(float, const void *);

typedef void (*SendChatRemoteFn)(
    void *self,
    void *senderName,
    void *text,
    int32_t senderTeam,
    bool isTeamChat,
    const void *method
);

typedef void  (*OnEventFn)(void *, void *, const void *);
typedef void  (*DisconnectFn)(void *, const void *);

typedef bool  (*Bool0Fn)(const void *);
typedef bool  (*Bool1ObjFn)(void *, const void *);

typedef void *(*Object0Fn)(const void *);
typedef bool  (*PeerAction1Fn)(void *, const void *);

typedef void *(*PlayerGetNameFn)(void *, const void *);
typedef int32_t (*PlayerGetIDFn)(void *, const void *);

typedef void *(*FastAllocateStringFn)(
    int32_t length,
    const void *method
);

typedef void (*OnDisconnectFn)(
    void *,
    void *,
    const void *
);

// ============================================================
// MARK: - Original functions
// ============================================================

static Update0Fn        orig_CashUpdate        = NULL;
static Update0Fn        orig_ChatUpdate        = NULL;
static SendChatRemoteFn orig_SendChatRemote    = NULL;
static OnDisconnectFn   orig_OnDisconnect      = NULL;
static OnEventFn        orig_OnEvent           = NULL;
static DisconnectFn     orig_Disconnect        = NULL;

// ============================================================
// MARK: - Runtime state
// ============================================================

typedef struct {
    bool inRoom;
    bool isMaster;

    uint32_t selectedPeer;

    float gameSpeed;
    bool speedDirty;

    uint64_t generation;
    uint64_t readFailures;

    int32_t chatMode;

    int32_t insideNetworkEvent;

    uint32_t blockedKicksCount;

    uintptr_t capturedNetPeer;

    char customKickPhrase[OGS_MAX_NAME_BYTES];

} OGSRuntimeState;

static OGSRuntimeState gOGS = {
    .inRoom             = false,
    .isMaster           = false,
    .selectedPeer       = 0,

    .gameSpeed          = 1.0f,
    .speedDirty         = false,

    .generation         = 0,
    .readFailures       = 0,

    .chatMode           = 0,
    .insideNetworkEvent = 0,

    .blockedKicksCount  = 0,
    .capturedNetPeer    = 0,

    .customKickPhrase   = " تم طرده من الغرفة "
};

// ============================================================
// MARK: - Image resolver
// ============================================================

static uintptr_t gImageBase = 0;

static uintptr_t OGSFindGameImage(void)
{
    uintptr_t cached =
        __atomic_load_n(
            &gImageBase,
            __ATOMIC_ACQUIRE
        );

    if (cached)
        return cached;

    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {

        const char *path =
            _dyld_get_image_name(i);

        if (!path)
            continue;

        const char *slash =
            strrchr(path, '/');

        const char *filename =
            slash ? slash + 1 : path;

        if (strcmp(filename, "fps") != 0)
            continue;

        intptr_t slide =
            _dyld_get_image_vmaddr_slide(i);

        uintptr_t base =
            0x100000000ULL +
            (uintptr_t)slide;

        if (base < 0x100000000ULL)
            return 0;

        __atomic_store_n(
            &gImageBase,
            base,
            __ATOMIC_RELEASE
        );

        return base;
    }

    // Fail closed.
    // Never use image 0 as fallback.
    return 0;
}

static uintptr_t OGSResolveRVA(uintptr_t rva)
{
    if (!rva)
        return 0;

    uintptr_t base =
        OGSFindGameImage();

    if (!base)
        return 0;

    if (UINTPTR_MAX - base < rva)
        return 0;

    return base + rva;
}

// ============================================================
// MARK: - Safe memory reading
// ============================================================

static bool OGSReadMemory(
    uintptr_t address,
    void *output,
    size_t size)
{
    if (!output ||
        size == 0 ||
        address < 0x100000000ULL)
        return false;

    vm_size_t copied = 0;

    kern_return_t kr =
        vm_read_overwrite(
            mach_task_self(),
            (vm_address_t)address,
            (vm_size_t)size,
            (vm_address_t)output,
            &copied
        );

    if (kr != KERN_SUCCESS ||
        copied != (vm_size_t)size) {

        __atomic_fetch_add(
            &gOGS.readFailures,
            1,
            __ATOMIC_RELAXED
        );

        return false;
    }

    return true;
}

static bool OGSReadPointer(
    uintptr_t address,
    void **output)
{
    if (!output)
        return false;

    uintptr_t value = 0;

    if (!OGSReadMemory(
            address,
            &value,
            sizeof(value)))
        return false;

    if (value < 0x100000000ULL)
        return false;

    *output = (void *)value;

    return true;
}

// ============================================================
// MARK: - IL2CPP String reading
// ============================================================

static NSString *OGSReadIl2CppString(void *object)
{
    if (!object ||
        (uintptr_t)object < 0x100000000ULL)
        return nil;

    uintptr_t address =
        (uintptr_t)object;

    int32_t length = 0;

    if (!OGSReadMemory(
            address + 0x10,
            &length,
            sizeof(length)))
        return nil;

    if (length <= 0 ||
        length > OGS_MAX_STRING_LEN)
        return nil;

    size_t bytes =
        (size_t)length *
        sizeof(unichar);

    unichar *buffer =
        calloc(
            (size_t)length,
            sizeof(unichar)
        );

    if (!buffer)
        return nil;

    if (!OGSReadMemory(
            address + 0x14,
            buffer,
            bytes)) {

        free(buffer);
        return nil;
    }

    NSString *result =
        [[NSString alloc]
            initWithCharacters:buffer
                        length:(NSUInteger)length];

    free(buffer);

    return result;
}

static NSString *OGSNormalizeKey(
    NSString *value)
{
    if (!value)
        return @"";

    NSString *trimmed =
        [value
            stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];

    return trimmed.lowercaseString;
}

// ============================================================
// MARK: - Managed IL2CPP String allocation
// ============================================================

static void *OGSManagedStringFromNSString(
    NSString *text)
{
    if (!text)
        return NULL;

    NSUInteger length =
        text.length;

    if (length == 0 ||
        length > INT32_MAX)
        return NULL;

    uintptr_t address =
        OGSResolveRVA(
            gOffsets.rvaFastAllocateString
        );

    if (!address)
        return NULL;

    FastAllocateStringFn allocate =
        (FastAllocateStringFn)address;

    void *managed =
        allocate(
            (int32_t)length,
            NULL
        );

    if (!managed)
        return NULL;

    unichar *characters =
        (unichar *)(
            (uintptr_t)managed +
            0x14
        );

    [text
        getCharacters:characters
                range:NSMakeRange(
                    0,
                    length
                )];

    return managed;
}

// ============================================================
// MARK: - Snapshot model
// ============================================================

typedef struct {
    int32_t actorID;
    bool isHost;

    char name[
        OGS_MAX_NAME_BYTES
    ];

} OGSPeerSnapshot;

typedef struct {
    uint64_t generation;

    bool inRoom;
    bool isMaster;

    uint32_t count;

    OGSPeerSnapshot peers[
        OGS_MAX_PEERS
    ];

} OGSRoomSnapshot;

static os_unfair_lock gSnapshotLock =
    OS_UNFAIR_LOCK_INIT;

static OGSRoomSnapshot
    gPublishedSnapshot;

static void OGSPublishSnapshot(
    const OGSRoomSnapshot *snapshot)
{
    if (!snapshot)
        return;

    os_unfair_lock_lock(
        &gSnapshotLock
    );

    gPublishedSnapshot =
        *snapshot;

    os_unfair_lock_unlock(
        &gSnapshotLock
    );
}

static OGSRoomSnapshot
OGSCurrentSnapshot(void)
{
    OGSRoomSnapshot output;

    os_unfair_lock_lock(
        &gSnapshotLock
    );

    output =
        gPublishedSnapshot;

    os_unfair_lock_unlock(
        &gSnapshotLock
    );

    return output;
}

// ============================================================
// MARK: - Player extraction
// ============================================================

static bool OGSReadPeer(
    void *peer,
    void *master,
    OGSPeerSnapshot *output)
{
    if (!peer ||
        !output)
        return false;

    memset(
        output,
        0,
        sizeof(*output)
    );

    output->isHost =
        (peer == master);

    uintptr_t idAddress =
        OGSResolveRVA(
            gOffsets.rvaPlayerGetID
        );

    uintptr_t nameAddress =
        OGSResolveRVA(
            gOffsets.rvaPlayerGetName
        );

    if (!idAddress ||
        !nameAddress)
        return false;

    PlayerGetIDFn getID =
        (PlayerGetIDFn)idAddress;

    PlayerGetNameFn getName =
        (PlayerGetNameFn)nameAddress;

    output->actorID =
        getID(
            peer,
            NULL
        );

    void *nameObject =
        getName(
            peer,
            NULL
        );

    NSString *name =
        OGSReadIl2CppString(
            nameObject
        );

    if (!name.length) {

        snprintf(
            output->name,
            sizeof(output->name),
            "ID:%d",
            output->actorID
        );

        return true;
    }

    NSData *utf8 =
        [name
            dataUsingEncoding:NSUTF8StringEncoding
            allowLossyConversion:YES];

    if (!utf8.length)
        return false;

    size_t length =
        MIN(
            utf8.length,
            sizeof(output->name) - 1
        );

    memcpy(
        output->name,
        utf8.bytes,
        length
    );

    output->name[length] =
        '\0';

    return true;
}

static uint32_t OGSReadPlayerArray(
    uintptr_t listRVA,
    void *output[OGS_MAX_PEERS])
{
    if (!output)
        return 0;

    memset(
        output,
        0,
        sizeof(void *) *
        OGS_MAX_PEERS
    );

    uintptr_t inRoomAddress =
        OGSResolveRVA(
            gOffsets.rvaInRoom
        );

    uintptr_t listAddress =
        OGSResolveRVA(
            listRVA
        );

    if (!inRoomAddress ||
        !listAddress)
        return 0;

    Bool0Fn inRoom =
        (Bool0Fn)inRoomAddress;

    Object0Fn getList =
        (Object0Fn)listAddress;

    if (!inRoom(NULL))
        return 0;

    void *array =
        getList(NULL);

    if (!array)
        return 0;

    uintptr_t count = 0;

    if (!OGSReadMemory(
            (uintptr_t)array + 0x18,
            &count,
            sizeof(count)))
        return 0;

    if (count == 0 ||
        count > OGS_MAX_PEERS)
        return 0;

    uint32_t valid = 0;

    for (uintptr_t i = 0;
         i < count &&
         valid < OGS_MAX_PEERS;
         i++) {

        void *peer = NULL;

        uintptr_t itemAddress =
            (uintptr_t)array +
            0x20 +
            i * sizeof(void *);

        if (!OGSReadPointer(
                itemAddress,
                &peer))
            continue;

        output[valid++] =
            peer;
    }

    return valid;
}

// ============================================================
// MARK: - Local player
// ============================================================

static void *OGSFindLocalPlayer(void)
{
    uintptr_t address =
        OGSResolveRVA(
            gOffsets.rvaGetLocalPlayer
        );

    if (!address)
        return NULL;

    void *player =
        ((Object0Fn)address)(
            NULL
        );

    if (!player ||
        (uintptr_t)player <
            0x100000000ULL)
        return NULL;

    return player;
}

static int32_t OGSGetLocalPlayerID(
    void **outPlayer)
{
    void *player =
        OGSFindLocalPlayer();

    if (outPlayer)
        *outPlayer = player;

    if (!player)
        return 0;

    uintptr_t address =
        OGSResolveRVA(
            gOffsets.rvaPlayerGetID
        );

    if (!address)
        return 0;

    return
        ((PlayerGetIDFn)address)(
            player,
            NULL
        );
}

// ============================================================
// MARK: - NetworkingPeer resolver
// ============================================================

static void *OGSGetNetworkingPeerSafe(void)
{
    uintptr_t slot =
        OGSResolveRVA(
            RVA_PHOTON_NET_TYPEINFO
        );

    if (!slot)
        return NULL;

    void *klass = NULL;

    if (!OGSReadPointer(
            slot,
            &klass))
        return NULL;

    void *staticFields =
        NULL;

    if (!OGSReadPointer(
            (uintptr_t)klass +
            0xB8,
            &staticFields))
        return NULL;

    void *netPeer =
        NULL;

    if (!OGSReadPointer(
            (uintptr_t)staticFields +
            0x10,
            &netPeer))
        return NULL;

    /*
     Verified:
       +0x158 = currentRoom
       +0x160 = LocalPlayer

     +0x1C0 is deliberately NOT used as
     a MasterClientId validation field.
    */

    void *currentRoom =
        NULL;

    void *localPlayer =
        NULL;

    OGSReadPointer(
        (uintptr_t)netPeer +
        0x158,
        &currentRoom
    );

    OGSReadPointer(
        (uintptr_t)netPeer +
        0x160,
        &localPlayer
    );

    if (!currentRoom &&
        !localPlayer)
        return NULL;

    __atomic_store_n(
        &gOGS.capturedNetPeer,
        (uintptr_t)netPeer,
        __ATOMIC_RELEASE
    );

    return netPeer;
}

// ============================================================
// MARK: - Speed
// ============================================================

static void OGSApplyTimescaleNow(
    float speed)
{
    uintptr_t address =
        OGSResolveRVA(
            gOffsets.rvaSetTimescale
        );

    if (!address)
        return;

    ((SetTime1Fn)address)(
        speed,
        NULL
    );
}

static void OGSRequestSpeed(
    float speed)
{
    if (!isfinite(speed))
        return;

    speed =
        fmaxf(
            0.1f,
            fminf(
                speed,
                20.0f
            )
        );

    __atomic_store_n(
        &gOGS.gameSpeed,
        speed,
        __ATOMIC_RELEASE
    );

    __atomic_store_n(
        &gOGS.speedDirty,
        true,
        __ATOMIC_RELEASE
    );
}

static void OGSProcessSpeed(void)
{
    bool dirty =
        __atomic_exchange_n(
            &gOGS.speedDirty,
            false,
            __ATOMIC_ACQ_REL
        );

    if (!dirty)
        return;

    float speed =
        __atomic_load_n(
            &gOGS.gameSpeed,
            __ATOMIC_ACQUIRE
        );

    OGSApplyTimescaleNow(
        speed
    );
}

// ============================================================
// MARK: - Forward declarations
// ============================================================

@interface OGSPassthroughContainer : UIView

@property (weak, nonatomic)
UIButton *floatingButton;

@property (weak, nonatomic)
UIView *menuPanel;

@end

@implementation OGSPassthroughContainer

- (BOOL)pointInside:
    (CGPoint)p
    withEvent:(UIEvent *)e
{
    if (self.floatingButton &&
        !self.floatingButton.hidden &&
        [self.floatingButton
            pointInside:
            [self convertPoint:
                p
                toView:
                self.floatingButton]
            withEvent:e])
        return YES;

    if (self.menuPanel &&
        !self.menuPanel.hidden &&
        [self.menuPanel
            pointInside:
            [self convertPoint:
                p
                toView:
                self.menuPanel]
            withEvent:e])
        return YES;

    return NO;
}

@end

@interface OGSModMenu : NSObject

@property (strong, nonatomic)
OGSPassthroughContainer *containerView;

@property (strong, nonatomic)
UIButton *floatingButton;

@property (strong, nonatomic)
UIView *menuPanel;

@property (strong, nonatomic)
UILabel *titleLabel;

@property (strong, nonatomic)
UILabel *playerLabel;

@property (strong, nonatomic)
UILabel *statusLabel;

@property (strong, nonatomic)
UIButton *syncCloudButton;

@property (strong, nonatomic)
UIButton *unbanButton;

@property (strong, nonatomic)
UIButton *lockButton;

@property (strong, nonatomic)
UIButton *hostLockButton;

@property (strong, nonatomic)
UIButton *antiKickLockButton;

@property (strong, nonatomic)
UIButton *muteChatButton;

@property (strong, nonatomic)
UIButton *speedSetButton;

@property (strong, nonatomic)
NSMutableSet<NSString *> *bannedNames;

@property (strong, nonatomic)
NSMutableSet<NSNumber *> *bannedActorIDs;

@property (strong, nonatomic)
NSMutableSet<NSString *> *allowedNamesWhenLocked;

@property (assign, nonatomic)
BOOL roomLockActive;

@property (strong, nonatomic)
NSTimer *masterTimer;

+ (instancetype)sharedInstance;

- (void)setupMenu;
- (void)ensureMenuVisible;

- (void)fetchGitHubCloudConfigWithFeedback:
    (BOOL)showFeedback;

- (BOOL)shouldAutoKickPeerWithName:
    (NSString *)name
    actorID:(int32_t)actorID;

@end

// ============================================================
// MARK: - Snapshot update
// ============================================================

static int32_t gSnapshotBusy = 0;

static void OGSUpdateRoomSnapshot(void)
{
    if (__atomic_exchange_n(
            &gSnapshotBusy,
            1,
            __ATOMIC_ACQ_REL))
        return;

    OGSRoomSnapshot snapshot =
        {0};

    uintptr_t inRoomAddress =
        OGSResolveRVA(
            gOffsets.rvaInRoom
        );

    uintptr_t masterStateAddress =
        OGSResolveRVA(
            gOffsets.rvaIsMaster
        );

    uintptr_t masterPlayerAddress =
        OGSResolveRVA(
            gOffsets.rvaGetMasterPeer
        );

    if (!inRoomAddress ||
        !masterStateAddress ||
        !masterPlayerAddress)
        goto finish;

    Bool0Fn inRoomFn =
        (Bool0Fn)inRoomAddress;

    Bool0Fn isMasterFn =
        (Bool0Fn)masterStateAddress;

    Object0Fn masterFn =
        (Object0Fn)masterPlayerAddress;

    snapshot.inRoom =
        inRoomFn(NULL);

    __atomic_store_n(
        &gOGS.inRoom,
        snapshot.inRoom,
        __ATOMIC_RELEASE
    );

    if (!snapshot.inRoom) {

        __atomic_store_n(
            &gOGS.isMaster,
            false,
            __ATOMIC_RELEASE
        );

        goto finish;
    }

    snapshot.isMaster =
        isMasterFn(NULL);

    __atomic_store_n(
        &gOGS.isMaster,
        snapshot.isMaster,
        __ATOMIC_RELEASE
    );

    void *master =
        masterFn(NULL);

    void *players[
        OGS_MAX_PEERS
    ];

    uint32_t count =
        OGSReadPlayerArray(
            gOffsets.rvaGetPeers,
            players
        );

    for (uint32_t i = 0;
         i < count &&
         snapshot.count <
            OGS_MAX_PEERS;
         i++) {

        OGSPeerSnapshot peer;

        if (!OGSReadPeer(
                players[i],
                master,
                &peer))
            continue;

        snapshot.peers[
            snapshot.count++
        ] = peer;
    }

finish:

    snapshot.generation =
        __atomic_fetch_add(
            &gOGS.generation,
            1,
            __ATOMIC_RELAXED
        ) + 1;

    OGSPublishSnapshot(
        &snapshot
    );

    __atomic_store_n(
        &gSnapshotBusy,
        0,
        __ATOMIC_RELEASE
    );
}

// ============================================================
// MARK: - Legitimate Photon admin calls
// ============================================================

static bool OGSRequestMasterNormally(void)
{
    if (!gOGS.inRoom)
        return false;

    void *localPlayer =
        NULL;

    int32_t localID =
        OGSGetLocalPlayerID(
            &localPlayer
        );

    if (!localPlayer ||
        localID <= 0)
        return false;

    uintptr_t slot =
        OGSResolveRVA(
            gOffsets.tblSetMaster
        );

    void *fn =
        NULL;

    if (!slot ||
        !OGSReadPointer(
            slot,
            &fn) ||
        !fn)
        return false;

    return
        ((PeerAction1Fn)fn)(
            localPlayer,
            NULL
        );
}

static bool OGSDisconnectPeerNormally(
    int32_t actorID)
{
    if (actorID <= 0 ||
        !gOGS.inRoom ||
        !gOGS.isMaster)
        return false;

    void *players[
        OGS_MAX_PEERS
    ];

    uint32_t count =
        OGSReadPlayerArray(
            gOffsets.rvaGetPeers,
            players
        );

    uintptr_t idAddress =
        OGSResolveRVA(
            gOffsets.rvaPlayerGetID
        );

    if (!idAddress)
        return false;

    PlayerGetIDFn getID =
        (PlayerGetIDFn)idAddress;

    void *target =
        NULL;

    for (uint32_t i = 0;
         i < count;
         i++) {

        int32_t id =
            getID(
                players[i],
                NULL
            );

        if (id == actorID) {
            target =
                players[i];
            break;
        }
    }

    if (!target)
        return false;

    uintptr_t slot =
        OGSResolveRVA(
            gOffsets.tblPeerSync
        );

    void *fn =
        NULL;

    if (!slot ||
        !OGSReadPointer(
            slot,
            &fn) ||
        !fn)
        return false;

    return
        ((PeerAction1Fn)fn)(
            target,
            NULL
        );
}

// ============================================================
// MARK: - Hooks
// ============================================================

static void hook_CashUpdate(
    void *self,
    const void *method)
{
    if (orig_CashUpdate)
        orig_CashUpdate(
            self,
            method
        );
}

static void hook_ChatUpdate(
    void *self,
    const void *method)
{
    if (orig_ChatUpdate)
        orig_ChatUpdate(
            self,
            method
        );

    /*
     No room scanning here.
     Periodic state work is owned by the UI timer.
    */
}

static void hook_SendChatRemote(
    void *self,
    void *senderName,
    void *text,
    int32_t senderTeam,
    bool isTeamChat,
    const void *method)
{
    int32_t mode =
        __atomic_load_n(
            &gOGS.chatMode,
            __ATOMIC_ACQUIRE
        );

    if (mode == 1)
        return;

    /*
     Mode 2 intentionally does not synchronously
     scan/kick from inside the RPC receiver.
     That was a re-entrancy hazard.
    */

    if (orig_SendChatRemote)
        orig_SendChatRemote(
            self,
            senderName,
            text,
            senderTeam,
            isTeamChat,
            method
        );
}

static void hook_OnEvent(
    void *self,
    void *eventData,
    const void *method)
{
    if (self &&
        (uintptr_t)self >=
            0x100000000ULL) {

        __atomic_store_n(
            &gOGS.capturedNetPeer,
            (uintptr_t)self,
            __ATOMIC_RELEASE
        );
    }

    /*
     Do NOT classify incoming code 203 as a
     guaranteed kick event.
    */

    __atomic_fetch_add(
        &gOGS.insideNetworkEvent,
        1,
        __ATOMIC_ACQ_REL
    );

    if (orig_OnEvent)
        orig_OnEvent(
            self,
            eventData,
            method
        );

    __atomic_fetch_sub(
        &gOGS.insideNetworkEvent,
        1,
        __ATOMIC_ACQ_REL
    );
}

static void hook_Disconnect(
    void *self,
    const void *method)
{
    if (self &&
        (uintptr_t)self >=
            0x100000000ULL) {

        __atomic_store_n(
            &gOGS.capturedNetPeer,
            (uintptr_t)self,
            __ATOMIC_RELEASE
        );
    }

    /*
     Allow normal Photon lifecycle cleanup.
    */

    if (orig_Disconnect)
        orig_Disconnect(
            self,
            method
        );
}

static void hook_OnPhotonPlayerDisconnected(
    void *self,
    void *player,
    const void *method)
{
    if (orig_OnDisconnect)
        orig_OnDisconnect(
            self,
            player,
            method
        );
}

// ============================================================
// MARK: - Hook installation
// ============================================================

static os_unfair_lock gHookLock =
    OS_UNFAIR_LOCK_INIT;

static bool gHooksInstalled =
    false;

static bool OGSInstallTableHook(
    uintptr_t tableRVA,
    void *replacement,
    void **original)
{
    if (!tableRVA ||
        !replacement ||
        !original)
        return false;

    uintptr_t slotAddress =
        OGSResolveRVA(
            tableRVA
        );

    if (!slotAddress)
        return false;

    void *current =
        NULL;

    if (!OGSReadPointer(
            slotAddress,
            &current))
        return false;

    if (current ==
        replacement)
        return true;

    if (*original)
        return false;

    *original =
        current;

    void **slot =
        (void **)slotAddress;

    *slot =
        replacement;

    return true;
}

static void OGSInstallHooks(void)
{
    os_unfair_lock_lock(
        &gHookLock
    );

    if (gHooksInstalled) {

        os_unfair_lock_unlock(
            &gHookLock
        );

        return;
    }

    if (!OGSFindGameImage()) {

        os_unfair_lock_unlock(
            &gHookLock
        );

        return;
    }

    bool a =
        OGSInstallTableHook(
            gOffsets.tblCashUpdate,
            (void *)&hook_CashUpdate,
            (void **)&orig_CashUpdate
        );

    bool b =
        OGSInstallTableHook(
            gOffsets.tblChatUpdate,
            (void *)&hook_ChatUpdate,
            (void **)&orig_ChatUpdate
        );

    bool c =
        OGSInstallTableHook(
            gOffsets.tblSendChatRemote,
            (void *)&hook_SendChatRemote,
            (void **)&orig_SendChatRemote
        );

    bool d =
        OGSInstallTableHook(
            gOffsets.tblOnEvent,
            (void *)&hook_OnEvent,
            (void **)&orig_OnEvent
        );

    bool e =
        OGSInstallTableHook(
            gOffsets.tblDisconnect,
            (void *)&hook_Disconnect,
            (void **)&orig_Disconnect
        );

    bool f =
        OGSInstallTableHook(
            gOffsets.tblOnDisconnect,
            (void *)&hook_OnPhotonPlayerDisconnected,
            (void **)&orig_OnDisconnect
        );

    /*
     IMPORTANT:

     0x238FF50 and 0x238FF58 are deliberately
     NOT hooked.

     In this build they resolve to unrelated
     NetworkingPeer methods, not SetMasterClient.
    */

    gHooksInstalled =
        a && b && c &&
        d && e && f;

    os_unfair_lock_unlock(
        &gHookLock
    );
}

// ============================================================
// MARK: - Runtime tick
// ============================================================

static void OGSRuntimeTick(void)
{
    OGSProcessSpeed();

    OGSUpdateRoomSnapshot();

    (void)
        OGSGetNetworkingPeerSafe();
}

// ============================================================
// MARK: - UI
// ============================================================

@implementation OGSModMenu

+ (instancetype)sharedInstance
{
    static OGSModMenu *instance =
        nil;

    static dispatch_once_t once;

    dispatch_once(
        &once,
        ^{
            instance =
                [[OGSModMenu alloc]
                    init];

            instance.bannedNames =
                [NSMutableSet set];

            instance.bannedActorIDs =
                [NSMutableSet set];

            instance.allowedNamesWhenLocked =
                [NSMutableSet set];

            NSArray *saved =
                [[NSUserDefaults
                    standardUserDefaults]
                    stringArrayForKey:
                    @"OGS_SavedBannedNames"];

            if (saved)
                [instance.bannedNames
                    addObjectsFromArray:
                    saved];
        }
    );

    return instance;
}

- (void)saveLocalBans
{
    NSArray *copy =
        self.bannedNames.allObjects;

    [[NSUserDefaults
        standardUserDefaults]
        setObject:copy
        forKey:
        @"OGS_SavedBannedNames"];
}

- (BOOL)shouldAutoKickPeerWithName:
    (NSString *)name
    actorID:(int32_t)actorID
{
    if (name.length &&
        [self.bannedNames
            containsObject:name])
        return YES;

    if (actorID > 0 &&
        [self.bannedActorIDs
            containsObject:
            @(actorID)])
        return YES;

    if (self.roomLockActive &&
        name.length &&
        ![self.allowedNamesWhenLocked
            containsObject:name])
        return YES;

    return NO;
}

- (UIWindow *)gameMainWindow
{
    UIWindow *best =
        nil;

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if (![scene
            isKindOfClass:
            UIWindowScene.class])
            continue;

        for (UIWindow *window in
             ((UIWindowScene *)scene).windows) {

            if (window.isKeyWindow)
                return window;

            if (!window.hidden &&
                window.alpha > 0.01)
                best = window;
        }
    }

    if (best)
        return best;

    return
        UIApplication
        .sharedApplication
        .windows
        .firstObject;
}

- (UIButton *)makeBtn:
    (CGRect)frame
    title:(NSString *)title
    bg:(UIColor *)background
    action:(SEL)action
{
    UIButton *button =
        [UIButton
            buttonWithType:
            UIButtonTypeSystem];

    button.frame =
        frame;

    button.backgroundColor =
        background;

    [button
        setTitle:title
        forState:UIControlStateNormal];

    [button
        setTitleColor:
        UIColor.whiteColor
        forState:UIControlStateNormal];

    button.titleLabel.font =
        [UIFont
            boldSystemFontOfSize:
            10.5];

    button.layer.cornerRadius =
        7.0;

    [button
        addTarget:self
        action:action
        forControlEvents:
        UIControlEventTouchUpInside];

    return button;
}

- (void)ensureMenuVisible
{
    UIWindow *window =
        [self gameMainWindow];

    if (!window ||
        !self.containerView)
        return;

    if (self.containerView.superview !=
        window)
        [window
            addSubview:
            self.containerView];

    if (!CGRectEqualToRect(
            self.containerView.frame,
            window.bounds))
        self.containerView.frame =
            window.bounds;

    self.containerView.hidden =
        NO;

    self.floatingButton.hidden =
        NO;

    [window
        bringSubviewToFront:
        self.containerView];
}

- (void)setupMenu
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (self.containerView) {
                [self ensureMenuVisible];
                return;
            }

            UIWindow *window =
                [self gameMainWindow];

            if (!window)
                return;

            self.containerView =
                [[OGSPassthroughContainer alloc]
                    initWithFrame:
                    window.bounds];

            self.containerView.autoresizingMask =
                UIViewAutoresizingFlexibleWidth |
                UIViewAutoresizingFlexibleHeight;

            self.floatingButton =
                [UIButton
                    buttonWithType:
                    UIButtonTypeCustom];

            self.floatingButton.frame =
                CGRectMake(
                    18,
                    95,
                    48,
                    48
                );

            self.floatingButton.backgroundColor =
                UIColor.blackColor;

            [self.floatingButton
                setTitle:@"OGS"
                forState:UIControlStateNormal];

            self.floatingButton.titleLabel.font =
                [UIFont
                    boldSystemFontOfSize:
                    13];

            self.floatingButton.layer.cornerRadius =
                24;

            self.floatingButton.layer.borderWidth =
                2;

            self.floatingButton.layer.borderColor =
                UIColor.systemRedColor.CGColor;

            [self.floatingButton
                addTarget:self
                action:@selector(toggleMenu)
                forControlEvents:
                UIControlEventTouchUpInside];

            UIPanGestureRecognizer *pan =
                [[UIPanGestureRecognizer alloc]
                    initWithTarget:self
                    action:
                    @selector(handlePan:)];

            [self.floatingButton
                addGestureRecognizer:
                pan];

            [self.containerView
                addSubview:
                self.floatingButton];

            self.menuPanel =
                [[UIView alloc]
                    initWithFrame:
                    CGRectMake(
                        75,
                        18,
                        315,
                        252
                    )];

            self.menuPanel.backgroundColor =
                [UIColor
                    colorWithRed:0.09
                    green:0.09
                    blue:0.11
                    alpha:0.96];

            self.menuPanel.layer.cornerRadius =
                14;

            self.menuPanel.layer.borderWidth =
                2;

            self.menuPanel.layer.borderColor =
                UIColor.systemRedColor.CGColor;

            self.menuPanel.hidden =
                YES;

            self.titleLabel =
                [[UILabel alloc]
                    initWithFrame:
                    CGRectMake(
                        10,
                        5,
                        260,
                        18
                    )];

            self.titleLabel.text =
                @"OGS v13 — Stable QA Console";

            self.titleLabel.textColor =
                UIColor.whiteColor;

            self.titleLabel.textAlignment =
                NSTextAlignmentCenter;

            self.titleLabel.font =
                [UIFont
                    boldSystemFontOfSize:
                    10.5];

            [self.menuPanel
                addSubview:
                self.titleLabel];

            self.syncCloudButton =
                [self
                    makeBtn:
                    CGRectMake(
                        273,
                        3,
                        32,
                        21
                    )
                    title:@"🔄"
                    bg:
                    [UIColor
                        colorWithRed:0.18
                        green:0.45
                        blue:0.75
                        alpha:1]
                    action:
                    @selector(syncCloudTapped:)];

            [self.menuPanel
                addSubview:
                self.syncCloudButton];

            UIView *infoBox =
                [[UIView alloc]
                    initWithFrame:
                    CGRectMake(
                        10,
                        25,
                        295,
                        40
                    )];

            infoBox.backgroundColor =
                [UIColor
                    colorWithRed:0.16
                    green:0.17
                    blue:0.20
                    alpha:1];

            infoBox.layer.cornerRadius =
                8;

            self.playerLabel =
                [[UILabel alloc]
                    initWithFrame:
                    CGRectMake(
                        6,
                        2,
                        283,
                        18
                    )];

            self.playerLabel.text =
                @"المحدد: لا يوجد لاعبين";

            self.playerLabel.textColor =
                UIColor.systemYellowColor;

            self.playerLabel.textAlignment =
                NSTextAlignmentCenter;

            self.playerLabel.font =
                [UIFont
                    boldSystemFontOfSize:
                    12];

            [infoBox
                addSubview:
                self.playerLabel];

            self.statusLabel =
                [[UILabel alloc]
                    initWithFrame:
                    CGRectMake(
                        6,
                        20,
                        283,
                        17
                    )];

            self.statusLabel.text =
                @"الغرفة: غير متصل";

            self.statusLabel.textColor =
                UIColor.systemGreenColor;

            self.statusLabel.textAlignment =
                NSTextAlignmentCenter;

            self.statusLabel.font =
                [UIFont
                    systemFontOfSize:
                    10.5];

            [infoBox
                addSubview:
                self.statusLabel];

            [self.menuPanel
                addSubview:
                infoBox];

            UIColor *gray =
                [UIColor
                    colorWithRed:0.22
                    green:0.23
                    blue:0.28
                    alpha:1];

            UIColor *orange =
                [UIColor
                    colorWithRed:0.80
                    green:0.35
                    blue:0.10
                    alpha:1];

            UIColor *red =
                [UIColor
                    colorWithRed:0.70
                    green:0.12
                    blue:0.15
                    alpha:1];

            UIColor *blue =
                [UIColor
                    colorWithRed:0.14
                    green:0.42
                    blue:0.72
                    alpha:1];

            [self.menuPanel addSubview:
                [self makeBtn:
                    CGRectMake(10,70,95,30)
                    title:@"▶ السابق"
                    bg:gray
                    action:@selector(prevPlayer:)]];

            [self.menuPanel addSubview:
                [self makeBtn:
                    CGRectMake(110,70,95,30)
                    title:@"طلب الهوست 👑"
                    bg:blue
                    action:@selector(claimHostNow:)]];

            [self.menuPanel addSubview:
                [self makeBtn:
                    CGRectMake(210,70,95,30)
                    title:@"التالي ◀"
                    bg:gray
                    action:@selector(nextPlayer:)]];

            [self.menuPanel addSubview:
                [self makeBtn:
                    CGRectMake(161,105,144,32)
                    title:@"طرد المحدد"
                    bg:orange
                    action:@selector(kickSelected:)]];

            [self.menuPanel addSubview:
                [self makeBtn:
                    CGRectMake(10,105,144,32)
                    title:@"طرد وحظر"
                    bg:red
                    action:@selector(banSelected:)]];

            self.lockButton =
                [self makeBtn:
                    CGRectMake(205,142,100,32)
                    title:@"قفل الروم: مفتوح"
                    bg:gray
                    action:@selector(toggleRoomLock:)];

            [self.menuPanel
                addSubview:
                self.lockButton];

            self.muteChatButton =
                [self makeBtn:
                    CGRectMake(105,142,95,32)
                    title:@"الشات: مفتوح"
                    bg:gray
                    action:@selector(cycleChatMode:)];

            [self.menuPanel
                addSubview:
                self.muteChatButton];

            self.unbanButton =
                [self makeBtn:
                    CGRectMake(10,142,90,32)
                    title:@"فك الحظر (0)"
                    bg:gray
                    action:@selector(clearBanList:)];

            [self.menuPanel
                addSubview:
                self.unbanButton];

            [self.menuPanel addSubview:
                [self makeBtn:
                    CGRectMake(10,184,55,30)
                    title:@"سرعة -"
                    bg:gray
                    action:@selector(speedDown:)]];

            self.speedSetButton =
                [self makeBtn:
                    CGRectMake(70,184,175,30)
                    title:@"السرعة: 1.0x"
                    bg:blue
                    action:@selector(promptCustomSpeed:)];

            [self.menuPanel
                addSubview:
                self.speedSetButton];

            [self.menuPanel addSubview:
                [self makeBtn:
                    CGRectMake(250,184,55,30)
                    title:@"سرعة +"
                    bg:gray
                    action:@selector(speedUp:)]];

            UILabel *stable =
                [[UILabel alloc]
                    initWithFrame:
                    CGRectMake(
                        10,
                        220,
                        295,
                        20
                    )];

            stable.text =
                @"Stable hooks • managed strings • race-safe snapshot";

            stable.textColor =
                UIColor.systemGrayColor;

            stable.textAlignment =
                NSTextAlignmentCenter;

            stable.font =
                [UIFont
                    systemFontOfSize:
                    9];

            [self.menuPanel
                addSubview:
                stable];

            [self.containerView
                addSubview:
                self.menuPanel];

            self.containerView.floatingButton =
                self.floatingButton;

            self.containerView.menuPanel =
                self.menuPanel;

            [window
                addSubview:
                self.containerView];

            [window
                bringSubviewToFront:
                self.containerView];

            self.masterTimer =
                [NSTimer
                    scheduledTimerWithTimeInterval:
                    0.25
                    target:self
                    selector:
                    @selector(onMasterTick)
                    userInfo:nil
                    repeats:YES];

            self.masterTimer.tolerance =
                0.04;

            [self
                fetchGitHubCloudConfigWithFeedback:
                NO];
        }
    );
}

// ============================================================
// MARK: - Cloud config
// ============================================================

- (void)syncCloudTapped:
    (UIButton *)sender
{
    [self
        fetchGitHubCloudConfigWithFeedback:
        YES];
}

- (void)tryFetchFromCandidateURLs:
    (NSArray<NSString *> *)candidates
    index:(NSUInteger)index
    showFeedback:(BOOL)feedback
{
    if (index >=
        candidates.count) {

        if (feedback)
            self.statusLabel.text =
                @"تعذر تحميل إعدادات GitHub";

        return;
    }

    NSString *baseURL =
        candidates[index];

    NSString *separator =
        [baseURL
            containsString:@"?"]
        ? @"&"
        : @"?";

    NSString *urlString =
        [NSString
            stringWithFormat:
            @"%@%@t=%lld",
            baseURL,
            separator,
            (long long)(
                NSDate.date
                .timeIntervalSince1970 *
                1000
            )];

    NSURL *url =
        [NSURL
            URLWithString:
            urlString];

    if (!url) {

        [self
            tryFetchFromCandidateURLs:
            candidates
            index:index + 1
            showFeedback:feedback];

        return;
    }

    NSURLRequest *request =
        [NSURLRequest
            requestWithURL:url
            cachePolicy:
            NSURLRequestReloadIgnoringLocalAndRemoteCacheData
            timeoutInterval:
            6];

    [[NSURLSession.sharedSession
        dataTaskWithRequest:request
        completionHandler:
        ^(
            NSData *data,
            NSURLResponse *response,
            NSError *error
        ) {

            NSHTTPURLResponse *http =
                [response
                    isKindOfClass:
                    NSHTTPURLResponse.class]
                ? (NSHTTPURLResponse *)response
                : nil;

            if (error ||
                !data ||
                (http &&
                 http.statusCode != 200)) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        [self
                            tryFetchFromCandidateURLs:
                            candidates
                            index:index + 1
                            showFeedback:feedback];
                    }
                );

                return;
            }

            NSError *jsonError =
                nil;

            id object =
                [NSJSONSerialization
                    JSONObjectWithData:data
                    options:0
                    error:&jsonError];

            if (jsonError ||
                ![object
                    isKindOfClass:
                    NSDictionary.class]) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{
                        [self
                            tryFetchFromCandidateURLs:
                            candidates
                            index:index + 1
                            showFeedback:feedback];
                    }
                );

                return;
            }

            dispatch_async(
                dispatch_get_main_queue(),
                ^{
                    [self
                        applyCloudConfigDictionary:
                        (NSDictionary *)object];

                    if (feedback)
                        self.statusLabel.text =
                            @"تم تحديث GitHub ✅";
                }
            );

        }]
        resume];
}

- (void)fetchGitHubCloudConfigWithFeedback:
    (BOOL)feedback
{
    if (feedback)
        self.statusLabel.text =
            @"جاري التحديث من GitHub...";

    NSString *custom =
        [NSUserDefaults.standardUserDefaults
            stringForKey:
            @"OGS_GitHubConfigURL"];

    NSArray *urls =
        OGSCandidateCloudURLs(
            custom ?:
            kDefaultGitHubConfigURL
        );

    [self
        tryFetchFromCandidateURLs:
        urls
        index:0
        showFeedback:feedback];
}

- (void)applyCloudConfigDictionary:
    (NSDictionary *)json
{
    NSString *kick =
        [json[@"kick_message"]
            isKindOfClass:
            NSString.class]
        ? json[@"kick_message"]
        : nil;

    if (kick.length) {

        NSData *data =
            [kick
                dataUsingEncoding:
                NSUTF8StringEncoding
                allowLossyConversion:YES];

        size_t length =
            MIN(
                data.length,
                sizeof(
                    gOGS.customKickPhrase
                ) - 1
            );

        memset(
            gOGS.customKickPhrase,
            0,
            sizeof(
                gOGS.customKickPhrase
            )
        );

        memcpy(
            gOGS.customKickPhrase,
            data.bytes,
            length
        );
    }

    NSNumber *speed =
        [json[@"default_speed"]
            isKindOfClass:
            NSNumber.class]
        ? json[@"default_speed"]
        : nil;

    if (speed)
        [self
            applySpeed:
            speed.floatValue];

    NSArray *names =
        [json[@"banned_names"]
            isKindOfClass:
            NSArray.class]
        ? json[@"banned_names"]
        : nil;

    for (id item in names) {

        if (![item
            isKindOfClass:
            NSString.class])
            continue;

        NSString *normalized =
            OGSNormalizeKey(
                item
            );

        if (normalized.length)
            [self.bannedNames
                addObject:
                normalized];
    }

    NSArray *ids =
        [json[@"banned_ids"]
            isKindOfClass:
            NSArray.class]
        ? json[@"banned_ids"]
        : nil;

    for (id item in ids) {

        if ([item
            isKindOfClass:
            NSNumber.class])
            [self.bannedActorIDs
                addObject:item];
    }

    [self saveLocalBans];

    [self refreshUI];
}

// ============================================================
// MARK: - UI runtime
// ============================================================

- (void)onMasterTick
{
    [self ensureMenuVisible];

    OGSRuntimeTick();

    if (!self.menuPanel ||
        self.menuPanel.hidden)
        return;

    [self refreshUI];
}

- (void)refreshUI
{
    OGSRoomSnapshot snapshot =
        OGSCurrentSnapshot();

    uint32_t selected =
        __atomic_load_n(
            &gOGS.selectedPeer,
            __ATOMIC_ACQUIRE
        );

    if (!snapshot.count) {

        __atomic_store_n(
            &gOGS.selectedPeer,
            0,
            __ATOMIC_RELEASE
        );

        self.playerLabel.text =
            @"المحدد: لا يوجد لاعبين";

    } else {

        if (selected >=
            snapshot.count) {

            selected = 0;

            __atomic_store_n(
                &gOGS.selectedPeer,
                0,
                __ATOMIC_RELEASE
            );
        }

        OGSPeerSnapshot peer =
            snapshot.peers[
                selected
            ];

        NSString *name =
            [NSString
                stringWithUTF8String:
                peer.name];

        if (!name.length)
            name = @"لاعب";

        self.playerLabel.text =
            [NSString
                stringWithFormat:
                @"(%u/%u) %@%@",
                selected + 1,
                snapshot.count,
                name,
                peer.isHost
                    ? @" 👑"
                    : @""];
    }

    if (!snapshot.inRoom) {

        self.statusLabel.text =
            @"الغرفة: غير متصل";

    } else if (snapshot.isMaster) {

        self.statusLabel.text =
            [NSString
                stringWithFormat:
                @"الهوست: أنت 👑 | اللاعبون: %u",
                snapshot.count];

    } else {

        self.statusLabel.text =
            [NSString
                stringWithFormat:
                @"متصل | اللاعبون: %u",
                snapshot.count];
    }

    [self.unbanButton
        setTitle:
        [NSString
            stringWithFormat:
            @"فك الحظر (%lu)",
            (unsigned long)
            self.bannedNames.count]
        forState:
        UIControlStateNormal];
}

- (void)toggleMenu
{
    self.menuPanel.hidden =
        !self.menuPanel.hidden;

    if (!self.menuPanel.hidden) {

        OGSInstallHooks();

        OGSUpdateRoomSnapshot();

        [self refreshUI];
    }
}

- (void)handlePan:
    (UIPanGestureRecognizer *)gesture
{
    CGPoint translation =
        [gesture
            translationInView:
            self.containerView];

    gesture.view.center =
        CGPointMake(
            gesture.view.center.x +
            translation.x,
            gesture.view.center.y +
            translation.y
        );

    [gesture
        setTranslation:
        CGPointZero
        inView:
        self.containerView];
}

- (void)nextPlayer:
    (UIButton *)sender
{
    OGSRoomSnapshot snapshot =
        OGSCurrentSnapshot();

    if (!snapshot.count)
        return;

    uint32_t current =
        __atomic_load_n(
            &gOGS.selectedPeer,
            __ATOMIC_ACQUIRE
        );

    current =
        (current + 1) %
        snapshot.count;

    __atomic_store_n(
        &gOGS.selectedPeer,
        current,
        __ATOMIC_RELEASE
    );

    [self refreshUI];
}

- (void)prevPlayer:
    (UIButton *)sender
{
    OGSRoomSnapshot snapshot =
        OGSCurrentSnapshot();

    if (!snapshot.count)
        return;

    uint32_t current =
        __atomic_load_n(
            &gOGS.selectedPeer,
            __ATOMIC_ACQUIRE
        );

    current =
        (current +
         snapshot.count -
         1) %
        snapshot.count;

    __atomic_store_n(
        &gOGS.selectedPeer,
        current,
        __ATOMIC_RELEASE
    );

    [self refreshUI];
}

- (void)claimHostNow:
    (UIButton *)sender
{
    bool ok =
        OGSRequestMasterNormally();

    self.statusLabel.text =
        ok
        ? @"تم إرسال طلب الهوست 👑"
        : @"تعذر طلب الهوست";

    OGSUpdateRoomSnapshot();
}

- (void)kickSelected:
    (UIButton *)sender
{
    OGSRoomSnapshot snapshot =
        OGSCurrentSnapshot();

    if (!snapshot.count)
        return;

    uint32_t selected =
        __atomic_load_n(
            &gOGS.selectedPeer,
            __ATOMIC_ACQUIRE
        );

    if (selected >=
        snapshot.count)
        selected = 0;

    OGSPeerSnapshot peer =
        snapshot.peers[
            selected
        ];

    bool ok =
        OGSDisconnectPeerNormally(
            peer.actorID
        );

    NSString *name =
        [NSString
            stringWithUTF8String:
            peer.name];

    self.statusLabel.text =
        ok
        ? [NSString
            stringWithFormat:
            @"تم إرسال الطرد: %@",
            name ?: @"اللاعب"]
        : @"الطرد يتطلب صلاحية الهوست";
}

- (void)banSelected:
    (UIButton *)sender
{
    OGSRoomSnapshot snapshot =
        OGSCurrentSnapshot();

    if (!snapshot.count)
        return;

    uint32_t selected =
        __atomic_load_n(
            &gOGS.selectedPeer,
            __ATOMIC_ACQUIRE
        );

    if (selected >=
        snapshot.count)
        selected = 0;

    OGSPeerSnapshot peer =
        snapshot.peers[
            selected
        ];

    NSString *name =
        [NSString
            stringWithUTF8String:
            peer.name];

    NSString *normalized =
        OGSNormalizeKey(
            name
        );

    if (normalized.length)
        [self.bannedNames
            addObject:
            normalized];

    if (peer.actorID > 0)
        [self.bannedActorIDs
            addObject:
            @(peer.actorID)];

    [self saveLocalBans];

    bool kicked =
        OGSDisconnectPeerNormally(
            peer.actorID
        );

    [self refreshUI];

    self.statusLabel.text =
        kicked
        ? [NSString
            stringWithFormat:
            @"تم حظر وطرد: %@",
            name ?: @"اللاعب"]
        : [NSString
            stringWithFormat:
            @"تم الحظر محلياً: %@",
            name ?: @"اللاعب"];
}

- (void)toggleRoomLock:
    (UIButton *)sender
{
    OGSUpdateRoomSnapshot();

    OGSRoomSnapshot snapshot =
        OGSCurrentSnapshot();

    self.roomLockActive =
        !self.roomLockActive;

    [self.allowedNamesWhenLocked
        removeAllObjects];

    if (self.roomLockActive) {

        for (uint32_t i = 0;
             i < snapshot.count;
             i++) {

            NSString *name =
                [NSString
                    stringWithUTF8String:
                    snapshot.peers[i].name];

            NSString *normalized =
                OGSNormalizeKey(
                    name
                );

            if (normalized.length)
                [self.allowedNamesWhenLocked
                    addObject:
                    normalized];
        }

        [sender
            setTitle:
            @"قفل الروم: مقفل 🔒"
            forState:
            UIControlStateNormal];

        sender.backgroundColor =
            [UIColor
                colorWithRed:0.15
                green:0.55
                blue:0.25
                alpha:1];

    } else {

        [sender
            setTitle:
            @"قفل الروم: مفتوح"
            forState:
            UIControlStateNormal];

        sender.backgroundColor =
            [UIColor
                colorWithRed:0.22
                green:0.23
                blue:0.28
                alpha:1];
    }

    [self refreshUI];
}

- (void)cycleChatMode:
    (UIButton *)sender
{
    int32_t mode =
        __atomic_load_n(
            &gOGS.chatMode,
            __ATOMIC_ACQUIRE
        );

    /*
     Stable build:
       0 = open
       1 = local mute

     Removed synchronous kick-from-RPC mode.
    */

    mode =
        (mode + 1) % 2;

    __atomic_store_n(
        &gOGS.chatMode,
        mode,
        __ATOMIC_RELEASE
    );

    if (mode == 1) {

        [sender
            setTitle:
            @"الشات: كتم 🔇"
            forState:
            UIControlStateNormal];

        sender.backgroundColor =
            [UIColor
                colorWithRed:0.80
                green:0.35
                blue:0.10
                alpha:1];

    } else {

        [sender
            setTitle:
            @"الشات: مفتوح"
            forState:
            UIControlStateNormal];

        sender.backgroundColor =
            [UIColor
                colorWithRed:0.22
                green:0.23
                blue:0.28
                alpha:1];
    }
}

- (void)clearBanList:
    (UIButton *)sender
{
    [self.bannedNames
        removeAllObjects];

    [self.bannedActorIDs
        removeAllObjects];

    [self saveLocalBans];

    [self refreshUI];

    self.statusLabel.text =
        @"تم مسح قائمة الحظر";
}

- (void)applySpeed:
    (float)value
{
    OGSRequestSpeed(
        value
    );

    float actual =
        __atomic_load_n(
            &gOGS.gameSpeed,
            __ATOMIC_ACQUIRE
        );

    [self.speedSetButton
        setTitle:
        [NSString
            stringWithFormat:
            @"السرعة: %.1fx",
            actual]
        forState:
        UIControlStateNormal];
}

- (void)speedDown:
    (UIButton *)sender
{
    float speed =
        __atomic_load_n(
            &gOGS.gameSpeed,
            __ATOMIC_ACQUIRE
        );

    [self
        applySpeed:
        speed - 0.5f];
}

- (void)speedUp:
    (UIButton *)sender
{
    float speed =
        __atomic_load_n(
            &gOGS.gameSpeed,
            __ATOMIC_ACQUIRE
        );

    [self
        applySpeed:
        speed + 0.5f];
}

- (void)promptCustomSpeed:
    (UIButton *)sender
{
    UIWindow *window =
        [self gameMainWindow];

    UIViewController *controller =
        window.rootViewController;

    if (!controller)
        return;

    while (controller.presentedViewController)
        controller =
            controller.presentedViewController;

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:
            @"تحديد السرعة"
            message:
            @"اكتب السرعة من 0.1 إلى 20"
            preferredStyle:
            UIAlertControllerStyleAlert];

    [alert
        addTextFieldWithConfigurationHandler:
        ^(UITextField *field) {

            float speed =
                __atomic_load_n(
                    &gOGS.gameSpeed,
                    __ATOMIC_ACQUIRE
                );

            field.text =
                [NSString
                    stringWithFormat:
                    @"%.1f",
                    speed];

            field.keyboardType =
                UIKeyboardTypeDecimalPad;
        }];

    __weak typeof(self) weakSelf =
        self;

    [alert
        addAction:
        [UIAlertAction
            actionWithTitle:@"تطبيق"
            style:
            UIAlertActionStyleDefault
            handler:
            ^(UIAlertAction *action) {

                float value =
                    [alert
                        .textFields
                        .firstObject
                        .text
                        floatValue];

                if (value >= 0.1f &&
                    value <= 20.0f)
                    [weakSelf
                        applySpeed:
                        value];
            }]];

    [alert
        addAction:
        [UIAlertAction
            actionWithTitle:@"إلغاء"
            style:
            UIAlertActionStyleCancel
            handler:nil]];

    [controller
        presentViewController:
        alert
        animated:YES
        completion:nil];
}

@end

// ============================================================
// MARK: - Constructor
// ============================================================

__attribute__((constructor))
static void ogs_init(void)
{
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(
                0.75 *
                NSEC_PER_SEC
            )
        ),
        dispatch_get_main_queue(),
        ^{
            OGSInstallHooks();
        }
    );

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(
                3.5 *
                NSEC_PER_SEC
            )
        ),
        dispatch_get_main_queue(),
        ^{
            OGSInstallHooks();

            [[OGSModMenu
                sharedInstance]
                setupMenu];
        }
    );
}
