//
//  DVTVersion.m
//  DVTFoundation
//

#import "DVTVersion.h"

#import <string.h>
#import <sys/utsname.h>

@implementation DVTVersion
{
    NSUInteger _majorComponent;
    NSUInteger _minorComponent;
    NSUInteger _updateComponent;
    NSString *_buildNumber;
}

/*
 `buildNumber` is the one property backed by an explicitly named ivar, which
 matches the original's property list; the three scalar components are
 auto-synthesized.
 */
@synthesize buildNumber = _buildNumber;

#pragma mark - Lifecycle

- (instancetype)initWithVersionComponents:(DVTVersionComponents)components
                              buildNumber:(NSString *)buildNumber
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _majorComponent = (NSUInteger)components.components.majorComponent;
    _minorComponent = (NSUInteger)components.components.minorComponent;
    _updateComponent = (NSUInteger)components.components.updateComponent;
    _buildNumber = [buildNumber copy];
    return self;
}

- (instancetype)initWithString:(NSString *)stringValue
{
    /*
     Parsing produces the same state the designated initializer would, so build
     the components first and hand them to it.
     */
    NSUInteger components[3] = {0, 0, 0};
    NSUInteger found = 0;
    NSScanner *scanner = [NSScanner scannerWithString:stringValue ?: @""];
    unsigned long long scanned = 0;
    while (found < 3) {
        if (![scanner scanUnsignedLongLong:&scanned]) {
            break;
        }
        /* Store before the end-of-input check, or the last component is lost. */
        components[found] = (NSUInteger)scanned;
        found++;
        if ([scanner isAtEnd]) {
            break;
        }
        if (![scanner scanString:@"." intoString:NULL]) {
            break;
        }
    }
    if (found == 0) {
        components[0] = 0;
        components[1] = 0;
        components[2] = 0;
    }

    DVTVersionComponents packed;
    memset(&packed, 0, sizeof(packed));
    packed.components.majorComponent = (short)components[0];
    packed.components.minorComponent = (short)components[1];
    packed.components.updateComponent = (int)components[2];
    return [self initWithVersionComponents:packed buildNumber:nil];
}

#pragma mark - Components

- (NSString *)buildNumber
{
    return _buildNumber;
}

- (NSUInteger)majorComponent
{
    return _majorComponent;
}

- (NSUInteger)minorComponent
{
    return _minorComponent;
}

- (NSUInteger)updateComponent
{
    return _updateComponent;
}

#pragma mark - Rendering

- (NSString *)stringValue
{
    if (_updateComponent != 0) {
        return [NSString stringWithFormat:@"%lu.%lu.%lu", (unsigned long)_majorComponent,
                (unsigned long)_minorComponent, (unsigned long)_updateComponent];
    }
    return [NSString stringWithFormat:@"%lu.%lu", (unsigned long)_majorComponent, (unsigned long)_minorComponent];
}

- (NSString *)stringValueTrimmingAllZeroes
{
    NSUInteger components[3] = {_majorComponent, _minorComponent, _updateComponent};
    NSUInteger count = 3;
    while (count > 1 && components[count - 1] == 0) {
        count--;
    }

    NSMutableString *result = [NSMutableString stringWithFormat:@"%lu", (unsigned long)components[0]];
    for (NSUInteger index = 1; index < count; index++) {
        [result appendFormat:@".%lu", (unsigned long)components[index]];
    }
    return result;
}

- (NSString *)stringValueWithBuildNumber
{
    if (_buildNumber == nil) {
        return self.stringValue;
    }
    return [NSString stringWithFormat:@"%@ (%@)", self.stringValue, _buildNumber];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<DVTVersion: %p %@>", (void *)self, self.stringValueWithBuildNumber];
}

#pragma mark - Availability form

- (NSUInteger)availabilityFormIncludingUpdate:(BOOL)includeUpdate
{
    NSUInteger update = includeUpdate ? _updateComponent : 0;
    return _majorComponent * 10000 + _minorComponent * 100 + update;
}

- (NSUInteger)availabilityFormIncludingUpdate:(BOOL)includeUpdate shortForm:(BOOL)shortForm
{
    (void)shortForm;
    return [self availabilityFormIncludingUpdate:includeUpdate];
}

#pragma mark - Comparison

- (NSComparisonResult)compare:(DVTVersion *)otherVersion
{
    if (otherVersion == nil) {
        return NSOrderedDescending;
    }
    if (_majorComponent != otherVersion->_majorComponent) {
        return _majorComponent < otherVersion->_majorComponent ? NSOrderedAscending : NSOrderedDescending;
    }
    if (_minorComponent != otherVersion->_minorComponent) {
        return _minorComponent < otherVersion->_minorComponent ? NSOrderedAscending : NSOrderedDescending;
    }
    if (_updateComponent != otherVersion->_updateComponent) {
        return _updateComponent < otherVersion->_updateComponent ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (BOOL)isEqualToOrNewerThanVersion:(DVTVersion *)otherVersion
{
    return [self compare:otherVersion] != NSOrderedAscending;
}

- (BOOL)isEqual:(id)other
{
    if (self == other) {
        return YES;
    }
    if (![other isKindOfClass:[DVTVersion class]]) {
        return NO;
    }
    /* The build number is presentation only, so it is not part of equality. */
    return [self compare:other] == NSOrderedSame;
}

- (NSUInteger)hash
{
    return _majorComponent * 10000 + _minorComponent * 100 + _updateComponent;
}

- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    return self; /* Immutable. */
}

#pragma mark - Construction

+ (void)initialize
{
    if (self != [DVTVersion class]) {
        return;
    }
    /* Versions are immutable, so shared instances can be handed out directly. */
}

+ (instancetype)versionWithMajorComponent:(NSUInteger)majorComponent
                          minorComponent:(NSUInteger)minorComponent
                          updateComponent:(NSUInteger)updateComponent
{
    DVTVersionComponents components;
    memset(&components, 0, sizeof(components));
    components.components.majorComponent = (short)majorComponent;
    components.components.minorComponent = (short)minorComponent;
    components.components.updateComponent = (int)updateComponent;
    return [[self alloc] initWithVersionComponents:components buildNumber:nil];
}

+ (instancetype)versionWithStringValue:(NSString *)stringValue
{
    return [[self alloc] initWithString:stringValue];
}

+ (instancetype)versionWithStringValue:(NSString *)stringValue buildNumber:(NSString *)buildNumber
{
    DVTVersion *version = [[self alloc] initWithString:stringValue];
    version->_buildNumber = [buildNumber copy];
    return version;
}

+ (instancetype)versionWithAvailabilityForm:(NSUInteger)availabilityForm
{
    DVTVersionComponents components;
    memset(&components, 0, sizeof(components));
    components.components.majorComponent = (short)((availabilityForm / 10000) % 0x10000);
    components.components.minorComponent = (short)((availabilityForm / 100) % 100);
    components.components.updateComponent = (int)(availabilityForm % 100);
    return [[self alloc] initWithVersionComponents:components buildNumber:nil];
}

+ (NSString *)userRepresentationOfVersion:(NSString *)stringValue build:(NSString *)build
{
    if (build == nil) {
        return [stringValue copy];
    }
    return [NSString stringWithFormat:@"%@ (%@)", stringValue, build];
}

#pragma mark - Current versions

+ (instancetype)currentSystemVersion
{
    static DVTVersion *current;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
        NSString *build = [[NSProcessInfo processInfo] operatingSystemVersionString];
        /*
         `operatingSystemVersionString` is like "Version 26.5.2 (Build 25F84)";
         the build number is the part in parentheses.
         */
        NSRange open = [build rangeOfString:@"("];
        NSRange close = [build rangeOfString:@")" options:NSBackwardsSearch];
        if (open.location != NSNotFound && close.location != NSNotFound && close.location > open.location) {
            NSString *inner = [build substringWithRange:NSMakeRange(open.location + 1,
                                                                    close.location - open.location - 1)];
            inner = [inner stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([inner hasPrefix:@"Build "]) {
                inner = [inner substringFromIndex:@"Build ".length];
            }
            build = inner;
        } else {
            build = nil;
        }

        DVTVersion *result = [[self alloc] initWithString:[NSString stringWithFormat:@"%ld.%ld.%ld",
                                                            (long)version.majorVersion,
                                                            (long)version.minorVersion,
                                                            (long)version.patchVersion]];
        result->_buildNumber = [build copy];
        current = result;
    });
    return current;
}

+ (instancetype)currentDarwinVersion
{
    static DVTVersion *current;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        /* The kernel reports its version as the osrelease of the kern.osproductversion. */
        int major = 0;
        int minor = 0;
        int patch = 0;
        struct utsname name;
        if (uname(&name) == 0) {
            sscanf(name.release, "%d.%d.%d", &major, &minor, &patch);
        }
        DVTVersionComponents components;
        memset(&components, 0, sizeof(components));
        components.components.majorComponent = (short)major;
        components.components.minorComponent = (short)minor;
        components.components.updateComponent = patch;
        current = [[self alloc] initWithVersionComponents:components buildNumber:nil];
    });
    return current;
}

+ (instancetype)currentiOSSupportSystemVersion
{
    /*
     On macOS the "iOS support version" is the newest system version the machine
     is entitled to run. It tracks Darwin's major release one ahead, keeping the
     minor version: a Darwin 25.5 host reports 26.5.
     */
    DVTVersion *darwin = [self currentDarwinVersion];
    return [self versionWithMajorComponent:darwin.majorComponent + 1
                            minorComponent:darwin.minorComponent
                            updateComponent:0];
}

@end
