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
#include <pthread.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <libkern/OSByteOrder.h>

#import "DVTFoundation.h"

/** An object that claims to be equal to nothing, not even to itself. */
@interface DVTPicky : NSObject
@end

@implementation DVTPicky
- (BOOL)isEqual:(id)other { (void)other; return NO; }
- (NSUInteger)hash { return 0; }
@end

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

/* How many of four submitted tasks are ever in flight together. A serial queue
   peaks at one, a concurrent queue at more. */
static int DVTPeakConcurrency(dispatch_queue_t queue)
{
    if (queue == NULL) {
        return -1;
    }
    __block int active = 0;
    __block int peak = 0;
    for (int i = 0; i < 4; i++) {
        dispatch_async(queue, ^{
            int now = __sync_fetch_and_add(&active, 1) + 1;
            if (now > peak) {
                peak = now;
            }
            usleep(40000);
            __sync_fetch_and_sub(&active, 1);
        });
    }
    usleep(400000);
    return peak;
}

static void DVTTestDispatch(void)
{
    /* A non-zero first argument means serial. The label is the fourth argument,
       not the first, and it survives the trip. */
    dispatch_queue_t serial = DVTDispatchCreateQueue(YES, QOS_CLASS_DEFAULT, 0, "dvt.test.serial");
    DVTExpect(serial != NULL, @"create queue returns a queue");
    DVTExpectEqualCStrings(dispatch_queue_get_label(serial), "dvt.test.serial",
                           @"serial queue keeps its label");
    DVTExpect(DVTPeakConcurrency(serial) == 1, @"serial queue runs one task at a time");

    dispatch_queue_t concurrent = DVTDispatchCreateQueue(NO, QOS_CLASS_DEFAULT, 0, "dvt.test.concurrent");
    DVTExpect(concurrent != NULL, @"create queue returns a concurrent queue");
    DVTExpectEqualCStrings(dispatch_queue_get_label(concurrent), "dvt.test.concurrent",
                           @"concurrent queue keeps its label");
    DVTExpect(DVTPeakConcurrency(concurrent) > 1, @"concurrent queue overlaps tasks");

    /* The unused third argument must not disturb the result. */
    dispatch_queue_t ignored = DVTDispatchCreateQueue(YES, QOS_CLASS_DEFAULT, 0xdead, "dvt.test.ignored");
    DVTExpectEqualCStrings(dispatch_queue_get_label(ignored), "dvt.test.ignored",
                           @"ignored argument does not affect the label");

    /* Sync completes before it returns. */
    __block int syncRan = 0;
    DVTDispatchSync(serial, ^{
        syncRan = 1;
    });
    DVTExpect(syncRan, @"sync runs the block before returning");

    /* Async is deferred behind work already on the queue, and runs off the
       calling thread. Occupying the queue first keeps this from racing. */
    __block int asyncRan = 0;
    __block int onCallerThread = 1;
    pthread_t caller = pthread_self();
    dispatch_async(serial, ^{
        usleep(250000);
    });
    usleep(30000);
    DVTDispatchAsync(serial, ^{
        asyncRan = 1;
        onCallerThread = pthread_equal(pthread_self(), caller);
    });
    usleep(40000);
    DVTExpect(!asyncRan, @"async defers behind a queue that is already busy");
    usleep(300000);
    DVTExpect(asyncRan, @"async runs once the queue drains");
    DVTExpect(!onCallerThread, @"async runs on the queue, not the caller");

    /* Barrier work also lands on the queue. */
    __block int barrierRan = 0;
    DVTDispatchBarrierAsync(serial, ^{
        barrierRan = 1;
    });
    usleep(150000);
    DVTExpect(barrierRan, @"barrier async runs the block");

    /* Delayed work does not run inline. */
    __block int afterRan = 0;
    DVTDispatchAfter(dispatch_time(DISPATCH_TIME_NOW, 20 * 1000 * 1000), serial, ^{
        afterRan = 1;
    });
    DVTExpect(!afterRan, @"after does not run inline");
    usleep(200000);
    DVTExpect(afterRan, @"after runs once its deadline passes");

    /* Group notify waits for the group, and fires exactly once. */
    __block int notifyRuns = 0;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    DVTDispatchGroupNotify(group, serial, ^{
        notifyRuns++;
    });
    usleep(50000);
    DVTExpect(notifyRuns == 0, @"group notify waits for the group to drain");
    dispatch_group_leave(group);
    usleep(200000);
    DVTExpect(notifyRuns == 1, @"group notify fires once after the group drains");

    /* Dispatch source handlers. */
    __block int events = 0;
    __block int cancelled = 0;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, serial);
    DVTDispatchSourceSetEventHandler(source, ^{
        events++;
    });
    DVTDispatchSourceSetCancelHandler(source, ^{
        cancelled = 1;
    }, dispatch_group_create());
    dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, 10 * 1000 * 1000),
                              10 * 1000 * 1000, 0);
    dispatch_resume(source);
    usleep(120000);
    DVTExpect(events > 0, @"source event handler runs on each tick");
    dispatch_source_cancel(source);
    usleep(80000);
    DVTExpect(cancelled, @"source cancel handler runs on cancellation");
}

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
    /* Every match goes, not just the first: see the method's disassembly note. */
    DVTExpectEqualObjects([@[@"a", @"b", @"a"] dvt_arrayByRemovingObject:@"a"], (@[@"b"]),
                          @"every occurrence is removed, not just the first");
    DVTExpectEqualObjects([@[@"a", @"a", @"a"] dvt_arrayByRemovingObject:@"a"], (@[]),
                          @"all three occurrences are removed");
    DVTExpectEqualObjects([sample dvt_arrayByRemovingObject:sample.lastObject], (@[@"a", @"bb"]),
                          @"a pointer-identical element is removed");
    /* A pointer-identical object is dropped even when isEqual: would say no. */
    DVTPicky *picky = [DVTPicky new];
    DVTExpectEqualObjects([@[picky, @"x"] dvt_arrayByRemovingObject:picky], (@[@"x"]),
                          @"identity is tested before isEqual:");
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
    DVTExpect(![sample dvt_allObjectsPassTest:^BOOL(id o) { return [o isEqualToString:@"a"]; }],
              @"allObjectsPassTest rejects a non-matching element");
    DVTExpect([sample dvt_allObjectsPassTest:^BOOL(id o) { return YES; }],
              @"allObjectsPassTest accepts when every element passes");
    DVTExpect([@[] dvt_allObjectsPassTest:^BOOL(id o) { return NO; }],
              @"allObjectsPassTest is vacuously true when empty");
    BOOL (^nilTest)(id) = nil;
    DVTExpect([sample dvt_allObjectsPassTest:nilTest],
              @"allObjectsPassTest treats a nil test as vacuously true, even when non-empty");
    /* The same selector on NSSet and NSHashTable. Apple faults on a non-empty
       collection with a nil test, so the guard is a documented deviation. */
    NSSet *members = [NSSet setWithObjects:@"a", @"b", nil];
    DVTExpect(![members dvt_allObjectsPassTest:^BOOL(id o) { return [o isEqualToString:@"a"]; }],
              @"set allObjectsPassTest rejects a non-matching member");
    DVTExpect([members dvt_allObjectsPassTest:^BOOL(id o) { return YES; }],
              @"set allObjectsPassTest accepts when every member passes");
    DVTExpect([[NSSet set] dvt_allObjectsPassTest:^BOOL(id o) { return NO; }],
              @"set allObjectsPassTest is vacuously true when empty");
    DVTExpect([members dvt_allObjectsPassTest:nilTest], @"set allObjectsPassTest guards a nil test");
    NSHashTable *table = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    [table addObject:@"a"];
    [table addObject:@"b"];
    DVTExpect(![table dvt_allObjectsPassTest:^BOOL(id o) { return NO; }],
              @"hash table allObjectsPassTest rejects a non-matching object");
    DVTExpect([table dvt_allObjectsPassTest:^BOOL(id o) { return [o isKindOfClass:[NSString class]]; }],
              @"hash table allObjectsPassTest accepts when every object passes");
    DVTExpect([[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality]
                  dvt_allObjectsPassTest:^BOOL(id o) { return NO; }],
              @"hash table allObjectsPassTest is vacuously true when empty");
    DVTExpect([table dvt_allObjectsPassTest:nilTest], @"hash table allObjectsPassTest guards a nil test");
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
        /* An empty argument becomes two double quotes, not two single quotes. */
        @[@"empty argument is quoted", @[@""], @"\"\""],
        @[@"every empty argument is quoted", @[@"", @""], @"\"\" \"\""],
        @[@"spaces are backslash escaped", @[@"a b"], @"a\\ b"],
        @[@"single quotes are escaped", @[@"a'b"], @"a\\'b"],
        @[@"double quotes are escaped", @[@"a\"b"], @"a\\\"b"],
        @[@"tabs are backslash escaped", @[@"a\tb"], @"a\\\tb"],
        /* The escaping set is only quote, space, and tab, so a backslash is
           already literal and must not be doubled, and the rest of the shell
           metacharacters are not escaped at all. */
        @[@"backslashes are left alone", @[@"a\\b"], @"a\\b"],
        @[@"other shell metacharacters are left alone", @[@"a$b*c;d|e&f>g<h~i#j!k"], @"a$b*c;d|e&f>g<h~i#j!k"],
        @[@"newlines are left alone", @[@"a\nb"], @"a\nb"],
        @[@"non-strings are described", @[@1, @2], @"1 2"],
        /* Describing NSNull keeps the argument count intact. None of the
           characters in <null> are in the escaping set, so it is emitted as is. */
        @[@"NSNull keeps its place", @[@"x", [NSNull null], @"y"], @"x <null> y"],
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

    /* The selector is an integer, and nothing is selected by default, so the
       out-of-range case is the quiet one. */
    DVTExpect(!DVTIsAssertionEnvironment(-1), @"no environment selected is quiet");
    DVTExpect(!DVTIsAssertionEnvironment(9), @"an unknown environment is quiet");
    DVTExpect(DVTIsAssertionEnvironment(0), @"environment 0 needs no gate");
    for (NSInteger environment = 1; environment <= 5; environment++) {
        DVTExpect(!DVTIsAssertionEnvironment(environment),
                 @"gated environments are off unless their own gate is set");
    }

    /* Each gate answers only for its own case, and the case numbers run in a
       different order from the keys in the binary: 2 is QuickLook, 3 CPU, 4
       Memory, 5 Validation. Case 1 is gated but named by nothing, so it can
       never be switched on. */
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    struct {
        __unsafe_unretained NSString *key;
        NSInteger environment;
    } const gates[] = {
        { @"DVTEnableAssertionsForQuickLookTestSuite", 2 },
        { @"DVTEnableAssertionsForCPUPerformanceTestSuite", 3 },
        { @"DVTEnableAssertionsForMemoryPerformanceTestSuite", 4 },
        { @"DVTEnableAssertionsForValidationTestSuite", 5 },
    };
    for (size_t index = 0; index < sizeof(gates) / sizeof(gates[0]); index++) {
        [defaults setBool:YES forKey:gates[index].key];
        const NSInteger own = gates[index].environment;
        DVTExpect(DVTIsAssertionEnvironment(own), @"the open gate answers for its own case");
        for (NSInteger environment = 1; environment <= 5; environment++) {
            if (environment != own) {
                DVTExpect(!DVTIsAssertionEnvironment(environment),
                         @"Is never carries a gate backwards to another case");
            }
        }
        [defaults removeObjectForKey:gates[index].key];
    }
    DVTExpect(!DVTIsAssertionEnvironment(1),
             @"case 1 is gated but no key names it, so it stays closed");

    /* ShouldAssert is the permissive variant: a closed gate falls through to
       the later ones, so opening the last gate answers for every earlier case
       while leaving later ones quiet. That direction is easy to get backwards. */
    [defaults setBool:YES forKey:@"DVTEnableAssertionsForValidationTestSuite"];
    for (NSInteger environment = 1; environment <= 5; environment++) {
        DVTExpect(DVTShouldAssertForEnvironment(environment),
                 @"the last gate carries every earlier case");
    }
    DVTExpect(!DVTShouldAssertForEnvironment(6),
             @"an unknown environment ignores a suite gate and asks the master switch");
    [defaults removeObjectForKey:@"DVTEnableAssertionsForValidationTestSuite"];

    [defaults setBool:YES forKey:@"DVTEnableAssertionsForQuickLookTestSuite"];
    DVTExpect(DVTShouldAssertForEnvironment(1), @"the first gate answers for itself");
    DVTExpect(DVTShouldAssertForEnvironment(2), @"and for its own case");
    DVTExpect(!DVTShouldAssertForEnvironment(3),
             @"an earlier gate does not reach a later case");
    [defaults removeObjectForKey:@"DVTEnableAssertionsForQuickLookTestSuite"];
    DVTExpect(!DVTShouldAssertForEnvironment(1), @"clearing the gate closes the case again");

    /* Unrecognised selectors defer to the master switch, which is unset here. */
    DVTExpect(!DVTShouldAssertForEnvironment(-1), @"unselected asks the master switch");
    DVTExpect(!DVTShouldAssertForEnvironment(9), @"unknown asks the master switch");
    DVTExpect(DVTShouldAssertForEnvironment(0), @"environment 0 asserts either way");
    for (NSInteger environment = 1; environment <= 5; environment++) {
        DVTExpect(!DVTShouldAssertForEnvironment(environment),
                 @"a closed gate falls through and stays closed");
    }

    /* DVTEnableAllAssertions is a master switch, not a sixth case: it answers
       ShouldAssert for every selector but leaves Is alone for every gated one. */
    [defaults setBool:YES forKey:@"DVTEnableAllAssertions"];
    DVTExpect(DVTIsAssertionEnvironment(0), @"Is still needs no gate");
    for (NSInteger environment = 1; environment <= 5; environment++) {
        DVTExpect(!DVTIsAssertionEnvironment(environment),
                 @"the master switch is not one of the gated cases");
        DVTExpect(DVTShouldAssertForEnvironment(environment),
                 @"the master switch answers every gated case");
    }
    DVTExpect(DVTShouldAssertForEnvironment(-1), @"including unselected");
    DVTExpect(DVTShouldAssertForEnvironment(9), @"including unknown");
    [defaults removeObjectForKey:@"DVTEnableAllAssertions"];

    [DVTAssertionReportHandler setCurrentHandler:nil];
    DVTExpect([DVTAssertionReportHandler currentHandler] != nil, @"there is always a default handler");
    DVTExpect([[DVTAssertionReportHandler currentHandlerForThread:[NSThread currentThread]] class] != Nil,
              @"per-thread handler lookup works");
}

#pragma mark - main

static void DVTTestComparison(void)
{
    fprintf(stdout, "\n== comparison ==\n");

    DVTExpect(DVTCompareBools(NO, NO) == 0, @"NO is NO");
    DVTExpect(DVTCompareBools(NO, YES) == -1, @"NO precedes YES");
    DVTExpect(DVTCompareBools(YES, NO) == 1, @"YES follows NO");
    DVTExpect(DVTCompareBools(YES, YES) == 0, @"YES is YES");

    DVTExpect(DVTCompareIntegers(1, 2) == -1, @"1 precedes 2");
    DVTExpect(DVTCompareIntegers(2, 1) == 1, @"2 follows 1");
    DVTExpect(DVTCompareIntegers(7, 7) == 0, @"7 equals 7");
    /* The extremes must not be subtracted from one another. */
    DVTExpect(DVTCompareIntegers(NSIntegerMin, 0) == -1, @"NSIntegerMin precedes 0");
    DVTExpect(DVTCompareIntegers(0, NSIntegerMin) == 1, @"0 follows NSIntegerMin");
    DVTExpect(DVTCompareIntegers(NSIntegerMax, NSIntegerMin) == 1, @"NSIntegerMax follows NSIntegerMin");

    DVTExpect(DVTCompareDoubles(1.0, 2.0) == -1, @"1.0 precedes 2.0");
    DVTExpect(DVTCompareDoubles(2.0, 1.0) == 1, @"2.0 follows 1.0");
    DVTExpect(DVTCompareDoubles(1.5, 1.5) == 0, @"1.5 equals 1.5");
    /* -0.0 is ordered equal to 0.0. */
    DVTExpect(DVTCompareDoubles(-0.0, 0.0) == 0, @"-0.0 equals 0.0");

    /* A NaN is ordered by the sign bit of the operand it is compared with. */
    DVTExpect(DVTCompareDoubles(NAN, 1.0) == -1, @"NaN is unordered against 1.0");
    DVTExpect(DVTCompareDoubles(NAN, -1.0) == 1, @"NaN is unordered against -1.0");
    DVTExpect(DVTCompareDoubles(NAN, 0.0) == -1, @"NaN is unordered against 0.0");
    DVTExpect(DVTCompareDoubles(NAN, -0.0) == 1, @"NaN reads the sign bit of -0.0");
    DVTExpect(DVTCompareDoubles(1.0, NAN) == 1, @"1.0 against NaN takes the other branch");
    DVTExpect(DVTCompareDoubles(-1.0, NAN) == -1, @"-1.0 against NaN takes the other branch");
    DVTExpect(DVTCompareDoubles(NAN, NAN) == 0, @"NaN equals NaN");
    DVTExpect(DVTCompareDoubles(-NAN, 1.0) == -1, @"a negative NaN is still unordered");

    /* The tolerance is relative, so it is meaningful away from the origin. */
    DVTExpect(DVTEqualDoublesWithEpsilon(1.0, 1.0000001, 1e-6), @"1.0 is within 1e-6 of 1.0000001");
    DVTExpect(DVTEqualDoublesWithEpsilon(1.0, 1.5, 1e-6) == NO, @"1.0 is not within 1e-6 of 1.5");
    DVTExpect(DVTEqualDoublesWithEpsilon(1e9, 1e9 + 1.0, 1e-6), @"the test scales with magnitude");
    /* Either operand being zero collapses the scale, leaving exact equality. */
    DVTExpect(DVTEqualDoublesWithEpsilon(0.0, -0.0, 1e-6), @"-0.0 is within epsilon of 0.0");
    DVTExpect(DVTEqualDoublesWithEpsilon(0.0, 0.25, 1e-6) == NO, @"0.0 is not within 1e-6 of 0.25");
    /* Equal infinities have an infinite scale but a NaN difference. */
    DVTExpect(DVTEqualDoublesWithEpsilon(INFINITY, INFINITY, 1e-6) == NO, @"INFINITY differs from INFINITY");
    DVTExpect(DVTEqualDoublesWithEpsilon(INFINITY, -INFINITY, 1e-6), @"INFINITY is within epsilon of -INFINITY");
    DVTExpect(DVTEqualDoublesWithEpsilon(NAN, 1.0, 1e-6) == NO, @"NaN is within epsilon of nothing");
    DVTExpect(DVTEqualDoublesWithEpsilon(1.0, NAN, 1e-6) == NO, @"nothing is within epsilon of NaN");

    DVTExpect(DVTCompareDoublesWithEpsilon(1.0, 1.0000001, 1e-6) == 0, @"a tolerated pair compares equal");
    DVTExpect(DVTCompareDoublesWithEpsilon(1.0, 1.5, 1e-6) == -1, @"1.0 precedes 1.5");
    DVTExpect(DVTCompareDoublesWithEpsilon(1.5, 1.0, 1e-6) == 1, @"1.5 follows 1.0");
    /* Unlike DVTCompareDoubles, every unordered pair is reported as greater. */
    DVTExpect(DVTCompareDoublesWithEpsilon(1.0, NAN, 1e-6) == 1, @"1.0 against NaN compares greater");
    DVTExpect(DVTCompareDoublesWithEpsilon(-1.0, NAN, 1e-6) == 1, @"-1.0 against NaN compares greater");
    DVTExpect(DVTCompareDoublesWithEpsilon(NAN, 1.0, 1e-6) == 1, @"NaN against 1.0 compares greater");
    DVTExpect(DVTCompareDoublesWithEpsilon(NAN, NAN, 1e-6) == 1, @"NaN against NaN compares greater");
    DVTExpect(DVTCompareDoublesWithEpsilon(INFINITY, INFINITY, 1e-6) == 1, @"INFINITY compares greater than itself");
    DVTExpect(DVTCompareDoublesWithEpsilon(INFINITY, -INFINITY, 1e-6) == 0, @"INFINITY equals -INFINITY");

    /* Arrays are compared as unordered collections. */
    DVTExpect(DVTCompareArrays(@[], @[]) == 0, @"two empty arrays are equal");
    DVTExpect(DVTCompareArrays(@[@1], @[@1]) == 0, @"a one element array equals itself");
    DVTExpect(DVTCompareArrays(@[@1, @2], @[@2, @1]) == 0, @"element order does not matter");
    DVTExpect(DVTCompareArrays(@[@3, @1, @2], @[@1, @2, @3]) == 0, @"a shuffled array equals its sorted form");
    DVTExpect(DVTCompareArrays(@[@"a", @"b"], @[@"b", @"a"]) == 0, @"string order does not matter");
    DVTExpect(DVTCompareArrays(@[], @[@1]) == -1, @"an empty array precedes a longer one");
    DVTExpect(DVTCompareArrays(@[@1], @[]) == 1, @"a longer array follows an empty one");
    DVTExpect(DVTCompareArrays(@[@1, @2], @[@1, @2, @3]) == -1, @"the shorter array precedes the longer");
    DVTExpect(DVTCompareArrays(@[@1, @2], @[@1, @3]) == -1, @"the first differing element decides");
    DVTExpect(DVTCompareArrays(@[@1, @3], @[@1, @2]) == 1, @"the first differing element decides the other way");
    DVTExpect(DVTCompareArrays(@[@1, @1], @[@1, @2]) == -1, @"duplicates are compared by value");
    /* compare: is case sensitive, which separates it from caseInsensitiveCompare:. */
    DVTExpect(DVTCompareArrays(@[@"a"], @[@"A"]) == 1, @"sorting is case sensitive");
    DVTExpect(DVTCompareArrays(@[@"B"], @[@"a"]) == -1, @"sorting is case sensitive both ways");
    /* A nil array is sorted to nothing and so compares as empty. */
    DVTExpect(DVTCompareArrays(nil, nil) == 0, @"two nil arrays are equal");
    DVTExpect(DVTCompareArrays(nil, @[@1]) == -1, @"nil precedes a populated array");
    DVTExpect(DVTCompareArrays(@[@1], nil) == 1, @"a populated array follows nil");
}

@interface DVTKeyPathProbeBase : NSObject
@property (nonatomic, copy) NSString *name;
@end
@implementation DVTKeyPathProbeBase
@end

@interface DVTKeyPathProbeDerived : DVTKeyPathProbeBase
@property (nonatomic, assign) int number;
@end
@implementation DVTKeyPathProbeDerived
@end

static void DVTTestKeyPathComparison(void)
{
    DVTKeyPathProbeBase *base = [DVTKeyPathProbeBase new];
    base.name = @"shared";
    DVTKeyPathProbeBase *twin = [DVTKeyPathProbeBase new];
    twin.name = @"shared";
    DVTKeyPathProbeBase *other = [DVTKeyPathProbeBase new];
    other.name = @"different";
    DVTKeyPathProbeDerived *derived = [DVTKeyPathProbeDerived new];
    derived.name = @"shared";

    /* Identity is checked before anything else, so it wins even when the mode
       is not one the function knows. Two nils are identical, and so equal. */
    DVTExpect(DVTEqualObjectsUsingKeyPaths(base, base, 7, @[@"nope"]), @"an object equals itself under any mode");
    DVTExpect(DVTEqualObjectsUsingKeyPaths(nil, nil, 0, @[]), @"two nils are identical and therefore equal");
    DVTExpect(!DVTEqualObjectsUsingKeyPaths(nil, base, 0, @[]), @"nil against an object is not equal");
    DVTExpect(!DVTEqualObjectsUsingKeyPaths(base, nil, 0, @[]), @"an object against nil is not equal");

    /* Mode 0 accepts a subclass, mode 1 does not, and the check is one
       directional: a derived left operand against a base right one fails,
       because it asks whether the *right* operand is a kind of the left one. */
    DVTExpect(DVTEqualObjectsUsingKeyPaths(base, derived, DVTKeyPathClassMatchAllowsSubclass, @[]),
              @"mode 0 allows a subclass on the right");
    DVTExpect(!DVTEqualObjectsUsingKeyPaths(base, derived, DVTKeyPathClassMatchRequiresIdenticalClass, @[]),
              @"mode 1 requires the identical class");
    DVTExpect(!DVTEqualObjectsUsingKeyPaths(derived, base, DVTKeyPathClassMatchAllowsSubclass, @[]),
              @"the subclass allowance only runs left to right");
    DVTExpect(!DVTEqualObjectsUsingKeyPaths(base, twin, 2, @[]), @"an unknown mode is never equal");
    DVTExpect(!DVTEqualObjectsUsingKeyPaths(base, twin, NSUIntegerMax, @[]), @"nor is any other unknown mode");

    /* An empty key path list passes, so the class check alone decides. */
    DVTExpect(DVTEqualObjectsUsingKeyPaths(base, twin, 0, @[]), @"equal classes with no key paths are equal");
    DVTExpect(DVTEqualObjectsUsingKeyPaths(base, other, 0, @[]), @"unequal contents do not matter without key paths");

    /* With key paths, each pair of values is compared by identity and then
       isEqual:. */
    DVTExpect(DVTEqualObjectsUsingKeyPaths(base, twin, 0, @[@"name"]), @"equal key path values are equal");
    DVTExpect(!DVTEqualObjectsUsingKeyPaths(base, other, 0, @[@"name"]), @"differing key path values are not");
    DVTExpect(DVTEqualObjectsUsingKeyPaths(base, twin, 0, @[@"name", @"name"]),
              @"every key path has to agree, not just one");
    DVTExpect(!DVTEqualObjectsUsingKeyPaths(base, other, 0, @[@"name", @"name"]),
              @"one disagreeing key path is enough to fail");

    /* Two distinct objects can hold the identical value, and identity is tried
       first, so a pair of shared strings matches. */
    NSString *shared = @"shared";
    DVTExpect(DVTEqualObjectsUsingKeyPaths([DVTKeyPathProbeBase new], twin, 0, @[@"name"]) == NO,
              @"a nil key path value is not equal to a string");
    (void)shared;

    /* A key path that does not resolve raises out of the function rather than
       being treated as a mismatch. */
    @try {
        DVTEqualObjectsUsingKeyPaths(base, twin, 0, @[@"missing"]);
        DVTExpect(NO, @"an undefined key path raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:@"NSUnknownKeyException"],
                  @"an undefined key path raises NSUnknownKeyException");
    }

    /* keyPaths has to be a collection that answers dvt_allObjectsPassTest:. */
    @try {
        DVTEqualObjectsUsingKeyPaths(base, twin, 0, @"name");
        DVTExpect(NO, @"a non-collection key path list raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:NSInvalidArgumentException],
                  @"a non-collection key path list raises NSInvalidArgumentException");
    }
    DVTExpect(!DVTEqualObjectsUsingKeyPaths(base, twin, 0, nil), @"a nil key path list is not equal");
}

static void DVTTestCertificateComparison(void)
{
    NSString *iOSDev = @"1.2.840.113635.100.6.1.2";
    NSString *iOSDist = @"1.2.840.113635.100.6.1.4";
    NSString *macDev = @"1.2.840.113635.100.6.1.12";
    NSString *macApp = @"1.2.840.113635.100.6.1.7";
    NSString *macInst = @"1.2.840.113635.100.6.1.8";
    NSString *devID = @"1.2.840.113635.100.6.1.13";
    NSString *directApp = @"1.2.840.113635.100.6.1.14";

    /* Kinds are ordered by their rank in the table, not by the OID text. This
       is the whole reason the function exists, and it is why the OIDs cannot be
       compared directly: ...6.1.12 has to sort before ...6.1.7. */
    DVTExpect(DVTCompareCertificateKinds(iOSDev, iOSDist) == -1, @"iOS Development precedes iOS Distribution");
    DVTExpect(DVTCompareCertificateKinds(iOSDist, iOSDev) == 1, @"and the reverse holds");
    DVTExpect(DVTCompareCertificateKinds(macDev, macApp) == -1, @"Mac Development precedes Mac App Distribution");
    DVTExpect(DVTCompareCertificateKinds(macApp, macDev) == 1, @"rank order is not OID order");
    DVTExpect(DVTCompareCertificateKinds(macApp, macInst) == -1, @"Mac App Distribution precedes Mac Installer");
    DVTExpect(DVTCompareCertificateKinds(devID, directApp) == -1, @"the last two ranks are adjacent and ordered");
    DVTExpect(DVTCompareCertificateKinds(iOSDev, iOSDev) == 0, @"a kind equals itself");
    DVTExpect(DVTCompareCertificateKinds(iOSDev, [iOSDev copy]) == 0, @"equal but distinct objects are the same kind");

    /* nil is ordered by address, so it precedes everything and follows nothing. */
    DVTExpect(DVTCompareCertificateKinds(nil, nil) == 0, @"two nils are equal");
    DVTExpect(DVTCompareCertificateKinds(nil, iOSDev) == -1, @"nil precedes a kind");
    DVTExpect(DVTCompareCertificateKinds(iOSDev, nil) == 1, @"a kind follows nil");

    /* An unknown kind on one side only is also settled by address, which puts it
       *before* the known kind no matter which side it appears on. */
    NSString *unknown = @"1.2.840.113635.100.6.1.99";
    DVTExpect(DVTCompareCertificateKinds(unknown, iOSDev) == -1, @"an unknown kind precedes a known one");
    DVTExpect(DVTCompareCertificateKinds(iOSDev, unknown) == 1, @"and a known kind follows an unknown one");

    /* Two unknown kinds fall through to comparing the operands, so they order by
       text. @7 against @3 is the case that pins this down: both are unknown, so
       the answer is 1 rather than the 0 that comparing two nil ranks would give. */
    DVTExpect(DVTCompareCertificateKinds(@7, @3) == 1, @"two unknown kinds compare by value, not as both nil");
    DVTExpect(DVTCompareCertificateKinds(@3, @7) == -1, @"two unknown kinds compare by value both ways");
    DVTExpect(DVTCompareCertificateKinds(unknown, [unknown copy]) == 0, @"equal unknown kinds are equal");

    /* DVTCompareCertificateKindSets cannot succeed: the sorting selector it needs
       is not implemented, in Apple's framework or in this one. */
    @try {
        DVTCompareCertificateKindSets(@[iOSDev], @[iOSDev]);
        DVTExpect(NO, @"comparing kind sets raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:NSInvalidArgumentException],
                  @"comparing kind sets raises NSInvalidArgumentException");
    }
    @try {
        /* Two nil sets are the one input that survives: messaging nil returns
           nil, so neither array is ever sent the missing selector and the two
           nil first objects compare equal. One populated side is enough to make
           it raise, and a nil operand is no escape from that. */
        DVTExpect(DVTCompareCertificateKindSets(nil, nil) == 0, @"two nil kind sets do not raise");
    } @catch (NSException *exception) {
        DVTExpect(NO, @"two nil kind sets do not raise");
    }
    @try {
        DVTCompareCertificateKindSets(nil, @[iOSDev]);
        DVTExpect(NO, @"nil against a populated kind set still raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:NSInvalidArgumentException],
                  @"a populated operand is enough to raise");
    }
}

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
        DVTTestDispatch();
        DVTTestMachO();
        DVTTestClassAdditions();
        DVTTestAssertions();
        DVTTestComparison();
        DVTTestCertificateComparison();
        DVTTestKeyPathComparison();

        fprintf(stdout, "\n%d checks, %d failures\n", DVTTestCount, DVTTestFailures);
    }

    return DVTTestFailures == 0 ? 0 : 1;
}
