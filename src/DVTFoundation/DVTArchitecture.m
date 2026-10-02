//
//  DVTArchitecture.m
//  DVTFoundation
//

#import "DVTArchitecture.h"

#import <string.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>

/** One row of the known-architecture table. */
typedef struct DVTKnownArchitecture {
    __unsafe_unretained NSString *canonicalName;
    __unsafe_unretained NSString *displayName;
    int cpuType;
    int cpuSubType;
    BOOL is64Bit;
    NSUInteger sortPriority;
    int analyticsEnum;
} DVTKnownArchitecture;

/** Subtypes carry capability bits in the high byte; the low byte is identity. */
static inline int DVTSubTypeBase(cpu_subtype_t subType)
{
    return subType & ~CPU_SUBTYPE_MASK;
}

/** Packs a cpu type and base subtype into one dictionary key. */
static inline NSNumber *DVTCPUPairKey(int cpuType, int cpuSubType)
{
    uint64_t packed = ((uint64_t)(uint32_t)cpuType << 32) | (uint32_t)DVTSubTypeBase((cpu_subtype_t)cpuSubType);
    return @(packed);
}

static const DVTKnownArchitecture DVTKnownArchitectures[] = {
    { @"i386",     @"i386",     CPU_TYPE_X86,       CPU_SUBTYPE_X86_ALL,       NO,  10, 1 },
    { @"x86_64",   @"x86_64",   CPU_TYPE_X86_64,    CPU_SUBTYPE_X86_64_ALL,    YES, 20, 2 },
    { @"x86_64h",  @"x86_64h",  CPU_TYPE_X86_64,    CPU_SUBTYPE_X86_64_H,      YES, 21, 3 },
    { @"armv6",    @"Arm v6",   CPU_TYPE_ARM,       CPU_SUBTYPE_ARM_V6,        NO,  30, 4 },
    { @"armv7",    @"Arm v7",   CPU_TYPE_ARM,       CPU_SUBTYPE_ARM_V7,        NO,  31, 5 },
    { @"armv7s",   @"Arm v7s",  CPU_TYPE_ARM,       CPU_SUBTYPE_ARM_V7S,       NO,  32, 6 },
    { @"armv7k",   @"Arm v7k",  CPU_TYPE_ARM,       CPU_SUBTYPE_ARM_V7K,       NO,  33, 7 },
    { @"arm64",    @"Arm 64",   CPU_TYPE_ARM64,     CPU_SUBTYPE_ARM64_ALL,     YES, 40, 8 },
    { @"arm64e",   @"Arm 64e",  CPU_TYPE_ARM64,     CPU_SUBTYPE_ARM64E,        YES, 41, 9 },
    { @"arm64_32", @"Arm 64 32-bit", CPU_TYPE_ARM64_32, CPU_SUBTYPE_ARM64_32_V8, YES, 50, 10 },
};

static const size_t DVTKnownArchitectureCount = sizeof(DVTKnownArchitectures) / sizeof(DVTKnownArchitectures[0]);

@implementation DVTArchitecture
{
    NSString *_canonicalName;
    NSString *_displayName;
    int _CPUType;
    int _CPUSubType;
    BOOL _is64Bit;
    NSUInteger _sortPriority;
    int _analyticsEnum;
}

@synthesize canonicalName = _canonicalName;
@synthesize displayName = _displayName;
@synthesize CPUType = _CPUType;
@synthesize CPUSubType = _CPUSubType;
@synthesize is64Bit = _is64Bit;
@synthesize sortPriority = _sortPriority;
@synthesize analyticsEnum = _analyticsEnum;

/** Architectures handed out so far, so repeated lookups return one instance. */
static NSMutableDictionary<NSString *, DVTArchitecture *> *DVTArchitectureByCanonicalName;
static NSMutableDictionary<NSNumber *, DVTArchitecture *> *DVTArchitectureByCPUPair;
static NSMutableSet<DVTArchitecture *> *DVTArchitectureInstances;

+ (void)initialize
{
    if (self != [DVTArchitecture class]) {
        return;
    }
    DVTArchitectureByCanonicalName = [NSMutableDictionary dictionaryWithCapacity:DVTKnownArchitectureCount];
    DVTArchitectureByCPUPair = [NSMutableDictionary dictionaryWithCapacity:DVTKnownArchitectureCount];
    DVTArchitectureInstances = [NSMutableSet setWithCapacity:DVTKnownArchitectureCount];
}

#pragma mark - Lifecycle

- (instancetype)initWithCanonicalName:(NSString *)canonicalName
                          displayName:(NSString *)displayName
                             CPUType:(int)cpuType
                          CPUSubType:(int)cpuSubType
                             is64Bit:(BOOL)is64Bit
                        sortPriority:(NSUInteger)sortPriority
                        analyticsEnum:(int)analyticsEnum
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _canonicalName = [canonicalName copy];
    _displayName = [displayName copy];
    _CPUType = cpuType;
    _CPUSubType = cpuSubType;
    _is64Bit = is64Bit;
    _sortPriority = sortPriority;
    _analyticsEnum = analyticsEnum;
    return self;
}

- (instancetype)initWithExtension:(NSString *)extension
{
    return [self initWithCanonicalName:extension
                           displayName:extension
                              CPUType:0
                           CPUSubType:0
                              is64Bit:NO
                         sortPriority:0
                        analyticsEnum:0];
}

- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    return self; /* Immutable. */
}

#pragma mark - Accessors

- (NSString *)canonicalName
{
    return _canonicalName;
}

- (NSString *)displayName
{
    return _displayName;
}

- (int)CPUType
{
    return _CPUType;
}

- (int)CPUSubType
{
    return _CPUSubType;
}

- (BOOL)is64Bit
{
    return _is64Bit;
}

- (NSUInteger)sortPriority
{
    return _sortPriority;
}

- (int)analyticsEnum
{
    return _analyticsEnum;
}

#pragma mark - Matching

- (BOOL)matchesCPUType:(cpu_type_t)cpuType andSubType:(cpu_subtype_t)cpuSubType
{
    if (cpuType != (cpu_type_t)_CPUType) {
        return NO;
    }
    /* Capability bits are not part of identity, so ignore them; the base
       subtype still has to match exactly, keeping arm64 and arm64e apart. */
    return DVTSubTypeBase(cpuSubType) == DVTSubTypeBase((cpu_subtype_t)_CPUSubType);
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<DVTArchitecture: %p %@>", (void *)self, _canonicalName];
}

#pragma mark - Lookup

/** Registers the table entry at `index` and returns the cached instance. */
static DVTArchitecture *DVTKnownArchitectureAtIndex(size_t index)
{
    const DVTKnownArchitecture *known = &DVTKnownArchitectures[index];
    DVTArchitecture *architecture = [[DVTArchitecture alloc] initWithCanonicalName:known->canonicalName
                                                                       displayName:known->displayName
                                                                          CPUType:known->cpuType
                                                                       CPUSubType:known->cpuSubType
                                                                          is64Bit:known->is64Bit
                                                                     sortPriority:known->sortPriority
                                                                     analyticsEnum:known->analyticsEnum];
    [DVTArchitectureInstances addObject:architecture];
    DVTArchitectureByCanonicalName[known->canonicalName] = architecture;
    DVTArchitectureByCPUPair[DVTCPUPairKey(known->cpuType, known->cpuSubType)] = architecture;
    return architecture;
}

/** Loads the table into the registries exactly once. */
static void DVTLoadKnownArchitecturesIfNeeded(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (size_t index = 0; index < DVTKnownArchitectureCount; index++) {
            DVTKnownArchitectureAtIndex(index);
        }
    });
}

+ (NSSet<DVTArchitecture *> *)allArchitectures
{
    DVTLoadKnownArchitecturesIfNeeded();
    return [DVTArchitectureInstances copy];
}

+ (DVTArchitecture *)architectureWithCPUType:(cpu_type_t)cpuType subType:(cpu_subtype_t)cpuSubType
{
    DVTLoadKnownArchitecturesIfNeeded();
    return DVTArchitectureByCPUPair[DVTCPUPairKey((int)cpuType, (int)cpuSubType)];
}

+ (DVTArchitecture *)architectureWithCanonicalName:(NSString *)canonicalName
{
    DVTLoadKnownArchitecturesIfNeeded();
    return DVTArchitectureByCanonicalName[canonicalName];
}

+ (DVTArchitecture *)architectureForLocalHost
{
    DVTLoadKnownArchitecturesIfNeeded();

    struct utsname name;
    if (uname(&name) != 0) {
        return nil;
    }

    /*
     Translate the kernel's `uname` machine string ("arm64", "x86_64", ...)
     into the matching architecture, which is more reliable than asking the
     kernel for a cpu type.
     */
    return [self architectureWithCanonicalName:[NSString stringWithUTF8String:name.machine]];
}

#pragma mark - Allowable sets

static NSSet<DVTArchitecture *> *DVTAllowableArchitecturesAllowing64Bit(BOOL allow64Bit,
                                                                      BOOL allowWatchABI,
                                                                      DVTArchitecture *nativeArchitecture)
{
    NSMutableSet<DVTArchitecture *> *result = [NSMutableSet set];
    if (nativeArchitecture == nil) {
        return result;
    }

    for (DVTArchitecture *candidate in [DVTArchitecture allArchitectures]) {
        if (!allow64Bit && candidate.is64Bit) {
            continue;
        }
        if (allowWatchABI == NO && [candidate.canonicalName isEqualToString:@"arm64_32"]) {
            /* arm64_32 exists only for watchOS. */
            continue;
        }
        if (allowWatchABI == YES && ![candidate.canonicalName isEqualToString:@"arm64_32"]) {
            /* WatchOS runs only arm64_32 and its 64-bit counterpart. */
            if (![candidate.canonicalName isEqualToString:@"arm64"]) {
                continue;
            }
        }
        [result addObject:candidate];
    }
    return result;
}

+ (NSSet<DVTArchitecture *> *)allowableArchitecturesOnMacOSForNativeArchitecture:(DVTArchitecture *)nativeArchitecture
{
    return DVTAllowableArchitecturesAllowing64Bit(YES, NO, nativeArchitecture);
}

+ (NSSet<DVTArchitecture *> *)allowableArchitecturesOnEmbeddedOSForNativeArchitecture:(DVTArchitecture *)nativeArchitecture
{
    /* Embedded devices run 64-bit only. */
    return DVTAllowableArchitecturesAllowing64Bit(YES, NO, nativeArchitecture);
}

+ (NSSet<DVTArchitecture *> *)allowableArchitecturesOnWatchOSForNativeArchitecture:(DVTArchitecture *)nativeArchitecture
{
    return DVTAllowableArchitecturesAllowing64Bit(YES, YES, nativeArchitecture);
}

@end
