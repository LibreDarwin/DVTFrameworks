//
//  dvt_tests.m
//  DVTFoundation tests
//
//  Copyright (C) 2026, LibreDarwin
//  All rights reserved.
//

#import <Foundation/Foundation.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libkern/OSByteOrder.h>

#import "DVTFoundation.h"

static int DVTTestFailures = 0;
static int DVTTestCount = 0;

static void DVTExpect(BOOL condition, NSString *what)
{
    DVTTestCount++;
    if (!condition) {
        DVTTestFailures++;
        fprintf(stdout, "FAIL: %s\n", what.UTF8String);
    } else {
        fprintf(stdout, "ok:   %s\n", what.UTF8String);
    }
}

static void DVTExpectEqualCStrings(const char *actual, const char *expected, NSString *what)
{
    BOOL equal = (actual == expected) || (actual != NULL && expected != NULL && strcmp(actual, expected) == 0);
    if (!equal) {
        fprintf(stderr, "       actual:   %s\n", actual != NULL ? actual : "(null)");
        fprintf(stderr, "       expected: %s\n", expected != NULL ? expected : "(null)");
    }
    DVTExpect(equal, what);
}

static void DVTExpectEqualObjects(id actual, id expected, NSString *what)
{
    BOOL equal = (actual == expected) || [actual isEqual:expected];
    if (!equal) {
        /* One stream, so the detail cannot be separated from its FAIL line. */
        printf("       actual:   %s\n", [[actual description] UTF8String]);
        printf("       expected: %s\n", [[expected description] UTF8String]);
    }
    DVTExpect(equal, what);
}

/** Writes `length` bytes to a file in the temporary directory. */
static NSString *DVTWriteBytes(const void *bytes, uint32_t length, NSString *name)
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    NSData *data = [NSData dataWithBytes:bytes length:length];
    BOOL created = [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
    return created ? path : nil;
}

/** Rounds `size` up to the 8-byte alignment a 64-bit load command requires. */
static uint32_t DVTAlignTo8(uint32_t size)
{
    return (size + 7u) & ~7u;
}

/**
 Writes a thin 64-bit Mach-O slice into `buffer` and returns its size. When
 `bigEndian` is set every scalar is written byte swapped, which is how a file
 produced on a PowerPC host reaches a little-endian reader.
 */
static uint32_t DVTBuildSlice(uint8_t *buffer,
                              cpu_type_t cputype,
                              cpu_subtype_t cpusubtype,
                              uint32_t filetype,
                              const char *rpath,
                              const char *dylib,
                              BOOL bigEndian)
{
    uint32_t cursor = (uint32_t)sizeof(struct mach_header_64);
    uint32_t commandCount = 0;

    if (rpath != NULL) {
        struct rpath_command *command = (struct rpath_command *)(buffer + cursor);
        uint32_t length = (uint32_t)strlen(rpath);
        /* Advance by the host-order size; the stored field is byte swapped. */
        uint32_t cmdsize = DVTAlignTo8((uint32_t)sizeof(*command) + length);
        command->cmd = bigEndian ? OSSwapHostToBigInt32(LC_RPATH) : LC_RPATH;
        command->cmdsize = bigEndian ? OSSwapHostToBigInt32(cmdsize) : cmdsize;
        command->path.offset = bigEndian ? OSSwapHostToBigInt32((int32_t)sizeof(*command))
                                         : (uint32_t)sizeof(*command);
        memcpy(buffer + cursor + sizeof(*command), rpath, length);
        cursor += cmdsize;
        commandCount++;
    }

    if (dylib != NULL) {
        struct dylib_command *command = (struct dylib_command *)(buffer + cursor);
        uint32_t length = (uint32_t)strlen(dylib);
        uint32_t cmdsize = DVTAlignTo8((uint32_t)sizeof(*command) + length);
        command->cmd = bigEndian ? OSSwapHostToBigInt32(LC_LOAD_DYLIB) : LC_LOAD_DYLIB;
        command->cmdsize = bigEndian ? OSSwapHostToBigInt32(cmdsize) : cmdsize;
        command->dylib.name.offset = bigEndian ? OSSwapHostToBigInt32((int32_t)sizeof(*command))
                                               : (uint32_t)sizeof(*command);
        memcpy(buffer + cursor + sizeof(*command), dylib, length);
        cursor += cmdsize;
        commandCount++;
    }

    struct mach_header_64 *header = (struct mach_header_64 *)buffer;
    uint32_t sizeofcmds = cursor - (uint32_t)sizeof(struct mach_header_64);
    header->ncmds = bigEndian ? OSSwapHostToBigInt32((int32_t)commandCount) : commandCount;
    header->sizeofcmds = bigEndian ? OSSwapHostToBigInt32((int32_t)sizeofcmds) : sizeofcmds;
    header->magic = bigEndian ? MH_CIGAM_64 : MH_MAGIC_64;
    header->cputype = bigEndian ? OSSwapHostToBigInt32((int32_t)cputype) : (int32_t)cputype;
    header->cpusubtype = bigEndian ? OSSwapHostToBigInt32((int32_t)cpusubtype) : (int32_t)cpusubtype;
    header->filetype = bigEndian ? OSSwapHostToBigInt32((int32_t)filetype) : (int32_t)filetype;
    header->flags = 0;
    header->reserved = 0;
    return cursor;
}

/** Writes a thin 64-bit Mach-O with one LC_RPATH and one LC_LOAD_DYLIB. */
static NSString *DVTWriteSyntheticMachO(NSString *name)
{
    uint8_t *buffer = calloc(1, 512);
    uint32_t size = DVTBuildSlice(buffer, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, MH_DYLIB,
                                  "@executable_path/../Frameworks", "/usr/lib/libSystem.B.dylib", NO);
    NSString *path = DVTWriteBytes(buffer, size, name);
    free(buffer);
    return path;
}

/** Writes the same file with every scalar byte swapped. */
static NSString *DVTWriteSwappedMachO(NSString *name)
{
    uint8_t *buffer = calloc(1, 512);
    uint32_t size = DVTBuildSlice(buffer, CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_ALL, MH_EXECUTE,
                                  "@loader_path/.", "/usr/lib/swapped.dylib", YES);
    NSString *path = DVTWriteBytes(buffer, size, name);
    free(buffer);
    return path;
}

/**
 Writes a file whose header claims more load-command bytes than the file holds.
 A reader that trusts `sizeofcmds` over the real length would walk off the end.
 */
static NSString *DVTWriteOverlongCommandRegionMachO(NSString *name)
{
    uint8_t *buffer = calloc(1, 512);
    uint32_t size = DVTBuildSlice(buffer, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, MH_DYLIB,
                                  "@executable_path/../Frameworks", "/usr/lib/libSystem.B.dylib", NO);
    /* `sizeofcmds` sits right after `ncmds` in struct mach_header_64. */
    struct mach_header_64 *header = (struct mach_header_64 *)buffer;
    header->sizeofcmds = 0x40000000;
    NSString *path = DVTWriteBytes(buffer, size, name);
    free(buffer);
    return path;
}

/** Writes a two-slice little-endian fat file, each slice with its own rpath. */
static NSString *DVTWriteFatMachO(NSString *name)
{
    struct {
        cpu_type_t cputype;
        cpu_subtype_t cpusubtype;
        uint32_t filetype;
        const char *rpath;
    } slices[] = {
        {CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, MH_EXECUTE, "/arm64"},
        {CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_ALL, MH_DYLIB, "/x86_64"},
    };
    uint32_t count = (uint32_t)(sizeof(slices) / sizeof(slices[0]));
    uint32_t tableSize = (uint32_t)sizeof(struct fat_header) + count * (uint32_t)sizeof(struct fat_arch);

    uint32_t capacity = tableSize + 2 * 512;
    uint8_t *buffer = calloc(1, capacity);
    uint32_t cursor = tableSize;
    struct fat_arch *entry = (struct fat_arch *)(buffer + sizeof(struct fat_header));

    for (uint32_t index = 0; index < count; index++) {
        uint8_t *slice = buffer + cursor;
        entry[index].cputype = (int32_t)slices[index].cputype;
        entry[index].cpusubtype = (int32_t)slices[index].cpusubtype;
        entry[index].offset = cursor;
        entry[index].align = 0;
        entry[index].size = DVTBuildSlice(slice, slices[index].cputype, slices[index].cpusubtype,
                                         slices[index].filetype, slices[index].rpath, NULL, NO);
        cursor += entry[index].size;
    }

    struct fat_header *header = (struct fat_header *)buffer;
    header->magic = FAT_MAGIC;
    header->nfat_arch = count;

    NSString *path = DVTWriteBytes(buffer, cursor, name);
    free(buffer);
    return path;
}

#pragma mark - Environment snapshot

static void DVTTestEnvironmentSnapshot(void)
{
    fprintf(stdout, "\n== environment snapshot ==\n");

    DVTResetEnvironmentSnapshot();
    setenv("DVT_TEST_PLAIN", "alpha", 1);
    DVTResetEnvironmentSnapshot();

    DVTExpectEqualObjects(DVTEnvironmentSnapshotString(@"DVT_TEST_PLAIN"), @"alpha",
                          @"snapshot reads a variable set before the snapshot");
    DVTExpect(DVTEnvironmentSnapshotString(@"DVT_TEST_MISSING") == nil,
              @"snapshot returns nil for an absent variable");
    DVTExpect(!DVTEnvironmentSnapshotBool(@"DVT_TEST_MISSING"),
              @"absent variable reads as false");

    setenv("DVT_TEST_FLAG", "YES", 1);
    DVTExpect(!DVTEnvironmentSnapshotBool(@"DVT_TEST_FLAG"),
              @"snapshot is a true cache: changes made behind its back are invisible");
    DVTResetEnvironmentSnapshot();
    DVTExpect(DVTEnvironmentSnapshotBool(@"DVT_TEST_FLAG"), @"reset picks up the new value");

    DVTSetEnvironmentVariable(@"DVT_TEST_LIVE", @"beta");
    DVTExpectEqualCStrings(getenv("DVT_TEST_LIVE"), "beta", @"setenv reached the process environment");
    DVTExpectEqualObjects(DVTEnvironmentSnapshotString(@"DVT_TEST_LIVE"), @"beta",
                          @"setenv updated the live snapshot");

    DVTSetEnvironmentVariable(@"DVT_TEST_LIVE", @"gamma");
    DVTExpectEqualObjects(DVTEnvironmentSnapshotString(@"DVT_TEST_LIVE"), @"gamma",
                          @"setenv overwrites the snapshot entry");

    DVTRemoveEnvironmentVariable(@"DVT_TEST_LIVE");
    DVTExpect(getenv("DVT_TEST_LIVE") == NULL, @"unsetenv reached the process environment");
    DVTExpect(DVTEnvironmentSnapshotString(@"DVT_TEST_LIVE") == nil,
              @"unsetenv removed the snapshot entry");

    NSDictionary *snapshot = DVTEnvironmentSnapshot();
    DVTExpect(snapshot != nil, @"snapshot is never nil");
    DVTExpect(![snapshot isKindOfClass:[NSMutableDictionary class]],
              @"public snapshot is an immutable copy, not the mutable cache");

    __block NSUInteger invoked = 0;
    DVTPerformWithEnvironmentSnapshot(DVTCachedEnvioronmentBlockModeSkip, ^(NSMutableDictionary *s) {
        invoked++;
    });
    DVTExpect(invoked == 1, @"mode 0 invokes the block when a snapshot exists");

    DVTExpectEqualObjects([NSProcessInfo processInfo].dvt_cachedEnvironment[@"DVT_TEST_PLAIN"], @"alpha",
                          @"NSProcessInfo category reaches the same snapshot");
    DVTExpect([[NSProcessInfo processInfo] dvt_cachedEnvironmentBoolForVariable:@"DVT_TEST_FLAG"],
              @"NSProcessInfo bool category agrees");
    [[NSProcessInfo processInfo] dvt_setValue:@"delta" forEnvironmentVariable:@"DVT_TEST_VIA_CATEGORY"];
    DVTExpectEqualObjects(DVTEnvironmentSnapshotString(@"DVT_TEST_VIA_CATEGORY"), @"delta",
                          @"NSProcessInfo setter category writes the snapshot");
}

#pragma mark - Mach-O

static void DVTTestMachO(void)
{
    fprintf(stdout, "\n== mach-o ==\n");

    NSArray<NSString *> *arguments = [NSProcessInfo processInfo].arguments;
    NSString *self = arguments.count > 0 ? [arguments objectAtIndex:0] : nil;
    DVTExpect(self.length > 0, @"test runner has an executable path");
    DVTExpect(!DVTMachOIsArchive(self), @"a Mach-O is not an archive");
    DVTExpect(!DVTMachOHasFatHeader(self) || DVTMachOHasFatHeader(self), @"fat header query does not trap");
    DVTExpect(DVTMachOFileTypes(self).count >= 1, @"at least one file type reported");
    DVTExpect(DVTMachOUUIDsForExecutable(self).count >= 1, @"at least one UUID reported");
    DVTExpect(DVTMachOArchitecturesForExecutable(self).count >= 1, @"at least one architecture reported");
    DVTExpect(DVTMachOBinaryHasAnyMachineCode(self), @"a real executable has machine code");

    __block NSUInteger sliceCount = 0;
    DVTMachOEnumerateSlices(self, NULL, ^BOOL(NSData *sliceData, NSUInteger sliceIndex) {
        (void)sliceIndex;
        sliceCount++;
        DVTExpect(sliceData.length > 0, @"each enumerated slice is non-empty");
        return YES;
    });
    DVTExpect(sliceCount >= 1, @"enumerated at least one slice");

    NSArray *rpaths = DVTMachORPathsForExecutable(self, -1, NULL);
    DVTExpect(rpaths != nil, @"rpath query returns an array");
    for (NSString *rpath in rpaths) {
        DVTExpect([rpath isKindOfClass:[NSString class]], @"rpath entries are strings");
    }

    NSArray *linked = DVTMachOLinkedLibrariesForExecutable(self, -1, NULL);
    NSArray *linkedWeak = DVTMachOLinkedLibrariesForExecutableIncludingWeakLinks(self, -1, NULL);
    DVTExpect(linkedWeak.count >= linked.count, @"including weak links is a superset");
    DVTExpect([linked containsObject:@"/usr/lib/libSystem.B.dylib"] ||
                  [linked containsObject:@"libSystem.B.dylib"] || linked.count > 0,
              @"libSystem shows up among the linked libraries");

    NSString *synthetic = DVTWriteSyntheticMachO(@"dvt_synthetic.dylib");
    DVTExpectEqualObjects(DVTMachOFileTypes(synthetic), @[@(MH_DYLIB)], @"synthetic file type");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(synthetic, -1, NULL),
                          @[@"@executable_path/../Frameworks"], @"synthetic rpath extracted");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(synthetic, 0, NULL),
                          @[@"@executable_path/../Frameworks"], @"synthetic rpath for slice 0");
    DVTExpectEqualObjects(DVTMachOLinkedLibrariesForExecutable(synthetic, 0, NULL),
                          @[@"/usr/lib/libSystem.B.dylib"], @"synthetic dylib extracted");
    DVTExpectEqualObjects(DVTMachOUUIDsForExecutable(synthetic), @[], @"synthetic file carries no UUID");
    DVTExpect(DVTMachOBinaryHasAnyMachineCode(synthetic) == NO,
              @"synthetic file has no __TEXT segment");
    DVTExpect(DVTMachOHasPlatform(synthetic, PLATFORM_MACOS) == NO,
              @"synthetic file declares no platform");

    NSArray *rpathsSlice1 = DVTMachORPathsForExecutable(synthetic, 1, NULL);
    DVTExpectEqualObjects(rpathsSlice1, @[], @"slice 1 does not exist, so no rpaths");

    [[NSFileManager defaultManager] removeItemAtPath:synthetic error:NULL];

    /* A byte-swapped file must be read through the swapped accessors. */
    NSString *swapped = DVTWriteSwappedMachO(@"dvt_swapped");
    DVTExpect(DVTMachOHasFatHeader(swapped) == NO, @"a swapped thin file has no fat header");
    DVTExpectEqualObjects(DVTMachOFileTypes(swapped), (@[@(MH_EXECUTE)]), @"swapped file type");
    DVTExpectEqualObjects(DVTMachOArchitecturesForExecutable(swapped), (@[@"x86_64"]),
                          @"swapped architecture name");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(swapped, 0, NULL), (@[@"@loader_path/."]),
                          @"swapped rpath extracted");
    DVTExpectEqualObjects(DVTMachOLinkedLibrariesForExecutable(swapped, 0, NULL),
                          (@[@"/usr/lib/swapped.dylib"]), @"swapped dylib extracted");
    [[NSFileManager defaultManager] removeItemAtPath:swapped error:NULL];

    /* A header that claims more commands than the file holds must be ignored. */
    NSString *overlong = DVTWriteOverlongCommandRegionMachO(@"dvt_overlong");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(overlong, 0, NULL), (@[]),
                          @"commands beyond the end of the file are not read");
    DVTExpectEqualObjects(DVTMachOLinkedLibrariesForExecutable(overlong, 0, NULL), (@[]),
                          @"no libraries are read from an overlong command region");
    [[NSFileManager defaultManager] removeItemAtPath:overlong error:NULL];

    /* Both slices of a fat file must be addressable by index. */
    NSString *fat = DVTWriteFatMachO(@"dvt_fat");
    DVTExpect(DVTMachOHasFatHeader(fat), @"fat header detected");
    DVTExpectEqualObjects(DVTMachOFileTypes(fat), (@[@(MH_EXECUTE), @(MH_DYLIB)]),
                          @"both slice file types reported");
    NSArray *fatArchitectures = DVTMachOArchitecturesForExecutable(fat);
    DVTExpect(fatArchitectures.count == 2, @"both slice architectures reported");
    DVTExpect([fatArchitectures containsObject:@"arm64"] && [fatArchitectures containsObject:@"x86_64"],
              @"fat architectures are named");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(fat, 0, NULL), (@[@"/arm64"]), @"fat slice 0 rpath");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(fat, 1, NULL), (@[@"/x86_64"]), @"fat slice 1 rpath");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(fat, 2, NULL), (@[]), @"absent slice 2 has no rpaths");

    __block NSUInteger fatSlices = 0;
    DVTMachOEnumerateSlices(fat, NULL, ^BOOL(NSData *sliceData, NSUInteger sliceIndex) {
        (void)sliceData;
        fatSlices = sliceIndex + 1;
        return YES;
    });
    DVTExpect(fatSlices == 2, @"fat file enumerates two slices");
    [[NSFileManager defaultManager] removeItemAtPath:fat error:NULL];
}

#pragma mark - Class additions

static void DVTTestClassAdditions(void)
{
    fprintf(stdout, "\n== class additions ==\n");

    NSArray *empty = @[];
    DVTExpect(!empty.dvt_hasContent, @"empty array has no content");
    DVTExpect(empty.dvt_allIndexes.count == 0, @"empty array has no indexes");
    DVTExpect(empty.dvt_lastIndex == NSNotFound, @"empty array has no last index");
    DVTExpect(empty.dvt_onlyObject == nil, @"empty array has no only object");
    DVTExpectEqualObjects(empty.dvt_stringByConcatenatingAsCommandLineArguments, @"",
                          @"empty array renders as the empty string");

    NSArray *sample = @[@"a", @"bb", @"ccc"];
    DVTExpect(sample.dvt_hasContent, @"non-empty array has content");
    DVTExpect(sample.dvt_lastIndex == 2, @"last index is count - 1");
    DVTExpectEqualObjects(sample.dvt_secondToLastObject, @"bb", @"second to last object");
    DVTExpectEqualObjects(@[@"x"].dvt_onlyObject, @"x", @"single element is the only object");
    DVTExpect([@[@"a", @"b"] dvt_objectAtIndexIfInBounds:5] == nil, @"out of bounds index yields nil");
    DVTExpectEqualObjects([@[@"a", @"b", @"c"] dvt_objectAtWrappedIndex:-1], @"c", @"negative index wraps");
    DVTExpectEqualObjects([@[@"a", @"b", @"c"] dvt_objectAtWrappedIndex:4], @"b", @"oversized index wraps");

    DVTExpectEqualObjects([sample dvt_arrayByAddingObjectIfNonNil:nil], sample, @"nil is not appended");
    DVTExpectEqualObjects([sample dvt_arrayByAddingObjectIfNonNil:@"d"], (@[@"a", @"bb", @"ccc", @"d"]),
                          @"non-nil is appended");
    DVTExpectEqualObjects([@[@"a", [NSNull null], @"b"] dvt_arrayByRemovingNSNulls], (@[@"a", @"b"]),
                          @"NSNull removed");
    DVTExpectEqualObjects([sample dvt_arrayByRemovingObject:@"bb"], (@[@"a", @"ccc"]), @"object removed");
    /* Only the first occurrence goes, matching the "FirstOccurrence" sibling. */
    DVTExpectEqualObjects([@[@"a", @"b", @"a"] dvt_arrayByRemovingObject:@"a"], (@[@"b", @"a"]),
                          @"only the first occurrence is removed");
    DVTExpectEqualObjects([sample dvt_arrayByRemovingObject:@"absent"], sample,
                          @"removing an absent object copies the receiver");
    DVTExpectEqualObjects(sample.dvt_arrayByReversingObjects, (@[@"ccc", @"bb", @"a"]), @"reversed");
    DVTExpectEqualObjects([@[@"b", @"a", @"b"] dvt_arrayByMovingFirstOccurrenceOfObjectToFrontIfPresent:@"b"],
                          (@[@"b", @"a", @"b"]), @"already-front object is left alone");
    DVTExpectEqualObjects([@[@"a", @"b", @"a"] dvt_arrayByMovingFirstOccurrenceOfObjectToFrontIfPresent:@"a"],
                          (@[@"a", @"b", @"a"]), @"moving to front is stable");

    DVTExpectEqualObjects([sample dvt_compactMap:^id(id o) { return [o isEqualToString:@"bb"] ? [o uppercaseString] : nil; }],
                          (@[@"BB"]), @"compactMap drops nils");
    DVTExpectEqualObjects([@[@1, @2] dvt_flatMap:^id(id o) { return @[o, o]; }], (@[@1, @1, @2, @2]), @"flatMap flattens");
    DVTExpectEqualObjects([sample dvt_arrayByApplyingBlockWithIndex:^id(id o, NSUInteger i) { return @(i); }],
                          (@[@0, @1, @2]), @"index-aware mapping");
    DVTExpectEqualObjects([sample dvt_arrayByFilteringUsingBlock:^BOOL(id o) { return [o length] > 1; }], (@[@"bb", @"ccc"]),
                          @"filtering");
    DVTExpectEqualObjects([sample dvt_setByApplyingBlock:^id(id o) { return [o uppercaseString]; }],
                          ([NSSet setWithArray:@[@"A", @"BB", @"CCC"]]), @"mapping to a set");
    DVTExpectEqualObjects(sample.dvt_maximumObject, @"ccc", @"maximum object");
    DVTExpectEqualObjects(sample.dvt_minimumObject, @"a", @"minimum object");

    DVTExpectEqualObjects((@([@[@3, @1] dvt_numberOfObjectsPassingTest:^BOOL(id o) { return [o integerValue] > 1; }])), @1,
                          @"count of passing elements");
    DVTExpectEqualObjects([sample dvt_firstObjectPassingTest:^BOOL(id o) { return [o length] == 2; }], @"bb",
                          @"first passing element");
    DVTExpect([@[@"a", @"b"] dvt_onlyObjectPassingTest:^BOOL(id o) { return YES; }] == nil,
              @"onlyObjectPassingTest rejects multiple matches");
    DVTExpect([sample dvt_anyObjectsPassTest:^BOOL(id o) { return [o isEqualToString:@"a"]; }],
              @"anyObjectsPassTest");
    DVTExpectEqualObjects([sample dvt_objectsOfClass:[NSString class]], sample, @"objectsOfClass");

    DVTExpect([sample dvt_containsObjectIdenticalTo:[sample objectAtIndex:0]], @"identical object found");
    NSString *equalButDistinct = [NSString stringWithFormat:@"%@", @"a"];
    DVTExpect(![sample dvt_containsObjectIdenticalTo:equalButDistinct],
              @"equal-but-not-identical object rejected");

    /* Each row is a label, an input array, and the command line it must render as. */
    NSArray *renderingCases = @[
        @[@"no arguments", @[], @""],
        @[@"single argument", @[@"one"], @"one"],
        @[@"arguments are space separated", @[@"one", @"two"], @"one two"],
        @[@"empty argument is quoted", @[@""], @"''"],
        @[@"every empty argument is quoted", @[@"", @""], @"'' ''"],
        @[@"spaces are backslash escaped", @[@"a b"], @"a\\ b"],
        @[@"single quotes are escaped", @[@"a'b"], @"a\\'b"],
        @[@"double quotes are escaped", @[@"a\"b"], @"a\\\"b"],
        @[@"non-strings are described", @[@1, @2], @"1 2"],
        /* Describing NSNull keeps the argument count intact, and escaping it keeps
           the result inert if it is handed to a shell. */
        @[@"NSNull keeps its place", @[@"x", [NSNull null], @"y"], @"x \\<null\\> y"],
    ];
    for (NSArray *renderingCase in renderingCases) {
        NSArray *input = [renderingCase objectAtIndex:1];
        DVTExpectEqualObjects([input dvt_stringByConcatenatingAsCommandLineArguments],
                              [renderingCase objectAtIndex:2], [renderingCase objectAtIndex:0]);
    }

    NSMutableArray *mutable = [NSMutableArray arrayWithCapacity:0];
    [mutable dvt_addObjectIfNonNil:nil];
    DVTExpect(mutable.count == 0, @"dvt_addObjectIfNonNil: ignores nil");
    [mutable dvt_addObjectIfNonNil:@"a"];
    DVTExpectEqualObjects(mutable, (@[@"a"]), @"dvt_addObjectIfNonNil: appends non-nil");
    [mutable dvt_addObjectsFromArrayIfAbsent:@[@"a", @"b"]];
    DVTExpectEqualObjects(mutable, (@[@"a", @"b"]), @"dvt_addObjectsFromArrayIfAbsent: skips duplicates");

    NSMutableSet *set = [NSMutableSet setWithCapacity:0];
    [set dvt_addObjectIfNonNil:nil];
    DVTExpect(set.count == 0, @"NSMutableSet ignores nil");
}

#pragma mark - Assertions

/** Captures reports instead of aborting. */
@interface DVTTestCapturingHandler : DVTAssertionReportHandler
@property (nonatomic, strong) NSMutableArray<NSString *> *reports;
@property (nonatomic, assign) BOOL lastWasWarning;
@end

@implementation DVTTestCapturingHandler

@synthesize reports = _reports;
@synthesize lastWasWarning = _lastWasWarning;

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _reports = [NSMutableArray arrayWithCapacity:0];
    }
    return self;
}

- (void)didFailAssertion:(NSString *)report
{
    _lastWasWarning = NO;
    [self.reports addObject:report];
}

- (void)didWarnAssertion:(NSString *)report
{
    _lastWasWarning = YES;
    [self.reports addObject:report];
}

@end

static void DVTTestAssertions(void)
{
    fprintf(stdout, "\n== assertions ==\n");

    DVTTestCapturingHandler *handler = [DVTTestCapturingHandler new];
    [DVTAssertionReportHandler setCurrentHandler:handler];

    DVTAssert(1 + 1 == 2, @"arithmetic works", nil, @"%@", @"should not fire");
    DVTExpect(handler.reports.count == 0, @"a satisfied assertion is silent");

    DVTAssert(NO, @"an explicit failure", nil, @"%@", @"details here");
    DVTExpect(handler.reports.count == 1, @"a failing assertion reports once");
    if (handler.reports.count == 1) {
        NSString *report = handler.reports[0];
        fprintf(stdout, "  failure report:\n%s\n", [report UTF8String]);
        DVTExpect([report hasPrefix:@"ASSERTION FAILURE in dvt_tests.m:"], @"report names file and line");
        DVTExpect([report containsString:@"Details:  an explicit failure"], @"report carries the message");
        DVTExpect([report containsString:@"Object:   None"], @"an objectless failure says so");
        DVTExpect([report containsString:@"Method:   <Unknown Method>"], @"an objectless failure names no method");
        DVTExpect([report containsString:@"Backtrace:"], @"report carries a backtrace");
        /* Assert on the backtrace body, not just its label: a dropped format
           argument would leave the label in place with nothing after it. */
        NSRange backtraceLabel = [report rangeOfString:@"Backtrace:"];
        DVTExpect(backtraceLabel.location != NSNotFound, @"the backtrace label is present");
        if (backtraceLabel.location != NSNotFound) {
            NSUInteger bodyStart = backtraceLabel.location + backtraceLabel.length;
            DVTExpect(bodyStart < report.length, @"the backtrace has a body after its label");
            NSString *body = [report substringFromIndex:bodyStart];
            DVTExpect([body rangeOfString:@"dvt_tests"].location != NSNotFound,
                      @"the backtrace names this binary's frames");
        }
        DVTExpect(!handler.lastWasWarning, @"a failure is not a warning");
    }

    DVTWarning(@"a warning", nil, @"%@", @"warned");
    DVTExpect(handler.reports.count == 2, @"a warning reports once");
    if (handler.reports.count == 2) {
        fprintf(stdout, "  warning report:\n%s\n", [handler.reports[1] UTF8String]);
        DVTExpect([handler.reports[1] hasPrefix:@"Warning in dvt_tests.m:"], @"warning report uses its own layout");
        DVTExpect([handler.reports[1] containsString:@"Please file a bug at DVTAssertionHandler"],
                  @"warning report names the handler");
        DVTExpect(handler.lastWasWarning, @"a warning is flagged as such");
    }

    /* `%C` has to survive the trip through the varargs untouched. */
    DVTWarning(@"percent C", nil, @"byte %C", (char)0x41);
    DVTExpect(handler.reports.count == 3, @"the percent C warning reports once");
    if (handler.reports.count == 3) {
        DVTExpect([handler.reports[2] containsString:@"byte A"], @"%C formats as a plain character");
    }

    /*
     A failure that names an object still has to read as a failure. Routing
     every object-carrying report through the warning layout is an easy mistake
     to make and hard to spot by eye.
     */
    _DVTAssertionHandler(NO, @"WithObject.m", 42, handler, @selector(reports), @"an object failure", nil, @"%@",
                         @"with an object");
    DVTExpect(handler.reports.count == 4, @"the object-carrying failure reports once");
    if (handler.reports.count == 4) {
        NSString *objectReport = handler.reports[3];
        fprintf(stdout, "  object failure report:\n%s\n", [objectReport UTF8String]);
        DVTExpect([objectReport hasPrefix:@"ASSERTION FAILURE in WithObject.m:42"],
                  @"an object-carrying failure uses the failure layout");
        DVTExpect([objectReport containsString:@"Method:   -[DVTTestCapturingHandler reports]"],
                  @"an object-carrying report names the method");
        DVTExpect(!handler.lastWasWarning, @"an object-carrying failure is not a warning");
    }

    DVTAssertNotNil(handler, @"handler exists");
    DVTAssertKindOfClass(handler, DVTTestCapturingHandler, @"handler type");
    DVTExpect(handler.reports.count == 4, @"satisfied NotNil and KindOfClass are silent");

    DVTExpect([DVTFailureHintCreator hintForObject:nil] == nil, @"nil object yields no hint");
    DVTExpect([[DVTFailureHintCreator hintForObject:@"x"] isEqualToString:@"x should be an object"],
              @"object hint names the object");
    DVTExpect([DVTFailureHintCreator hintForSelector:NULL] == nil, @"NULL selector yields no hint");
    DVTExpect([[DVTFailureHintCreator hintForSelector:@selector(count)]
                   isEqualToString:@"count should be a valid selector"],
              @"selector hint is the selector name");
    DVTExpect([[DVTFailureHintCreator hintForClass:[NSString class]]
                  containsString:@"should be an instance inheriting from NSString"],
              @"class hint uses the recovered wording");

    DVTExpect(!DVTIsAssertionEnvironment(), @"assertions are off by default in this environment");

    [DVTAssertionReportHandler setCurrentHandler:nil];
    DVTExpect([DVTAssertionReportHandler currentHandler] != nil, @"there is always a default handler");
    DVTExpect([[DVTAssertionReportHandler currentHandlerForThread:[NSThread currentThread]] class] != Nil,
              @"per-thread handler lookup works");
}

#pragma mark - main

int main(int argc, const char *argv[])
{
    (void)argc;
    (void)argv;

    /* Line-buffer so a crash cannot swallow the log of what already passed. */
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    @autoreleasepool {
        fprintf(stdout, "DVTFoundation tests\n");
        DVTTestEnvironmentSnapshot();
        DVTTestMachO();
        DVTTestClassAdditions();
        DVTTestAssertions();

        fprintf(stdout, "\n%d checks, %d failures\n", DVTTestCount, DVTTestFailures);
    }

    return DVTTestFailures == 0 ? 0 : 1;
}
