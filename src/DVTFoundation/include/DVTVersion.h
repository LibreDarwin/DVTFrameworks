//
//  DVTVersion.h
//  DVTFoundation
//
//  A three-component version number, optionally carrying a build number.
//

#import <Foundation/Foundation.h>

#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
  The components a version is assembled from.

  This mirrors the layout the original passes to
  `-initWithVersionComponents:buildNumber:` so the calling convention matches.
 */
typedef struct DVTVersionComponents {
    struct {
        unsigned long long reserved;
        short majorComponent;
        short minorComponent;
        int updateComponent;
    } components;
    unsigned long long buildNumber;
} DVTVersionComponents;

/**
  A version number such as 15.0.1, optionally paired with a build number like
  `22A123`.

  Versions compare and hash on their three numeric components only; the build
  number is presentation data and does not participate. That is why
  `15.0.1` and `15.0.1 (22A123)` are equal.
 */
@interface DVTVersion : NSObject <NSCopying>

/** The build number, or `nil` when the version has none. */
@property (readonly, copy, nullable) NSString *buildNumber;

@property (readonly) NSUInteger majorComponent;
@property (readonly) NSUInteger minorComponent;
@property (readonly) NSUInteger updateComponent;

/**
  `major.minor`, extended with `.update` when the update component is non-zero.

  So 15.0 renders as `15.0` and 15.0.1 as `15.0.1`.
 */
@property (readonly, copy) NSString *stringValue;

/** `stringValue` with trailing zero components removed: 15.0 becomes `15`. */
@property (readonly, copy) NSString *stringValueTrimmingAllZeroes;

/** `stringValue` with the build number appended in parentheses, when present. */
@property (readonly, copy) NSString *stringValueWithBuildNumber;

- (instancetype)initWithVersionComponents:(DVTVersionComponents)components
                              buildNumber:(nullable NSString *)buildNumber NS_DESIGNATED_INITIALIZER;

/** Parses `major[.minor[.update]]`; unparseable input yields 0.0. */
- (instancetype)initWithString:(NSString *)stringValue;

/**
  A single number packing the version as `major * 10000 + minor * 100 + update`.

  With `includeUpdate` false the update component is treated as zero.
 */
- (NSUInteger)availabilityFormIncludingUpdate:(BOOL)includeUpdate;

/** As above; `shortForm` selects the two-component form when true. */
- (NSUInteger)availabilityFormIncludingUpdate:(BOOL)includeUpdate shortForm:(BOOL)shortForm;

- (NSComparisonResult)compare:(DVTVersion *)otherVersion;
- (BOOL)isEqualToOrNewerThanVersion:(DVTVersion *)otherVersion;

+ (instancetype)versionWithMajorComponent:(NSUInteger)majorComponent
                          minorComponent:(NSUInteger)minorComponent
                          updateComponent:(NSUInteger)updateComponent;

+ (instancetype)versionWithStringValue:(NSString *)stringValue;
+ (instancetype)versionWithStringValue:(NSString *)stringValue buildNumber:(nullable NSString *)buildNumber;

/** Decodes a value produced by `-availabilityFormIncludingUpdate:`. */
+ (nullable instancetype)versionWithAvailabilityForm:(NSUInteger)availabilityForm;

/** Formats a version and build the way the user-visible strings do. */
+ (NSString *)userRepresentationOfVersion:(NSString *)stringValue build:(nullable NSString *)build;

/** The running system version, including its build number. */
+ (instancetype)currentSystemVersion;

/** The running Darwin kernel version, which has no build number. */
+ (instancetype)currentDarwinVersion;

/** The newest system version this system still supports. */
+ (instancetype)currentiOSSupportSystemVersion;

@end

NS_ASSUME_NONNULL_END
