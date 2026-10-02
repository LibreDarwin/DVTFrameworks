//
//  DVTArchitecture.h
//  DVTFoundation
//
//  A CPU architecture, as a Mach-O slice describes itself.
//

#import <Foundation/Foundation.h>
#import <mach/machine.h>

#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
  Identifies one Mach-O architecture: its canonical and display names, the
  `(cpu_type_t, cpu_subtype_t)` pair that appears in a Mach-O header, and some
  metadata used when ordering and reporting architecture choices.

  Subtypes are matched exactly, so `arm64` and `arm64e` are different
  architectures.
 */
@interface DVTArchitecture : NSObject <NSCopying>

/** The name used in canonical contexts, for example `arm64e`. */
@property (readonly, copy) NSString *canonicalName;

/** The name shown to people, for example `Arm 64e`. */
@property (readonly, copy) NSString *displayName;

@property (readonly) int CPUType;
@property (readonly) int CPUSubType;
@property (readonly) BOOL is64Bit;

/** Lower values sort first when choosing between architectures. */
@property (readonly) NSUInteger sortPriority;

/** A stable numeric identifier used when recording architecture choices. */
@property (readonly) int analyticsEnum;

/**
  Whether the receiver describes `cpuType`/`cpuSubType`.

  Capability bits in the subtype are ignored, but the base subtype is compared,
  so `arm64` does not match `arm64e`.
 */
- (BOOL)matchesCPUType:(cpu_type_t)cpuType andSubType:(cpu_subtype_t)cpuSubType;

- (instancetype)initWithCanonicalName:(NSString *)canonicalName
                          displayName:(NSString *)displayName
                             CPUType:(int)cpuType
                          CPUSubType:(int)cpuSubType
                             is64Bit:(BOOL)is64Bit
                        sortPriority:(NSUInteger)sortPriority
                        analyticsEnum:(int)analyticsEnum NS_DESIGNATED_INITIALIZER;

/**
  The architecture whose canonical name is `extension`, for example `arm64e`.

  Returns `nil` when the name is not a known architecture.
 */
- (nullable instancetype)initWithExtension:(NSString *)extension;

/** Every architecture this class knows about. */
@property (class, nonatomic, readonly) NSSet<DVTArchitecture *> *allArchitectures;

+ (nullable instancetype)architectureWithCPUType:(cpu_type_t)cpuType subType:(cpu_subtype_t)cpuSubType;
+ (nullable instancetype)architectureWithCanonicalName:(NSString *)canonicalName;

/** The architecture of the machine this is running on. */
+ (nullable instancetype)architectureForLocalHost;

/** The architectures a binary for `nativeArchitecture` can be built for. */
+ (NSSet<DVTArchitecture *> *)allowableArchitecturesOnMacOSForNativeArchitecture:(DVTArchitecture *)nativeArchitecture;
+ (NSSet<DVTArchitecture *> *)allowableArchitecturesOnEmbeddedOSForNativeArchitecture:(DVTArchitecture *)nativeArchitecture;
+ (NSSet<DVTArchitecture *> *)allowableArchitecturesOnWatchOSForNativeArchitecture:(DVTArchitecture *)nativeArchitecture;

@end

NS_ASSUME_NONNULL_END
