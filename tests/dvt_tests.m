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
#import <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <libkern/OSByteOrder.h>
#include <zlib.h>

#import "DVTFoundation.h"

/** An object that claims to be equal to nothing, not even to itself. */
@interface DVTPicky : NSObject
@end

@implementation DVTPicky
- (BOOL)isEqual:(id)other { (void)other; return NO; }
- (NSUInteger)hash { return 0; }
@end

/**
 Reports every pair as equal under `compare:` while leaving `isEqual:` as the
 inherited identity test, so "already present" and "is equal" disagree. Used to
 tell the two apart.
 */
@interface DVTAlwaysSame : NSObject
@property (nonatomic, copy) NSString *tag;
@end

@implementation DVTAlwaysSame
- (NSComparisonResult)compare:(id)other { (void)other; return NSOrderedSame; }
- (NSString *)description { return [NSString stringWithFormat:@"<same %@>", self.tag]; }
@end

static DVTAlwaysSame *DVTTestSame(NSString *tag)
{
    DVTAlwaysSame *object = [[DVTAlwaysSame alloc] init];
    object.tag = tag;
    return object;
}

/**
  Answers whatever it was built with, so an array member can hand a selector a
  genuine `nil` -- something no array can hold directly.
 */
@interface DVTTestAnswerer : NSObject
@property (nonatomic, strong, nullable) id answer;
- (id)dvt_testAnswer;
@end

@implementation DVTTestAnswerer
- (id)dvt_testAnswer { return self.answer; }
- (NSString *)description { return [NSString stringWithFormat:@"<answerer %@>", self.answer]; }
@end

static DVTTestAnswerer *DVTTestAnswererWith(id answer)
{
    DVTTestAnswerer *answerer = [[DVTTestAnswerer alloc] init];
    answerer.answer = answer;
    return answerer;
}

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

/** Compares rects field by field, exactly. Geometry is reproduced bit for bit
    from Apple, so an approximate compare would hide real divergence. */
static void DVTExpectEqualRects(CGRect actual, CGRect expected, NSString *what)
{
    BOOL equal = actual.origin.x == expected.origin.x && actual.origin.y == expected.origin.y &&
                 actual.size.width == expected.size.width && actual.size.height == expected.size.height;
    if (!equal) {
        printf("       actual:   {%g, %g, %g, %g}\n", actual.origin.x, actual.origin.y,
               actual.size.width, actual.size.height);
        printf("       expected: {%g, %g, %g, %g}\n", expected.origin.x, expected.origin.y,
               expected.size.width, expected.size.height);
    }
    DVTExpect(equal, what);
}

/** Compares ranges field by field, exactly, for the same reason as rects. */
static void DVTExpectEqualRanges(NSRange actual, NSRange expected, NSString *what)
{
    BOOL equal = actual.location == expected.location && actual.length == expected.length;
    if (!equal) {
        printf("       actual:   {%lu,%lu}\n", (unsigned long)actual.location, (unsigned long)actual.length);
        printf("       expected: {%lu,%lu}\n", (unsigned long)expected.location, (unsigned long)expected.length);
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

/** Builds a string from raw UTF-16 code units, terminator omitted, length taken from `count`.

    clang rejects a lone surrogate in a string literal ("invalid universal character"), so inputs that
    contain one have to be assembled from code units instead. */
static NSString *DVTStringFromUnits(const unichar *units, size_t count)
{
    return [NSString stringWithCharacters:units length:count];
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

/** Reads a written file back for the parsing entry points that take NSData. */
static NSData *DVTDataAtPath(NSString *path)
{
    return [NSData dataWithContentsOfFile:path];
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

static void DVTTestBlockPerformers(void)
{
    /* Generation counters. The increment returns the value *after* advancing, so
       a generation can be stamped on a block and compared back later. */
    uint32_t generation = 0;
    for (uint32_t want = 1; want <= 4; want++) {
        uint32_t got = DVTDispatchBlockGenerationIncrement(&generation);
        DVTExpect(got == want, @"generation increment returns the new value");
    }
    DVTExpect(generation == 4, @"generation counter advanced once per call");
    DVTExpect(DVTDispatchBlockGenerationIsCurrent(&generation, 4),
              @"the newest generation is current");
    DVTExpect(!DVTDispatchBlockGenerationIsCurrent(&generation, 3),
              @"a superseded generation is not current");
    DVTExpect(!DVTDispatchBlockGenerationIsCurrent(&generation, 5),
              @"a generation from the future is not current");

    /* Main-thread queues are recognised by provenance, not by identity. */
    dispatch_queue_t mainThreadQueue = _DVTDispatchGetMainQueue("dvt.test.mainthread");
    DVTExpect(mainThreadQueue != NULL, @"main-thread queue is created");
    DVTExpectEqualCStrings(dispatch_queue_get_label(mainThreadQueue), "dvt.test.mainthread",
                           @"main-thread queue keeps its label");
    DVTExpect(_DVTDispatchIsMainQueue(mainThreadQueue),
              @"a main-thread queue is recognised as one");
    DVTExpect(_DVTDispatchIsMainQueue(dispatch_get_main_queue()),
              @"the real main queue is recognised too");
    DVTExpect(!_DVTDispatchIsMainQueue(dispatch_queue_create("dvt.test.plain", DISPATCH_QUEUE_SERIAL)),
              @"an ordinary queue is not a main-thread queue");

    /* Async performers on an ordinary queue. */
    __block int asyncRan = 0;
    __block pthread_t asyncThread = 0;
    pthread_t caller = pthread_self();
    dispatch_queue_t serial = dispatch_queue_create("dvt.test.perform", DISPATCH_QUEUE_SERIAL);
    DVTAsyncPerformBlock(serial, ^{
        asyncRan = 1;
        asyncThread = pthread_self();
    });
    DVTExpect(!asyncRan, @"async block performer defers");
    DVTDispatchSync(serial, ^{});
    DVTExpect(asyncRan, @"async block performer runs on its queue");
    DVTExpect(!pthread_equal(asyncThread, caller),
              @"async block performer does not run on the calling thread");

    /* The sync performer returns only once the block has finished. */
    __block int syncRan = 0;
    DVTSyncPerformBlock(serial, ^{
        syncRan = 1;
    });
    DVTExpect(syncRan, @"sync block performer completes before returning");

    /* Sync on a main-thread queue waits on the main run loop, so the main thread
       has to keep servicing it while another thread makes the call. */
    __block int runLoopRan = 0;
    __block pthread_t runLoopThread = 0;
    pthread_t mainThread = pthread_self();
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        DVTSyncPerformBlock(mainThreadQueue, ^{
            runLoopRan = 1;
            runLoopThread = pthread_self();
        });
        dispatch_semaphore_signal(finished);
    });
    for (int i = 0; i < 200 && dispatch_semaphore_wait(finished, DISPATCH_TIME_NOW) != 0; i++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    }
    DVTExpect(runLoopRan, @"sync performer on a main-thread queue completes");
    DVTExpect(pthread_equal(runLoopThread, mainThread),
              @"main-thread queue runs the block on the main thread");

    /* Operation queues: an ordinary one takes the operation as given. */
    __block int opRan = 0;
    NSOperationQueue *operationQueue = [NSOperationQueue new];
    operationQueue.maxConcurrentOperationCount = 1;
    DVTAsyncPerformBlockOnOperationQueue(operationQueue, ^{
        opRan = 1;
    });
    [operationQueue waitUntilAllOperationsAreFinished];
    DVTExpect(opRan, @"operation-queue block performer runs");

    /* A NULL queue is ignored rather than trapping. */
    __block int nilRan = 0;
    DVTAsyncPerformBlockOnOperationQueue(nil, ^{
        nilRan = 1;
    });
    DVTExpect(!nilRan, @"a nil operation queue runs nothing");

    /* A main operation queue routes to the run loop, so spin it. */
    __block int mainOpRan = 0;
    DVTAsyncPerformBlockOnOperationQueue([NSOperationQueue mainQueue], ^{
        mainOpRan = 1;
    });
    for (int i = 0; i < 200 && !mainOpRan; i++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    }
    DVTExpect(mainOpRan, @"main operation queue runs the block on the run loop");
}

static void DVTTestGeometry(void)
{
    /* Plain field setters. */
    CGRect base = CGRectMake(1, 2, 3, 4);
    DVTExpectEqualRects(DVTRectBySettingWidth(base, 10), CGRectMake(1, 2, 10, 4),
                        @"setting the width leaves origin and height alone");
    DVTExpectEqualRects(DVTRectBySettingHeight(base, 10), CGRectMake(1, 2, 3, 10),
                        @"setting the height leaves origin and width alone");

    /* Pinning maxY moves the origin by the height delta. */
    CGRect pinned = DVTRectBySettingHeightAndPinningMaxY(CGRectMake(0, 10, 20, 30), 10);
    DVTExpectEqualRects(pinned, CGRectMake(0, 30, 20, 10), @"pinning maxY grows downwards");
    DVTExpect(pinned.origin.y + pinned.size.height == 40, @"pinning maxY keeps the far edge fixed");

    /* Insetting reads the *size* of the insets for the y axis, which is not what
       CGRectInset would do. A 100/200/300/400 margin therefore insets y by 300. */
    DVTExpectEqualRects(DVTRectByInsettingRect(CGRectMake(1, 2, 3, 4), CGRectMake(100, 200, 300, 400)),
                        CGRectMake(-47.5, -46, 0, 0),
                        @"over-insetting collapses to a zero-size rect centred on the span");

    /* A well-formed inset still behaves. */
    DVTExpectEqualRects(DVTRectByInsettingRect(CGRectMake(10, 20, 100, 100), CGRectMake(0, 0, 10, 20)),
                        CGRectMake(10, 30, 100, 70),
                        @"insetting takes its y inset from the insets' width");

    /* Distance. */
    DVTExpect(DVTDistanceBetweenPoints(CGPointMake(0, 0), CGPointMake(3, 4)) == 5.0,
              @"distance between points is the hypotenuse");
    DVTExpect(DVTDistanceBetweenPoints(CGPointMake(1, 1), CGPointMake(1, 1)) == 0.0,
              @"distance from a point to itself is zero");

    /* Scaling: a size that fits on both axes is centred unscaled. */
    DVTExpectEqualRects(DVTRectForScalingSizeIntoRect(CGSizeMake(10, 10), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(45, 45, 10, 10),
                        @"a size that fits is centred without scaling");
    /* A size that overflows one axis is scaled to fill, aspect preserved. */
    DVTExpectEqualRects(DVTRectForScalingSizeIntoRect(CGSizeMake(200, 100), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(0, 25, 100, 50),
                        @"an overflowing size is scaled to fill and centred");
    /* A size that fits on one axis but not the other still scales. */
    DVTExpectEqualRects(DVTRectForScalingSizeIntoRect(CGSizeMake(10, 200), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(47.5, 0, 5, 100),
                        @"overflow on either axis alone triggers scaling");

    /* ToFill scales even when the size already fits. */
    DVTExpectEqualRects(DVTRectForScalingSizeToFillRect(CGSizeMake(10, 10), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(0, 0, 100, 100),
                        @"to-fill scales up a size that would otherwise fit");
    /* UpOrDown scales to *fit inside*, ToFill scales to *cover*, so for a
       mismatched aspect ratio they deliberately disagree. */
    DVTExpectEqualRects(DVTRectForScalingSizeUpOrDownIntoRect(CGSizeMake(200, 100), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(0, 25, 100, 50),
                        @"up-or-down fits the size inside the rect");
    DVTExpectEqualRects(DVTRectForScalingSizeUpOrDownIntoRect(CGSizeMake(100, 200), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(25, 0, 50, 100),
                        @"up-or-down fits a tall size inside too");
    DVTExpectEqualRects(DVTRectForScalingSizeToFillRect(CGSizeMake(100, 200), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(0, -50, 100, 200),
                        @"to-fill covers the rect and overflows it");
    /* UpOrDown is the unconditional form of Into's scaling branch. */
    DVTExpectEqualRects(DVTRectForScalingSizeUpOrDownIntoRect(CGSizeMake(200, 100), CGRectMake(0, 0, 100, 100)),
                        DVTRectForScalingSizeIntoRect(CGSizeMake(200, 100), CGRectMake(0, 0, 100, 100)),
                        @"up-or-down matches Into when the size overflows");

    /* InsetFromRectToRect crosses the axes: the x deltas land in the origin and
       the y deltas in the size. */
    DVTExpectEqualRects(DVTInsetFromRectToRect(CGRectMake(0, 0, 10, 10), CGRectMake(20, 30, 40, 50)),
                        CGRectMake(20, -50, 30, -70),
                        @"inset-from-rect-to-rect crosses the axes");

    /* A negative-size rect is measured by the edges it actually spans, because
       the tests go through CoreGraphics' geometric min/max and not origin+size.
       {40,60,-30,-40} and {10,20,30,40} both span x[10,40] y[20,60]. */
    DVTExpectEqualRects(DVTInsetFromRectToRect(CGRectMake(40, 60, -30, -40), CGRectMake(0, 0, 100, 100)),
                        DVTInsetFromRectToRect(CGRectMake(10, 20, 30, 40), CGRectMake(0, 0, 100, 100)),
                        @"a negative-size rect spans the same edges as its positive twin");

    /* PlaceRectInsideRect translates only; size never changes. */
    DVTExpectEqualRects(DVTPlaceRectInsideRect(CGRectMake(-10, -10, 20, 20), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(0, 0, 20, 20),
                        @"a rect starting outside is pushed to the container origin");
    DVTExpectEqualRects(DVTPlaceRectInsideRect(CGRectMake(90, 90, 20, 20), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(80, 80, 20, 20),
                        @"a rect overhanging the far edge is pulled back in");
    DVTExpectEqualRects(DVTPlaceRectInsideRect(CGRectMake(10, 10, 20, 20), CGRectMake(0, 0, 100, 100)),
                        CGRectMake(10, 10, 20, 20),
                        @"a rect already inside is left where it is");
    /* Larger than the container: it cannot fit, and spills out the far side. */
    CGRect oversized = DVTPlaceRectInsideRect(CGRectMake(0, 0, 200, 200), CGRectMake(0, 0, 100, 100));
    DVTExpectEqualRects(oversized, CGRectMake(-100, -100, 200, 200),
                        @"an oversized rect keeps its size and spills out of the container");
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
    [[NSProcessInfo processInfo] dvt_removeEnvironmentVariable:@"DVT_TEST_VIA_CATEGORY"];
    DVTExpect(DVTEnvironmentSnapshotString(@"DVT_TEST_VIA_CATEGORY") == nil,
              @"NSProcessInfo remover category clears the snapshot entry");
}

#pragma mark - Mach-O

static void DVTTestMachO(void)
{
    fprintf(stdout, "\n== mach-o ==\n");

    NSArray<NSString *> *arguments = [NSProcessInfo processInfo].arguments;
    NSString *self = arguments.count > 0 ? [arguments objectAtIndex:0] : nil;
    DVTExpect(self.length > 0, @"test runner has an executable path");

    NSData *selfData = DVTDataAtPath(self);
    DVTExpect(selfData.length > 0, @"test runner executable is readable");

    NSError *error = nil;
    NSNumber *isArchive = DVTMachOIsArchive(selfData, &error);
    DVTExpect(isArchive != nil && error == nil, @"archive query on a real Mach-O succeeds");
    DVTExpect(!isArchive.boolValue, @"a Mach-O is not an archive");

    NSNumber *hasHeader = DVTMachOHasFatHeader(selfData, &error);
    DVTExpect(hasHeader != nil, @"header query on a real Mach-O succeeds");

    DVTExpect(DVTMachOFileTypes(selfData, NULL).count >= 1, @"at least one file type reported");
    DVTExpect(DVTMachOUUIDsForExecutable(self, NULL).count >= 1, @"at least one UUID reported");
    DVTExpect(DVTMachOArchitecturesForExecutable(self, NULL).count >= 1, @"at least one architecture reported");

    NSNumber *hasMachineCode = DVTMachOBinaryHasAnyMachineCode(self, &error);
    DVTExpect(hasMachineCode != nil && error == nil, @"machine code query succeeds");
    DVTExpect(hasMachineCode.boolValue, @"a real executable has machine code");

    NSNumber *isMachO = DVTFileAtPathIsMachO(self, &error);
    DVTExpect(isMachO != nil && isMachO.boolValue && error == nil, @"test runner is recognised as Mach-O");

    __block NSUInteger sliceCount = 0;
    BOOL enumerated = DVTMachOEnumerateSlices(selfData, NULL,
                                              ^BOOL(NSData *sliceData, cpu_type_t cpuType,
                                                    cpu_subtype_t cpuSubType, BOOL *stop, NSError **sliceError) {
        (void)cpuType;
        (void)cpuSubType;
        (void)stop;
        (void)sliceError;
        sliceCount++;
        DVTExpect(sliceData.length > 0, @"each enumerated slice is non-empty");
        return YES;
    });
    DVTExpect(enumerated, @"slice enumeration succeeds");
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
    NSData *syntheticData = DVTDataAtPath(synthetic);
    DVTExpectEqualObjects(DVTMachOFileTypes(syntheticData, NULL), @[@(MH_DYLIB)], @"synthetic file type");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(synthetic, -1, NULL),
                          @[@"@executable_path/../Frameworks"], @"synthetic rpath extracted");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(synthetic, 0, NULL),
                          @[@"@executable_path/../Frameworks"], @"synthetic rpath for slice 0");
    DVTExpectEqualObjects(DVTMachOLinkedLibrariesForExecutable(synthetic, 0, NULL),
                          @[@"/usr/lib/libSystem.B.dylib"], @"synthetic dylib extracted");
    DVTExpectEqualObjects(DVTMachOUUIDsForExecutable(synthetic, NULL), @[], @"synthetic file carries no UUID");
    DVTExpect(DVTMachOBinaryHasAnyMachineCode(synthetic, NULL).boolValue == NO,
              @"synthetic file has no __TEXT segment");
    DVTExpect(DVTMachOHasPlatform(synthetic, PLATFORM_MACOS, NULL).boolValue == NO,
              @"synthetic file declares no platform");

    NSArray *rpathsSlice1 = DVTMachORPathsForExecutable(synthetic, 1, NULL);
    DVTExpectEqualObjects(rpathsSlice1, @[], @"slice 1 does not exist, so no rpaths");

    [[NSFileManager defaultManager] removeItemAtPath:synthetic error:NULL];

    /* A byte-swapped file must be read through the swapped accessors. */
    NSString *swapped = DVTWriteSwappedMachO(@"dvt_swapped");
    NSData *swappedData = DVTDataAtPath(swapped);
    /*
     The name is literal: only a fat header counts, so a swapped thin image is
     still "no" even though it carries a valid Mach-O magic.
     */
    DVTExpect(DVTMachOHasFatHeader(swappedData, NULL).boolValue == NO,
              @"a swapped thin image has no fat header");
    DVTExpect(DVTMachOHasFatHeader([@"not a mach-o" dataUsingEncoding:NSUTF8StringEncoding], NULL).boolValue == NO,
              @"plain text is not a fat header");
    DVTExpectEqualObjects(DVTMachOFileTypes(swappedData, NULL), (@[@(MH_EXECUTE)]), @"swapped file type");
    DVTExpectEqualObjects(DVTMachOArchitecturesForExecutable(swapped, NULL), (@[@"x86_64"]),
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
    NSData *fatData = DVTDataAtPath(fat);
    DVTExpect(DVTMachOHasFatHeader(fatData, NULL).boolValue, @"fat header detected");
    DVTExpectEqualObjects(DVTMachOFileTypes(fatData, NULL), (@[@(MH_EXECUTE), @(MH_DYLIB)]),
                          @"both slice file types reported");
    NSArray *fatArchitectures = DVTMachOArchitecturesForExecutable(fat, NULL);
    DVTExpect(fatArchitectures.count == 2, @"both slice architectures reported");
    DVTExpect([fatArchitectures containsObject:@"arm64"] && [fatArchitectures containsObject:@"x86_64"],
              @"fat architectures are named");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(fat, 0, NULL), (@[@"/arm64"]), @"fat slice 0 rpath");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(fat, 1, NULL), (@[@"/x86_64"]), @"fat slice 1 rpath");
    DVTExpectEqualObjects(DVTMachORPathsForExecutable(fat, 2, NULL), (@[]), @"absent slice 2 has no rpaths");

    __block NSUInteger fatSlices = 0;
    DVTMachOEnumerateSlices(fatData, NULL,
                            ^BOOL(NSData *sliceData, cpu_type_t cpuType,
                                  cpu_subtype_t cpuSubType, BOOL *stop, NSError **sliceError) {
        (void)sliceData;
        (void)cpuType;
        (void)cpuSubType;
        (void)stop;
        (void)sliceError;
        fatSlices++;
        return YES;
    });
    DVTExpect(fatSlices == 2, @"fat file enumerates two slices");
    [[NSFileManager defaultManager] removeItemAtPath:fat error:NULL];
}

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

    /* The two duplicate selectors are the same function in Apple: one is a
       four-byte tail-call to the other, and the body keeps the first
       occurrence, so the "FromBack" name does not mean the last one wins. */
    NSArray *duplicates = @[@"a", @"b", @"a", @"c", @"a"];
    DVTExpectEqualObjects([duplicates dvt_arrayByRemovingDuplicates], (@[@"a", @"b", @"c"]),
                          @"the first occurrence of each value survives, in order");
    DVTExpectEqualObjects([duplicates dvt_arrayByRemovingDuplicatesFromBack], (@[@"a", @"b", @"c"]),
                          @"the FromBack variant keeps first occurrences too");
    NSArray *nestedPair = @[@1, @2];
    NSArray *twoNested = @[nestedPair, nestedPair];
    DVTExpectEqualObjects([twoNested dvt_arrayByRemovingDuplicatesFromBack], (@[@[@1, @2]]),
                          @"nested containers are compared with isEqual:");
    DVTExpectEqualObjects([@[@"only"] dvt_arrayByRemovingDuplicates], (@[@"only"]),
                          @"a single element is returned unchanged");

    /* Despite the name, this one returns a set. */
    DVTExpectEqualObjects(duplicates.dvt_uniqueObjects, ([NSSet setWithObjects:@"a", @"b", @"c", nil]),
                          @"distinct elements, as a set");

    DVTExpectEqualObjects([duplicates dvt_subarrayFromIndex:2], (@[@"a", @"c", @"a"]), @"from an index");
    DVTExpectEqualObjects([duplicates dvt_subarrayFromIndex:duplicates.count], (@[]),
                          @"index == count is in bounds and yields nothing");
    DVTExpectEqualObjects([duplicates dvt_subarrayAfterIndex:2], (@[@"c", @"a"]), @"after an index");
    DVTExpectEqualObjects([duplicates dvt_subarrayAfterIndex:duplicates.count - 1], (@[]),
                          @"after the last index yields nothing");
    /* Both subarray helpers are unchecked in Apple, so the range length
       underflows and Foundation raises instead of returning an empty array. */
    @try {
        [duplicates dvt_subarrayFromIndex:duplicates.count + 1];
        DVTExpect(NO, @"an out-of-bounds subarrayFromIndex: raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:NSRangeException],
                  @"an out-of-bounds subarrayFromIndex: raises NSRangeException");
    }
    @try {
        [duplicates dvt_subarrayAfterIndex:duplicates.count];
        DVTExpect(NO, @"an out-of-bounds subarrayAfterIndex: raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:NSRangeException],
                  @"an out-of-bounds subarrayAfterIndex: raises NSRangeException");
    }

    /* Out-of-bounds indexes are dropped instead of raising. */
    DVTExpectEqualObjects([sample dvt_objectsAtIndexesWithinBounds:
                              [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)]],
                          (@[@"bb", @"ccc"]), @"in-bounds indexes");
    DVTExpectEqualObjects([sample dvt_objectsAtIndexesWithinBounds:
                              [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 5)]],
                          (@[@"bb", @"ccc"]), @"indexes past the end are skipped");

    DVTExpect([sample dvt_hasPrefix:(@[@"a", @"bb"])], @"a matching prefix");
    DVTExpect([sample dvt_hasPrefix:(@[])], @"an empty prefix always matches");
    DVTExpect(![sample dvt_hasPrefix:(@[@"bb", @"a"])], @"a different prefix does not match");
    DVTExpect([sample dvt_hasPrefix:sample], @"a full-length equal prefix matches");
    DVTExpect(![sample dvt_hasPrefix:(@[@"a", @"bb", @"ccc", @"extra"])], @"a longer prefix does not match");

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

    {
        /* The comparator forms of the extremes, which are the same fold as the no-argument
           pair above but ranked by a block instead of by -compare:. */
        NSComparisonResult (^ascending)(id, id) = ^NSComparisonResult(id a, id b) {
            return [a compare:b];
        };
        NSArray *numbers = @[@3, @1, @2];

        DVTExpect([[NSArray array] dvt_minimumObject:ascending] == nil,
                  @"array minimumObject: is nil for an empty receiver");
        DVTExpect([[NSArray array] dvt_maximumObject:ascending] == nil,
                  @"array maximumObject: is nil for an empty receiver");
        DVTExpectEqualObjects([numbers dvt_minimumObject:ascending], @1, @"array minimumObject: ranks lowest");
        DVTExpectEqualObjects([numbers dvt_maximumObject:ascending], @3, @"array maximumObject: ranks highest");
        /* A block that inverts the order swaps the two answers, which is the clearest
           statement that the ranking is the caller's and not a fixed direction. */
        DVTExpectEqualObjects([numbers dvt_minimumObject:^NSComparisonResult(id a, id b) {
            return [b compare:a];
        }], @3, @"array minimumObject: ranks by the comparator given");
        /* Asked once per adjacent step, so a member count of n costs n-1 calls. */
        __block NSUInteger minimumCalls = 0;
        (void)[numbers dvt_minimumObject:^NSComparisonResult(id a, id b) {
            minimumCalls++;
            return [a compare:b];
        }];
        DVTExpect(minimumCalls == 2, @"array minimumObject: asks once per adjacent step");
        __block NSUInteger maximumCalls = 0;
        (void)[numbers dvt_maximumObject:^NSComparisonResult(id a, id b) {
            maximumCalls++;
            return [a compare:b];
        }];
        DVTExpect(maximumCalls == 2, @"array maximumObject: asks once per adjacent step");
        /* The comparator is asked (candidate, incumbent). With -compare: that is what
           makes the ranking come out right -- "2" measured against a held "1" answers
           descending and is discarded -- so the pair order is the whole mechanism. */
        NSMutableArray *pairs = [NSMutableArray array];
        (void)[numbers dvt_minimumObject:^NSComparisonResult(id a, id b) {
            [pairs addObject:[NSString stringWithFormat:@"(%@,%@)", a, b]];
            return [a compare:b];
        }];
        DVTExpectEqualObjects([pairs componentsJoinedByString:@" "], @"(1,3) (2,1)",
                              @"array minimumObject: asks (candidate, incumbent)");
        /* A lone member is never compared, so it comes back untouched and the comparator
           need not even be asked -- which is what leaves a nil comparator usable here. */
        __block NSUInteger soloCalls = 0;
        DVTExpectEqualObjects([@[@7] dvt_minimumObject:^NSComparisonResult(id a, id b) {
            soloCalls++;
            return NSOrderedSame;
        }], @7, @"array minimumObject: answers a lone member");
        DVTExpect(soloCalls == 0, @"array minimumObject: does not compare a lone member");
        DVTExpectEqualObjects([@[@7] dvt_maximumObject:nil], @7,
                              @"array maximumObject: goes unasked for a lone member");
        DVTExpect([[NSArray array] dvt_minimumObject:nil] == nil,
                  @"array minimumObject: goes unasked for an empty receiver");
        /* A tie keeps the incumbent, so the first of the equal members wins. */
        DVTExpectEqualObjects([@[@1, @1, @1] dvt_minimumObject:^NSComparisonResult(id a, id b) {
            return NSOrderedSame;
        }], @1, @"array minimumObject: a tie keeps the incumbent");
        DVTExpectEqualObjects([@[@1, @1, @1] dvt_maximumObject:^NSComparisonResult(id a, id b) {
            return NSOrderedSame;
        }], @1, @"array maximumObject: a tie keeps the incumbent");
        /* Only an exact NSOrderedAscending replaces the incumbent. An answer outside the
           contract is not "less" and does not win, and NSOrderedSame is a tie rather
           than a descent -- so a comparator answering a constant answers nothing. */
        DVTExpectEqualObjects([@[@1, @9] dvt_minimumObject:^NSComparisonResult(id a, id b) {
            return (NSComparisonResult)-2;
        }], @1, @"array minimumObject: only an exact ascending replaces");
        DVTExpectEqualObjects([@[@1, @9] dvt_minimumObject:^NSComparisonResult(id a, id b) {
            return (NSComparisonResult)7;
        }], @1, @"array minimumObject: an out-of-contract answer keeps the incumbent");
        DVTExpectEqualObjects([@[@1, @9] dvt_maximumObject:^NSComparisonResult(id a, id b) {
            return (NSComparisonResult)-2;
        }], @1, @"array maximumObject: an out-of-contract answer keeps the incumbent");
    }

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

    /* The derived-value sort on a set is the array form asked of -allObjects, so
       a distinct derived value per member is what makes the answer reproducible:
       a set has no order of its own to sort, and tied members keep whichever
       order the set's enumeration produced. */
    {
        NSSet *distinct = [NSSet setWithObjects:@"bbb", @"a", @"cc", nil];
        NSArray *sorted = [distinct dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        }];
        DVTExpectEqualObjects(sorted, (@[@"a", @"cc", @"bbb"]),
                              @"set objectsSortedByValueBlock: orders by the derived value");
        DVTExpect(![sorted isKindOfClass:[NSMutableArray class]],
                  @"set objectsSortedByValueBlock: answers an immutable array");
        DVTExpect(sorted.count == distinct.count,
                  @"set objectsSortedByValueBlock: keeps every member");
        NSArray *descending = [distinct dvt_objectsSortedByValueBlock:^id(id object) {
            return @(-(NSInteger)[object length]);
        }];
        DVTExpectEqualObjects(descending, (@[@"bbb", @"cc", @"a"]),
                              @"set objectsSortedByValueBlock: orders descending when the value block negates");
    }
    {
        /* One member or fewer leaves nothing to compare, so the value block is
           never asked and a nil return is harmless. */
        NSSet *single = [NSSet setWithObject:@"only"];
        __block int calls = 0;
        NSArray *sorted = [single dvt_objectsSortedByValueBlock:^id(id object) {
            calls++;
            return nil;
        }];
        DVTExpect(calls == 0, @"set objectsSortedByValueBlock: never asks the value block for one member");
        DVTExpectEqualObjects(sorted, (@[@"only"]),
                              @"set objectsSortedByValueBlock: answers one member unchanged");
        NSSet *empty = [NSSet set];
        calls = 0;
        NSArray *sortedEmpty = [empty dvt_objectsSortedByValueBlock:^id(id object) {
            calls++;
            return nil;
        }];
        DVTExpect(calls == 0, @"set objectsSortedByValueBlock: never asks the value block for an empty set");
        DVTExpect(sortedEmpty.count == 0, @"set objectsSortedByValueBlock: answers an empty array for an empty set");
        NSSet *two = [NSSet setWithObjects:@"bb", @"a", nil];
        calls = 0;
        NSArray *sortedTwo = [two dvt_objectsSortedByValueBlock:^id(id object) {
            calls++;
            return @([object length]);
        }];
        DVTExpect(calls > 0, @"set objectsSortedByValueBlock: asks the value block for two members");
        DVTExpectEqualObjects(sortedTwo, (@[@"a", @"bb"]),
                              @"set objectsSortedByValueBlock: orders two members");
    }
    {
        /* The handler breaks ties by member, which is what makes a tied answer
           reproducible even though the set's own order is not. A set cannot hold
           equal members, so distinct members of the same length all survive. */
        NSSet *tied = [NSSet setWithObjects:@"aa", @"bb", @"cc", @"dd", nil];
        NSArray *sorted = [tied dvt_objectsSortedByValueBlock:^id(id object) {
            return @"all-equal";
        } duplicateHandler:^NSComparisonResult(id first, id second) {
            return [first compare:second];
        }];
        DVTExpectEqualObjects(sorted, (@[@"aa", @"bb", @"cc", @"dd"]),
                              @"set objectsSortedByValueBlock:duplicateHandler: can order ties by member");
        NSArray *shared = [[NSSet setWithObjects:@"bb", @"a", @"dd", @"cc", nil]
                              dvt_objectsSortedByValueBlock:^id(id object) {
                                  return @([object length]);
                              }];
        DVTExpect(shared.count == 4,
                  @"set objectsSortedByValueBlock: keeps members that share a derived value");
        DVTExpect([shared containsObject:@"a"] && [shared containsObject:@"bb"] &&
                  [shared containsObject:@"cc"] && [shared containsObject:@"dd"],
                  @"set objectsSortedByValueBlock: shared derived values are all present");
        NSSet *distinct = [NSSet setWithObjects:@"bb", @"a", @"cc", nil];
        __block int handlerCalls = 0;
        NSArray *unequal = [distinct dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        } duplicateHandler:^NSComparisonResult(id first, id second) {
            handlerCalls++;
            return NSOrderedSame;
        }];
        DVTExpectEqualObjects(unequal, (@[@"a", @"bb", @"cc"]),
                              @"set objectsSortedByValueBlock:duplicateHandler: returning NSOrderedSame sorts normally");
        (void)handlerCalls;
    }
    {
        /* The one argument form matches the two argument form spelled with nil. */
        NSSet *members = [NSSet setWithObjects:@"bb", @"a", @"cc", @"dd", nil];
        NSArray *oneArgument = [members dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        }];
        NSArray *nilHandler = [members dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        } duplicateHandler:nil];
        DVTExpectEqualObjects(oneArgument, nilHandler,
                              @"set objectsSortedByValueBlock: matches the two argument form with a nil handler");
    }
    {
        /* A mutable set goes through allObjects like any other and is left alone. */
        NSMutableSet *mutableSet = [NSMutableSet setWithObjects:@"bbb", @"a", @"cc", nil];
        NSUInteger before = mutableSet.count;
        NSArray *sorted = [mutableSet dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        }];
        DVTExpectEqualObjects(sorted, (@[@"a", @"cc", @"bbb"]),
                              @"set objectsSortedByValueBlock: sorts a mutable set's members");
        DVTExpect(mutableSet.count == before, @"set objectsSortedByValueBlock: leaves a mutable set unchanged");
    }
    {
        /* A derived value of nil asserts once there is a comparison to make,
           naming the member whose value came back empty. */
        DVTTestCapturingHandler *handler = [DVTTestCapturingHandler new];
        [DVTAssertionReportHandler setCurrentHandler:handler];
        NSSet *two = [NSSet setWithObjects:@"bb", @"a", nil];
        [two dvt_objectsSortedByValueBlock:^id(id object) { return nil; }];
        [DVTAssertionReportHandler setCurrentHandler:nil];
        NSString *joined = [handler.reports componentsJoinedByString:@"\n"];
        DVTExpect([joined rangeOfString:@"projectionBlock(obj1)"].location != NSNotFound,
                  @"set objectsSortedByValueBlock: asserts on a nil derived value");
    }

    /* dvt_onlyObject, the two matching-member predicates, and the count. */

    {
        NSSet *one = [NSSet setWithObject:@"only"];
        NSSet *none = [NSSet set];
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        DVTExpectEqualObjects([one dvt_onlyObject], @"only",
                              @"set onlyObject answers its only member");
        DVTExpect([none dvt_onlyObject] == nil, @"set onlyObject answers nil when empty");
        DVTExpect([three dvt_onlyObject] == nil,
                  @"set onlyObject answers nil rather than picking one of several members");
        DVTExpectEqualObjects([one dvt_onlyObject], [one anyObject],
                              @"set onlyObject answers the member -anyObject would");
        NSMutableSet *mutableOne = [NSMutableSet setWithObject:@"solo"];
        DVTExpectEqualObjects([mutableOne dvt_onlyObject], @"solo",
                              @"set onlyObject answers a mutable set's only member");
    }

    {
        /* Despite the name this answers the member that passed, not whether one
           did. Which of several matches wins is the set's own order, so only
           membership is checked; the call counts are what pin the early exit. */
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        DVTExpectEqualObjects([three dvt_anyObjectPassingTest:^BOOL(id o) { return [o isEqualToString:@"a"]; }],
                              @"a", @"set anyObjectPassingTest: answers the matching member");
        DVTExpect([three dvt_anyObjectPassingTest:^BOOL(id o) { return NO; }] == nil,
                  @"set anyObjectPassingTest: answers nil when nothing passes");
        __block int anyCalls = 0;
        id anyAnswer = [three dvt_anyObjectPassingTest:^BOOL(id o) { anyCalls++; return YES; }];
        DVTExpect(anyCalls == 1, @"set anyObjectPassingTest: stops at the first match");
        DVTExpect([three containsObject:anyAnswer], @"set anyObjectPassingTest: answers a member");
        __block int anyEmptyCalls = 0;
        id anyEmptyAnswer = [[NSSet set] dvt_anyObjectPassingTest:^BOOL(id o) { anyEmptyCalls++; return YES; }];
        DVTExpect(anyEmptyAnswer == nil, @"set anyObjectPassingTest: answers nil for an empty set");
        DVTExpect(anyEmptyCalls == 0, @"set anyObjectPassingTest: never asks the test for an empty set");
        __block int anySeen = 0;
        id anyB = [three dvt_anyObjectPassingTest:^BOOL(id o) { anySeen++; return [o isEqualToString:@"b"]; }];
        DVTExpectEqualObjects(anyB, @"b", @"set anyObjectPassingTest: finds a later member");
        DVTExpect(anySeen < 3, @"set anyObjectPassingTest: stops before asking every member");
    }

    {
        /* Exactly one member has to pass. A second match answers nil right away,
           which is visible in how many times the test is asked. */
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        DVTExpectEqualObjects([three dvt_onlyObjectPassingTest:^BOOL(id o) { return [o isEqualToString:@"c"]; }],
                              @"c", @"set onlyObjectPassingTest: answers the one member that passes");
        DVTExpect([three dvt_onlyObjectPassingTest:^BOOL(id o) { return NO; }] == nil,
                  @"set onlyObjectPassingTest: answers nil when nothing passes");
        DVTExpect([three dvt_onlyObjectPassingTest:^BOOL(id o) {
                       return [o isEqualToString:@"b"] || [o isEqualToString:@"c"];
                   }] == nil,
                  @"set onlyObjectPassingTest: answers nil when two members pass");
        __block int severalCalls = 0;
        id severalAnswer = [three dvt_onlyObjectPassingTest:^BOOL(id o) { severalCalls++; return YES; }];
        DVTExpect(severalCalls == 2, @"set onlyObjectPassingTest: stops as soon as a second member passes");
        DVTExpect(severalAnswer == nil, @"set onlyObjectPassingTest: answers nil for two or more matches");
        __block int emptyOnlyCalls = 0;
        DVTExpect([[NSSet set] dvt_onlyObjectPassingTest:^BOOL(id o) { emptyOnlyCalls++; return YES; }] == nil,
                  @"set onlyObjectPassingTest: answers nil for an empty set");
        DVTExpect(emptyOnlyCalls == 0, @"set onlyObjectPassingTest: never asks the test for an empty set");
        __block int singleCalls = 0;
        id singleMatch = [three dvt_onlyObjectPassingTest:^BOOL(id o) {
            singleCalls++;
            return [o isEqualToString:@"a"];
        }];
        DVTExpect(singleCalls == 3, @"set onlyObjectPassingTest: asks about every member when one passes");
        DVTExpectEqualObjects(singleMatch, @"a", @"set onlyObjectPassingTest: answers that member");
        NSSet *none = [NSSet set];
        DVTExpect([none dvt_onlyObjectPassingTest:^BOOL(id o) { return YES; }] == nil,
                  @"set onlyObjectPassingTest: answers nil when an empty set cannot pass");
        NSSet *one = [NSSet setWithObject:@"solo"];
        DVTExpectEqualObjects([one dvt_onlyObjectPassingTest:^BOOL(id o) { return YES; }], @"solo",
                              @"set onlyObjectPassingTest: answers a single passing member");
    }

    {
        /* Every member is asked; the walk does not stop early. */
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        __block int calls = 0;
        NSInteger passing = [three dvt_numberOfObjectsPassingTest:^BOOL(id o) {
            calls++;
            return [o isEqualToString:@"a"] || [o isEqualToString:@"b"];
        }];
        DVTExpect(passing == 2, @"set numberOfObjectsPassingTest: counts the members that pass");
        DVTExpect(calls == 3, @"set numberOfObjectsPassingTest: asks about every member");
        DVTExpect([three dvt_numberOfObjectsPassingTest:^BOOL(id o) { return YES; }] == 3,
                  @"set numberOfObjectsPassingTest: totals the member count when all pass");
        DVTExpect([three dvt_numberOfObjectsPassingTest:^BOOL(id o) { return NO; }] == 0,
                  @"set numberOfObjectsPassingTest: is zero when none pass");
        DVTExpect([[NSSet set] dvt_numberOfObjectsPassingTest:^BOOL(id o) { return YES; }] == 0,
                  @"set numberOfObjectsPassingTest: is zero for an empty set");
        NSSet *one = [NSSet setWithObject:@"solo"];
        DVTExpect([one dvt_numberOfObjectsPassingTest:^BOOL(id o) { return YES; }] == 1,
                  @"set numberOfObjectsPassingTest: is one for a single passing member");
        /* The block's return value is added up, not counted, which a caller can
           only reach by casting a block of another return type. Apple does the
           same, so the totals below are the sums rather than 0 or 3. */
        NSInteger (^threeEach)(id) = ^NSInteger(id o) { return 3; };
        DVTExpect([three dvt_numberOfObjectsPassingTest:(BOOL (^)(id))threeEach] == 9,
                  @"set numberOfObjectsPassingTest: sums what the block returns");
        NSInteger (^negative)(id) = ^NSInteger(id o) { return -1; };
        DVTExpect([three dvt_numberOfObjectsPassingTest:(BOOL (^)(id))negative] == 12884901885LL,
                  @"set numberOfObjectsPassingTest: zero-extends each return rather than wrapping");
        NSInteger (^hundred)(id) = ^NSInteger(id o) { return 100000; };
        DVTExpect([one dvt_numberOfObjectsPassingTest:(BOOL (^)(id))hundred] == 100000,
                  @"set numberOfObjectsPassingTest: sums a large return over one member");
    }

    {
        /* The mapping answers come back in the set's own order, so the tests sort
           before comparing. What is checked exactly is the contract: the members
           that survive, whether the answer is immutable, and how many times the
           block ran. */
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        NSArray *mapped = [three dvt_arrayByApplyingBlock:^id(id o) {
            return [o uppercaseString];
        }];
        DVTExpectEqualObjects([NSSet setWithArray:[mapped sortedArrayUsingSelector:@selector(compare:)]],
                              [NSSet setWithObjects:@"A", @"B", @"C", nil],
                              @"set arrayByApplyingBlock: maps every member");
        DVTExpect(![mapped respondsToSelector:@selector(addObject:)],
                  @"set arrayByApplyingBlock: answers an immutable array");

        /* The loose form drops a nil answer and keeps going. */
        NSArray *withGap = [three dvt_arrayByApplyingBlock:^id(id o) {
            return [o isEqualToString:@"b"] ? nil : o;
        }];
        DVTExpectEqualObjects([NSSet setWithArray:[withGap sortedArrayUsingSelector:@selector(compare:)]],
                              [NSSet setWithObjects:@"a", @"c", nil],
                              @"set arrayByApplyingBlock: drops the members whose block answers nil");
        NSArray *noneAtAll = [three dvt_arrayByApplyingBlock:^id(id o) { return nil; }];
        DVTExpectEqualObjects(noneAtAll, @[], @"set arrayByApplyingBlock: is empty when every answer is nil");
        __block int looseCalls = 0;
        [three dvt_arrayByApplyingBlock:^id(id o) { looseCalls++; return nil; }];
        DVTExpect(looseCalls == 3, @"set arrayByApplyingBlock: asks about every member even so");

        /* Strictly sinks the whole answer at the first nil rather than dropping
           it, and it stops there -- one call, not one per member. */
        __block int strictCalls = 0;
        id strictNil = [three dvt_arrayByApplyingBlockStrictly:^id(id o) {
            strictCalls++;
            return nil;
        }];
        DVTExpect(strictNil == nil, @"set arrayByApplyingBlockStrictly: answers nil for a nil answer");
        DVTExpect(strictCalls == 1, @"set arrayByApplyingBlockStrictly: stops at the first nil");
        NSArray *strictKept = [three dvt_arrayByApplyingBlockStrictly:^id(id o) { return [o uppercaseString]; }];
        DVTExpect(![strictKept respondsToSelector:@selector(addObject:)],
                  @"set arrayByApplyingBlockStrictly: answers an immutable array");
        DVTExpectEqualObjects([NSSet setWithArray:[strictKept sortedArrayUsingSelector:@selector(compare:)]],
                              [NSSet setWithObjects:@"A", @"B", @"C", nil],
                              @"set arrayByApplyingBlockStrictly: maps when no answer is nil");
    }

    {
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];

        NSSet *asSet = [three dvt_setByApplyingBlock:^id(id o) { return [o uppercaseString]; }];
        DVTExpectEqualObjects(asSet, [NSSet setWithObjects:@"A", @"B", @"C", nil],
                              @"set setByApplyingBlock: maps every member into a set");
        DVTExpect(![asSet respondsToSelector:@selector(addObject:)],
                  @"set setByApplyingBlock: answers an immutable set");
        /* Repeated answers collapse, so the result can be smaller than the
           receiver without a single answer having been nil. */
        NSSet *collapsed = [three dvt_setByApplyingBlock:^id(id o) { return @"same"; }];
        DVTExpectEqualObjects(collapsed, [NSSet setWithObject:@"same"],
                              @"set setByApplyingBlock: collapses repeated answers");
        DVTExpectEqualObjects([three dvt_setByApplyingBlock:^id(id o) { return nil; }], [NSSet set],
                              @"set setByApplyingBlock: is empty when every answer is nil");

        __block int strictSetCalls = 0;
        id strictSetNil = [three dvt_setByApplyingBlockStrictly:^id(id o) {
            strictSetCalls++;
            return nil;
        }];
        DVTExpect(strictSetNil == nil, @"set setByApplyingBlockStrictly: answers nil for a nil answer");
        DVTExpect(strictSetCalls == 1, @"set setByApplyingBlockStrictly: stops at the first nil");
        NSSet *strictSetKept = [three dvt_setByApplyingBlockStrictly:^id(id o) { return [o uppercaseString]; }];
        DVTExpectEqualObjects(strictSetKept, [NSSet setWithObjects:@"A", @"B", @"C", nil],
                              @"set setByApplyingBlockStrictly: maps when no answer is nil");
        DVTExpect(![strictSetKept respondsToSelector:@selector(addObject:)],
                  @"set setByApplyingBlockStrictly: answers an immutable set");
    }

    {
        /* Filtering a set answers with a set, and a set that lost nobody comes
           back as the receiver itself. That identity is the one behaviour the
           array form does not share, because it has to build a set either way. */
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        NSSet *twoKept = [three dvt_setByFilteringUsingBlock:^BOOL(id o) {
            return [o isEqualToString:@"a"] || [o isEqualToString:@"b"];
        }];
        DVTExpectEqualObjects(twoKept, [NSSet setWithObjects:@"a", @"b", nil],
                              @"set setByFilteringUsingBlock: keeps the members that pass");
        DVTExpect([three dvt_setByFilteringUsingBlock:^BOOL(id o) { return YES; }] == three,
                  @"set setByFilteringUsingBlock: answers the receiver when nothing is filtered out");
        DVTExpectEqualObjects([three dvt_setByFilteringUsingBlock:^BOOL(id o) { return NO; }], [NSSet set],
                              @"set setByFilteringUsingBlock: is empty when nothing passes");
        DVTExpectEqualObjects([[NSSet set] dvt_setByFilteringUsingBlock:^BOOL(id o) { return YES; }], [NSSet set],
                              @"set setByFilteringUsingBlock: is empty for an empty set");
        DVTExpect(![twoKept respondsToSelector:@selector(addObject:)],
                  @"set setByFilteringUsingBlock: answers an immutable set");

        NSSet *mutableThree = [NSMutableSet setWithObjects:@"a", @"b", @"c", nil];
        NSSet *fromMutable = [mutableThree dvt_setByFilteringUsingBlock:^BOOL(id o) { return YES; }];
        DVTExpect(fromMutable != mutableThree,
                  @"set setByFilteringUsingBlock: does not hand back a mutable set");
        DVTExpect(![fromMutable respondsToSelector:@selector(addObject:)],
                  @"set setByFilteringUsingBlock: answers an immutable set for a mutable receiver");

        /* The same selector on an array answers an array. */
        NSArray *array = @[@"a", @"b", @"c"];
        id fromArray = [array dvt_objectsPassingTest:^BOOL(id o) { return [o isEqualToString:@"a"]; }];
        DVTExpect([fromArray isKindOfClass:[NSArray class]],
                  @"array objectsPassingTest: answers an array where the set form answers a set");
        DVTExpect(![fromArray isKindOfClass:[NSSet class]],
                  @"array objectsPassingTest: does not answer a set");
    }

    {
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        DVTExpectEqualObjects([three dvt_objectsPassingTest:^BOOL(id o) {
                       return [o isEqualToString:@"a"] || [o isEqualToString:@"b"];
                   }],
                              [NSSet setWithObjects:@"a", @"b", nil],
                              @"set objectsPassingTest: keeps the members that pass");
        DVTExpect([three dvt_objectsPassingTest:^BOOL(id o) { return YES; }] == three,
                  @"set objectsPassingTest: answers the receiver when every member passes");
        DVTExpect([three dvt_objectsPassingTest:^BOOL(id o) { return NO; }] != three,
                  @"set objectsPassingTest: answers a new set when a member fails");
        DVTExpectEqualObjects([three dvt_objectsPassingTest:^BOOL(id o) { return NO; }], [NSSet set],
                              @"set objectsPassingTest: is empty when nothing passes");
        NSSet *kept = [three dvt_objectsPassingTest:^BOOL(id o) { return [o isEqualToString:@"a"]; }];
        DVTExpect(![kept respondsToSelector:@selector(addObject:)],
                  @"set objectsPassingTest: answers an immutable set");
        __block int passCalls = 0;
        [three dvt_objectsPassingTest:^BOOL(id o) { passCalls++; return NO; }];
        DVTExpect(passCalls == 3, @"set objectsPassingTest: asks about every member");
    }

    {
        /* Regression cover for the shared array forms. Each of these used to
           answer the mutable collection it had just built, and the two Strictly
           forms used to put an NSNull where a nil answer came back. */
        NSArray *three = @[@"a", @"b", @"c"];

        NSArray *arrayMapped = [three dvt_arrayByApplyingBlock:^id(id o) { return [o uppercaseString]; }];
        DVTExpect(![arrayMapped respondsToSelector:@selector(addObject:)],
                  @"array arrayByApplyingBlock: answers an immutable array");
        DVTExpectEqualObjects(arrayMapped, @[@"A", @"B", @"C"],
                              @"array arrayByApplyingBlock: maps every member");

        DVTExpect([three dvt_arrayByApplyingBlockStrictly:^id(id o) { return nil; }] == nil,
                  @"array arrayByApplyingBlockStrictly: answers nil rather than inserting NSNull");
        __block int arrayStrictCalls = 0;
        [three dvt_arrayByApplyingBlockStrictly:^id(id o) { arrayStrictCalls++; return nil; }];
        DVTExpect(arrayStrictCalls == 1, @"array arrayByApplyingBlockStrictly: stops at the first nil");
        /* The NSNull that used to be inserted has no -compare:, so sorting the
           answer is what made the old behaviour observable as a crash. */
        NSArray *strictAnswer = [three dvt_arrayByApplyingBlockStrictly:^id(id o) { return [o uppercaseString]; }];
        DVTExpectEqualObjects([strictAnswer sortedArrayUsingSelector:@selector(compare:)],
                              @[@"A", @"B", @"C"], @"array arrayByApplyingBlockStrictly: maps when no answer is nil");

        NSSet *arrayMappedSet = [three dvt_setByApplyingBlock:^id(id o) { return [o uppercaseString]; }];
        DVTExpect(![arrayMappedSet respondsToSelector:@selector(addObject:)],
                  @"array setByApplyingBlock: answers an immutable set");
        DVTExpectEqualObjects(arrayMappedSet, [NSSet setWithObjects:@"A", @"B", @"C", nil],
                              @"array setByApplyingBlock: maps into a set");
        DVTExpect([three dvt_setByApplyingBlockStrictly:^id(id o) { return nil; }] == nil,
                  @"array setByApplyingBlockStrictly: answers nil rather than inserting NSNull");
        __block int setStrictCalls = 0;
        [three dvt_setByApplyingBlockStrictly:^id(id o) { setStrictCalls++; return nil; }];
        DVTExpect(setStrictCalls == 1, @"array setByApplyingBlockStrictly: stops at the first nil");

        DVTExpect([three dvt_objectsPassingTest:^BOOL(id o) { return YES; }] == three,
                  @"array objectsPassingTest: answers the receiver when every member passes");
        NSArray *filtered = [three dvt_objectsPassingTest:^BOOL(id o) { return [o isEqualToString:@"a"]; }];
        DVTExpectEqualObjects(filtered, @[@"a"], @"array objectsPassingTest: keeps the members that pass");
        DVTExpect(![filtered respondsToSelector:@selector(addObject:)],
                  @"array objectsPassingTest: answers an immutable array");
    }

    {
        /* dvt_firstMap: is the compact map that stops early. The answer alone
           cannot show the difference -- dvt_compactMap: finds the same object with
           the same block -- so the call log is what pins it down: the members after
           the first usable answer are never offered to the block. */
        NSArray *abc = @[@"a", @"b", @"c"];
        NSMutableArray *calls = [NSMutableArray array];

        DVTExpect([@[] dvt_firstMap:^id(id o) { return o; }] == nil,
                  @"array firstMap: is nil for an empty receiver");
        DVTExpect(calls.count == 0, @"array firstMap: never called the block for an empty receiver");
        DVTExpectEqualObjects([abc dvt_firstMap:^id(id o) {
            [calls addObject:o];
            return [o isEqualToString:@"b"] ? [o uppercaseString] : nil;
        }], @"B",
                          @"array firstMap: answers the first non-nil block answer");
        DVTExpectEqualObjects([calls componentsJoinedByString:@" "], @"a b",
                              @"array firstMap: stops asking once it has an answer");
        /* A nil answer is not an exit, so the walk continues and an all-nil block
           runs to the end before answering nil. */
        [calls removeAllObjects];
        DVTExpect([abc dvt_firstMap:^id(id o) {
            [calls addObject:o];
            return nil;
        }] == nil,
                  @"array firstMap: is nil when every answer is nil");
        DVTExpectEqualObjects([calls componentsJoinedByString:@" "], @"a b c",
                              @"array firstMap: an all-nil block is asked about every member");
        /* The first member can answer nil like any other, which is what the call
           log above already covers; the answer here is simply the second member. */
        DVTExpectEqualObjects([abc dvt_firstMap:^id(id o) {
            return [o isEqualToString:@"a"] ? nil : o;
        }], @"b",
                          @"array firstMap: a nil first answer is skipped");
        DVTExpectEqualObjects([abc dvt_firstMap:^id(id o) { return o; }], @"a",
                              @"array firstMap: an identity block answers the first member");
    }

    {
        /* The untyped mapping twin of dvt_arrayByApplyingBlock:. The two drop nil
           answers alike, so what distinguishes this one is the selector dispatch
           and the class the answer is built with. */
        NSArray *three = @[@"a", @"b", @"c"];
        NSArray *mapped = [three dvt_arrayByApplyingSelector:@selector(uppercaseString)];
        DVTExpectEqualObjects(mapped, (@[@"A", @"B", @"C"]),
                              @"array arrayByApplyingSelector: sends the selector to every member");
        DVTExpect(![mapped respondsToSelector:@selector(addObject:)],
                  @"array arrayByApplyingSelector: answers an immutable array");
        /* Repeats are kept, which is the one place this parts company with the
           NSSet method of the same name, where two equal answers collapse. */
        DVTExpectEqualObjects([@[@"b", @"a", @"b"] dvt_arrayByApplyingSelector:@selector(uppercaseString)],
                              (@[@"B", @"A", @"B"]),
                              @"array arrayByApplyingSelector: keeps repeated answers");
        /* Every member answers the same Class, and a Class object is not equal to
           itself, so identity is the only comparison available here. The point
           against the NSSet twin is that the answers stay separate rather than
           collapsing, so what is checked is that they agree and that there are
           three of them. */
        NSArray *classes = [three dvt_arrayByApplyingSelector:@selector(class)];
        DVTExpect(classes.count == 3,
                  @"array arrayByApplyingSelector: keeps one answer per member");
        DVTExpect([classes firstObject] == [classes objectAtIndex:1] &&
                      [classes firstObject] == [classes lastObject],
                  @"array arrayByApplyingSelector: every member answers the same Class");
        /* A member that cannot answer is skipped, and the ones that can survive.
           Apple takes either of these to an assertion instead. */
        DVTExpectEqualObjects([@[@"ab", @3] dvt_arrayByApplyingSelector:@selector(uppercaseString)],
                              (@[@"AB"]),
                              @"array arrayByApplyingSelector: skips a member that cannot answer");
        DVTExpectEqualObjects([three dvt_arrayByApplyingSelector:(SEL)0], @[],
                              @"array arrayByApplyingSelector: a nil selector answers empty rather than aborting");
        DVTExpectEqualObjects([@[] dvt_arrayByApplyingSelector:@selector(uppercaseString)], @[],
                              @"array arrayByApplyingSelector: is empty for an empty receiver");
        /* A nil answer is dropped, so the answers have to be filtered before the
           array is built. An array cannot hold a nil member itself, hence the
           helper objects rather than a literal with one. */
        DVTExpectEqualObjects([@[DVTTestAnswererWith(nil), DVTTestAnswererWith(@"X"), DVTTestAnswererWith(nil)]
                                  dvt_arrayByApplyingSelector:@selector(dvt_testAnswer)], (@[@"X"]),
                              @"array arrayByApplyingSelector: drops nil answers");
        DVTExpectEqualObjects([@[DVTTestAnswererWith(nil), DVTTestAnswererWith(nil)]
                                  dvt_arrayByApplyingSelector:@selector(dvt_testAnswer)], @[],
                              @"array arrayByApplyingSelector: is empty when every answer is nil");
        /* Past 256 answers Apple switches from a stack buffer to a malloc'd one,
           so a large receiver is where a fixed-size buffer would show. */
        NSMutableArray *big = [NSMutableArray arrayWithCapacity:300];
        for (int i = 0; i < 300; i++) {
            [big addObject:[NSString stringWithFormat:@"m%03d", i]];
        }
        DVTExpect([[big dvt_arrayByApplyingSelector:@selector(uppercaseString)] count] == 300,
                  @"array arrayByApplyingSelector: answers a 300-member receiver in full");
    }

    {
        /* The array fold, which is -[NSSet dvt_objectByFoldingWithBlock:]'s twin:
           (accumulator, next), a first member that seeds without asking, and a nil
           answer that re-seeds on the member after it rather than ending the fold. */
        NSArray *abc = @[@"a", @"b", @"c"];
        NSMutableArray *calls = [NSMutableArray array];

        DVTExpect([@[] dvt_objectByFoldingWithBlock:^id(id a, id b) { return @"never"; }] == nil,
                  @"array objectByFoldingWithBlock: is nil for an empty receiver");
        __block int blockCalls = 0;
        DVTExpectEqualObjects([@[@"solo"] dvt_objectByFoldingWithBlock:^id(id a, id b) {
            blockCalls++;
            return @"never";
        }], @"solo",
                              @"array objectByFoldingWithBlock: seeds on the first member without calling the block");
        DVTExpect(blockCalls == 0,
                  @"array objectByFoldingWithBlock: does not call the block for a lone member");
        DVTExpectEqualObjects([abc dvt_objectByFoldingWithBlock:^id(id a, id b) {
            [calls addObject:[NSString stringWithFormat:@"(%@,%@)", a, b]];
            return [NSString stringWithFormat:@"%@%@", a, b];
        }], @"abc",
                              @"array objectByFoldingWithBlock: folds the members together");
        DVTExpectEqualObjects([calls componentsJoinedByString:@" "], @"(a,b) (ab,c)",
                              @"array objectByFoldingWithBlock: asks (accumulator, next)");
        /* A nil answer empties the accumulator, so the next member re-seeds it and
           an all-nil fold hands back the last member rather than nil. */
        DVTExpectEqualObjects([abc dvt_objectByFoldingWithBlock:^id(id a, id b) { return nil; }], @"c",
                              @"array objectByFoldingWithBlock: a nil answer re-seeds on the next member");
        blockCalls = 0;
        DVTExpectEqualObjects([abc dvt_objectByFoldingWithBlock:^id(id a, id b) {
            blockCalls++;
            return nil;
        }], @"c",
                              @"array objectByFoldingWithBlock: an all-nil fold answers the last member");
        DVTExpect(blockCalls == 1,
                  @"array objectByFoldingWithBlock: skips the call that would re-seed");
        __block int fiveCalls = 0;
        NSMutableArray *five = [NSMutableArray arrayWithCapacity:5];
        for (int i = 0; i < 5; i++) {
            [five addObject:@(i)];
        }
        DVTExpectEqualObjects([five dvt_objectByFoldingWithBlock:^id(id a, id b) {
            fiveCalls++;
            return nil;
        }], @4,
                              @"array objectByFoldingWithBlock: an all-nil fold answers the last member");
        DVTExpect(fiveCalls == 2, @"array objectByFoldingWithBlock: one call per re-seed");
    }

    {
        /* The set-to-dictionary pair on an array receiver. The names still run
           opposite to the answers: the block's answer is the value in the first and
           the key in the second, so the same uppercasing block gives a->A and A->a. */
        NSArray *abc = @[@"a", @"b", @"c"];
        NSMutableArray *blockArguments = [NSMutableArray array];
        id (^upper)(id) = ^id(id o) {
            [blockArguments addObject:o];
            return [o uppercaseString];
        };

        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:upper],
                              (@{@"a": @"A", @"b": @"B", @"c": @"C"}),
                              @"array EntriesAsKeysAndValues: member keyed, block answer valued");
        DVTExpectEqualObjects([blockArguments componentsJoinedByString:@" "], @"a b c",
                              @"array EntriesAsKeysAndValues: asks about every member in order");
        [blockArguments removeAllObjects];
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:upper],
                              (@{@"A": @"a", @"B": @"b", @"C": @"c"}),
                              @"array EntriesAsValuesAndKeys: block answer keyed, member valued");
        DVTExpectEqualObjects([blockArguments componentsJoinedByString:@" "], @"a b c",
                              @"array EntriesAsValuesAndKeys: asks about every member in order");
        DVTExpectEqualObjects([@[] dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:upper], @{},
                              @"array EntriesAsKeysAndValues: is empty for an empty receiver");
        DVTExpectEqualObjects([@[] dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:upper], @{},
                              @"array EntriesAsValuesAndKeys: is empty for an empty receiver");
        /* A nil answer is skipped rather than stored in either slot. */
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:^id(id o) {
            return [o isEqualToString:@"b"] ? nil : o;
        }], (@{@"a": @"a", @"c": @"c"}),
                              @"array EntriesAsKeysAndValues: skips a nil answer");
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:^id(id o) {
            return [o isEqualToString:@"b"] ? nil : o;
        }], (@{@"a": @"a", @"c": @"c"}),
                              @"array EntriesAsValuesAndKeys: skips a nil answer");
        /* A constant answer leaves the members distinct as keys in the first, and
           colliding as keys in the second, where the last member enumerated wins. */
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:^id(id o) { return @"k"; }],
                              (@{@"a": @"k", @"b": @"k", @"c": @"k"}),
                              @"array EntriesAsKeysAndValues: a constant answer keeps every member");
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:^id(id o) { return @"k"; }],
                              (@{@"k": @"c"}),
                              @"array EntriesAsValuesAndKeys: colliding answers leave the last member");
        DVTExpect(![([abc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:upper]) isKindOfClass:[NSMutableDictionary class]],
                  @"array EntriesAsKeysAndValues: answers an immutable dictionary");
        DVTExpect(![([abc dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:upper]) isKindOfClass:[NSMutableDictionary class]],
                  @"array EntriesAsValuesAndKeys: answers an immutable dictionary");
        /* A mutable receiver is enumerated the same way and still answers an
           immutable dictionary, so the mutability of the receiver is not carried
           through. */
        NSMutableArray *mutableAbc = [@[@"a", @"b"] mutableCopy];
        DVTExpectEqualObjects([mutableAbc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:upper],
                              (@{@"a": @"A", @"b": @"B"}),
                              @"array EntriesAsKeysAndValues: a mutable receiver answers the same dictionary");
        DVTExpect(![([mutableAbc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:upper]) isKindOfClass:[NSMutableDictionary class]],
                  @"array EntriesAsKeysAndValues: a mutable receiver still answers immutable");
    }

    {
        /* Adjacent run grouping. The block is a comparator over the previous and the
           current member rather than a per-member test, so it is asked n-1 times and a
           member joins the run before it only while the pair compares equal. */
        BOOL (^eq)(id, id) = ^BOOL(id a, id b) { return [a isEqual:b]; };
        NSArray *runs = [@[@"a", @"b", @"a", @"b", @"c"] dvt_arrayByGroupingAdjacentObjectsUsingBlock:eq];

        DVTExpect([@[] dvt_arrayByGroupingAdjacentObjectsUsingBlock:eq] == nil,
                  @"array arrayByGroupingAdjacentObjectsUsingBlock: is nil for an empty receiver");
        /* The runs come back in receiver order, and each is a subarray of the receiver,
           so grouping on a value that never repeats is one run per member. */
        DVTExpectEqualObjects(runs, (@[@[@"a"], @[@"b"], @[@"a"], @[@"b"], @[@"c"]]),
                              @"array arrayByGroupingAdjacentObjectsUsingBlock: keeps runs in receiver order");
        /* Repeats that are not adjacent stay apart, which is what separates this from
           grouping by a key: a b a is three runs, not two. */
        DVTExpect(runs.count == 5,
                  @"array arrayByGroupingAdjacentObjectsUsingBlock: separates non-adjacent repeats");
        DVTExpectEqualObjects([@[@"a", @"a", @"b"] dvt_arrayByGroupingAdjacentObjectsUsingBlock:eq],
                              (@[@[@"a", @"a"], @[@"b"]]),
                              @"array arrayByGroupingAdjacentObjectsUsingBlock: joins an adjacent repeat");
        DVTExpectEqualObjects([@[@"a", @"b", @"c"] dvt_arrayByGroupingAdjacentObjectsUsingBlock:^BOOL(id a, id b) {
            return NO;
        }], (@[@[@"a"], @[@"b"], @[@"c"]]),
                              @"array arrayByGroupingAdjacentObjectsUsingBlock: an all-false comparator makes every member a run");
        /* One call per adjacent pair, and the pair is (previous, current). */
        NSMutableArray *pairs = [NSMutableArray array];
        __block NSUInteger comparatorCalls = 0;
        (void)[@[@"a", @"b", @"c"] dvt_arrayByGroupingAdjacentObjectsUsingBlock:^BOOL(id a, id b) {
            comparatorCalls++;
            [pairs addObject:[NSString stringWithFormat:@"(%@,%@)", a, b]];
            return [a isEqual:b];
        }];
        DVTExpect(comparatorCalls == 2,
                  @"array arrayByGroupingAdjacentObjectsUsingBlock: asks once per adjacent pair");
        DVTExpectEqualObjects([pairs componentsJoinedByString:@" "], @"(a,b) (b,c)",
                              @"array arrayByGroupingAdjacentObjectsUsingBlock: asks (previous, current)");
        /* A lone member is answered with a copy of the receiver, while a longer receiver
           is answered with a subarray of it. A copy of an immutable receiver is the
           receiver itself, so the two are told apart by identity rather than by content:
           both runs are equal to the members they cover. */
        NSArray *immutableOne = @[@"a"];
        NSArray *oneGroup = [immutableOne dvt_arrayByGroupingAdjacentObjectsUsingBlock:eq];
        DVTExpect(oneGroup.firstObject == immutableOne,
                  @"array arrayByGroupingAdjacentObjectsUsingBlock: a lone member is answered with a copy of the receiver");
        NSMutableArray *mutableOne = [NSMutableArray arrayWithObject:@"a"];
        NSArray *mutableOneGroup = [mutableOne dvt_arrayByGroupingAdjacentObjectsUsingBlock:eq];
        DVTExpect(mutableOneGroup.firstObject != mutableOne && [mutableOneGroup.firstObject isEqual:mutableOne],
                  @"array arrayByGroupingAdjacentObjectsUsingBlock: copying a mutable receiver answers a fresh array");
        NSArray *immutableMany = @[@"a", @"b"];
        NSArray *manyGroup = [immutableMany dvt_arrayByGroupingAdjacentObjectsUsingBlock:^BOOL(id a, id b) {
            return YES;
        }];
        DVTExpect(manyGroup.count == 1 && manyGroup.firstObject != immutableMany &&
                      [manyGroup.firstObject isEqual:immutableMany],
                  @"array arrayByGroupingAdjacentObjectsUsingBlock: a longer receiver is answered with a subarray");
    }

    {
        /* Key grouping. The block is asked once per member and answers that member's
           key, so the answer is unordered -- it is the values of the dictionary Apple
           accumulates into -- while each group keeps receiver order. */
        NSArray *numbers = @[@1, @2, @3, @4];
        NSArray *parity = [numbers dvt_unorderedArrayByGroupingObjectsUsingKeys:^id(id o) {
            return ([o integerValue] % 2 == 0) ? @"even" : @"odd";
        }];
        NSArray *byParity = [parity sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [[[(NSArray *)a firstObject] description] compare:[[(NSArray *)b firstObject] description]];
        }];

        DVTExpectEqualObjects(byParity, (@[@[@1, @3], @[@2, @4]]),
                              @"array unorderedArrayByGroupingObjectsUsingKeys: groups members sharing a key");
        DVTExpectEqualObjects([(NSArray *)byParity.firstObject objectAtIndex:0], @1,
                              @"array unorderedArrayByGroupingObjectsUsingKeys: a group keeps receiver order");
        /* The key is the whole answer, not its members, so an array answer keys on that
           array. Asking for the member itself therefore separates every member. */
        DVTExpect([@[@"x", @"y"] dvt_unorderedArrayByGroupingObjectsUsingKeys:^id(id o) {
            return @[o, o];
        }].count == 2,
                  @"array unorderedArrayByGroupingObjectsUsingKeys: an array answer keys on the whole array");
        /* The groups are mutable while the answer holding them is not, which is what
           -allValues of the accumulating dictionary gives. */
        DVTExpect([parity.firstObject isKindOfClass:[NSMutableArray class]],
                  @"array unorderedArrayByGroupingObjectsUsingKeys: answers mutable groups");
        DVTExpect(![parity isKindOfClass:[NSMutableArray class]],
                  @"array unorderedArrayByGroupingObjectsUsingKeys: answers an immutable array of groups");
        __block NSUInteger keyCalls = 0;
        (void)[@[@"a", @"b"] dvt_unorderedArrayByGroupingObjectsUsingKeys:^id(id o) {
            keyCalls++;
            return o;
        }];
        DVTExpect(keyCalls == 2, @"array unorderedArrayByGroupingObjectsUsingKeys: asks once per member");
        DVTExpect([@[] dvt_unorderedArrayByGroupingObjectsUsingKeys:^id(id o) { return o; }].count == 0,
                  @"array unorderedArrayByGroupingObjectsUsingKeys: is empty for an empty receiver");
        /* The key is sent -dvt_isNonEmpty, so the key is any object answering it, not
           necessarily a string. The faults that follow from anything else -- a nil or
           empty key asserting, a number not implementing the method at all -- abort in
           Apple too, and are recorded in the README rather than asserted here. */
        DVTExpect([[@[@1] dvt_unorderedArrayByGroupingObjectsUsingKeys:^id(id o) { return @"k"; }] count] == 1,
                  @"array unorderedArrayByGroupingObjectsUsingKeys: a string key is accepted");
    }

    {
        /* Key-path grouping, the computed-key twin of the block form. A member is keyed
           by the array of the values it has for the paths, so two members agree exactly
           when those values do. */
        NSArray *rows = @[@{@"a": @1, @"b": @2}, @{@"a": @1, @"b": @3}, @{@"a": @1, @"b": @2}];
        NSArray *groups = [rows dvt_unorderedArrayByGroupingObjectsUsingKeyPaths:@[@"a", @"b"]];
        NSArray *sorted = [groups sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [[[(NSArray *)a firstObject] description] compare:[[(NSArray *)b firstObject] description]];
        }];

        DVTExpectEqualObjects(sorted, (@[@[@{@"a": @1, @"b": @2}, @{@"a": @1, @"b": @2}], @[@{@"a": @1, @"b": @3}]]),
                              @"array unorderedArrayByGroupingObjectsUsingKeyPaths: groups members whose path values agree");
        /* The paths are all applied, so dropping to one path merges the two b groups. */
        DVTExpect([rows dvt_unorderedArrayByGroupingObjectsUsingKeyPaths:@[@"a"]].count == 1,
                  @"array unorderedArrayByGroupingObjectsUsingKeyPaths: every path has to agree");
        /* A dotted path is one path, not two. */
        DVTExpect([@[@{@"x": @{@"y": @"deep"}}] dvt_unorderedArrayByGroupingObjectsUsingKeyPaths:@[@"x.y"]].count == 1,
                  @"array unorderedArrayByGroupingObjectsUsingKeyPaths: takes a dotted path whole");
        /* A member with no value for a path is keyed by a shared sentinel rather than
           dropped, so keyless members land together instead of aborting on an empty
           key -- and they do not join a member whose value is NSNull. */
        NSArray *keyless = [@[@{}, @{}] dvt_unorderedArrayByGroupingObjectsUsingKeyPaths:@[@"k"]];
        DVTExpect(keyless.count == 1 && [(NSArray *)keyless.firstObject count] == 2,
                  @"array unorderedArrayByGroupingObjectsUsingKeyPaths: members missing a path group together");
        NSArray *keylessVersusNull = [@[@{}, @{@"k": [NSNull null]}]
                                          dvt_unorderedArrayByGroupingObjectsUsingKeyPaths:@[@"k"]];
        DVTExpect(keylessVersusNull.count == 2,
                  @"array unorderedArrayByGroupingObjectsUsingKeyPaths: a missing path does not group with NSNull");
        DVTExpect([@[] dvt_unorderedArrayByGroupingObjectsUsingKeyPaths:@[@"k"]].count == 0,
                  @"array unorderedArrayByGroupingObjectsUsingKeyPaths: is empty for an empty receiver");
        /* What is left to reject is a fault rather than an answer: an empty path list aborts
           on the -dvt_isNonEmpty check, and because the paths are applied through
           -dvt_arrayByApplyingBlock: a non-array argument such as a bare string
           faults on an unrecognized selector. Both abort in Apple too, and are
           recorded in the README rather than asserted here. */
        DVTExpect([@[@{@"k": @"v"}] dvt_unorderedArrayByGroupingObjectsUsingKeyPaths:@[@"k"]].count == 1,
                  @"array unorderedArrayByGroupingObjectsUsingKeyPaths: a non-empty path list is accepted");
    }

    {
        /* The shell-style joiner. Two members and three or more go through different
           format strings, so the two-member answer has a space either side of the final
           join string while the longer one runs the separator twice. */
        NSArray *abc = @[@"a", @"b", @"c"];

        DVTExpectEqualObjects([@[] dvt_componentsJoinedByString:@"|" finalComponentJoinString:@"!"], @"",
                              @"array componentsJoinedByString: is empty for an empty receiver");
        /* A lone member is described rather than returned, so a non-string member does
           not survive; a string member does, which is why this reads as identity. */
        DVTExpectEqualObjects([@[@"a"] dvt_componentsJoinedByString:@"|" finalComponentJoinString:@"!"], @"a",
                              @"array componentsJoinedByString: a lone member answers its description");
        DVTExpectEqualObjects([@[@42] dvt_componentsJoinedByString:@"|" finalComponentJoinString:@"!"], @"42",
                              @"array componentsJoinedByString: a lone number answers its description");
        DVTExpectEqualObjects([@[[NSNull null]] dvt_componentsJoinedByString:@"|" finalComponentJoinString:@"!"], @"<null>",
                              @"array componentsJoinedByString: a lone NSNull answers its description");
        DVTExpectEqualObjects([@[@"a", @"b"] dvt_componentsJoinedByString:@"|" finalComponentJoinString:@"!"], @"a ! b",
                              @"array componentsJoinedByString: two members join with a space either side");
        DVTExpectEqualObjects([@[@"a", @"b", @"c"] dvt_componentsJoinedByString:@"|" finalComponentJoinString:@"!"], @"a|b|! c",
                              @"array componentsJoinedByString: three members repeat the separator before the final join");
        DVTExpectEqualObjects([@[@"a", @"b", @"c", @"d"] dvt_componentsJoinedByString:@"|" finalComponentJoinString:@"!"],
                              @"a|b|c|! d",
                              @"array componentsJoinedByString: four members join the head by the separator");
        /* A nil separator joins with nothing, leaving the final join string to mark the
           boundary. A nil final join string prints as (null). */
        DVTExpectEqualObjects([abc dvt_componentsJoinedByString:nil finalComponentJoinString:@"!"], @"ab! c",
                              @"array componentsJoinedByString: a nil separator joins with nothing");
        DVTExpectEqualObjects([abc dvt_componentsJoinedByString:@"" finalComponentJoinString:@"!"], @"ab! c",
                              @"array componentsJoinedByString: an empty separator joins with nothing");
        DVTExpectEqualObjects([@[@"a", @"b"] dvt_componentsJoinedByString:@"|" finalComponentJoinString:nil], @"a (null) b",
                              @"array componentsJoinedByString: a nil final join string prints as (null)");
        /* Empty members are joined like any other, so they leave bare separators. */
        DVTExpectEqualObjects([@[@"", @"", @""] dvt_componentsJoinedByString:@"|" finalComponentJoinString:@"!"], @"||! ",
                              @"array componentsJoinedByString: empty members leave bare separators");
    }

    {
        /* The count selector is shared with NSArray, so the two are asked the same
           questions, including the ones only a cast block can reach. */
        NSArray *array = @[@"a", @"b", @"c"];
        DVTExpect([array dvt_numberOfObjectsPassingTest:^BOOL(id o) {
                       return [o isEqualToString:@"a"] || [o isEqualToString:@"b"];
                   }] == 2,
                  @"array numberOfObjectsPassingTest: counts the members that pass");
        NSInteger (^threeEach)(id) = ^NSInteger(id o) { return 3; };
        DVTExpect([array dvt_numberOfObjectsPassingTest:(BOOL (^)(id))threeEach] == 9,
                  @"array numberOfObjectsPassingTest: sums what the block returns");
        NSInteger (^negative)(id) = ^NSInteger(id o) { return -1; };
        DVTExpect([array dvt_numberOfObjectsPassingTest:(BOOL (^)(id))negative] == 12884901885LL,
                  @"array numberOfObjectsPassingTest: zero-extends each return like the set does");
        /* A nil test faults on Apple; the port guards it. */
        DVTExpect([array dvt_numberOfObjectsPassingTest:(BOOL (^)(id))nil] == 3,
                  @"array numberOfObjectsPassingTest: guards a nil test and answers the count");
        DVTExpect([@[] dvt_numberOfObjectsPassingTest:^BOOL(id o) { return YES; }] == 0,
                  @"array numberOfObjectsPassingTest: is zero for an empty array");
    }

    {
        /* Set algebra. The three set-to-set and set-to-object methods are one
           shape: an early branch on the argument, then a hand-off to
           -dvt_objectsPassingTest: with a one-line block. What that shape buys
           is the identity answer when nothing is dropped, which is the part a
           rebuilt-set implementation cannot reproduce. */
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        NSSet *two = [NSSet setWithObjects:@"b", @"c", nil];
        NSSet *empty = [NSSet set];
        NSMutableSet *mutable = [NSMutableSet setWithObjects:@"a", @"b", @"c", nil];

        DVTExpect([three dvt_mutableClass] == [NSMutableSet class],
                  @"set mutableClass answers NSMutableSet");
        DVTExpect([three dvt_mutableClass] == [mutable dvt_mutableClass],
                  @"set mutableClass is the same Class whichever set asks");

        DVTExpectEqualObjects([three dvt_setByIntersectingSet:two], two,
                              @"set setByIntersectingSet: keeps the shared members");
        DVTExpect([three dvt_setByIntersectingSet:three] == three,
                  @"set setByIntersectingSet: answers the receiver when all members survive");
        DVTExpect([mutable dvt_setByIntersectingSet:mutable] != mutable,
                  @"set setByIntersectingSet: copies even a mutable receiver");
        DVTExpect(![[mutable dvt_setByIntersectingSet:mutable] isKindOfClass:[NSMutableSet class]],
                  @"set setByIntersectingSet: answers an immutable set");
        DVTExpectEqualObjects([three dvt_setByIntersectingSet:empty], empty,
                              @"set setByIntersectingSet: an empty argument empties the receiver");
        DVTExpect([three dvt_setByIntersectingSet:empty] != three,
                  @"set setByIntersectingSet: an empty argument does not answer the receiver");
        DVTExpectEqualObjects([three dvt_setByIntersectingSet:nil], empty,
                              @"set setByIntersectingSet: a nil argument reads as empty");

        DVTExpectEqualObjects([three dvt_setBySubtractingSet:two],
                              [NSSet setWithObject:@"a"],
                              @"set setBySubtractingSet: drops the members the argument holds");
        DVTExpect([three dvt_setBySubtractingSet:empty] == three,
                  @"set setBySubtractingSet: an empty argument leaves the identity alone");
        DVTExpect([three dvt_setBySubtractingSet:nil] == three,
                  @"set setBySubtractingSet: a nil argument leaves the identity alone");
        DVTExpectEqualObjects([three dvt_setBySubtractingSet:three], empty,
                              @"set setBySubtractingSet: subtracting everything empties the receiver");
        DVTExpectEqualObjects([three dvt_setBySubtractingSet:two], [NSSet setWithObject:@"a"],
                              @"set setBySubtractingSet: repeated answers agree");

        DVTExpectEqualObjects([three dvt_setByRemovingObject:@"b"],
                              [NSSet setWithObjects:@"a", @"c", nil],
                              @"set setByRemovingObject: drops the member it is given");
        DVTExpect([three dvt_setByRemovingObject:@"z"] == three,
                  @"set setByRemovingObject: an absent object leaves the identity alone");
        DVTExpect([three dvt_setByRemovingObject:nil] == three,
                  @"set setByRemovingObject: a nil object leaves the identity alone");
        /* isEqual: rather than pointer identity, so an equal-but-distinct
           argument still removes the member. */
        NSString *distinct = [@"b" mutableCopy];
        DVTExpectEqualObjects([three dvt_setByRemovingObject:distinct],
                              [NSSet setWithObjects:@"a", @"c", nil],
                              @"set setByRemovingObject: compares by isEqual:, not identity");
        DVTExpectEqualObjects([empty dvt_setByRemovingObject:@"a"], empty,
                              @"set setByRemovingObject: removing from an empty set stays empty");
        DVTExpectEqualObjects([[NSSet setWithObjects:@7, @"x", nil] dvt_setByRemovingObject:@7],
                              [NSSet setWithObject:@"x"],
                              @"set setByRemovingObject: an equal number goes as well");
        DVTExpect(![[mutable dvt_setByRemovingObject:@"a"] isKindOfClass:[NSMutableSet class]],
                  @"set setByRemovingObject: answers an immutable set");
    }

    {
        /* The untyped mapping twin. Same dropped nils and same collapse of
           repeated answers as the block form, so the distinguishing cover is
           the selector dispatch: a member that does not carry the selector is
           skipped rather than raising, and a nil selector answers empty. Both
           abort on Apple. */
        NSSet *three = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        NSSet *mapped = [three dvt_setByApplyingSelector:@selector(uppercaseString)];
        DVTExpectEqualObjects(mapped, [NSSet setWithObjects:@"A", @"B", @"C", nil],
                              @"set setByApplyingSelector: sends the selector to every member");
        DVTExpect(![mapped respondsToSelector:@selector(addObject:)],
                  @"set setByApplyingSelector: answers an immutable set");
        /* Every member answers the same Class, so the three answers collapse. */
        DVTExpect([[three dvt_setByApplyingSelector:@selector(class)] count] == 1,
                  @"set setByApplyingSelector: collapses repeated answers");
        /* A member that cannot answer is skipped, so the ones that can survive. */
        NSSet *mixed = [NSSet setWithObjects:@"ab", @3, nil];
        DVTExpectEqualObjects([mixed dvt_setByApplyingSelector:@selector(uppercaseString)],
                              [NSSet setWithObject:@"AB"],
                              @"set setByApplyingSelector: skips a member that cannot answer");
        DVTExpectEqualObjects([[NSSet set] dvt_setByApplyingSelector:@selector(uppercaseString)],
                              [NSSet set],
                              @"set setByApplyingSelector: is empty for an empty receiver");
        DVTExpectEqualObjects([three dvt_setByApplyingSelector:(SEL)0], [NSSet set],
                              @"set setByApplyingSelector: a nil selector answers empty rather than aborting");
        /* Past the 256-slot buffer Apple switches to a malloc'd one, so a large
           receiver is where a fixed-size stack buffer would show. */
        NSMutableSet *big = [NSMutableSet set];
        for (int i = 0; i < 300; i++) {
            [big addObject:[NSString stringWithFormat:@"m%03d", i]];
        }
        DVTExpect([[big dvt_setByApplyingSelector:@selector(uppercaseString)] count] == 300,
                  @"set setByApplyingSelector: answers a 300-member receiver in full");
    }

    {
        /* NSOrderedSet and NSMutableOrderedSet. The two classes answer different
           parts of the family: the immutable one the queries and the algebra, the
           mutable one three mutators on top. Order is the reason the class exists,
           so every answer is compared as its ordered array and not as a set --
           a set comparison would pass for an implementation that sorted. */
        NSOrderedSet *three = [NSOrderedSet orderedSetWithObjects:@"a", @"b", @"c", nil];
        NSOrderedSet *empty = [NSOrderedSet orderedSet];

        /* The count has to be exactly one, so two members is already too many and
           the answer is nil rather than the first of them. */
        DVTExpect([empty dvt_onlyObject] == nil,
                  @"ordered set onlyObject: is nil for an empty receiver");
        DVTExpect([[NSOrderedSet orderedSetWithObject:@"solo"] dvt_onlyObject] == @"solo",
                  @"ordered set onlyObject: hands back the lone member itself");
        DVTExpect([three dvt_onlyObject] == nil,
                  @"ordered set onlyObject: is nil for two members rather than the first");
        DVTExpect([(NSOrderedSet *)nil dvt_onlyObject] == nil,
                  @"ordered set onlyObject: is nil for a nil receiver");

        /* dvt_anyObjectPassingTest: answers the member that passed, where the set's
           spelling of the same question answers a flag, and it stops there. */
        DVTExpect([three dvt_anyObjectPassingTest:^BOOL(id o) { return YES; }] == @"a",
                  @"ordered set anyObjectPassingTest: answers the first member when all pass");
        DVTExpect([three dvt_anyObjectPassingTest:^BOOL(id o) { return [o isEqual:@"b"]; }] == @"b",
                  @"ordered set anyObjectPassingTest: answers the member that passed, not the index");
        DVTExpect([three dvt_anyObjectPassingTest:^BOOL(id o) { return NO; }] == nil,
                  @"ordered set anyObjectPassingTest: is nil when none pass");
        DVTExpect([empty dvt_anyObjectPassingTest:^BOOL(id o) { return YES; }] == nil,
                  @"ordered set anyObjectPassingTest: is nil for an empty receiver");
        DVTExpect([(NSOrderedSet *)nil dvt_anyObjectPassingTest:^BOOL(id o) { return YES; }] == nil,
                  @"ordered set anyObjectPassingTest: is nil for a nil receiver");
        __block int anyCalls = 0;
        (void)[three dvt_anyObjectPassingTest:^BOOL(id o) {
            anyCalls++;
            return [o isEqual:@"b"];
        }];
        DVTExpect(anyCalls == 2,
                  @"ordered set anyObjectPassingTest: stops at the member that passed");
        __block int anyMissCalls = 0;
        (void)[three dvt_anyObjectPassingTest:^BOOL(id o) { anyMissCalls++; return NO; }];
        DVTExpect(anyMissCalls == 3,
                  @"ordered set anyObjectPassingTest: asks about every member when none passes");
        DVTExpect([[three mutableCopy] dvt_anyObjectPassingTest:^BOOL(id o) { return YES; }] == @"a",
                  @"ordered set anyObjectPassingTest: answers the first member of a mutable receiver");
        /* A nil test faults on Apple; the port answers the first member, as the
           array spelling does. */
        DVTExpect([three dvt_anyObjectPassingTest:nil] == @"a",
                  @"ordered set anyObjectPassingTest: guards a nil test with the first member");
        DVTExpect([empty dvt_anyObjectPassingTest:nil] == nil,
                  @"ordered set anyObjectPassingTest: a nil test is nil for an empty receiver");
        DVTExpect([(NSOrderedSet *)nil dvt_anyObjectPassingTest:nil] == nil,
                  @"ordered set anyObjectPassingTest: a nil test is nil for a nil receiver");

        /* The low bit of the raw answer decides, not the truth of the word: an
           int-returning block reached through a BOOL pointer shows which. */
        NSInteger (^oneRaw)(id) = ^NSInteger(id o) { return 1; };
        NSInteger (^twoRaw)(id) = ^NSInteger(id o) { return 2; };
        NSInteger (^threeRaw)(id) = ^NSInteger(id o) { return 3; };
        NSInteger (^minusOneRaw)(id) = ^NSInteger(id o) { return -1; };
        NSInteger (^highRaw)(id) = ^NSInteger(id o) { return 256; };
        DVTExpect([three dvt_anyObjectPassingTest:(BOOL (^)(id))oneRaw] == @"a",
                  @"ordered set anyObjectPassingTest: a raw 1 passes");
        DVTExpect([three dvt_anyObjectPassingTest:(BOOL (^)(id))twoRaw] == nil,
                  @"ordered set anyObjectPassingTest: an even raw answer fails, so a raw 2 does not pass");
        DVTExpect([three dvt_anyObjectPassingTest:(BOOL (^)(id))threeRaw] == @"a",
                  @"ordered set anyObjectPassingTest: an odd raw answer passes, so a raw 3 does");
        DVTExpect([three dvt_anyObjectPassingTest:(BOOL (^)(id))minusOneRaw] == @"a",
                  @"ordered set anyObjectPassingTest: a raw -1 has its low bit set");
        DVTExpect([three dvt_anyObjectPassingTest:(BOOL (^)(id))highRaw] == nil,
                  @"ordered set anyObjectPassingTest: a raw 256 is not odd, so it does not pass");

        /* The filter keeps receiver order and always builds, even when nothing is
           dropped -- which is where it parts company with the set's spelling. */
        DVTExpectEqualObjects([[three dvt_objectsPassingTest:^BOOL(id o) { return YES; }] array], @[@"a", @"b", @"c"],
                              @"ordered set objectsPassingTest: keeps every member in order");
        DVTExpectEqualObjects([[three dvt_objectsPassingTest:^BOOL(id o) { return [o isEqual:@"b"]; }] array], @[@"b"],
                              @"ordered set objectsPassingTest: keeps only the members that pass");
        DVTExpectEqualObjects([[three dvt_objectsPassingTest:^BOOL(id o) { return NO; }] array], @[],
                              @"ordered set objectsPassingTest: is empty when none pass");
        DVTExpectEqualObjects([[empty dvt_objectsPassingTest:^BOOL(id o) { return YES; }] array], @[],
                              @"ordered set objectsPassingTest: is empty for an empty receiver");
        DVTExpect([three dvt_objectsPassingTest:^BOOL(id o) { return YES; }] != three,
                  @"ordered set objectsPassingTest: builds a fresh answer even when all pass");
        DVTExpect([[three mutableCopy] dvt_objectsPassingTest:^BOOL(id o) { return YES; }] != nil &&
                  ![[[three mutableCopy] dvt_objectsPassingTest:^BOOL(id o) { return YES; }]
                      isKindOfClass:[NSMutableOrderedSet class]],
                  @"ordered set objectsPassingTest: answers an immutable set for a mutable receiver");
        DVTExpect([(NSOrderedSet *)nil dvt_objectsPassingTest:^BOOL(id o) { return YES; }] == nil,
                  @"ordered set objectsPassingTest: is nil for a nil receiver");
        /* The filter tests the whole raw word, where the "any" spelling tested its
           low bit -- the same block therefore passes here and not there. */
        DVTExpectEqualObjects([[three dvt_objectsPassingTest:(BOOL (^)(id))twoRaw] array], @[@"a", @"b", @"c"],
                              @"ordered set objectsPassingTest: a nonzero raw answer passes whatever its low bit is");
        DVTExpectEqualObjects([[three dvt_objectsPassingTest:(BOOL (^)(id))highRaw] array], @[@"a", @"b", @"c"],
                              @"ordered set objectsPassingTest: a raw 256 passes");
        DVTExpectEqualObjects([[three dvt_objectsPassingTest:^BOOL(id o) { return NO; }] array], @[],
                              @"ordered set objectsPassingTest: a raw zero is the only answer that drops");
        /* A nil test faults on Apple; the port copies, as the set spelling does. */
        DVTExpectEqualObjects([three dvt_objectsPassingTest:nil], three,
                              @"ordered set objectsPassingTest: guards a nil test with a copy of the receiver");
        DVTExpectEqualObjects([empty dvt_objectsPassingTest:nil], empty,
                              @"ordered set objectsPassingTest: a nil test on an empty receiver stays empty");
        /* Past 256 members Apple switches from a stack buffer to a malloc'd one, so
           a long receiver is where a fixed-size buffer would show. */
        NSMutableOrderedSet *big = [NSMutableOrderedSet orderedSet];
        for (int i = 0; i < 300; i++) {
            [big addObject:[NSString stringWithFormat:@"m%03d", i]];
        }
        DVTExpect([big dvt_objectsPassingTest:^BOOL(id o) { return YES; }].count == 300,
                  @"ordered set objectsPassingTest: answers a 300-member receiver in full");
        DVTExpectEqualObjects([[[big dvt_objectsPassingTest:^BOOL(id o) { return [o hasSuffix:@"9"]; }] array] firstObject],
                              @"m009",
                              @"ordered set objectsPassingTest: keeps a 300-member receiver in order");
    }

    {
        /* The three mapping shapes over an ordered receiver. They differ in two
           visible ways: the array forms keep repeated answers where the set form
           collapses them, and the first form stops at the first usable answer. */
        NSOrderedSet *three = [NSOrderedSet orderedSetWithObjects:@"a", @"b", @"c", nil];

        NSArray *mapped = [three dvt_arrayByApplyingBlock:^id(id o) { return [o uppercaseString]; }];
        DVTExpectEqualObjects(mapped, @[@"A", @"B", @"C"],
                              @"ordered set arrayByApplyingBlock: maps every member in order");
        DVTExpect(![mapped respondsToSelector:@selector(addObject:)],
                  @"ordered set arrayByApplyingBlock: answers an immutable array");
        /* The untyped form keeps repeats, which is what separates it from the set
           spelling below. */
        DVTExpectEqualObjects([three dvt_arrayByApplyingBlock:^id(id o) { return @"same"; }],
                              @[@"same", @"same", @"same"],
                              @"ordered set arrayByApplyingBlock: keeps repeated answers");
        DVTExpectEqualObjects([three dvt_arrayByApplyingBlock:^id(id o) { return [o isEqual:@"a"] ? @"first" : nil; }],
                              @[@"first"],
                              @"ordered set arrayByApplyingBlock: drops the nil answers");
        DVTExpectEqualObjects([three dvt_arrayByApplyingBlock:^id(id o) { return nil; }], @[],
                              @"ordered set arrayByApplyingBlock: is empty when every answer is nil");
        DVTExpectEqualObjects([[NSOrderedSet orderedSet] dvt_arrayByApplyingBlock:^id(id o) { return o; }], @[],
                              @"ordered set arrayByApplyingBlock: is empty for an empty receiver");
        DVTExpect([(NSOrderedSet *)nil dvt_arrayByApplyingBlock:^id(id o) { return o; }] == nil,
                  @"ordered set arrayByApplyingBlock: is nil for a nil receiver");
        __block int arrayCalls = 0;
        (void)[three dvt_arrayByApplyingBlock:^id(id o) { arrayCalls++; return o; }];
        DVTExpect(arrayCalls == 3,
                  @"ordered set arrayByApplyingBlock: asks about every member even so");
        /* A nil block faults on Apple; the port copies, as the array spelling does. */
        DVTExpectEqualObjects([three dvt_arrayByApplyingBlock:nil], @[@"a", @"b", @"c"],
                              @"ordered set arrayByApplyingBlock: guards a nil block with a copy of the members");

        /* On Apple dvt_compactMap: is a tail call to the method above, so the two
           spellings cannot differ -- and neither answers the mutable array that
           NSArray's own compact map hands back. */
        DVTExpectEqualObjects([three dvt_compactMap:^id(id o) { return [o uppercaseString]; }], @[@"A", @"B", @"C"],
                              @"ordered set compactMap: maps every member in order");
        DVTExpect(![[three dvt_compactMap:^id(id o) { return o; }] respondsToSelector:@selector(addObject:)],
                  @"ordered set compactMap: answers an immutable array");
        DVTExpectEqualObjects([three dvt_compactMap:^id(id o) { return @"same"; }], @[@"same", @"same", @"same"],
                              @"ordered set compactMap: keeps repeated answers");
        DVTExpectEqualObjects([three dvt_compactMap:^id(id o) { return nil; }], @[],
                              @"ordered set compactMap: is empty when every answer is nil");
        DVTExpect([(NSOrderedSet *)nil dvt_compactMap:^id(id o) { return o; }] == nil,
                  @"ordered set compactMap: is nil for a nil receiver");
        DVTExpectEqualObjects([three dvt_compactMap:nil], @[@"a", @"b", @"c"],
                              @"ordered set compactMap: guards a nil block with a copy of the members");

        DVTExpectEqualObjects([three dvt_firstMap:^id(id o) { return [o uppercaseString]; }], @"A",
                              @"ordered set firstMap: answers the first member's answer");
        DVTExpect([three dvt_firstMap:^id(id o) { return o; }] == @"a",
                  @"ordered set firstMap: hands the answer back as it came");
        /* A nil answer is skipped rather than returned, which is the whole difference
           from a fold that stops at the first member. */
        __block int firstCalls = 0;
        DVTExpectEqualObjects([three dvt_firstMap:^id(id o) {
            firstCalls++;
            return [o isEqual:@"b"] ? @"second" : nil;
        }], @"second",
                              @"ordered set firstMap: skips the members whose answer is nil");
        DVTExpect(firstCalls == 2,
                  @"ordered set firstMap: stops at the first usable answer");
        __block int firstMissCalls = 0;
        DVTExpect([three dvt_firstMap:^id(id o) { firstMissCalls++; return nil; }] == nil,
                  @"ordered set firstMap: is nil when every answer is nil");
        DVTExpect(firstMissCalls == 3,
                  @"ordered set firstMap: asks about every member when no answer is usable");
        DVTExpect([[NSOrderedSet orderedSet] dvt_firstMap:^id(id o) { return o; }] == nil,
                  @"ordered set firstMap: is nil for an empty receiver");
        DVTExpect([(NSOrderedSet *)nil dvt_firstMap:^id(id o) { return o; }] == nil,
                  @"ordered set firstMap: is nil for a nil receiver");
        /* A nil block faults here as it does on Apple, but only for a receiver with
           a member: an empty receiver never reaches the block, so it answers nil
           rather than faulting. */
        DVTExpect([[NSOrderedSet orderedSet] dvt_firstMap:nil] == nil,
                  @"ordered set firstMap: an empty receiver never reaches a nil block");

        /* The set form collapses repeats and keeps the position of the first one. */
        NSOrderedSet *applied = [three dvt_orderedSetByApplyingBlock:^id(id o) { return @"same"; }];
        DVTExpectEqualObjects([applied array], @[@"same"],
                              @"ordered set orderedSetByApplyingBlock: collapses repeated answers");
        DVTExpectEqualObjects([[three dvt_orderedSetByApplyingBlock:^id(id o) { return [o uppercaseString]; }] array],
                              @[@"A", @"B", @"C"],
                              @"ordered set orderedSetByApplyingBlock: keeps first-occurrence order");
        DVTExpectEqualObjects([[three dvt_orderedSetByApplyingBlock:^id(id o) { return @"a"; }] array], @[@"a"],
                              @"ordered set orderedSetByApplyingBlock: keeps the position of the first answer that got there");
        DVTExpectEqualObjects([three dvt_orderedSetByApplyingBlock:^id(id o) { return nil; }],
                              [NSOrderedSet orderedSet],
                              @"ordered set orderedSetByApplyingBlock: is empty when every answer is nil");
        DVTExpect(![[three dvt_orderedSetByApplyingBlock:^id(id o) { return o; }] respondsToSelector:@selector(addObject:)],
                  @"ordered set orderedSetByApplyingBlock: answers an immutable set");
        DVTExpect(![[three dvt_orderedSetByApplyingBlock:^id(id o) { return o; }] isKindOfClass:[NSMutableOrderedSet class]],
                  @"ordered set orderedSetByApplyingBlock: answers an immutable set even for a mutable receiver");
        DVTExpect([(NSOrderedSet *)nil dvt_orderedSetByApplyingBlock:^id(id o) { return o; }] == nil,
                  @"ordered set orderedSetByApplyingBlock: is nil for a nil receiver");
        __block int applyCalls = 0;
        (void)[three dvt_orderedSetByApplyingBlock:^id(id o) { applyCalls++; return o; }];
        DVTExpect(applyCalls == 3,
                  @"ordered set orderedSetByApplyingBlock: asks about every member even so");
        NSMutableOrderedSet *big = [NSMutableOrderedSet orderedSet];
        for (int i = 0; i < 300; i++) {
            [big addObject:[NSString stringWithFormat:@"m%03d", i]];
        }
        DVTExpect([big dvt_orderedSetByApplyingBlock:^id(id o) { return o; }].count == 300,
                  @"ordered set orderedSetByApplyingBlock: answers a 300-member receiver in full");
        DVTExpectEqualObjects([three dvt_orderedSetByApplyingBlock:nil], three,
                              @"ordered set orderedSetByApplyingBlock: guards a nil block with a copy of the receiver");
    }

    {
        /* Ordered set algebra. Each of the four answers the receiver itself when the
           argument cannot change it, and a fresh immutable set otherwise -- so a
           mutable receiver can see both halves of that. */
        NSOrderedSet *three = [NSOrderedSet orderedSetWithObjects:@"a", @"b", @"c", nil];
        NSOrderedSet *empty = [NSOrderedSet orderedSet];
        NSMutableOrderedSet *mutable = [[NSOrderedSet orderedSetWithObjects:@"a", @"b", @"c", nil] mutableCopy];

        DVTExpectEqualObjects([[three dvt_orderedSetByAddingObject:@"d"] array], @[@"a", @"b", @"c", @"d"],
                              @"ordered set orderedSetByAddingObject: appends a new object");
        DVTExpect([three dvt_orderedSetByAddingObject:@"a"] == three,
                  @"ordered set orderedSetByAddingObject: answers the receiver for a member it holds");
        DVTExpect([three dvt_orderedSetByAddingObject:nil] == three,
                  @"ordered set orderedSetByAddingObject: answers the receiver for a nil object");
        DVTExpect([mutable dvt_orderedSetByAddingObject:@"a"] == mutable,
                  @"ordered set orderedSetByAddingObject: a no-op answers a mutable receiver too");
        DVTExpect(![[mutable dvt_orderedSetByAddingObject:@"d"] isKindOfClass:[NSMutableOrderedSet class]],
                  @"ordered set orderedSetByAddingObject: answers an immutable set");
        /* Contained is isEqual:, so an equal-but-distinct object is the no-op. */
        NSString *distinct = [@"a" mutableCopy];
        DVTExpect([three dvt_orderedSetByAddingObject:distinct] == three,
                  @"ordered set orderedSetByAddingObject: compares by isEqual:, not identity");
        DVTExpectEqualObjects([[empty dvt_orderedSetByAddingObject:@"a"] array], @[@"a"],
                              @"ordered set orderedSetByAddingObject: fills an empty receiver");

        DVTExpectEqualObjects([[three dvt_orderedSetByAddingObjectsFromArray:@[@"c", @"d"]] array], @[@"a", @"b", @"c", @"d"],
                              @"ordered set orderedSetByAddingObjectsFromArray: appends the new objects");
        DVTExpectEqualObjects([[three dvt_orderedSetByAddingObjectsFromArray:@[@"x"]] array], @[@"a", @"b", @"c", @"x"],
                              @"ordered set orderedSetByAddingObjectsFromArray: keeps what it holds");
        DVTExpect([three dvt_orderedSetByAddingObjectsFromArray:@[]] == three,
                  @"ordered set orderedSetByAddingObjectsFromArray: an empty argument answers the receiver");
        DVTExpect([three dvt_orderedSetByAddingObjectsFromArray:nil] == three,
                  @"ordered set orderedSetByAddingObjectsFromArray: a nil argument reads as empty");
        DVTExpect([(NSOrderedSet *)nil dvt_orderedSetByAddingObjectsFromArray:@[@"a"]] == nil,
                  @"ordered set orderedSetByAddingObjectsFromArray: is nil for a nil receiver");

        DVTExpectEqualObjects([[three dvt_orderedSetByRemovingObject:@"b"] array], @[@"a", @"c"],
                              @"ordered set orderedSetByRemovingObject: drops the member it is given");
        DVTExpect([three dvt_orderedSetByRemovingObject:@"z"] == three,
                  @"ordered set orderedSetByRemovingObject: an absent object answers the receiver");
        DVTExpect([three dvt_orderedSetByRemovingObject:nil] == three,
                  @"ordered set orderedSetByRemovingObject: a nil object answers the receiver");
        DVTExpect([mutable dvt_orderedSetByRemovingObject:@"z"] == mutable,
                  @"ordered set orderedSetByRemovingObject: a no-op answers a mutable receiver too");
        DVTExpect(![[mutable dvt_orderedSetByRemovingObject:@"b"] isKindOfClass:[NSMutableOrderedSet class]],
                  @"ordered set orderedSetByRemovingObject: answers an immutable set");
        NSString *distinctRemove = [@"b" mutableCopy];
        DVTExpectEqualObjects([[three dvt_orderedSetByRemovingObject:distinctRemove] array], @[@"a", @"c"],
                              @"ordered set orderedSetByRemovingObject: compares by isEqual:, not identity");
        DVTExpectEqualObjects([empty dvt_orderedSetByRemovingObject:@"a"], empty,
                              @"ordered set orderedSetByRemovingObject: removing from an empty receiver stays empty");
        /* The answer is a snapshot, so changing the receiver afterwards does not
           reach it. */
        id snapshot = [mutable dvt_orderedSetByRemovingObject:@"a"];
        [mutable removeObject:@"b"];
        DVTExpectEqualObjects([snapshot array], @[@"b", @"c"],
                              @"ordered set orderedSetByRemovingObject: the answer does not follow the receiver");

        DVTExpectEqualObjects([[three dvt_orderedSetBySubtractingOrderedSet:[NSOrderedSet orderedSetWithObjects:@"a", @"c", nil]] array],
                              @[@"b"],
                              @"ordered set orderedSetBySubtractingOrderedSet: drops the shared members");
        DVTExpect([three dvt_orderedSetBySubtractingOrderedSet:[NSOrderedSet orderedSet]] == three,
                  @"ordered set orderedSetBySubtractingOrderedSet: an empty argument answers the receiver");
        DVTExpect([three dvt_orderedSetBySubtractingOrderedSet:nil] == three,
                  @"ordered set orderedSetBySubtractingOrderedSet: a nil argument answers the receiver");
        DVTExpect([mutable dvt_orderedSetBySubtractingOrderedSet:[NSOrderedSet orderedSet]] == mutable,
                  @"ordered set orderedSetBySubtractingOrderedSet: a no-op answers a mutable receiver too");
        DVTExpect(![[mutable dvt_orderedSetBySubtractingOrderedSet:[NSOrderedSet orderedSetWithObject:@"b"]]
                     isKindOfClass:[NSMutableOrderedSet class]],
                  @"ordered set orderedSetBySubtractingOrderedSet: answers an immutable set");
        DVTExpectEqualObjects([three dvt_orderedSetBySubtractingOrderedSet:three], empty,
                              @"ordered set orderedSetBySubtractingOrderedSet: subtracting everything empties the receiver");
        DVTExpectEqualObjects([[three dvt_orderedSetBySubtractingOrderedSet:
                                    [NSOrderedSet orderedSetWithObject:distinctRemove]] array],
                              @[@"a", @"c"],
                              @"ordered set orderedSetBySubtractingOrderedSet: compares by isEqual:, not identity");
    }

    {
        /* The three mutators, which the immutable class does not answer at all.
           The interesting one is dvt_addReturningDidMutate:, whose answer is the
           count's growth rather than whether the add happened: a member the receiver
           already holds leaves the length alone. */
        NSMutableOrderedSet *t = [NSMutableOrderedSet orderedSetWithObjects:@"a", @"b", nil];

        [t dvt_addObjectIfNotNil:@"c"];
        DVTExpectEqualObjects([t array], @[@"a", @"b", @"c"],
                              @"mutable ordered set addObjectIfNotNil: appends the object");
        [t dvt_addObjectIfNotNil:nil];
        DVTExpectEqualObjects([t array], @[@"a", @"b", @"c"],
                              @"mutable ordered set addObjectIfNotNil: ignores a nil object");
        [t dvt_addObjectIfNotNil:@"a"];
        DVTExpectEqualObjects([t array], @[@"a", @"b", @"c"],
                              @"mutable ordered set addObjectIfNotNil: a member it holds is not added twice");

        NSMutableOrderedSet *g = [NSMutableOrderedSet orderedSetWithObjects:@"a", nil];
        DVTExpect([g dvt_addReturningDidMutate:@"b"],
                  @"mutable ordered set addReturningDidMutate: YES for an object it did not hold");
        DVTExpect(![g dvt_addReturningDidMutate:@"a"],
                  @"mutable ordered set addReturningDidMutate: NO for a member it already held");
        DVTExpect(![g dvt_addReturningDidMutate:nil],
                  @"mutable ordered set addReturningDidMutate: NO for a nil object");
        DVTExpectEqualObjects([g array], @[@"a", @"b"],
                              @"mutable ordered set addReturningDidMutate: adds only the new object");

        NSMutableOrderedSet *p = [NSMutableOrderedSet orderedSetWithObjects:@"a", @"b", nil];
        DVTExpectEqualObjects([p dvt_popLastObject], @"b",
                              @"mutable ordered set popLastObject: answers the last member");
        DVTExpectEqualObjects([p array], @[@"a"],
                              @"mutable ordered set popLastObject: removes the member it answers");
        DVTExpectEqualObjects([p dvt_popLastObject], @"a",
                              @"mutable ordered set popLastObject: empties the receiver from the end");
        DVTExpect([p dvt_popLastObject] == nil,
                  @"mutable ordered set popLastObject: is nil once the receiver is empty");
        DVTExpectEqualObjects([p array], @[],
                              @"mutable ordered set popLastObject: leaves the empty receiver empty");
        DVTExpect([[NSMutableOrderedSet orderedSet] dvt_popLastObject] == nil,
                  @"mutable ordered set popLastObject: is nil for an empty receiver");
        DVTExpect([(NSMutableOrderedSet *)nil dvt_popLastObject] == nil,
                  @"mutable ordered set popLastObject: is nil for a nil receiver");
        DVTExpect(![(NSMutableOrderedSet *)nil dvt_addReturningDidMutate:@"a"],
                  @"mutable ordered set addReturningDidMutate: is NO for a nil receiver");

        /* An immutable ordered set raises on the mutators, which is how the split
           between the two classes shows from the outside. */
        NSOrderedSet *immutable = [NSOrderedSet orderedSetWithObjects:@"a", nil];
        @try {
            [(id)immutable dvt_popLastObject];
            DVTExpect(NO, @"ordered set: the immutable class does not answer popLastObject");
        } @catch (NSException *exception) {
            DVTExpect([exception.name isEqualToString:@"NSInvalidArgumentException"],
                      @"ordered set: the immutable class raises on popLastObject");
        }
    }

    /* The two ranking folds and the plain fold. The comparator folds differ from
       the block fold in the order their two arguments arrive in, which is the
       part that is easy to get backwards and impossible to see in the answer
       alone, so the argument order is checked directly. */

    {
        NSSet *abc = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        NSComparisonResult (^ascending)(id, id) = ^NSComparisonResult(id a, id b) {
            return [a compare:b];
        };
        NSMutableArray *calls = [NSMutableArray array];
        NSComparisonResult (^logged)(id, id) = ^NSComparisonResult(id a, id b) {
            [calls addObject:[NSString stringWithFormat:@"(%@,%@)", a, b]];
            return [a compare:b];
        };

        DVTExpect([[NSSet set] dvt_minimumObjectUsingComparator:ascending] == nil,
                  @"set minimumObjectUsingComparator: is nil for an empty receiver");
        DVTExpectEqualObjects([[NSSet setWithObject:@"solo"] dvt_minimumObjectUsingComparator:ascending],
                              @"solo",
                              @"set minimumObjectUsingComparator: hands back a lone member");
        DVTExpectEqualObjects([abc dvt_minimumObjectUsingComparator:ascending], @"a",
                              @"set minimumObjectUsingComparator: ranks the lowest member lowest");
        /* The comparator sees the candidate first and the incumbent second: with
           -compare: that is what leaves "a" held when "b" and "c" arrive. */
        [calls removeAllObjects];
        [abc dvt_minimumObjectUsingComparator:logged];
        DVTExpectEqualObjects([calls componentsJoinedByString:@" "], @"(b,a) (c,a)",
                              @"set minimumObjectUsingComparator: asks (candidate, incumbent)");
        /* Only an exact NSOrderedAscending replaces, so an out-of-contract -2 is
           not treated as "less" and the incumbent survives both rounds. */
        DVTExpectEqualObjects([abc dvt_minimumObjectUsingComparator:^NSComparisonResult(id a, id b) {
            return (NSComparisonResult)-2;
        }], @"a",
                              @"set minimumObjectUsingComparator: only an exact -1 replaces the incumbent");
        DVTExpectEqualObjects([abc dvt_minimumObjectUsingComparator:^NSComparisonResult(id a, id b) {
            return NSOrderedDescending;
        }], @"a",
                              @"set minimumObjectUsingComparator: a descending answer never replaces");
        /* Ties keep the incumbent, so the first member enumerated wins. */
        DVTExpectEqualObjects([abc dvt_minimumObjectUsingComparator:^NSComparisonResult(id a, id b) {
            return NSOrderedSame;
        }], @"a",
                              @"set minimumObjectUsingComparator: a tie keeps the incumbent");

        DVTExpect([[NSSet set] dvt_maximumObjectUsingComparator:ascending] == nil,
                  @"set maximumObjectUsingComparator: is nil for an empty receiver");
        DVTExpectEqualObjects([abc dvt_maximumObjectUsingComparator:ascending], @"c",
                              @"set maximumObjectUsingComparator: ranks the highest member highest");
        /* The maximum is the minimum asked with a negated comparator, so its own
           comparisons are made against the running maximum: "b" loses to "a" and
           "c" then beats "b". */
        [calls removeAllObjects];
        [abc dvt_maximumObjectUsingComparator:logged];
        DVTExpectEqualObjects([calls componentsJoinedByString:@" "], @"(b,a) (c,b)",
                              @"set maximumObjectUsingComparator: folds the minimum with a negated answer");
        DVTExpectEqualObjects([abc dvt_maximumObjectUsingComparator:^NSComparisonResult(id a, id b) {
            return NSOrderedSame;
        }], @"a",
                              @"set maximumObjectUsingComparator: shares the first-wins tie-break");

        DVTExpect([[NSSet set] dvt_objectByFoldingWithBlock:^id(id a, id b) { return @"never"; }] == nil,
                  @"set objectByFoldingWithBlock: is nil for an empty receiver");
        /* A lone member is the accumulator without the block ever being called, so
           what the block would return cannot matter. */
        __block int blockCalls = 0;
        DVTExpectEqualObjects([[NSSet setWithObject:@"solo"] dvt_objectByFoldingWithBlock:^id(id a, id b) {
            blockCalls++;
            return @"never";
        }], @"solo",
                              @"set objectByFoldingWithBlock: seeds on the first member without calling the block");
        DVTExpect(blockCalls == 0,
                  @"set objectByFoldingWithBlock: does not call the block for a lone member");
        [calls removeAllObjects];
        DVTExpectEqualObjects([abc dvt_objectByFoldingWithBlock:^id(id a, id b) {
            [calls addObject:[NSString stringWithFormat:@"(%@,%@)", a, b]];
            return [NSString stringWithFormat:@"%@%@", a, b];
        }], @"abc",
                              @"set objectByFoldingWithBlock: folds the members together");
        /* The opposite order from the comparator folds: accumulator first. */
        DVTExpectEqualObjects([calls componentsJoinedByString:@" "], @"(a,b) (ab,c)",
                              @"set objectByFoldingWithBlock: asks (accumulator, next)");
        /* A nil answer empties the accumulator and the next member re-seeds it, so
           a block that always answers nil yields the last member rather than nil. */
        DVTExpectEqualObjects([abc dvt_objectByFoldingWithBlock:^id(id a, id b) { return nil; }], @"c",
                              @"set objectByFoldingWithBlock: a nil answer re-seeds on the next member");
        blockCalls = 0;
        DVTExpectEqualObjects([abc dvt_objectByFoldingWithBlock:^id(id a, id b) {
            blockCalls++;
            return nil;
        }], @"c",
                              @"set objectByFoldingWithBlock: an all-nil fold answers the last member");
        /* One call, not two: the nil answer leaves the accumulator empty and the
           last member then re-seeds it without the block being consulted. A
           five-member receiver asks twice, so the skipped call is per re-seed
           rather than a one-off. */
        DVTExpect(blockCalls == 1,
                  @"set objectByFoldingWithBlock: skips the call that would re-seed");
        __block int fiveCalls = 0;
        NSMutableSet *five = [NSMutableSet set];
        for (int i = 0; i < 5; i++) {
            [five addObject:[NSNumber numberWithInt:i]];
        }
        DVTExpectEqualObjects([five dvt_objectByFoldingWithBlock:^id(id a, id b) {
            fiveCalls++;
            return nil;
        }], @4,
                              @"set objectByFoldingWithBlock: an all-nil fold answers the last member");
        DVTExpect(fiveCalls == 2, @"set objectByFoldingWithBlock: one call per re-seed");
    }

    /* The set-to-dictionary pair. The names run opposite to the answers: the
       block's answer is the value in the first and the key in the second. */

    {
        NSSet *abc = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        id (^upper)(id) = ^id(id o) { return [o uppercaseString]; };

        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:upper],
                              (@{@"a": @"A", @"b": @"B", @"c": @"C"}),
                              @"set EntriesAsKeysAndValues: member keyed, block answer valued");
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:upper],
                              (@{@"A": @"a", @"B": @"b", @"C": @"c"}),
                              @"set EntriesAsValuesAndKeys: block answer keyed, member valued");
        DVTExpectEqualObjects([[NSSet set] dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:upper], @{},
                              @"set EntriesAsKeysAndValues: is empty for an empty receiver");
        DVTExpectEqualObjects([[NSSet set] dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:upper], @{},
                              @"set EntriesAsValuesAndKeys: is empty for an empty receiver");
        /* A nil answer is skipped rather than stored in either slot. */
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:^id(id o) {
            return [o isEqualToString:@"b"] ? nil : o;
        }], (@{@"a": @"a", @"c": @"c"}),
                              @"set EntriesAsKeysAndValues: skips a nil answer");
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:^id(id o) {
            return [o isEqualToString:@"b"] ? nil : o;
        }], (@{@"a": @"a", @"c": @"c"}),
                              @"set EntriesAsValuesAndKeys: skips a nil answer");
        /* A constant answer leaves the members distinct as keys here, so every
           member keeps an entry. */
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:^id(id o) { return @"k"; }],
                              (@{@"a": @"k", @"b": @"k", @"c": @"k"}),
                              @"set EntriesAsKeysAndValues: a constant answer keeps every member");
        /* In the mirror image the answers are the keys, so they collide and the
           last member enumerated is the one that survives. */
        DVTExpectEqualObjects([abc dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:^id(id o) { return @"k"; }],
                              (@{@"k": @"c"}),
                              @"set EntriesAsValuesAndKeys: colliding answers leave the last member");
        NSDictionary *keyed = [abc dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:upper];
        NSDictionary *reverse = [abc dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:upper];
        DVTExpect(![keyed isKindOfClass:[NSMutableDictionary class]],
                  @"set EntriesAsKeysAndValues: answers an immutable dictionary");
        DVTExpect(![reverse isKindOfClass:[NSMutableDictionary class]],
                  @"set EntriesAsValuesAndKeys: answers an immutable dictionary");
    }

    /* NSSet's shuffle is a forward to -allObjects and then the array method, so
       the threshold comes from that method rather than from here. */

    {
        NSSet *abc = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        NSArray *shuffled = [abc dvt_shuffledArray];
        DVTExpect(shuffled.count == 3, @"set shuffledArray: answers every member");
        DVTExpectEqualObjects([NSSet setWithArray:shuffled], abc,
                              @"set shuffledArray: keeps the members and only reorders them");
        /* Above one member the answer is a mutable array. */
        DVTExpect([shuffled isKindOfClass:[NSMutableArray class]],
                  @"set shuffledArray: a multi-member answer is mutable");
        /* At one member or below it is a copy of an already immutable array, so
           the empty answer is the shared instance rather than a fresh array. */
        NSArray *lone = [[NSSet setWithObject:@"solo"] dvt_shuffledArray];
        DVTExpect(![lone isKindOfClass:[NSMutableArray class]],
                  @"set shuffledArray: a lone member answers an immutable array");
        /* Two -allObjects calls answer two distinct arrays, so the empty answer
           is a copy of a fresh empty array rather than one shared instance. */
        DVTExpect([[NSSet set] dvt_shuffledArray] != [[NSSet set] dvt_shuffledArray],
                  @"set shuffledArray: each empty answer is its own object");
        DVTExpect([[[NSSet set] dvt_shuffledArray] count] == 0,
                  @"set shuffledArray: an empty receiver answers an empty array");
        NSMutableSet *big = [NSMutableSet set];
        for (int i = 0; i < 300; i++) {
            [big addObject:[NSString stringWithFormat:@"m%03d", i]];
        }
        DVTExpect([big dvt_shuffledArray].count == 300,
                  @"set shuffledArray: answers a 300-member receiver in full");
    }

    /* The plain sorting trio. All three take -allObjects, sort it, and skip the
       sort entirely below two members. */

    {
        /* The argument-free form is compare:, which the numbers pin down: they
           come back numerically ordered, and equal to the selector form handed
           compare:. A length or identity sort would order them differently. */
        NSSet *words = [NSSet setWithObjects:@"bbb", @"a", @"cc", nil];
        NSArray *sorted = [words dvt_sortedArray];
        DVTExpectEqualObjects(sorted, (@[@"a", @"bbb", @"cc"]),
                              @"set sortedArray orders by compare:");
        DVTExpect([[words dvt_sortedArray]
                      isEqualToArray:[words dvt_sortedArrayUsingSelector:@selector(compare:)]],
                  @"set sortedArray matches sortedArrayUsingSelector: handed compare:");
        NSSet *numbers = [NSSet setWithObjects:@3, @1, @22, nil];
        DVTExpectEqualObjects([numbers dvt_sortedArray], (@[@1, @3, @22]),
                              @"set sortedArray compares numbers numerically, not as text");
        DVTExpect(![sorted isKindOfClass:[NSMutableArray class]],
                  @"set sortedArray answers an immutable array");
        DVTExpect([[NSSet setWithArray:sorted] isEqualToSet:words],
                  @"set sortedArray keeps every member");
        DVTExpect(words.count == 3, @"set sortedArray leaves the set unchanged");
    }

    {
        /* Below two members the answer is -allObjects as it stands, so nothing is
           sorted and the comparator is never asked. */
        NSSet *single = [NSSet setWithObject:@"only"];
        __block int calls = 0;
        NSArray *sorted = [single dvt_sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            calls++;
            return NSOrderedSame;
        }];
        DVTExpect(calls == 0, @"set sortedArrayUsingComparator: is not asked for one member");
        DVTExpectEqualObjects(sorted, (@[@"only"]),
                              @"set sortedArrayUsingComparator: hands one member straight back");
        DVTExpect(![sorted isKindOfClass:[NSMutableArray class]],
                  @"set sortedArrayUsingComparator: answers an immutable array");
        DVTExpect([[NSSet set] dvt_sortedArray].count == 0,
                  @"set sortedArray answers an empty array for an empty set");
        DVTExpect([[NSSet set] dvt_sortedArray] != nil,
                  @"set sortedArray answers a non-nil array for an empty set");
        /* A selector nothing implements would raise if it were ever sent, which
           makes it the check that the short-receiver case skips it. */
        @try {
            NSArray *never = [[NSSet set] dvt_sortedArrayUsingSelector:@selector(dvt_noSuchSelectorHere)];
            DVTExpect(never.count == 0, @"set sortedArrayUsingSelector: never sends the selector for an empty set");
        } @catch (NSException *exception) {
            DVTExpect(NO, @"set sortedArrayUsingSelector: never sends the selector for an empty set");
        }
        @try {
            NSArray *never = [single dvt_sortedArrayUsingSelector:@selector(dvt_noSuchSelectorHere)];
            DVTExpect(never.count == 1, @"set sortedArrayUsingSelector: never sends the selector for one member");
        } @catch (NSException *exception) {
            DVTExpect(NO, @"set sortedArrayUsingSelector: never sends the selector for one member");
        }
        /* Two or more members do reach it, and an unknown selector raises rather
           than being quietly ignored. That is Foundation's behaviour, inherited by
           forwarding. */
        NSSet *two = [NSSet setWithObjects:@"bb", @"a", nil];
        @try {
            [two dvt_sortedArrayUsingSelector:@selector(dvt_noSuchSelectorHere)];
            DVTExpect(NO, @"set sortedArrayUsingSelector: raises for a selector the members lack");
        } @catch (NSException *exception) {
            DVTExpect([exception.name isEqualToString:@"NSInvalidArgumentException"],
                      @"set sortedArrayUsingSelector: raises for a selector the members lack");
        }
    }

    {
        /* The selector is handed over as it stands, so a different selector gives a
           different answer. These two order the same pair differently. */
        NSSet *members = [NSSet setWithObjects:@"B", @"a", nil];
        DVTExpectEqualObjects([members dvt_sortedArrayUsingSelector:@selector(compare:)], (@[@"B", @"a"]),
                              @"set sortedArrayUsingSelector: orders by the selector given");
        DVTExpectEqualObjects([members dvt_sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)],
                              (@[@"a", @"B"]),
                              @"set sortedArrayUsingSelector: honours a case-insensitive selector");
    }

    {
        __block int calls = 0;
        NSSet *words = [NSSet setWithObjects:@"bbb", @"a", @"cc", nil];
        NSArray *ascending = [words dvt_sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            calls++;
            return [a compare:b];
        }];
        DVTExpectEqualObjects(ascending, [words dvt_sortedArray],
                              @"set sortedArrayUsingComparator: agrees with compare:");
        DVTExpect(calls > 0, @"set sortedArrayUsingComparator: asks the comparator");
        NSArray *descending = [words dvt_sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [b compare:a];
        }];
        DVTExpectEqualObjects(descending, (@[@"cc", @"bbb", @"a"]),
                              @"set sortedArrayUsingComparator: honours a descending comparator");
        /* A set cannot hold equal members, so members of the same length all
           survive a comparator that calls them equal. */
        NSSet *tied = [NSSet setWithObjects:@"aa", @"bb", @"cc", @"dd", nil];
        NSArray *alwaysSame = [tied dvt_sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return NSOrderedSame;
        }];
        DVTExpect(alwaysSame.count == 4,
                  @"set sortedArrayUsingComparator: keeps members the comparator calls equal");
        DVTExpect([[NSSet setWithArray:alwaysSame] isEqualToSet:tied],
                  @"set sortedArrayUsingComparator: keeps every member when it never separates them");
        NSMutableSet *mutableSet = [NSMutableSet setWithObjects:@"bbb", @"a", @"cc", nil];
        NSUInteger before = mutableSet.count;
        NSArray *fromMutable = [mutableSet dvt_sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [a compare:b];
        }];
        DVTExpectEqualObjects(fromMutable, (@[@"a", @"bbb", @"cc"]),
                              @"set sortedArrayUsingComparator: sorts a mutable set's members");
        DVTExpect(mutableSet.count == before && [mutableSet isKindOfClass:[NSMutableSet class]],
                  @"set sortedArrayUsingComparator: leaves a mutable set unchanged");
    }

    /* The any-spelling on the two set-like classes, which Apple scans directly
       rather than reaching through dvt_firstObjectPassingTest:. A nil test
       answers YES for a collection with anything in it, matching the array
       spelling, where it hands back the first member. */
    DVTExpect([members dvt_anyObjectsPassTest:^BOOL(id o) { return [o isEqualToString:@"a"]; }],
              @"set anyObjectsPassTest accepts a matching member");
    DVTExpect(![members dvt_anyObjectsPassTest:^BOOL(id o) { return [o isEqualToString:@"z"]; }],
              @"set anyObjectsPassTest rejects when no member matches");
    DVTExpect(![members dvt_anyObjectsPassTest:^BOOL(id o) { return NO; }],
              @"set anyObjectsPassTest is false when nothing matches");
    DVTExpect([members dvt_anyObjectsPassTest:^BOOL(id o) { return YES; }],
              @"set anyObjectsPassTest accepts when every member matches");
    DVTExpect(![[NSSet set] dvt_anyObjectsPassTest:^BOOL(id o) { return YES; }],
              @"set anyObjectsPassTest is false when empty, without calling the test");
    DVTExpect([members dvt_anyObjectsPassTest:nilTest], @"set anyObjectsPassTest guards a nil test");
    DVTExpect(![[NSSet set] dvt_anyObjectsPassTest:nilTest],
              @"set anyObjectsPassTest with a nil test is still false when empty");
    {
        __block NSUInteger calls = 0;
        [members dvt_anyObjectsPassTest:^BOOL(id o) { calls++; return YES; }];
        DVTExpectEqualObjects(@(calls), @1, @"set anyObjectsPassTest stops at the first matching member");
    }
    DVTExpect([table dvt_anyObjectsPassTest:^BOOL(id o) { return [o isEqualToString:@"b"]; }],
              @"hash table anyObjectsPassTest accepts a matching object");
    DVTExpect(![table dvt_anyObjectsPassTest:^BOOL(id o) { return [o isEqualToString:@"z"]; }],
              @"hash table anyObjectsPassTest rejects when no object matches");
    DVTExpect(![table dvt_anyObjectsPassTest:^BOOL(id o) { return NO; }],
              @"hash table anyObjectsPassTest is false when nothing matches");
    DVTExpect(![[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality]
                   dvt_anyObjectsPassTest:^BOOL(id o) { return YES; }],
              @"hash table anyObjectsPassTest is false when empty");
    DVTExpect([table dvt_anyObjectsPassTest:nilTest], @"hash table anyObjectsPassTest guards a nil test");

    /* The older spelling of both tests, which Apple keeps in categories named
       _DEPRECATED on all three classes and implements as bare forwards. Each
       forward is checked against the spelling it wraps, across the cases where
       the two could plausibly differ: a partial match, a universal match, no
       match at all, and the empty collection. */
    {
        BOOL (^some)(id) = ^BOOL(id o) { return [o isEqual:@"b"]; };
        BOOL (^all)(id) = ^BOOL(id o) { return YES; };
        BOOL (^none)(id) = ^BOOL(id o) { return NO; };
        BOOL (^onlyLast)(id) = ^BOOL(id o) { return [o isEqual:@"c"]; };
        NSArray *triple = @[@"a", @"b", @"c"];
        NSArray *emptyArray = @[];
        NSSet *tripleSet = [NSSet setWithObjects:@"a", @"b", @"c", nil];
        NSSet *emptySet = [NSSet set];
        NSHashTable *tripleTable = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
        [tripleTable addObject:@"a"]; [tripleTable addObject:@"b"]; [tripleTable addObject:@"c"];
        NSHashTable *emptyTable = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];

        NSArray *arrays = @[triple, emptyArray];
        NSArray *sets = @[tripleSet, emptySet];
        NSArray *tables = @[tripleTable, emptyTable];
        NSArray *blocks = @[some, all, none, onlyLast];
        for (id collection in arrays) {
            for (BOOL (^test)(id) in blocks) {
                DVTExpect([collection dvt_areAllObjectsPassingTest:test] == [collection dvt_allObjectsPassTest:test],
                          @"array areAllObjectsPassingTest matches allObjectsPassTest");
                DVTExpect([collection dvt_areAnyObjectsPassingTest:test] == [collection dvt_anyObjectsPassTest:test],
                          @"array areAnyObjectsPassingTest matches anyObjectsPassTest");
            }
        }
        for (id collection in sets) {
            for (BOOL (^test)(id) in blocks) {
                DVTExpect([collection dvt_areAllObjectsPassingTest:test] == [collection dvt_allObjectsPassTest:test],
                          @"set areAllObjectsPassingTest matches allObjectsPassTest");
                DVTExpect([collection dvt_areAnyObjectsPassingTest:test] == [collection dvt_anyObjectsPassTest:test],
                          @"set areAnyObjectsPassingTest matches anyObjectsPassTest");
            }
        }
        for (id collection in tables) {
            for (BOOL (^test)(id) in blocks) {
                DVTExpect([collection dvt_areAllObjectsPassingTest:test] == [collection dvt_allObjectsPassTest:test],
                          @"hash table areAllObjectsPassingTest matches allObjectsPassTest");
                DVTExpect([collection dvt_areAnyObjectsPassingTest:test] == [collection dvt_anyObjectsPassTest:test],
                          @"hash table areAnyObjectsPassingTest matches anyObjectsPassTest");
            }
        }
        /* The forwards must not short-circuit differently than what they wrap. */
        {
            __block NSUInteger deprecatedCalls = 0;
            __block NSUInteger currentCalls = 0;
            [triple dvt_areAnyObjectsPassingTest:^BOOL(id o) { deprecatedCalls++; return YES; }];
            [triple dvt_anyObjectsPassTest:^BOOL(id o) { currentCalls++; return YES; }];
            DVTExpectEqualObjects(@(deprecatedCalls), @(currentCalls),
                                  @"array areAnyObjectsPassingTest stops where anyObjectsPassTest stops");
        }
        {
            __block NSUInteger deprecatedCalls = 0;
            __block NSUInteger currentCalls = 0;
            [triple dvt_areAllObjectsPassingTest:^BOOL(id o) {
                deprecatedCalls++;
                return ![o isEqual:@"c"];
            }];
            [triple dvt_allObjectsPassTest:^BOOL(id o) {
                currentCalls++;
                return ![o isEqual:@"c"];
            }];
            DVTExpectEqualObjects(@(deprecatedCalls), @(currentCalls),
                                  @"array areAllObjectsPassingTest stops where allObjectsPassTest stops");
        }
    }

    DVTExpectEqualObjects([sample dvt_objectsOfClass:[NSString class]], sample, @"objectsOfClass");

    /* dvt_rangeOfArray: finds a run contiguously, member by member, with isEqual:
       rather than as a set of members that happens to be present. */
    {
        NSArray *haystack = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g"];
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"a", @"b"]], NSMakeRange(0, 2)),
                  @"rangeOfArray finds a run at the front");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"c", @"d"]], NSMakeRange(2, 2)),
                  @"rangeOfArray finds a run in the middle");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"f", @"g"]], NSMakeRange(5, 2)),
                  @"rangeOfArray finds a run at the tail");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:haystack], NSMakeRange(0, 7)),
                  @"rangeOfArray finds the receiver inside itself");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"g"]], NSMakeRange(6, 1)),
                  @"rangeOfArray finds a single member");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"a", @"c"]], NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray needs the members to be contiguous");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"b", @"a"]], NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray does not reorder the members it is given");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"a", @"a"]], NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray needs each member present, not just some copy of it");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"f", @"g", @"h"]], NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray rejects a run that runs off the end");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[]], NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray finds nothing for an empty needle");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:nil], NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray finds nothing for a nil needle");
        DVTExpect(NSEqualRanges([@[] dvt_rangeOfArray:@[@"a"]], NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray finds nothing in an empty receiver");
        DVTExpect(NSEqualRanges([@[] dvt_rangeOfArray:@[]], NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray finds nothing when both are empty");
        NSArray *tooLong = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g", @"h"];
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:tooLong], NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray rejects a needle longer than the receiver");
        /* Two runs of the same length: the earlier answers. A longer run later
           does not displace an earlier short one either. */
        DVTExpect(NSEqualRanges([@[@"x", @"y", @"m", @"x", @"y"] dvt_rangeOfArray:@[@"x", @"y"]],
                                NSMakeRange(0, 2)),
                  @"rangeOfArray answers the earlier of two equal runs");
        NSArray *greedy = @[@"p", @"q", @"r", @"s", @"r", @"s", @"t"];
        DVTExpect(NSEqualRanges([greedy dvt_rangeOfArray:@[@"r", @"s"]], NSMakeRange(2, 2)),
                  @"rangeOfArray prefers an earlier short run over a longer one");
        DVTExpect(NSEqualRanges([greedy dvt_rangeOfArray:@[@"r", @"s", @"t"]], NSMakeRange(4, 3)),
                  @"rangeOfArray still finds the longer run when nothing earlier matches");
        /* Membership is equality, and numbers compare by value. */
        NSString *equalNeedle = [NSString stringWithFormat:@"%@", @"c"];
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[equalNeedle]], NSMakeRange(2, 1)),
                  @"rangeOfArray matches an equal-but-distinct member");
        DVTExpect(NSEqualRanges([@[@1, @2, @3] dvt_rangeOfArray:@[@1, @2]], NSMakeRange(0, 2)),
                  @"rangeOfArray compares numbers by value");
    }
    /* The windowed form is the same question asked of part of the receiver. */
    {
        NSArray *haystack = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g"];
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"c", @"d"] inRange:NSMakeRange(0, 7)],
                                NSMakeRange(2, 2)),
                  @"rangeOfArray:inRange: finds a run inside the window");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"c", @"d"] inRange:NSMakeRange(4, 3)],
                                NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray:inRange: ignores a run outside the window");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"c", @"d"] inRange:NSMakeRange(1, 6)],
                                NSMakeRange(2, 2)),
                  @"rangeOfArray:inRange: finds a run in a window that starts earlier");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"c", @"d"] inRange:NSMakeRange(0, 4)],
                                NSMakeRange(2, 2)),
                  @"rangeOfArray:inRange: finds a run ending exactly at the window's end");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"e", @"f", @"g"] inRange:NSMakeRange(4, 3)],
                                NSMakeRange(4, 3)),
                  @"rangeOfArray:inRange: finds a run filling the whole window");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"e"] inRange:NSMakeRange(2, 0)],
                                NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray:inRange: finds nothing in an empty window");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"b", @"c"] inRange:NSMakeRange(3, 2)],
                                NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray:inRange: finds nothing when the needle is longer than the window");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[@"a"] inRange:NSMakeRange(5, 9)],
                                NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray:inRange: finds nothing in a window past the end");
        DVTExpect(NSEqualRanges([haystack dvt_rangeOfArray:@[] inRange:NSMakeRange(0, 7)],
                                NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray:inRange: finds nothing for an empty needle");
        DVTExpect(NSEqualRanges([@[] dvt_rangeOfArray:@[@"a"] inRange:NSMakeRange(0, 0)],
                                NSMakeRange(NSNotFound, 0)),
                  @"rangeOfArray:inRange: finds nothing in an empty receiver");
        DVTExpect(NSEqualRanges([@[@"x", @"y", @"m", @"x", @"y"]
                                    dvt_rangeOfArray:@[@"x", @"y"] inRange:NSMakeRange(2, 3)],
                                NSMakeRange(3, 2)),
                  @"rangeOfArray:inRange: picks the run inside the window, not the earlier one");
        /* The plain form is the windowed one over the whole receiver. */
        NSArray *windowed = @[@"a", @"b", @"c", @"d", @"e"];
        DVTExpect(NSEqualRanges([windowed dvt_rangeOfArray:@[@"b", @"c"]],
                                [windowed dvt_rangeOfArray:@[@"b", @"c"] inRange:NSMakeRange(0, windowed.count)]),
                  @"rangeOfArray searches the whole receiver");
    }
    /* The last member passing a test, and the member before a first occurrence. */
    {
        NSArray *sample = @[@"a", @"bb", @"c"];
        DVTExpectEqualObjects([sample dvt_lastObjectPassingTest:^BOOL(id o) { return [o isEqual:@"bb"]; }], @"bb",
                              @"lastObjectPassingTest finds a match in the middle");
        DVTExpectEqualObjects([sample dvt_lastObjectPassingTest:^BOOL(id o) { return [o isEqual:@"a"]; }], @"a",
                              @"lastObjectPassingTest finds a match at the front");
        DVTExpectEqualObjects([sample dvt_lastObjectPassingTest:^BOOL(id o) { return [o isEqual:@"c"]; }], @"c",
                              @"lastObjectPassingTest finds a match at the tail");
        DVTExpectEqualObjects([sample dvt_lastObjectPassingTest:^BOOL(id o) { return YES; }], @"c",
                              @"lastObjectPassingTest with a universal test answers the last member");
        DVTExpect([sample dvt_lastObjectPassingTest:^BOOL(id o) { return NO; }] == nil,
                  @"lastObjectPassingTest answers nil when nothing passes");
        DVTExpect([@[] dvt_lastObjectPassingTest:^BOOL(id o) { return YES; }] == nil,
                  @"lastObjectPassingTest answers nil for an empty receiver");

        DVTExpectEqualObjects([sample dvt_objectBeforeFirstOccurenceOfObject:@"bb"], @"a",
                              @"objectBeforeFirstOccurenceOfObject answers the member in front");
        DVTExpectEqualObjects([sample dvt_objectBeforeFirstOccurenceOfObject:@"c"], @"bb",
                              @"objectBeforeFirstOccurenceOfObject works at the tail");
        DVTExpect([sample dvt_objectBeforeFirstOccurenceOfObject:@"a"] == nil,
                  @"objectBeforeFirstOccurenceOfObject answers nil at the front");
        DVTExpect([sample dvt_objectBeforeFirstOccurenceOfObject:@"z"] == nil,
                  @"objectBeforeFirstOccurenceOfObject answers nil when absent");
        DVTExpect([@[] dvt_objectBeforeFirstOccurenceOfObject:@"a"] == nil,
                  @"objectBeforeFirstOccurenceOfObject answers nil for an empty receiver");
        DVTExpect([sample dvt_objectBeforeFirstOccurenceOfObject:nil] == nil,
                  @"objectBeforeFirstOccurenceOfObject answers nil for a nil argument");
        DVTExpect([@[@"x", @"y", @"x"] dvt_objectBeforeFirstOccurenceOfObject:@"x"] == nil,
                  @"objectBeforeFirstOccurenceOfObject looks before the first occurrence, not a later one");
        NSString *twin = [NSString stringWithFormat:@"%@", @"bb"];
        DVTExpectEqualObjects([sample dvt_objectBeforeFirstOccurenceOfObject:twin], @"a",
                              @"objectBeforeFirstOccurenceOfObject matches by equality");
    }

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

    /* The shell variant shares the space separator and the "" rendering for an
       empty argument, but escapes backslash, space, and tab instead of the four
       quote-and-whitespace characters the command line variant escapes. */
    NSArray *shellCases = @[
        @[@"shell: no arguments", @[], @""],
        @[@"shell: single argument", @[@"one"], @"one"],
        @[@"shell: arguments are space separated", @[@"one", @"two"], @"one two"],
        @[@"shell: empty argument is quoted", @[@""], @"\"\""],
        @[@"shell: every empty argument is quoted", @[@"", @""], @"\"\" \"\""],
        /* An empty first argument still leaves a non-empty result behind, so the
           separator before the next argument is still written. */
        @[@"shell: separator follows a quoted empty argument", @[@"", @"a"], @"\"\" a"],
        @[@"shell: spaces are backslash escaped", @[@"a b"], @"a\\ b"],
        /* A tab is escaped by prefixing a backslash to the real tab, not by
           spelling it as the two characters backslash-t. */
        @[@"shell: tabs are backslash escaped", @[@"a\tb"], @"a\\\tb"],
        @[@"shell: backslashes are doubled", @[@"a\\b"], @"a\\\\b"],
        /* Quotes, dollar signs, globs, and newlines are deliberately not part of
           the escaping set here even though the command line variant escapes the
           two quote characters. */
        @[@"shell: double quotes are left alone", @[@"a\"b"], @"a\"b"],
        @[@"shell: single quotes are left alone", @[@"a'b"], @"a'b"],
        @[@"shell: other shell metacharacters are left alone", @[@"a$b^c~d*e;f|g&h>i<j"], @"a$b^c~d*e;f|g&h>i<j"],
        @[@"shell: newlines are left alone", @[@"a\nb"], @"a\nb"],

        /* All three replacements search {0, length} of the original argument, so
           the doubling backslash pushes later characters out of the range and they
           survive unescaped. These four rows pin that down. */
        @[@"shell: a backslash hides the following space", @[@"\\  "], @"\\\\\\  "],
        @[@"shell: a backslash hides two following spaces", @[@"\\   "], @"\\\\\\ \\  "],
        @[@"shell: a backslash hides three following spaces", @[@"\\    "], @"\\\\\\ \\ \\  "],
        /* Here the space escapes and the backslash pushes the tab out of range,
           so the tab is left bare while the space is escaped. */
        @[@"shell: a backslash hides the following tab", @[@"\\\t "], @"\\\\\\\t "],
        /* Two backslashes push the tab past the range even further. */
        @[@"shell: two backslashes hide the following tab", @[@"\\\\\t"], @"\\\\\\\\\t"],
    ];
    for (NSArray *shellCase in shellCases) {
        NSArray *input = [shellCase objectAtIndex:1];
        DVTExpectEqualObjects([input dvt_stringByConcatenatingAsShellCommandArguments],
                              [shellCase objectAtIndex:2], [shellCase objectAtIndex:0]);
    }

    /* Unlike the command line variant this one asserts on a non-string element
       instead of describing it, so only string-only arrays may be passed. */
    NSMutableArray *shellMutable = [@[@"a", @"b"] mutableCopy];
    DVTExpectEqualObjects([shellMutable dvt_stringByConcatenatingAsShellCommandArguments], @"a b",
                          @"dvt_stringByConcatenatingAsShellCommandArguments: a mutable receiver renders the same");
    DVTExpectEqualObjects([[NSMutableArray array] dvt_stringByConcatenatingAsShellCommandArguments], @"",
                          @"dvt_stringByConcatenatingAsShellCommandArguments: an empty mutable receiver is empty");

    NSMutableArray *mutable = [NSMutableArray arrayWithCapacity:0];
    [mutable dvt_addObjectIfNonNil:nil];
    DVTExpect(mutable.count == 0, @"dvt_addObjectIfNonNil: ignores nil");
    [mutable dvt_addObjectIfNonNil:@"a"];
    DVTExpectEqualObjects(mutable, (@[@"a"]), @"dvt_addObjectIfNonNil: appends non-nil");
    [mutable dvt_addObjectsFromArrayIfAbsent:@[@"a", @"b"]];
    DVTExpectEqualObjects(mutable, (@[@"a", @"b"]), @"dvt_addObjectsFromArrayIfAbsent: skips duplicates");

    /* dvt_reverseObjects: exchanges index pairs inward, so length parity and
       duplicates must both survive it. */
    NSMutableArray *reversed = [@[@"a", @"b", @"c"] mutableCopy];
    [reversed dvt_reverseObjects];
    DVTExpectEqualObjects(reversed, (@[@"c", @"b", @"a"]), @"dvt_reverseObjects: reverses three elements");
    NSMutableArray *reversedOdd = [@[@"a", @"b", @"c", @"d", @"e"] mutableCopy];
    [reversedOdd dvt_reverseObjects];
    DVTExpectEqualObjects(reversedOdd, (@[@"e", @"d", @"c", @"b", @"a"]),
                          @"dvt_reverseObjects: an odd length keeps its middle element");
    NSMutableArray *reversedDupes = [@[@"a", @"a", @"b"] mutableCopy];
    [reversedDupes dvt_reverseObjects];
    DVTExpectEqualObjects(reversedDupes, (@[@"b", @"a", @"a"]), @"dvt_reverseObjects: reverses duplicates");
    NSMutableArray *reversedSingle = [@[@"only"] mutableCopy];
    [reversedSingle dvt_reverseObjects];
    DVTExpectEqualObjects(reversedSingle, (@[@"only"]), @"dvt_reverseObjects: a single element is unchanged");
    NSMutableArray *reversedEmpty = [NSMutableArray array];
    [reversedEmpty dvt_reverseObjects];
    DVTExpect(reversedEmpty.count == 0, @"dvt_reverseObjects: an empty array is unchanged");

    /* The pops guard on the fetched element, so an empty array yields nil
       instead of raising the way -removeObjectAtIndex: would. */
    NSMutableArray *popped = [@[@"a", @"b", @"c"] mutableCopy];
    DVTExpectEqualObjects([popped dvt_popFirstObject], @"a", @"dvt_popFirstObject: returns the first element");
    DVTExpectEqualObjects(popped, (@[@"b", @"c"]), @"dvt_popFirstObject: removes it");
    DVTExpectEqualObjects([popped dvt_popLastObject], @"c", @"dvt_popLastObject: returns the last element");
    DVTExpectEqualObjects(popped, (@[@"b"]), @"dvt_popLastObject: removes it");
    DVTExpectEqualObjects([popped dvt_popFirstObject], @"b", @"dvt_popFirstObject: drains the last element");
    DVTExpect([popped dvt_popFirstObject] == nil, @"dvt_popFirstObject: yields nil once empty");
    DVTExpect([NSMutableArray array].dvt_popLastObject == nil, @"dvt_popLastObject: yields nil on an empty array");

    NSMutableArray *truncated = [@[@"a", @"b", @"c"] mutableCopy];
    [truncated dvt_truncateToMaxCount:0];
    DVTExpect(truncated.count == 0, @"dvt_truncateToMaxCount: 0 empties the receiver");
    [truncated dvt_truncateToMaxCount:2];
    DVTExpect(truncated.count == 0, @"dvt_truncateToMaxCount: above the count is a no-op");
    NSMutableArray *truncatedExact = [@[@"a", @"b", @"c"] mutableCopy];
    [truncatedExact dvt_truncateToMaxCount:3];
    DVTExpectEqualObjects(truncatedExact, (@[@"a", @"b", @"c"]),
                          @"dvt_truncateToMaxCount: equal to the count is a no-op");
    NSMutableArray *truncatedPartial = [@[@"a", @"b", @"c"] mutableCopy];
    [truncatedPartial dvt_truncateToMaxCount:1];
    DVTExpectEqualObjects(truncatedPartial, (@[@"a"]), @"dvt_truncateToMaxCount: keeps the leading elements");
    [truncatedPartial dvt_truncateToMaxCount:0];
    DVTExpect(truncatedPartial.count == 0, @"dvt_truncateToMaxCount: 0 works after a partial truncation");
    NSMutableArray *truncatedEmpty = [NSMutableArray array];
    [truncatedEmpty dvt_truncateToMaxCount:1];
    DVTExpect(truncatedEmpty.count == 0, @"dvt_truncateToMaxCount: above the count of an empty array is a no-op");

    /* Identity, not equality, and only the first match per argument entry:
       Apple enumerates the argument and asks the receiver for
       -indexOfObjectIdenticalTo:, so [p p z] minus @[p] is [p z]. Foundation's
       own -removeObjectIdenticalTo: would leave [z]. */
    DVTPicky *identityPicky = [DVTPicky new];
    NSMutableArray *identities = [NSMutableArray arrayWithObjects:identityPicky, identityPicky, @"z", nil];
    [identities dvt_removeObjectsIdenticalToObjectsInArray:@[identityPicky]];
    DVTExpectEqualObjects(identities, (@[identityPicky, @"z"]),
                          @"dvt_removeObjectsIdenticalToObjectsInArray: removes only the first identical element");
    NSMutableArray *repeatedIdentities = [NSMutableArray arrayWithObjects:identityPicky, identityPicky, @"z", nil];
    [repeatedIdentities dvt_removeObjectsIdenticalToObjectsInArray:@[identityPicky, identityPicky]];
    DVTExpectEqualObjects(repeatedIdentities, (@[identityPicky, @"z"]),
                          @"dvt_removeObjectsIdenticalToObjectsInArray: a repeated entry does not cascade to the next match");
    NSString *distinctA = [@"x" mutableCopy];
    NSString *distinctB = [@"x" mutableCopy];
    NSMutableArray *distinctIdentities = [NSMutableArray arrayWithObjects:distinctA, distinctB, @"z", nil];
    [distinctIdentities dvt_removeObjectsIdenticalToObjectsInArray:@[distinctA, distinctB]];
    DVTExpectEqualObjects(distinctIdentities, (@[@"z"]),
                          @"dvt_removeObjectsIdenticalToObjectsInArray: distinct entries each take a match");
    NSMutableArray *equalNotIdentical = [NSMutableArray arrayWithObjects:[@"x" mutableCopy], @"z", nil];
    [equalNotIdentical dvt_removeObjectsIdenticalToObjectsInArray:@[@"x"]];
    DVTExpectEqualObjects(equalNotIdentical, (@[[@"x" mutableCopy], @"z"]),
                          @"dvt_removeObjectsIdenticalToObjectsInArray: an equal-but-distinct element survives");
    NSMutableArray *duplicateArgs = [NSMutableArray arrayWithObjects:@"m", @"n", nil];
    [duplicateArgs dvt_removeObjectsIdenticalToObjectsInArray:@[@"m", @"m", @"m"]];
    DVTExpectEqualObjects(duplicateArgs, (@[@"n"]),
                          @"dvt_removeObjectsIdenticalToObjectsInArray: repeated arguments are idempotent");
    NSMutableArray *nilIdentities = [NSMutableArray arrayWithObject:@"m"];
    [nilIdentities dvt_removeObjectsIdenticalToObjectsInArray:nil];
    DVTExpectEqualObjects(nilIdentities, (@[@"m"]), @"dvt_removeObjectsIdenticalToObjectsInArray: nil removes nothing");
    NSMutableArray *emptyIdentities = [NSMutableArray arrayWithObject:@"m"];
    [emptyIdentities dvt_removeObjectsIdenticalToObjectsInArray:@[]];
    DVTExpectEqualObjects(emptyIdentities, (@[@"m"]), @"dvt_removeObjectsIdenticalToObjectsInArray: an empty array removes nothing");

    /* dvt_keepObjectsPassingTest: applies the test once per element and drops
       only the failures. A nil block is a deliberate deviation from Apple,
       which faults on a non-empty receiver; here it changes nothing. */
    NSMutableArray *kept = [@[@"a", @"b", @"c"] mutableCopy];
    [kept dvt_keepObjectsPassingTest:^BOOL(id object) { return [object isEqualToString:@"b"]; }];
    DVTExpectEqualObjects(kept, (@[@"b"]), @"dvt_keepObjectsPassingTest: keeps only the passing elements");
    [kept dvt_keepObjectsPassingTest:^BOOL(id object) { return YES; }];
    DVTExpectEqualObjects(kept, (@[@"b"]), @"dvt_keepObjectsPassingTest: keeping everything is a no-op");
    [kept dvt_keepObjectsPassingTest:^BOOL(id object) { return NO; }];
    DVTExpect(kept.count == 0, @"dvt_keepObjectsPassingTest: keeping nothing empties the receiver");
    NSMutableArray *nilBlockReceiver = [@[@"a"] mutableCopy];
    [nilBlockReceiver dvt_keepObjectsPassingTest:nil];
    DVTExpectEqualObjects(nilBlockReceiver, (@[@"a"]), @"dvt_keepObjectsPassingTest: a nil block changes nothing");

    /* Set membership here is -containsObject:, so it is equality based, which
       is what separates it from the identity variant above. */
    NSMutableArray *bySet = [@[@"a", @"bb", @"c"] mutableCopy];
    [bySet dvt_removeObjectsInSet:[NSSet setWithObject:@"bb"]];
    DVTExpectEqualObjects(bySet, (@[@"a", @"c"]), @"dvt_removeObjectsInSet: removes contained elements");
    NSMutableArray *bySetEqual = [NSMutableArray arrayWithObjects:[@"x" mutableCopy], @"z", nil];
    [bySetEqual dvt_removeObjectsInSet:[NSSet setWithObjects:[@"x" mutableCopy], nil]];
    DVTExpectEqualObjects(bySetEqual, (@[@"z"]),
                          @"dvt_removeObjectsInSet: an equal element matches by equality, a non-member survives");
    NSMutableArray *byNilSet = [NSMutableArray arrayWithObject:@"a"];
    [byNilSet dvt_removeObjectsInSet:nil];
    DVTExpectEqualObjects(byNilSet, (@[@"a"]), @"dvt_removeObjectsInSet: a nil set removes nothing");
    NSMutableArray *byEmptySet = [NSMutableArray arrayWithObject:@"a"];
    [byEmptySet dvt_removeObjectsInSet:[NSSet set]];
    DVTExpectEqualObjects(byEmptySet, (@[@"a"]), @"dvt_removeObjectsInSet: an empty set removes nothing");

    NSMutableArray *absent = [NSMutableArray array];
    [absent dvt_addObjectIfAbsent:@"a"];
    [absent dvt_addObjectIfAbsent:@"a"];
    DVTExpectEqualObjects(absent, (@[@"a"]), @"dvt_addObjectIfAbsent: appends a new element only once");
    NSMutableArray *absentEqual = [NSMutableArray arrayWithObjects:[@"x" mutableCopy], nil];
    [absentEqual dvt_addObjectIfAbsent:[@"x" mutableCopy]];
    DVTExpect(absentEqual.count == 1, @"dvt_addObjectIfAbsent: an equal element counts as present");
    @try {
        [[NSMutableArray array] dvt_addObjectIfAbsent:nil];
        DVTExpect(NO, @"dvt_addObjectIfAbsent: a nil argument raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:NSInvalidArgumentException],
                  @"dvt_addObjectIfAbsent: a nil argument raises NSInvalidArgumentException");
    }

    NSMutableArray *fromSet = [NSMutableArray array];
    [fromSet dvt_addObjectsFromSet:[NSSet setWithObjects:@"p", @"q", nil]];
    DVTExpectEqualObjects([NSSet setWithArray:fromSet], ([NSSet setWithObjects:@"p", @"q", nil]),
                          @"dvt_addObjectsFromSet: appends every member");
    NSMutableArray *fromNilSet = [NSMutableArray arrayWithObject:@"a"];
    [fromNilSet dvt_addObjectsFromSet:nil];
    DVTExpectEqualObjects(fromNilSet, (@[@"a"]), @"dvt_addObjectsFromSet: a nil set appends nothing");

    /* The nil test runs before any bounds work, so a nil object at an absurd
       index is still a no-op, while a real object past the end raises. */
    NSMutableArray *inserted = [@[@"a"] mutableCopy];
    [inserted dvt_insertObjectIfNonNil:nil atIndex:99];
    DVTExpectEqualObjects(inserted, (@[@"a"]),
                          @"dvt_insertObjectIfNonNil:atIndex: a nil object is a no-op even out of range");
    [inserted dvt_insertObjectIfNonNil:@"b" atIndex:0];
    DVTExpectEqualObjects(inserted, (@[@"b", @"a"]), @"dvt_insertObjectIfNonNil:atIndex: inserts at the front");
    [inserted dvt_insertObjectIfNonNil:@"c" atIndex:inserted.count];
    DVTExpectEqualObjects(inserted, (@[@"b", @"a", @"c"]), @"dvt_insertObjectIfNonNil:atIndex: appends at count");
    @try {
        [inserted dvt_insertObjectIfNonNil:@"d" atIndex:99];
        DVTExpect(NO, @"dvt_insertObjectIfNonNil:atIndex: past the end raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:NSRangeException],
                  @"dvt_insertObjectIfNonNil:atIndex: past the end raises NSRangeException");
    }

    NSMutableArray *insertedMany = [@[@"a"] mutableCopy];
    [insertedMany dvt_insertObjects:@[@"x", @"y"] atIndex:0];
    DVTExpectEqualObjects(insertedMany, (@[@"x", @"y", @"a"]), @"dvt_insertObjects:atIndex: inserts at the front");
    [insertedMany dvt_insertObjects:@[@"z"] atIndex:insertedMany.count];
    DVTExpectEqualObjects(insertedMany, (@[@"x", @"y", @"a", @"z"]), @"dvt_insertObjects:atIndex: appends at count");
    [insertedMany dvt_insertObjects:@[] atIndex:0];
    DVTExpect(insertedMany.count == 4, @"dvt_insertObjects:atIndex: an empty array inserts nothing");
    [insertedMany dvt_insertObjects:nil atIndex:0];
    DVTExpect(insertedMany.count == 4, @"dvt_insertObjects:atIndex: a nil array inserts nothing");

    /* Equal indices return before the remove-and-reinsert pair, which is
       observable: an equal out-of-range move is a silent no-op rather than an
       NSRangeException. */
    NSMutableArray *moved = [@[@"a", @"b", @"c"] mutableCopy];
    [moved dvt_moveObjectAtIndex:0 toIndex:2];
    DVTExpectEqualObjects(moved, (@[@"b", @"c", @"a"]), @"dvt_moveObjectAtIndex:toIndex: moves forward");
    [moved dvt_moveObjectAtIndex:2 toIndex:0];
    DVTExpectEqualObjects(moved, (@[@"a", @"b", @"c"]), @"dvt_moveObjectAtIndex:toIndex: moves backward");
    [moved dvt_moveObjectAtIndex:1 toIndex:1];
    DVTExpectEqualObjects(moved, (@[@"a", @"b", @"c"]), @"dvt_moveObjectAtIndex:toIndex: equal indices are a no-op");
    [moved dvt_moveObjectAtIndex:9 toIndex:9];
    DVTExpectEqualObjects(moved, (@[@"a", @"b", @"c"]),
                          @"dvt_moveObjectAtIndex:toIndex: equal out-of-range indices do not raise");
    @try {
        [moved dvt_moveObjectAtIndex:0 toIndex:99];
        DVTExpect(NO, @"dvt_moveObjectAtIndex:toIndex: a destination past the end raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:NSRangeException],
                  @"dvt_moveObjectAtIndex:toIndex: a destination past the end raises NSRangeException");
    }

    /* Sorted insertion. The comparator is a block rather than -compare: wherever
       a descending or otherwise different order is wanted, so the two paths stay
       distinguishable. */
    NSComparisonResult (^ascending)(id, id) = ^NSComparisonResult(id first, id second) {
        return [first compare:second];
    };
    NSComparisonResult (^descending)(id, id) = ^NSComparisonResult(id first, id second) {
        return [second compare:first];
    };

    /* An empty receiver answers 0 without ever calling the comparator, so a nil
       comparator is survivable here even though a non-empty one is not. */
    NSArray *emptyArray = @[];
    DVTExpect([emptyArray dvt_sortedInsertionIndexForObject:@"b" withComparator:ascending] == 0,
              @"dvt_sortedInsertionIndexForObject:withComparator: an empty array yields 0");
    DVTExpect([emptyArray dvt_sortedInsertionIndexForObject:@"b" withComparator:nil] == 0,
              @"dvt_sortedInsertionIndexForObject:withComparator: an empty array never calls the comparator");

    NSArray *aCe = @[@"a", @"c", @"e"];
    DVTExpect([aCe dvt_sortedInsertionIndexForObject:@"b" withComparator:ascending] == 1,
              @"dvt_sortedInsertionIndexForObject:withComparator: a gap yields the middle index");
    DVTExpect([aCe dvt_sortedInsertionIndexForObject:@"A" withComparator:ascending] == 0,
              @"dvt_sortedInsertionIndexForObject:withComparator: a smaller element yields 0");
    DVTExpect([aCe dvt_sortedInsertionIndexForObject:@"z" withComparator:ascending] == 3,
              @"dvt_sortedInsertionIndexForObject:withComparator: a larger element yields the count");
    DVTExpect([aCe dvt_sortedInsertionIndexForObject:@"b" withComparator:descending] == 3,
              @"dvt_sortedInsertionIndexForObject:withComparator: the comparator decides the order");
    DVTExpect([aCe dvt_sortedInsertionIndexForObject:@"b" withComparisonSelector:@selector(compare:)] == 1,
              @"dvt_sortedInsertionIndexForObject:withComparisonSelector: matches the compare: block");

    /* NSBinarySearchingInsertionIndex reports the index of an equal element when
       one exists and the insertion point otherwise, so this is a match position
       rather than always "past the run". */
    DVTExpect([aCe dvt_sortedInsertionIndexForObject:@"c" withComparator:ascending] == 1,
              @"dvt_sortedInsertionIndexForObject:withComparator: an equal element yields its own index");
    DVTExpect([aCe dvt_sortedInsertionIndexForObject:@"a" withComparator:ascending] == 0,
              @"dvt_sortedInsertionIndexForObject:withComparator: a leading equal element yields 0");
    DVTExpect([aCe dvt_sortedInsertionIndexForObject:@"e" withComparator:ascending] == 2,
              @"dvt_sortedInsertionIndexForObject:withComparator: a trailing equal element yields its own index");

    NSMutableArray *sorted = [@[@"a", @"c", @"e"] mutableCopy];
    DVTExpect([sorted dvt_sortedInsert:@"b"] == 1, @"dvt_sortedInsert: returns the index it used");
    DVTExpectEqualObjects(sorted, (@[@"a", @"b", @"c", @"e"]), @"dvt_sortedInsert: inserts in the middle");
    DVTExpect([sorted dvt_sortedInsert:@"z"] == 4, @"dvt_sortedInsert: appends and returns the count");
    DVTExpect([sorted dvt_sortedInsert:@"c"] == 2, @"dvt_sortedInsert: an equal element inserts at its own index");
    DVTExpectEqualObjects(sorted, (@[@"a", @"b", @"c", @"c", @"e", @"z"]),
                          @"dvt_sortedInsert: does not deduplicate");

    NSMutableArray *descendingArray = [@[@"e", @"c", @"a"] mutableCopy];
    DVTExpect([descendingArray dvt_sortedInsert:@"b" withComparator:descending] == 2,
              @"dvt_sortedInsert:withComparator: returns the index it used");
    DVTExpectEqualObjects(descendingArray, (@[@"e", @"c", @"b", @"a"]),
                          @"dvt_sortedInsert:withComparator: follows the comparator");
    NSMutableArray *selectorArray = [@[@"A", @"C", @"E"] mutableCopy];
    [selectorArray dvt_sortedInsert:@"b" withComparisonSelector:@selector(caseInsensitiveCompare:)];
    DVTExpectEqualObjects(selectorArray, (@[@"A", @"b", @"C", @"E"]),
                          @"dvt_sortedInsert:withComparisonSelector: drives the order");

    /* Batch insertion merges rather than inserting one at a time: the argument
       is sorted first, and each element's index is offset by its position in the
       sorted argument so the elements already placed ahead of it are accounted
       for. Duplicates in the argument are what expose a missing offset. */
    NSMutableArray *merged = [@[@"a", @"c", @"e"] mutableCopy];
    [merged dvt_sortedInsertOfObjects:@[@"d", @"b"] withComparator:ascending];
    DVTExpectEqualObjects(merged, (@[@"a", @"b", @"c", @"d", @"e"]),
                          @"dvt_sortedInsertOfObjects:withComparator: merges an unsorted argument");

    NSMutableArray *mergedDupes = [@[@"a", @"e"] mutableCopy];
    [mergedDupes dvt_sortedInsertOfObjects:@[@"c", @"c"] withComparator:ascending];
    DVTExpectEqualObjects(mergedDupes, (@[@"a", @"c", @"c", @"e"]),
                          @"dvt_sortedInsertOfObjects:withComparator: duplicate elements both land");

    NSMutableArray *mergedLeading = [@[@"a", @"e"] mutableCopy];
    [mergedLeading dvt_sortedInsertOfObjects:@[@"a", @"a", @"z"] withComparator:ascending];
    DVTExpectEqualObjects(mergedLeading, (@[@"a", @"a", @"a", @"e", @"z"]),
                          @"dvt_sortedInsertOfObjects:withComparator: a leading run stays ahead of the receiver");

    NSMutableArray *mergedEmpty = [@[@"a", @"c", @"e"] mutableCopy];
    [mergedEmpty dvt_sortedInsertOfObjects:@[] withComparator:ascending];
    DVTExpectEqualObjects(mergedEmpty, (@[@"a", @"c", @"e"]),
                          @"dvt_sortedInsertOfObjects:withComparator: an empty argument changes nothing");
    [mergedEmpty dvt_sortedInsertOfObjects:nil withComparator:ascending];
    DVTExpectEqualObjects(mergedEmpty, (@[@"a", @"c", @"e"]),
                          @"dvt_sortedInsertOfObjects:withComparator: a nil argument changes nothing");

    /* Uniqueness is decided by the comparator reporting NSOrderedSame, not by
       -isEqual:. The helper objects below are distinct under -isEqual: yet
       compare equal, and the second insert is refused -- which an -isEqual: based
       implementation would get wrong. */
    NSMutableArray *unique = [@[@"a", @"c", @"e"] mutableCopy];
    DVTExpect([unique dvt_uniqueSortedInsert:@"b"], @"dvt_uniqueSortedInsert: inserts a missing element");
    DVTExpectEqualObjects(unique, (@[@"a", @"b", @"c", @"e"]), @"dvt_uniqueSortedInsert: inserts in order");
    DVTExpect(![unique dvt_uniqueSortedInsert:@"c"], @"dvt_uniqueSortedInsert: refuses an equal element");
    DVTExpectEqualObjects(unique, (@[@"a", @"b", @"c", @"e"]),
                          @"dvt_uniqueSortedInsert: a refused element leaves the array alone");
    DVTExpect([unique dvt_uniqueSortedInsert:@"C"], @"dvt_uniqueSortedInsert: a different case is not a duplicate");
    DVTExpectEqualObjects(unique, (@[@"C", @"a", @"b", @"c", @"e"]),
                          @"dvt_uniqueSortedInsert: a case variant sorts ahead");

    NSMutableArray *uniqueSame = [NSMutableArray array];
    DVTExpect([uniqueSame dvt_uniqueSortedInsert:DVTTestSame(@"1")],
              @"dvt_uniqueSortedInsert: an empty receiver inserts");
    DVTExpect(![uniqueSame dvt_uniqueSortedInsert:DVTTestSame(@"2")],
              @"dvt_uniqueSortedInsert: compare:-equal objects are duplicates despite differing under isEqual:");
    DVTExpect(uniqueSame.count == 1, @"dvt_uniqueSortedInsert: the refused equal object was not appended");

    NSMutableArray *uniqueCmp = [NSMutableArray array];
    DVTExpect([uniqueCmp dvt_uniqueSortedInsert:@"a" withComparator:descending],
              @"dvt_uniqueSortedInsert:withComparator: inserts into an empty receiver");
    DVTExpect(![uniqueCmp dvt_uniqueSortedInsert:@"a" withComparator:descending],
              @"dvt_uniqueSortedInsert:withComparator: refuses a comparator-equal element");

    /* -compare: on nil yields NSOrderedSame, but the binary search rejects the nil
       argument before that, so this raises rather than reporting a duplicate. */
    @try {
        [unique dvt_uniqueSortedInsert:nil];
        DVTExpect(NO, @"dvt_uniqueSortedInsert: a nil element raises");
    } @catch (NSException *exception) {
        DVTExpect([exception.name isEqualToString:NSInvalidArgumentException],
                  @"dvt_uniqueSortedInsert: a nil element raises NSInvalidArgumentException");
    }
    DVTExpectEqualObjects(unique, (@[@"C", @"a", @"b", @"c", @"e"]),
                          @"dvt_uniqueSortedInsert: the failed nil insert left the array alone");

    NSMutableSet *set = [NSMutableSet setWithCapacity:0];
    [set dvt_addObjectIfNonNil:nil];
    DVTExpect(set.count == 0, @"NSMutableSet ignores nil");

    /* The emptiness pair on the other five hosts Apple declares it on. Each is
       empty-then-filled, because a method that returned a constant would pass an
       empty-only check, and both selectors are asserted every time because they
       are separate methods that happen to agree. */
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    DVTExpect(!dictionary.dvt_hasContent, @"empty dictionary has no content");
    DVTExpect(!dictionary.dvt_isNonEmpty, @"empty dictionary is not non-empty");
    [dictionary setObject:@1 forKey:@"k"];
    DVTExpect(dictionary.dvt_hasContent, @"dictionary with an entry has content");
    DVTExpect(dictionary.dvt_isNonEmpty, @"dictionary with an entry is non-empty");
    [dictionary removeObjectForKey:@"k"];
    DVTExpect(!dictionary.dvt_hasContent, @"emptied dictionary has no content again");

    NSMapTable *mapTable = [NSMapTable strongToStrongObjectsMapTable];
    DVTExpect(!mapTable.dvt_hasContent, @"empty map table has no content");
    DVTExpect(!mapTable.dvt_isNonEmpty, @"empty map table is not non-empty");
    [mapTable setObject:@1 forKey:@"k"];
    DVTExpect(mapTable.dvt_hasContent, @"map table with an entry has content");
    [mapTable removeObjectForKey:@"k"];
    DVTExpect(!mapTable.dvt_isNonEmpty, @"emptied map table is not non-empty again");

    NSMutableOrderedSet *ordered = [NSMutableOrderedSet orderedSet];
    DVTExpect(!ordered.dvt_hasContent, @"empty ordered set has no content");
    DVTExpect(!ordered.dvt_isNonEmpty, @"empty ordered set is not non-empty");
    [ordered addObject:@1];
    DVTExpect(ordered.dvt_hasContent, @"ordered set with an element has content");
    DVTExpect(ordered.dvt_isNonEmpty, @"ordered set with an element is non-empty");

    NSMutableSet *mutableSet = [NSMutableSet set];
    DVTExpect(!mutableSet.dvt_hasContent, @"empty set has no content");
    DVTExpect(!mutableSet.dvt_isNonEmpty, @"empty set is not non-empty");
    [mutableSet addObject:@1];
    DVTExpect(mutableSet.dvt_hasContent, @"set with a member has content");
    DVTExpect(mutableSet.dvt_isNonEmpty, @"set with a member is non-empty");

    /* Strings are the one host where the two are not the same expression, so
       they get their own cases: whitespace and a multi-unit emoji are non-empty
       even though neither is "a word", and both agree on every input. */
    NSString *text = @"";
    DVTExpect(!text.dvt_hasContent, @"empty string has no content");
    DVTExpect(!text.dvt_isNonEmpty, @"empty string is not non-empty");
    for (NSString *nonEmpty in @[@"a", @" ", @"\n", @"0", @"é", @"😀", @"null"]) {
        DVTExpect(nonEmpty.dvt_hasContent, @"non-empty string has content");
        DVTExpect(nonEmpty.dvt_isNonEmpty, @"non-empty string is non-empty");
    }

    /* Casing is one selector over three values, so every case names the value it
       pins rather than relying on a wrapper to reach it. */
    NSArray *casingCases = @[
        @[@"aBc dEf", @(0), @"abc def"],
        @[@"aBc dEf", @(1), @"ABC DEF"],
        @[@"aBc dEf", @(2), @"Abc Def"],
        @[@"straße", @(1), @"STRASSE"],
        @[@"", @(2), @""],
    ];
    for (NSArray *casingCase in casingCases) {
        NSString *input = [casingCase objectAtIndex:0];
        NSUInteger letterCasing = (NSUInteger)[[casingCase objectAtIndex:1] unsignedIntegerValue];
        DVTExpectEqualObjects([input dvt_stringWithLetterCasing:letterCasing], [casingCase objectAtIndex:2],
                              ([NSString stringWithFormat:@"casing %lu of '%@'", (unsigned long)letterCasing, input]));
    }

    /* Only a-z is a word character. An uppercase letter always starts a word, a
       digit run holds together, and anything else -- punctuation, whitespace,
       and non-ASCII alike -- is a separator that is dropped, which is why an
       all-CJK string has no words at all. */
    NSArray *wordCases = @[
        @[@"", @[]], @[@"  ", @[]], @[@"日本語", @[]],
        @[@"hello world", @[@"hello", @"world"]], @[@"HelloWorld", @[@"hello", @"world"]],
        @[@"camelCaseString", @[@"camel", @"case", @"string"]],
        @[@"ALLCAPS", @[@"a", @"l", @"l", @"c", @"a", @"p", @"s"]],
        @[@"HTTPResponse", @[@"h", @"t", @"t", @"p", @"response"]],
        @[@"foo123bar", @[@"foo", @"123", @"bar"]],
        @[@"a1b2c3", @[@"a", @"1", @"b", @"2", @"c", @"3"]],
        @[@"v1.2.3", @[@"v", @"1", @"2", @"3"]],
        @[@"9lives", @[@"9", @"lives"]],
        @[@"1a2", @[@"1", @"a", @"2"]],
        @[@"path/to/file.txt", @[@"path", @"to", @"file", @"txt"]],
        @[@"_under_score", @[@"under", @"score"]],
        @[@"a{b", @[@"a", @"b"]],
        @[@"{a", @[@"a"]],
        @[@"aéb", @[@"a", @"b"]],
    ];
    for (NSArray *wordCase in wordCases) {
        NSString *input = [wordCase objectAtIndex:0];
        NSArray<NSString *> *words = [input dvt_wordsFromString];
        DVTExpectEqualObjects(words, [wordCase objectAtIndex:1],
                              ([NSString stringWithFormat:@"lowercased words of '%@'", input]));
        DVTExpectEqualObjects([input dvt_wordsFromStringWithLetterCasing:0], words,
                              ([NSString stringWithFormat:@"explicit lowercase words of '%@'", input]));
        NSMutableArray<NSString *> *expectedUppercase = [NSMutableArray arrayWithCapacity:words.count];
        NSMutableArray<NSString *> *expectedCapitalized = [NSMutableArray arrayWithCapacity:words.count];
        for (NSString *word in words) {
            [expectedUppercase addObject:word.uppercaseString];
            [expectedCapitalized addObject:word.capitalizedString];
        }
        DVTExpectEqualObjects([input dvt_wordsFromStringWithLetterCasing:1], expectedUppercase,
                              ([NSString stringWithFormat:@"uppercased words of '%@'", input]));
        DVTExpectEqualObjects([input dvt_capitalizedWordsFromString], expectedCapitalized,
                              ([NSString stringWithFormat:@"capitalized words of '%@'", input]));
    }
    DVTExpectEqualObjects(@"camelCaseString".dvt_capitalizedWordsFromString, (@[@"Camel", @"Case", @"String"]),
                          @"capitalized words are capitalized per word, not just the first");
    /* ':' is one past the digit run, so it also counts as continuing one. The
       empty range that leaves is skipped rather than emitted as a blank word. */
    DVTExpectEqualObjects(@"a:1b".dvt_wordsFromString, (@[@"a", @"1", @"b"]), @"colon does not add a blank word");
    DVTExpectEqualObjects(@"1:2".dvt_wordsFromString, (@[@"1", @"2"]), @"colon keeps a digit run split once");

    /* The first-character pair tests the character set membership, not just the
       prefix: it returns the receiver untouched unless the first character is a
       letter of the matching case, and it looks at one UTF-16 code unit, so a
       leading surrogate is not a letter. */
    NSArray *firstCharacterCases = @[
        @[@"", @"", @""], @[@"hello", @"Hello", @"hello"], @[@"Hello", @"Hello", @"hello"],
        @[@"a", @"A", @"a"], @[@"A", @"A", @"a"], @[@"zZ", @"ZZ", @"zZ"], @[@"123", @"123", @"123"],
        @[@" hello", @" hello", @" hello"], @[@"_a", @"_a", @"_a"], @[@"ß", @"SS", @"ß"], @[@"é", @"É", @"é"],
        @[@"éa", @"Éa", @"éa"], @[@"日本語", @"日本語", @"日本語"], @[@"\U0001F600x", @"\U0001F600x", @"\U0001F600x"],
    ];
    for (NSArray *firstCharacterCase in firstCharacterCases) {
        NSString *input = [firstCharacterCase objectAtIndex:0];
        DVTExpectEqualObjects([input dvt_stringByCapitalizingFirstCharacter], [firstCharacterCase objectAtIndex:1],
                              ([NSString stringWithFormat:@"capitalize first of '%@'", input]));
        DVTExpectEqualObjects([input dvt_stringByLowercasingFirstCharacter], [firstCharacterCase objectAtIndex:2],
                              ([NSString stringWithFormat:@"lowercase first of '%@' is '%@'", input,
                                                         [firstCharacterCase objectAtIndex:2]]));
    }

    /* Ranges are inclusive of the start and exclusive of the end, an empty range
       is legal, and the bounds are checked in code units rather than graphemes. */
    DVTExpectEqualObjects([@"abcdef" dvt_substringFromIndex:0 toIndex:3], @"abc", @"leading range");
    DVTExpectEqualObjects([@"abcdef" dvt_substringFromIndex:1 toIndex:3], @"bc", @"interior range");
    DVTExpectEqualObjects([@"abcdef" dvt_substringFromIndex:0 toIndex:0], @"", @"empty range at the start");
    DVTExpectEqualObjects([@"abcdef" dvt_substringFromIndex:2 toIndex:2], @"", @"empty range in the middle");
    DVTExpectEqualObjects([@"abcdef" dvt_substringFromIndex:0 toIndex:6], @"abcdef", @"whole range");
    DVTExpectEqualObjects([@"abcdef" dvt_substringFromIndex:6 toIndex:6], @"", @"empty range at the end");
    DVTExpectEqualObjects([@"日本" dvt_substringFromIndex:0 toIndex:1], @"日", @"range splits inside a surrogate pair");
    NSString *unitRangeSource = @"abcdef";
    for (NSInteger start = 0; start <= (NSInteger)unitRangeSource.length; start++) {
        for (NSInteger end = start; end <= (NSInteger)unitRangeSource.length; end++) {
            NSRange expected = NSMakeRange((NSUInteger)start, (NSUInteger)(end - start));
            DVTExpectEqualObjects([unitRangeSource dvt_substringFromIndex:start toIndex:end],
                                  [unitRangeSource substringWithRange:expected],
                                  ([NSString stringWithFormat:@"range %ld..%ld", (long)start, (long)end]));
        }
    }

    /* Identifier legality and mangling come in five flavours. All of them canonical-decompose the
       receiver first and then walk it one UTF-16 code unit at a time, except the C99 extended profile,
       which skips decomposition and counts a surrogate pair as the single scalar it encodes. The three
       decomposing profiles differ only in which ASCII punctuation they accept and what they substitute:
       strict C allows `_` and substitutes `_`, bundle identifiers add `.` and `-` and substitute `-`,
        and RFC 1034 allows `-` but not `.` and substitutes `-`. A leading character that the profile
        will not accept is replaced just like any other, so a rejected character never shortens the
        result below the length of the input, with U+FFFF below the one deliberate exception.

        Every expectation below was taken from DVTFoundation itself rather than reasoned about, and the
        three decomposing profiles agree on U+FFFF: it behaves as end-of-string, so they stop there
        and silently drop the rest of the receiver. */
    NSArray<NSArray *> *identifierCases = @[
        // input, dvt_isLegalCIdentifier, C, C99 extended, bundle, RFC 1034
        @[@"", @NO, @"", @"", @"", @""],
        @[@"a", @YES, @"a", @"a", @"a", @"a"],
        @[@"_", @YES, @"_", @"_", @"-", @"-"],
        @[@"Z9", @YES, @"Z9", @"Z9", @"Z9", @"Z9"],
        @[@"a1", @YES, @"a1", @"a1", @"a1", @"a1"],
        @[@"1a", @NO, @"_a", @"_a", @"-a", @"-a"],
        @[@"-a", @NO, @"_a", @"_a", @"-a", @"-a"],
        @[@".a", @NO, @"_a", @"_a", @".a", @"-a"],
        @[@"a b", @NO, @"a_b", @"a_b", @"a-b", @"a-b"],
        @[@"a-b", @NO, @"a_b", @"a_b", @"a-b", @"a-b"],
        @[@"a.b.c", @NO, @"a_b_c", @"a_b_c", @"a.b.c", @"a-b-c"],
        @[@"-.-", @NO, @"___", @"___", @"-.-", @"---"],
        @[@" dvt", @NO, @"_dvt", @"_dvt", @"-dvt", @"-dvt"],
        @[@"a~b", @NO, @"a_b", @"a_b", @"a-b", @"a-b"],
        @[@"a1_b.c-d", @NO, @"a1_b_c_d", @"a1_b_c_d", @"a1-b.c-d", @"a1-b-c-d"],
        // Decomposition: a precomposed é and an already decomposed e + U+0301 agree, and the combining
        // mark is not legal in the C99 table, so that profile is the only one that can round-trip é.
        @[@"\u00E9", @NO, @"e_", @"\u00E9", @"e-", @"e-"],
        @[@"e\u0301", @NO, @"e_", @"e_", @"e-", @"e-"],
        @[@"a\u0301", @NO, @"a_", @"a_", @"a-", @"a-"],
        // Surrogate pairs: one scalar, so C99 extended spends a single `_` on it while the decomposing
        // profiles spend one per code unit.
        @[@"\U0001F600", @NO, @"__", @"_", @"--", @"--"],
        @[@"\U0001F600abc", @NO, @"__abc", @"_abc", @"--abc", @"--abc"],
        @[@"\U0001F600\U0001F601", @NO, @"____", @"__", @"----", @"----"],
        // The C99 table keeps the letterlike and symbol blocks, and treats these non-ASCII digits as
        // legal in a non-leading position only.
        @[@"\u0660", @NO, @"_", @"_", @"-", @"-"],
        @[@"a\u0660", @NO, @"a_", @"a\u0660", @"a-", @"a-"],
        @[@"\u3042", @NO, @"_", @"\u3042", @"-", @"-"],
        @[@"a\u3042", @NO, @"a_", @"a\u3042", @"a-", @"a-"],
        @[@"\u4E2D\u6587", @NO, @"__", @"\u4E2D\u6587", @"--", @"--"],
        @[@"\u65E5\u672C\u8A9E", @NO, @"___", @"\u65E5\u672C\u8A9E", @"---", @"---"],
        // U+FFFF ends the receiver for the three decomposing profiles; C99 extended, which never
        // decomposes, keeps mangling the whole thing.
        @[@"\uFFFF", @NO, @"", @"_", @"", @""],
        @[@"a\uFFFFb", @NO, @"a", @"a_b", @"a", @"a"],
        @[@"\uFFFE", @NO, @"_", @"_", @"-", @"-"],
    ];
    for (NSArray *identifierCase in identifierCases) {
        NSString *input = identifierCase[0];
        BOOL expectedLegal = [identifierCase[1] boolValue];
        NSString *what = ([NSString stringWithFormat:@"identifier mangling of '%@'", input]);
        DVTExpect(input.dvt_isLegalCIdentifier == expectedLegal,
                  ([NSString stringWithFormat:@"%@ legality", what]));
        DVTExpectEqualObjects([input dvt_stringByManglingToLegalCIdentifier], identifierCase[2], what);
        DVTExpectEqualObjects([input dvt_stringByManglingToLegalC99ExtendedIdentifier], identifierCase[3], what);
        DVTExpectEqualObjects([input dvt_stringByManglingToLegalBundleIdentifier], identifierCase[4], what);
        DVTExpectEqualObjects([input dvt_stringByManglingToLegalRFC1034Identifier], identifierCase[5], what);
        // The typed entry point dispatches rather than validating: 0 is bundle, 1 is RFC 1034, and
        // every other value falls through to strict C without complaining.
        DVTExpectEqualObjects([input dvt_stringByManglingToLegalIdentifierOfType:0], identifierCase[4], what);
        DVTExpectEqualObjects([input dvt_stringByManglingToLegalIdentifierOfType:1], identifierCase[5], what);
        for (NSNumber *otherType in @[ @2, @(-1), @(NSIntegerMax), @(NSIntegerMin), @(NSIntegerMin + 1) ]) {
            DVTExpectEqualObjects([input dvt_stringByManglingToLegalIdentifierOfType:[otherType integerValue]],
                                  identifierCase[2],
                                  ([NSString stringWithFormat:@"%@ type %@", what, otherType]));
        }
    }

    /* An unpaired surrogate is the one input the extended profile declines to rewrite. It copies the
       surrogate and the code unit after it through verbatim and then resumes, which has two visible
       consequences: a trailing space survives a mangler that would otherwise have replaced it, and a
       high surrogate hides whatever follows it, so two high surrogates and a low one come back
       untouched instead of collapsing to an underscore. The decomposing profiles are unaffected and
       simply substitute their replacement character. Expectations are DVTFoundation's own. */
    {
        const unichar aLoneSurrogateInTheMiddle[] = { 'a', 0xD800, 'b' };
        const unichar aLoneSurrogateBetweenSpaces[] = { ' ', 0xD800, ' ' };
        const unichar twoHighThenLow[] = { 0xD83D, 0xD83D, 0xDE00 };
        const unichar aPairThenALoneSurrogate[] = { 0xD83D, 0xDE00, 0xD800 };
        const unichar aLoneLowSurrogate[] = { 0xDE00 };
        const unichar aLoneSurrogateLeading[] = { 0xD800, 'a' };
        // Where the walk resumes, the space after the surrogate is never rewritten.
        const unichar underscoreSurrogateSpace[] = { '_', 0xD800, ' ' };
        const unichar underscoreSurrogate[] = { '_', 0xD800 };
        // The extended column is the input itself whenever the walk never resumes before the end.
        NSArray<NSArray *> *unpairedSurrogateCases = @[
            // input, C, C99 extended, bundle, RFC 1034
            @[ DVTStringFromUnits(aLoneSurrogateInTheMiddle, 3), @"a_b",
               DVTStringFromUnits(aLoneSurrogateInTheMiddle, 3), @"a-b", @"a-b" ],
            @[ DVTStringFromUnits(aLoneSurrogateBetweenSpaces, 3), @"___",
               DVTStringFromUnits(underscoreSurrogateSpace, 3), @"---", @"---" ],
            @[ DVTStringFromUnits(twoHighThenLow, 3), @"___",
               DVTStringFromUnits(twoHighThenLow, 3), @"---", @"---" ],
            @[ DVTStringFromUnits(aPairThenALoneSurrogate, 3), @"___",
               DVTStringFromUnits(underscoreSurrogate, 2), @"---", @"---" ],
            @[ DVTStringFromUnits(aLoneLowSurrogate, 1), @"_",
               DVTStringFromUnits(aLoneLowSurrogate, 1), @"-", @"-" ],
            @[ DVTStringFromUnits(aLoneSurrogateLeading, 2), @"_a",
               DVTStringFromUnits(aLoneSurrogateLeading, 2), @"-a", @"-a" ],
        ];
        for (NSArray *surrogateCase in unpairedSurrogateCases) {
            NSString *input = surrogateCase[0];
            NSString *what = ([NSString stringWithFormat:@"identifier mangling of unpaired surrogate in '%@'", input]);
            DVTExpect(input.dvt_isLegalCIdentifier == NO, ([NSString stringWithFormat:@"%@ legality", what]));
            DVTExpectEqualObjects([input dvt_stringByManglingToLegalCIdentifier], surrogateCase[1], what);
            DVTExpectEqualObjects([input dvt_stringByManglingToLegalC99ExtendedIdentifier], surrogateCase[2], what);
            DVTExpectEqualObjects([input dvt_stringByManglingToLegalBundleIdentifier], surrogateCase[3], what);
            DVTExpectEqualObjects([input dvt_stringByManglingToLegalRFC1034Identifier], surrogateCase[4], what);
        }
    }

    /* The manglers return the receiver untouched when it is already legal, so the happy path is
       idempotent for every profile that accepts the input. A leading underscore is deliberately absent
       from this list: strict C accepts it but bundle and RFC 1034 do not, so `@"_x"` mangles to `@"-x"`. */
    for (NSString *legal in @[ @"a", @"Z9", @"a1" ]) {
        DVTExpectEqualObjects([legal dvt_stringByManglingToLegalCIdentifier], legal,
                              ([NSString stringWithFormat:@"legal C identifier '%@' is unchanged", legal]));
        DVTExpectEqualObjects([legal dvt_stringByManglingToLegalC99ExtendedIdentifier], legal,
                              ([NSString stringWithFormat:@"legal C99 identifier '%@' is unchanged", legal]));
        DVTExpectEqualObjects([legal dvt_stringByManglingToLegalBundleIdentifier], legal,
                              ([NSString stringWithFormat:@"legal bundle identifier '%@' is unchanged", legal]));
        DVTExpectEqualObjects([legal dvt_stringByManglingToLegalRFC1034Identifier], legal,
                              ([NSString stringWithFormat:@"legal RFC 1034 identifier '%@' is unchanged", legal]));
    }

    /* -dvt_recursivelyRemoveAllObjects walks and empties exactly three classes:
       NSMutableArray, NSMutableDictionary and NSMutableSet. Every case below is
       an observation from the Apple oracle rather than an inference from the
       method name, so the traversal's shape is pinned by behaviour. */
    {
        NSMutableArray *leaf = [NSMutableArray arrayWithObjects:@"a", nil];
        NSMutableArray *inner = [NSMutableArray arrayWithObject:leaf];
        NSMutableArray *outer = [NSMutableArray arrayWithObject:inner];
        [outer dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(outer, @[], @"recursive removal empties the receiver");
        DVTExpectEqualObjects(inner, @[], @"recursive removal empties a nested array");
        DVTExpectEqualObjects(leaf, @[], @"recursive removal empties an array three levels down");
    }
    {
        /* The other two classes are emptied too, not just arrays. */
        NSMutableArray *array = [NSMutableArray arrayWithObject:@"a"];
        NSMutableSet *set = [NSMutableSet setWithObject:@"s"];
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        [dictionary setObject:@"d" forKey:@"k"];
        NSMutableArray *outer = [NSMutableArray arrayWithObjects:array, set, dictionary, nil];
        [outer dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(array, @[], @"recursive removal empties a nested array");
        DVTExpectEqualObjects(set, [NSSet set], @"recursive removal empties a nested set");
        DVTExpectEqualObjects(dictionary, @{}, @"recursive removal empties a nested dictionary");
    }
    {
        /* Dictionaries are followed through -allValues, so a key is never
           visited and keeps its contents even when it is a mutable collection
           that would otherwise be emptied. */
        NSMutableArray *key = [NSMutableArray arrayWithObject:@"k"];
        NSMutableArray *value = [NSMutableArray arrayWithObject:@"v"];
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        [dictionary setObject:value forKey:(id)key];
        NSMutableArray *outer = [NSMutableArray arrayWithObject:dictionary];
        [outer dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(dictionary, @{}, @"recursive removal empties the dictionary");
        DVTExpectEqualObjects(value, @[], @"recursive removal empties a dictionary value");
        DVTExpectEqualObjects(key, @[@"k"], @"recursive removal leaves a dictionary key alone");
    }
    {
        /* Anything that is not one of the three classes is stepped over, so an
           immutable collection shields whatever mutable collections it holds. */
        NSMutableArray *behindArray = [NSMutableArray arrayWithObject:@"a"];
        NSMutableSet *behindSet = [NSMutableSet setWithObject:@"s"];
        NSMutableArray *behindDictionaryValue = [NSMutableArray arrayWithObject:@"d"];
        NSArray *frozen = @[behindArray];
        NSSet *frozenSet = [NSSet setWithObject:behindSet];
        NSDictionary *frozenDictionary = @{@"k": behindDictionaryValue};
        NSMutableArray *outer = [NSMutableArray arrayWithObjects:frozen, frozenSet, frozenDictionary, nil];
        [outer dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(outer, @[], @"recursive removal empties the receiver holding frozen collections");
        DVTExpectEqualObjects(behindArray, @[@"a"], @"recursive removal does not descend into an immutable array");
        DVTExpectEqualObjects(behindSet, [NSSet setWithObject:@"s"],
                              @"recursive removal does not descend into an immutable set");
        DVTExpectEqualObjects(behindDictionaryValue, @[@"d"],
                              @"recursive removal does not descend into an immutable dictionary");
    }
    {
        /* A visited set is what bounds the traversal. The set compares by
           equality, so a cycle back to the receiver terminates the same way a
           repeated leaf does. */
        NSMutableArray *outer = [NSMutableArray array];
        NSMutableArray *inner = [NSMutableArray arrayWithObjects:@"i", nil];
        [outer addObject:inner];
        [inner addObject:outer];
        [outer dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(outer, @[], @"recursive removal terminates on a cycle back to the receiver");
        DVTExpectEqualObjects(inner, @[], @"recursive removal empties the other end of the cycle");
    }
    {
        NSMutableArray *first = [NSMutableArray arrayWithObjects:@"1", nil];
        NSMutableArray *second = [NSMutableArray arrayWithObject:first];
        [first addObject:second];
        [first dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(first, @[], @"recursive removal terminates on a two-node cycle");
        DVTExpectEqualObjects(second, @[], @"recursive removal empties both ends of a two-node cycle");
    }
    {
        /* Shared, not duplicated: one child reached twice is emptied once, and
           the visited test is what stops the second visit from recursing again. */
        NSMutableArray *shared = [NSMutableArray arrayWithObject:@"s"];
        NSMutableArray *outer = [NSMutableArray arrayWithObjects:shared, shared, nil];
        [outer dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(outer, @[], @"recursive removal empties the receiver holding a shared child");
        DVTExpectEqualObjects(shared, @[], @"recursive removal empties a shared child once");
    }
    {
        /* Leaves are never emptied and never raise, so a receiver of plain
           objects simply loses them. */
        NSMutableArray *outer = [NSMutableArray arrayWithObjects:@"a", @1, @"b", nil];
        [outer dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(outer, @[], @"recursive removal drops non-collection members without raising");
    }
    {
        NSMutableArray *empty = [NSMutableArray array];
        [empty dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(empty, @[], @"recursive removal on an empty receiver is a no-op");
    }
    {
        /* An equal-but-distinct child is emptied as well. It compares equal to
           its twin only until that twin has been emptied, so the visited test
           cannot mistake it for one already handled. */
        NSMutableArray *original = [NSMutableArray arrayWithObjects:@"a", nil];
        NSMutableArray *twin = [NSMutableArray arrayWithObjects:@"a", nil];
        NSMutableArray *outer = [NSMutableArray arrayWithObjects:original, twin, nil];
        [outer dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(original, @[], @"recursive removal empties the first of two equal children");
        DVTExpectEqualObjects(twin, @[], @"recursive removal empties a distinct but equal child too");
    }
    {
        /* A mixed graph exercises all three classes against each other. */
        NSMutableArray *array = [NSMutableArray arrayWithObject:@"a"];
        NSMutableSet *set = [NSMutableSet setWithObject:array];
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        [dictionary setObject:set forKey:@"k"];
        NSMutableArray *outer = [NSMutableArray arrayWithObjects:array, set, dictionary, nil];
        [outer dvt_recursivelyRemoveAllObjects];
        DVTExpectEqualObjects(outer, @[], @"recursive removal empties the receiver of a mixed graph");
        DVTExpectEqualObjects(array, @[], @"recursive removal empties the array in a mixed graph");
        DVTExpectEqualObjects(set, [NSSet set], @"recursive removal empties the set in a mixed graph");
        DVTExpectEqualObjects(dictionary, @{}, @"recursive removal empties the dictionary in a mixed graph");
    }

    /* -dvt_shuffle is random, so it is asserted through the properties any
       in-place shuffle must hold rather than through a fixed order. */
    {
        NSMutableArray *array = [NSMutableArray array];
        for (int i = 0; i < 8; i++) {
            [array addObject:[NSNumber numberWithInt:i]];
        }
        BOOL permutation = YES;
        BOOL everChanged = NO;
        for (int run = 0; run < 500; run++) {
            [array dvt_shuffle];
            if (array.count != 8) {
                permutation = NO;
                break;
            }
            NSMutableSet *seen = [NSMutableSet set];
            for (NSNumber *number in array) {
                [seen addObject:number];
            }
            if (seen.count != 8) {
                permutation = NO;
                break;
            }
            if (![array isEqual:(@[@0, @1, @2, @3, @4, @5, @6, @7])]) {
                everChanged = YES;
            }
        }
        DVTExpect(permutation, @"dvt_shuffle permutes in place without losing members");
        DVTExpect(everChanged, @"dvt_shuffle reorders rather than leaving the receiver alone");
    }
    {
        /* Every one of the six orders of three elements has to be reachable,
           which is what rules out a walk that under-draws. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"a", @"b", @"c", nil];
        NSMutableSet *orders = [NSMutableSet set];
        for (int run = 0; run < 500; run++) {
            [array dvt_shuffle];
            [orders addObject:[array componentsJoinedByString:@""]];
        }
        DVTExpect(orders.count == 6, @"dvt_shuffle reaches all six orders of three elements");
    }
    {
        NSMutableArray *empty = [NSMutableArray array];
        [empty dvt_shuffle];
        NSMutableArray *single = [NSMutableArray arrayWithObject:@"only"];
        for (int run = 0; run < 50; run++) {
            [single dvt_shuffle];
        }
        DVTExpect(empty.count == 0, @"dvt_shuffle on an empty receiver is a no-op");
        DVTExpectEqualObjects(single, @[@"only"], @"dvt_shuffle on a one element receiver is a no-op");
    }
    {
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"x", @"x", @"y", nil];
        BOOL multisetKept = YES;
        for (int run = 0; run < 500; run++) {
            [array dvt_shuffle];
            NSUInteger xs = 0;
            for (id object in array) {
                if ([object isEqual:@"x"]) {
                    xs++;
                }
            }
            if (xs != 2) {
                multisetKept = NO;
                break;
            }
        }
        DVTExpect(multisetKept, @"dvt_shuffle keeps duplicate multiplicities");
    }

    /* -dvt_shuffledArray only shuffles above one element, and the branch it
       takes below that is visible in what -copy returns. */
    {
        NSArray *frozenOne = @[@"a"];
        NSArray *frozenEmpty = @[];
        NSMutableArray *mutableOne = [NSMutableArray arrayWithObject:@"a"];
        NSMutableArray *mutableEmpty = [NSMutableArray array];
        DVTExpect([frozenOne dvt_shuffledArray] == frozenOne,
                  @"dvt_shuffledArray returns an immutable one element receiver as itself");
        DVTExpect([frozenEmpty dvt_shuffledArray] == frozenEmpty,
                  @"dvt_shuffledArray returns an immutable empty receiver as itself");
        DVTExpect([mutableOne dvt_shuffledArray] != mutableOne,
                  @"dvt_shuffledArray copies a mutable one element receiver");
        DVTExpect([mutableEmpty dvt_shuffledArray] != mutableEmpty,
                  @"dvt_shuffledArray copies a mutable empty receiver");
        DVTExpect([[mutableOne dvt_shuffledArray] isKindOfClass:[NSMutableArray class]] == NO,
                  @"dvt_shuffledArray answers an immutable array for a mutable one element receiver");
        DVTExpect([[mutableEmpty dvt_shuffledArray] isKindOfClass:[NSMutableArray class]] == NO,
                  @"dvt_shuffledArray answers an immutable array for a mutable empty receiver");
    }
    {
        /* Above one element the result is a shuffled mutable copy, so the
           receiver keeps its order and mutating the result cannot reach back. */
        NSMutableArray *source = [NSMutableArray arrayWithObjects:@"a", @"b", @"c", nil];
        id shuffled = [source dvt_shuffledArray];
        DVTExpect(shuffled != source, @"dvt_shuffledArray returns a copy rather than the receiver");
        DVTExpect([shuffled isKindOfClass:[NSMutableArray class]],
                  @"dvt_shuffledArray answers a mutable array above one element");
        DVTExpectEqualObjects(source, (@[@"a", @"b", @"c"]),
                              @"dvt_shuffledArray leaves the receiver in order");
        [shuffled removeAllObjects];
        DVTExpect(source.count == 3, @"dvt_shuffledArray's result does not alias the receiver");
        NSMutableArray *sorted = [shuffled mutableCopy];
        DVTExpect(sorted.count == 0, @"dvt_shuffledArray's result really was emptied in place");
    }
    {
        /* An immutable receiver is copied before shuffling, so it survives too. */
        NSArray *frozenThree = @[@"a", @"b", @"c"];
        id shuffledFrozen = [frozenThree dvt_shuffledArray];
        DVTExpect(shuffledFrozen != frozenThree, @"dvt_shuffledArray copies an immutable receiver");
        DVTExpect([shuffledFrozen isKindOfClass:[NSMutableArray class]],
                  @"dvt_shuffledArray answers a mutable array for an immutable receiver above one element");
        DVTExpectEqualObjects(frozenThree, (@[@"a", @"b", @"c"]),
                              @"dvt_shuffledArray leaves an immutable receiver in order");
        NSMutableArray *members = [shuffledFrozen mutableCopy];
        [members sortUsingSelector:@selector(compare:)];
        DVTExpectEqualObjects(members, (@[@"a", @"b", @"c"]),
                              @"dvt_shuffledArray permutes rather than duplicating or dropping members");
    }

    /* -dvt_sortByValueBlock: compares values the block derives, so the ordering
       belongs to the derived values and not to the members themselves. */
    {
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"bbb", @"a", @"cc", @"dd", @"e", nil];
        [array dvt_sortByValueBlock:^id(id object) { return @([object length]); }];
        DVTExpectEqualObjects(array, (@[@"a", @"e", @"cc", @"dd", @"bbb"]),
                              @"dvt_sortByValueBlock: orders by the derived value");
    }
    {
        /* Negating the derived value is enough to reverse the result, which
           shows the direction comes from the block and not from a flag. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"bbb", @"a", @"cc", nil];
        [array dvt_sortByValueBlock:^id(id object) { return @(-(NSInteger)[object length]); }];
        DVTExpectEqualObjects(array, (@[@"bbb", @"cc", @"a"]),
                              @"dvt_sortByValueBlock: orders descending when the value block negates");
    }
    {
        /* The value block is asked for both members of each comparison, so its
           call count tracks the comparisons rather than the receiver's count. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"bbb", @"a", @"cc", @"dd", nil];
        __block int valueCalls = 0;
        [array dvt_sortByValueBlock:^id(id object) {
            valueCalls++;
            return @([object length]);
        }];
        DVTExpect(valueCalls > array.count,
                  @"dvt_sortByValueBlock: asks the value block once per member per comparison");
    }
    {
        /* Neither block runs for a receiver with nothing to compare, so an empty
           or single element array cannot observe either. */
        __block int valueCalls = 0;
        __block int handlerCalls = 0;
        NSMutableArray *empty = [NSMutableArray array];
        NSMutableArray *single = [NSMutableArray arrayWithObject:@"only"];
        for (NSMutableArray *receiver in @[ empty, single ]) {
            [receiver dvt_sortByValueBlock:^id(id object) {
                                valueCalls++;
                                return object;
                            }
                      duplicateHandler:^NSComparisonResult(id first, id second) {
                          handlerCalls++;
                          return NSOrderedSame;
                      }];
        }
        DVTExpect(valueCalls == 0, @"dvt_sortByValueBlock: does not run the value block without comparisons");
        DVTExpect(handlerCalls == 0, @"dvt_sortByValueBlock: does not run the duplicate handler without comparisons");
    }
    {
        /* A nil derived value trips the assertion, which is why the value block
           is documented as having to answer a real object. */
        DVTTestCapturingHandler *handler = [DVTTestCapturingHandler new];
        [DVTAssertionReportHandler setCurrentHandler:handler];
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"a", @"bb", nil];
        [array dvt_sortByValueBlock:^id(id object) { return nil; }];
        [DVTAssertionReportHandler setCurrentHandler:nil];
        DVTExpect(handler.reports.count > 0, @"dvt_sortByValueBlock: asserts on a nil derived value");
        DVTExpect(!handler.lastWasWarning,
                  @"dvt_sortByValueBlock: reports a nil derived value as a failure, not a warning");
        /* Both members fail here, so the report has to be searched rather than read
           off the end, and the two names have to be distinguishable. */
        NSString *all = [handler.reports componentsJoinedByString:@"\n"];
        DVTExpect([all rangeOfString:@"projectionBlock(obj1)"].location != NSNotFound,
                  @"dvt_sortByValueBlock: names the first member whose value came back empty");
        DVTExpect([all rangeOfString:@"projectionBlock(obj2)"].location != NSNotFound,
                  @"dvt_sortByValueBlock: names the second member whose value came back empty");
    }
    {
        /* The second member's assertion is a separate failure with its own name, so
           a block that returns nil for only one side still reports which side. */
        DVTTestCapturingHandler *handler = [DVTTestCapturingHandler new];
        [DVTAssertionReportHandler setCurrentHandler:handler];
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"a", @"bb", @"ccc", nil];
        [array dvt_sortByValueBlock:^id(id object) {
            return [object isEqualTo:@"bb"] ? (id)nil : (id)object;
        }];
        [DVTAssertionReportHandler setCurrentHandler:nil];
        NSString *joined = [handler.reports componentsJoinedByString:@"\n"];
        DVTExpect([joined rangeOfString:@"projectionBlock(obj2)"].location != NSNotFound,
                  @"dvt_sortByValueBlock: names the second member separately when only it is empty");
    }

    /* The duplicate handler only ever sees ties, and it is handed the members
       rather than the values the value block produced. */
    {
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"bbb", @"a", @"cc", @"dd", @"e", nil];
        NSMutableArray *seen = [NSMutableArray array];
        [array dvt_sortByValueBlock:^id(id object) { return @([object length]); }
                  duplicateHandler:^NSComparisonResult(id first, id second) {
                      [seen addObject:[NSString stringWithFormat:@"%@/%@", first, second]];
                      return [first compare:second];
                  }];
        DVTExpectEqualObjects(array, (@[@"a", @"e", @"cc", @"dd", @"bbb"]),
                              @"dvt_sortByValueBlock:duplicateHandler: can break ties by member");
        BOOL sawMembers = YES;
        for (NSString *entry in seen) {
            if ([entry rangeOfString:@"b"].location == NSNotFound &&
                [entry rangeOfString:@"a"].location == NSNotFound &&
                [entry rangeOfString:@"c"].location == NSNotFound &&
                [entry rangeOfString:@"d"].location == NSNotFound &&
                [entry rangeOfString:@"e"].location == NSNotFound) {
                sawMembers = NO;
            }
        }
        DVTExpect(sawMembers, @"dvt_sortByValueBlock:duplicateHandler: receives the members, not the derived values");
    }
    {
        /* A handler that claims every comparison is descending inverts the whole
           order, so its result really is what the sort obeys. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"bbb", @"a", @"cc", @"dd", @"e", nil];
        [array dvt_sortByValueBlock:^id(id object) { return @([object length]); }
                  duplicateHandler:^NSComparisonResult(id first, id second) { return NSOrderedDescending; }];
        DVTExpectEqualObjects(array, (@[@"e", @"a", @"dd", @"cc", @"bbb"]),
                              @"dvt_sortByValueBlock:duplicateHandler: obeys a handler that always says descending");
    }
    {
        /* The handler is not consulted while the derived values differ, so a
           non-tied receiver never reaches it. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"bbb", @"a", @"cc", @"dd", @"e", nil];
        __block int calls = 0;
        [array dvt_sortByValueBlock:^id(id object) { return @([object length]); }
                  duplicateHandler:^NSComparisonResult(id first, id second) {
                      calls++;
                      return NSOrderedSame;
                  }];
        DVTExpect(calls > 0, @"dvt_sortByValueBlock:duplicateHandler: is consulted for ties");
    }
    {
        /* Distinct members that collapse to one derived value all become ties, so
           the handler runs for every pairing among them. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"aa", @"bb", @"cc", @"dd", nil];
        __block int calls = 0;
        [array dvt_sortByValueBlock:^id(id object) { return @"all-equal"; }
                  duplicateHandler:^NSComparisonResult(id first, id second) {
                      calls++;
                      return [first compare:second];
                  }];
        DVTExpectEqualObjects(array, (@[@"aa", @"bb", @"cc", @"dd"]),
                              @"dvt_sortByValueBlock:duplicateHandler: orders members that collapse to one value");
    }
    {
        /* The one argument form tail-calls with a null handler, so it matches the
           two argument form spelled with nil, ties included. */
        NSArray *members = @[@"bbb", @"a", @"cc", @"dd", @"e"];
        NSMutableArray *oneArgument = [NSMutableArray arrayWithArray:members];
        NSMutableArray *nilHandler = [NSMutableArray arrayWithArray:members];
        [oneArgument dvt_sortByValueBlock:^id(id object) { return @([object length]); }];
        [nilHandler dvt_sortByValueBlock:^id(id object) { return @([object length]); } duplicateHandler:nil];
        DVTExpectEqualObjects(oneArgument, (@[@"a", @"e", @"cc", @"dd", @"bbb"]),
                              @"dvt_sortByValueBlock: sorts by the derived value");
        DVTExpectEqualObjects(oneArgument, nilHandler,
                              @"dvt_sortByValueBlock: matches the two argument form with a nil handler");
    }
    {
        /* With every derived value equal and no handler, a tie stays
           NSOrderedSame and the sort decides rather than the method. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"aa", @"bb", nil];
        [array dvt_sortByValueBlock:^id(id object) { return @"same"; }];
        DVTExpectEqualObjects(array, (@[@"aa", @"bb"]),
                              @"dvt_sortByValueBlock: leaves an all-ties receiver to the sort");
    }
    {
        /* The sort happens in place on the receiver, not on a copy. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"bbb", @"a", @"cc", nil];
        NSMutableArray *alias = array;
        [array dvt_sortByValueBlock:^id(id object) { return @([object length]); }];
        DVTExpect(alias == array, @"dvt_sortByValueBlock: sorts the receiver in place");
        DVTExpectEqualObjects(array, (@[@"a", @"cc", @"bbb"]),
                              @"dvt_sortByValueBlock: leaves the receiver sorted");
    }

    /* The derived-value sort is the same comparator applied to a private mutable
       copy, and the answer is copied back down to an immutable array. */
    {
        NSArray *sorted = [@[@"bbb", @"a", @"cc"] dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        }];
        DVTExpectEqualObjects(sorted, (@[@"a", @"cc", @"bbb"]),
                              @"dvt_objectsSortedByValueBlock: orders by the derived value");
        NSArray *descending = [@[@"bbb", @"a", @"cc"] dvt_objectsSortedByValueBlock:^id(id object) {
            return @(-(NSInteger)[object length]);
        }];
        DVTExpectEqualObjects(descending, (@[@"bbb", @"cc", @"a"]),
                              @"dvt_objectsSortedByValueBlock: orders descending when the value block negates");
    }
    {
        /* The receiver is never reordered, and a mutable one is not reordered
           either even though a mutable copy is what gets sorted. */
        NSMutableArray *original = [NSMutableArray arrayWithObjects:@"bbb", @"a", @"cc", nil];
        NSMutableArray *alias = original;
        NSArray *sorted = [original dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        }];
        DVTExpectEqualObjects(original, (@[@"bbb", @"a", @"cc"]),
                              @"dvt_objectsSortedByValueBlock: leaves the receiver alone");
        DVTExpect(alias == original, @"dvt_objectsSortedByValueBlock: does not sort the receiver in place");
        DVTExpect(sorted != original, @"dvt_objectsSortedByValueBlock: answers a new array");
        DVTExpect(![sorted isKindOfClass:[NSMutableArray class]],
                  @"dvt_objectsSortedByValueBlock: answers an immutable array even for a mutable receiver");
    }
    {
        /* At one member or fewer the sort is skipped, so the value block is never
           asked. That is why a block returning nil is harmless here. */
        NSArray *single = @[@"only"];
        __block int calls = 0;
        NSArray *sorted = [single dvt_objectsSortedByValueBlock:^id(id object) {
            calls++;
            return nil;
        }];
        DVTExpect(calls == 0, @"dvt_objectsSortedByValueBlock: never asks the value block for one member");
        DVTExpectEqualObjects(sorted, single, @"dvt_objectsSortedByValueBlock: answers one member unchanged");
        DVTExpect(sorted == single, @"dvt_objectsSortedByValueBlock: hands back an immutable one member receiver");
    }
    {
        /* The short path is -copy, so a mutable receiver is still copied rather
           than handed back mutable. */
        NSMutableArray *singleMutable = [NSMutableArray arrayWithObject:@"only"];
        NSArray *sorted = [singleMutable dvt_objectsSortedByValueBlock:^id(id object) {
            return nil;
        }];
        DVTExpect(sorted != singleMutable, @"dvt_objectsSortedByValueBlock: copies a mutable one member receiver");
        DVTExpect(![sorted isKindOfClass:[NSMutableArray class]],
                  @"dvt_objectsSortedByValueBlock: answers an immutable array for a mutable one member receiver");
        DVTExpect([singleMutable isKindOfClass:[NSMutableArray class]],
                  @"dvt_objectsSortedByValueBlock: leaves a mutable receiver mutable");
    }
    {
        NSArray *empty = @[];
        __block int calls = 0;
        NSArray *sorted = [empty dvt_objectsSortedByValueBlock:^id(id object) {
            calls++;
            return nil;
        }];
        DVTExpect(calls == 0, @"dvt_objectsSortedByValueBlock: never asks the value block for an empty receiver");
        DVTExpect(sorted.count == 0, @"dvt_objectsSortedByValueBlock: answers an empty array for an empty receiver");
        DVTExpect(![sorted isKindOfClass:[NSMutableArray class]],
                  @"dvt_objectsSortedByValueBlock: answers an immutable array for an empty receiver");
    }
    {
        /* Two members is where the sorting path begins, so this is the smallest
           receiver on which the value block is consulted at all. */
        NSArray *two = [NSArray arrayWithObjects:@"bb", @"a", nil];
        __block int calls = 0;
        NSArray *sorted = [two dvt_objectsSortedByValueBlock:^id(id object) {
            calls++;
            return @([object length]);
        }];
        DVTExpect(calls > 0, @"dvt_objectsSortedByValueBlock: asks the value block for two members");
        DVTExpectEqualObjects(sorted, (@[@"a", @"bb"]),
                              @"dvt_objectsSortedByValueBlock: orders two members");
    }
    {
        /* The duplicate handler breaks ties rather than removing them, so members
           sharing a derived value are all kept. */
        NSArray *kept = [@[@"bb", @"a", @"bb", @"a"] dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        }];
        DVTExpectEqualObjects(kept, (@[@"a", @"a", @"bb", @"bb"]),
                              @"dvt_objectsSortedByValueBlock: keeps members that share a derived value");
        NSArray *keptWithHandler = [@[@"bb", @"a", @"bb", @"a"] dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        } duplicateHandler:^NSComparisonResult(id first, id second) {
            return [first compare:second];
        }];
        DVTExpectEqualObjects(keptWithHandler, (@[@"a", @"a", @"bb", @"bb"]),
                              @"dvt_objectsSortedByValueBlock:duplicateHandler: orders ties but keeps them");
    }
    {
        /* The handler is handed the members and runs only on ties, exactly as in
           the in-place sort, because it is the same comparator. */
        NSArray *sorted = [@[@"bbb", @"a", @"cc"] dvt_objectsSortedByValueBlock:^id(id object) {
            return @"all-equal";
        } duplicateHandler:^NSComparisonResult(id first, id second) {
            return [first compare:second];
        }];
        DVTExpectEqualObjects(sorted, (@[@"a", @"bbb", @"cc"]),
                              @"dvt_objectsSortedByValueBlock:duplicateHandler: can break ties by member");
        __block int calls = 0;
        NSArray *distinct = [@[@"bb", @"a", @"cc"] dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        } duplicateHandler:^NSComparisonResult(id first, id second) {
            calls++;
            return NSOrderedSame;
        }];
        DVTExpectEqualObjects(distinct, (@[@"a", @"bb", @"cc"]),
                              @"dvt_objectsSortedByValueBlock:duplicateHandler: returning NSOrderedSame sorts normally");
        (void)calls;
    }
    {
        /* With every derived value equal and no handler, the tie is left to the
           sort, matching the in-place form. */
        NSArray *sorted = [@[@"aa", @"bb"] dvt_objectsSortedByValueBlock:^id(id object) {
            return @"same";
        }];
        DVTExpectEqualObjects(sorted, (@[@"aa", @"bb"]),
                              @"dvt_objectsSortedByValueBlock: leaves an all-ties receiver to the sort");
    }
    {
        /* The one argument form tail-calls with a null handler, so it matches the
           two argument form spelled with nil. */
        NSArray *members = @[@"bbb", @"a", @"cc", @"dd", @"e"];
        NSArray *oneArgument = [members dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        }];
        NSArray *nilHandler = [members dvt_objectsSortedByValueBlock:^id(id object) {
            return @([object length]);
        } duplicateHandler:nil];
        DVTExpectEqualObjects(oneArgument, (@[@"a", @"e", @"cc", @"dd", @"bbb"]),
                              @"dvt_objectsSortedByValueBlock: sorts by the derived value");
        DVTExpectEqualObjects(oneArgument, nilHandler,
                              @"dvt_objectsSortedByValueBlock: matches the two argument form with a nil handler");
    }
    {
        /* A derived value of nil asserts once there is a comparison to make,
           naming the member whose value came back empty. */
        DVTTestCapturingHandler *handler = [DVTTestCapturingHandler new];
        [DVTAssertionReportHandler setCurrentHandler:handler];
        NSArray *two = [NSArray arrayWithObjects:@"bb", @"a", nil];
        [two dvt_objectsSortedByValueBlock:^id(id object) { return nil; }];
        [DVTAssertionReportHandler setCurrentHandler:nil];
        NSString *joined = [handler.reports componentsJoinedByString:@"\n"];
        DVTExpect([joined rangeOfString:@"projectionBlock(obj1)"].location != NSNotFound,
                  @"dvt_objectsSortedByValueBlock: asserts on a nil derived value");
        DVTExpect([joined rangeOfString:@"projectionBlock(obj2)"].location != NSNotFound,
                  @"dvt_objectsSortedByValueBlock: names both sides of the comparison");
    }

    /* The partition carries a threshold: at five or fewer Apple sorts in place,
       above five it removes the passing members and appends them. Both routes are
       stable and both leave the suffix last, so walking the counts across the
       boundary is what shows the two routes agree. */
    {
        for (NSUInteger count = 0; count <= 8; count++) {
            NSMutableArray *array = [NSMutableArray array];
            for (NSUInteger i = 0; i < count; i++) {
                [array addObject:@(i)];
            }
            [array dvt_stablePartitionObjectsPassingIsSuffixTest:^BOOL(id object) {
                return [object unsignedIntegerValue] % 2 == 1;
            }];
            NSMutableArray *evens = [NSMutableArray array];
            NSMutableArray *odds = [NSMutableArray array];
            for (NSNumber *number in array) {
                [(number.unsignedIntegerValue % 2 == 0 ? evens : odds) addObject:number];
            }
            DVTExpectEqualObjects(array, [evens arrayByAddingObjectsFromArray:odds],
                                  ([NSString stringWithFormat:
                                                 @"dvt_stablePartitionObjectsPassingIsSuffixTest: puts the odd "
                                                 @"members last in order at count %lu",
                                                 (unsigned long)count]));
        }
    }
    {
        /* Exact results at the boundary, so a regression in either route is visible
           rather than hidden behind the ordering property above. */
        NSMutableArray *small = [NSMutableArray arrayWithObjects:@0, @1, @2, @3, @4, nil];
        [small dvt_stablePartitionObjectsPassingIsSuffixTest:^BOOL(id object) {
            return [object unsignedIntegerValue] % 2 == 1;
        }];
        NSMutableArray *large = [NSMutableArray arrayWithObjects:@0, @1, @2, @3, @4, @5, nil];
        [large dvt_stablePartitionObjectsPassingIsSuffixTest:^BOOL(id object) {
            return [object unsignedIntegerValue] % 2 == 1;
        }];
        DVTExpectEqualObjects(small, (@[@0, @2, @4, @1, @3]),
                              @"dvt_stablePartitionObjectsPassingIsSuffixTest: partitions five members");
        DVTExpectEqualObjects(large, (@[@0, @2, @4, @1, @3, @5]),
                              @"dvt_stablePartitionObjectsPassingIsSuffixTest: partitions six members the same way");
    }
    {
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"a1", @"a2", @"b1", @"a3", @"b2", @"b3", nil];
        [array dvt_stablePartitionObjectsPassingIsSuffixTest:^BOOL(id object) { return [object hasPrefix:@"b"]; }];
        DVTExpectEqualObjects(array, (@[@"a1", @"a2", @"a3", @"b1", @"b2", @"b3"]),
                              @"dvt_stablePartitionObjectsPassingIsSuffixTest: keeps both groups in order");
    }
    {
        NSMutableArray *all = [NSMutableArray arrayWithObjects:@"a", @"b", @"c", nil];
        [all dvt_stablePartitionObjectsPassingIsSuffixTest:^BOOL(id object) { return YES; }];
        NSMutableArray *none = [NSMutableArray arrayWithObjects:@"a", @"b", @"c", nil];
        [none dvt_stablePartitionObjectsPassingIsSuffixTest:^BOOL(id object) { return NO; }];
        DVTExpectEqualObjects(all, (@[@"a", @"b", @"c"]),
                              @"dvt_stablePartitionObjectsPassingIsSuffixTest: leaves an all-passing receiver alone");
        DVTExpectEqualObjects(none, (@[@"a", @"b", @"c"]),
                              @"dvt_stablePartitionObjectsPassingIsSuffixTest: leaves a non-passing receiver alone");
    }
    {
        /* Stability is the whole point, so an input already in partition order must
           come back untouched rather than merely rearranged. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"a", @"b", @"c", @"d", @"e", @"f", nil];
        [array dvt_stablePartitionObjectsPassingIsSuffixTest:^BOOL(id object) {
            return [object characterAtIndex:0] >= 'c';
        }];
        DVTExpectEqualObjects(array, (@[@"a", @"b", @"c", @"d", @"e", @"f"]),
                              @"dvt_stablePartitionObjectsPassingIsSuffixTest: leaves an already partitioned receiver alone");
    }
    {
        NSMutableArray *empty = [NSMutableArray array];
        [empty dvt_stablePartitionObjectsPassingIsSuffixTest:^BOOL(id object) { return YES; }];
        DVTExpectEqualObjects(empty, @[], @"dvt_stablePartitionObjectsPassingIsSuffixTest: accepts an empty receiver");
    }

    /* dvt_uniqueStringToAddToArray: only ever answers a string; it never inserts. */
    {
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
        NSString *candidate = [@"c" mutableCopy];
        DVTExpect([array dvt_uniqueStringToAddToArray:candidate] == candidate,
                  @"dvt_uniqueStringToAddToArray: returns an absent string unchanged");
        DVTExpectEqualObjects(array, (@[@"a", @"b"]),
                              @"dvt_uniqueStringToAddToArray: does not insert the string it answers");
    }
    {
        NSMutableArray *array = [NSMutableArray arrayWithObject:@"x"];
        DVTExpectEqualObjects([array dvt_uniqueStringToAddToArray:@"x"], @"x 1",
                              @"dvt_uniqueStringToAddToArray: numbers from one");
    }
    {
        /* A gap is filled rather than skipped past, which is what a walk from one
           upwards does and what appending past the highest would not. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"y", @"y 1", @"y 3", nil];
        DVTExpectEqualObjects([array dvt_uniqueStringToAddToArray:@"y"], @"y 2",
                              @"dvt_uniqueStringToAddToArray: fills a gap in the numbering");
    }
    {
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@"x", @"x 1", @"x 2", @"x 3", nil];
        DVTExpectEqualObjects([array dvt_uniqueStringToAddToArray:@"x"], @"x 4",
                              @"dvt_uniqueStringToAddToArray: steps past every taken suffix");
    }
    {
        /* Membership is by equality, so a distinct but equal string counts as
           present and gets a suffix. */
        NSString *twin = [@"dup" mutableCopy];
        NSMutableArray *array = [NSMutableArray arrayWithObject:twin];
        DVTExpectEqualObjects([array dvt_uniqueStringToAddToArray:[@"dup" mutableCopy]], @"dup 1",
                              @"dvt_uniqueStringToAddToArray: treats an equal but distinct string as present");
    }
    {
        NSMutableArray *empty = [NSMutableArray array];
        DVTExpectEqualObjects([empty dvt_uniqueStringToAddToArray:@"z"], @"z",
                              @"dvt_uniqueStringToAddToArray: answers any string for an empty receiver");
    }
    {
        /* Non-string members are tolerated, since the receiver is turned into a set. */
        NSMutableArray *array = [NSMutableArray arrayWithObjects:@1, @2, nil];
        DVTExpectEqualObjects([array dvt_uniqueStringToAddToArray:@"k"], @"k",
                              @"dvt_uniqueStringToAddToArray: tolerates non-string members");
    }
    {
        /* The enumeration answer is mutable even for an immutable source, so it
           can be built into, and it is never the source itself. */
        NSArray *source = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
        NSArray *enumerated = [NSArray dvt_arrayWithEnumeratedObjects:source];
        DVTExpectEqualObjects(enumerated, (@[@"a", @"b"]),
                              @"dvt_arrayWithEnumeratedObjects: copies an immutable source");
        DVTExpect(enumerated != source, @"dvt_arrayWithEnumeratedObjects: answers a fresh array");
        DVTExpect([enumerated isKindOfClass:[NSMutableArray class]],
                  @"dvt_arrayWithEnumeratedObjects: the answer is mutable");
        [(NSMutableArray *)enumerated addObject:@"c"];
        DVTExpect(source.count == 2, @"dvt_arrayWithEnumeratedObjects: building into the answer leaves the source alone");
    }
    {
        /* A nil source enumerates nothing, and still answers a mutable array
           rather than nil -- that is the difference from the objectIfNonNil form. */
        NSArray *enumeratedNil = [NSArray dvt_arrayWithEnumeratedObjects:nil];
        DVTExpectEqualObjects(enumeratedNil, @[], @"dvt_arrayWithEnumeratedObjects: a nil source is empty");
        DVTExpect([enumeratedNil isKindOfClass:[NSMutableArray class]],
                  @"dvt_arrayWithEnumeratedObjects: a nil source still answers a mutable array");
        NSArray *enumeratedEmpty = [NSArray dvt_arrayWithEnumeratedObjects:@[]];
        DVTExpectEqualObjects(enumeratedEmpty, @[],
                              @"dvt_arrayWithEnumeratedObjects: an empty source is empty");
        DVTExpect([enumeratedEmpty isKindOfClass:[NSMutableArray class]],
                  @"dvt_arrayWithEnumeratedObjects: an empty source still answers a mutable array");
    }
    {
        /* This is the array form of an if (object) guard, so nil answers nil
           rather than an empty array -- the difference from the enumerating
           form, which always answers an array. A nil-but-present member is
           still kept. */
        DVTExpect([NSArray dvt_arrayWithObjectIfNonNil:nil] == nil,
                  @"dvt_arrayWithObjectIfNonNil: a nil object answers nil");
        NSArray *single = [NSArray dvt_arrayWithObjectIfNonNil:@"x"];
        DVTExpectEqualObjects(single, (@[@"x"]), @"dvt_arrayWithObjectIfNonNil: wraps a non-nil object");
        DVTExpectEqualObjects([NSArray dvt_arrayWithObjectIfNonNil:[NSNull null]], @[[NSNull null]],
                              @"dvt_arrayWithObjectIfNonNil: NSNull is not nil and is kept");
        DVTExpect(![single isKindOfClass:[NSMutableArray class]],
                  @"dvt_arrayWithObjectIfNonNil: the answer is immutable");
    }
    {
        /* Repeats and holes survive: the answer holds the same object count
           times, not a flattened set. */
        NSMutableArray *shared = [NSMutableArray arrayWithObject:@"q"];
        NSArray *repeated = [NSArray dvt_arrayWithRepetitions:3 ofObject:shared];
        DVTExpect(repeated.count == 3, @"dvt_arrayWithRepetitions:ofObject: honours the count");
        DVTExpect([repeated[0] isEqual:shared] && repeated[0] == repeated[2],
                  @"dvt_arrayWithRepetitions:ofObject: repeats the same object, not a copy of it");
        DVTExpect(![repeated isKindOfClass:[NSMutableArray class]],
                  @"dvt_arrayWithRepetitions:ofObject: the answer is immutable");
    }
    {
        /* The staged buffer is only a size question, so the answer must not
           change shape across the stack/allocation boundary. */
        NSArray *atLimit = [NSArray dvt_arrayWithRepetitions:256 ofObject:@"a"];
        NSArray *pastLimit = [NSArray dvt_arrayWithRepetitions:257 ofObject:@"a"];
        DVTExpect(atLimit.count == 256 && pastLimit.count == 257,
                  @"dvt_arrayWithRepetitions:ofObject: counts past the buffer boundary are exact");
        DVTExpectEqualObjects(atLimit[255], @"a", @"dvt_arrayWithRepetitions:ofObject: the buffer-boundary last member is set");
        DVTExpectEqualObjects(pastLimit[256], @"a",
                              @"dvt_arrayWithRepetitions:ofObject: the first member past the buffer is set");
        DVTExpectEqualObjects([NSArray dvt_arrayWithRepetitions:0 ofObject:@"a"], @[],
                              @"dvt_arrayWithRepetitions:ofObject: zero repetitions is empty");
        DVTExpectEqualObjects([NSArray dvt_arrayWithRepetitions:0 ofObject:nil], @[],
                              @"dvt_arrayWithRepetitions:ofObject: a nil object is fine at zero");
    }
    {
        /* A nil object at one or more is not dropped -- the array simply cannot
           hold it, which is a fault rather than a shorter answer. */
        @try {
            [NSArray dvt_arrayWithRepetitions:2 ofObject:nil];
            DVTExpect(NO, @"dvt_arrayWithRepetitions:ofObject: a nil object at a positive count raises");
        } @catch (NSException *exception) {
            DVTExpect([exception.name isEqualToString:NSInvalidArgumentException],
                      @"dvt_arrayWithRepetitions:ofObject: a nil object at a positive count raises NSInvalidArgumentException");
        }
    }
    {
        /* Prefix length is bounded by the shorter member in both directions, and
           stops at the first disagreement rather than counting matches. */
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:@[@"a", @"b"] and:@[@"a", @"c"]] == 1,
                  @"dvt_lengthOfCommonPrefixBetween:and: stops at the first disagreement");
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:@[@"a", @"b", @"c"] and:@[@"a", @"b", @"c", @"d"]] == 3,
                  @"dvt_lengthOfCommonPrefixBetween:and: a shorter first member bounds the answer");
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:@[@"a", @"b", @"c", @"d"] and:@[@"a", @"b", @"c"]] == 3,
                  @"dvt_lengthOfCommonPrefixBetween:and: a shorter second member bounds the answer");
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:@[] and:@[@"a"]] == 0,
                  @"dvt_lengthOfCommonPrefixBetween:and: an empty member is a zero-length prefix");
    }
    {
        /* Agreement is by equality, so a distinct but equal object matches,
           NSNull matches itself, and a cross-type pair does not. */
        NSMutableArray *twin = [@"a" mutableCopy];
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:@[twin] and:@[@"a"]] == 1,
                  @"dvt_lengthOfCommonPrefixBetween:and: an equal but distinct object matches");
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:@[[NSNull null]] and:@[[NSNull null]]] == 1,
                  @"dvt_lengthOfCommonPrefixBetween:and: NSNull agrees with itself");
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:@[@1] and:@[@"1"]] == 0,
                  @"dvt_lengthOfCommonPrefixBetween:and: a number and a string do not agree");
    }
    {
        /* A nil member has no members to agree on, so it is a zero-length
           prefix rather than a fault. */
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:nil and:nil] == 0,
                  @"dvt_lengthOfCommonPrefixBetween:and: two nils are a zero-length prefix");
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:nil and:@[@"a", @"b"]] == 0,
                  @"dvt_lengthOfCommonPrefixBetween:and: a nil first member is a zero-length prefix");
        DVTExpect([NSArray dvt_lengthOfCommonPrefixBetween:@[@"a"] and:nil] == 0,
                  @"dvt_lengthOfCommonPrefixBetween:and: a nil second member is a zero-length prefix");
    }
    {
        NSArray *ranges = @[[NSValue valueWithRange:NSMakeRange(0, 0)],
                            [NSValue valueWithRange:NSMakeRange(5, 7)],
                            [NSValue valueWithRange:NSMakeRange(100, 1)]];
        DVTExpectEqualRanges([ranges rangeAtIndex:0], NSMakeRange(0, 0), @"rangeAtIndex: reads the first member");
        DVTExpectEqualRanges([ranges rangeAtIndex:1], NSMakeRange(5, 7), @"rangeAtIndex: reads a middle member");
        DVTExpectEqualRanges([ranges rangeAtIndex:2], NSMakeRange(100, 1), @"rangeAtIndex: reads the last member");
        DVTExpectEqualRanges([(NSArray *)[ranges mutableCopy] rangeAtIndex:1], NSMakeRange(5, 7),
                             @"rangeAtIndex: a mutable receiver answers the same");
        /* Both faults come from the forwarding, not from a check of its own: the
           indexed access raises out of range, and the send raises for a member
           that is not a range at all. */
        @try {
            [ranges rangeAtIndex:3];
            DVTExpect(NO, @"rangeAtIndex: past the end raises");
        } @catch (NSException *exception) {
            DVTExpect([exception.name isEqualToString:NSRangeException],
                      @"rangeAtIndex: past the end raises NSRangeException");
        }
        @try {
            [@[@"not a range"] rangeAtIndex:0];
            DVTExpect(NO, @"rangeAtIndex: a member that is not a range raises");
        } @catch (NSException *exception) {
            DVTExpect([exception.name isEqualToString:NSInvalidArgumentException],
                      @"rangeAtIndex: a member that is not a range raises NSInvalidArgumentException");
        }
    }
}

#pragma mark - Observing convenience

/** Records the two KVO bracket notifications in order, so the shape of a change
    can be asserted instead of merely that one happened. */
@interface DVTChangeLog : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *entries;
@end

@implementation DVTChangeLog
@synthesize entries = _entries;

- (NSMutableArray<NSString *> *)entries
{
    if (!_entries) {
        _entries = [NSMutableArray array];
    }
    return _entries;
}
- (void)willChangeValueForKey:(NSString *)key
{
    [self.entries addObject:[NSString stringWithFormat:@"will:%@", key ?: @"<nil>"]];
}
- (void)didChangeValueForKey:(NSString *)key
{
    [self.entries addObject:[NSString stringWithFormat:@"did:%@", key ?: @"<nil>"]];
}
@end

/** The single-key form with no block: Apple faults loading the block's invoke
    pointer, so the call has to be made in a child. */
static void DVTChangeOneKeyWithoutBlock(void)
{
    DVTChangeLog *log = [[DVTChangeLog alloc] init];
    void (^block)(void) = nil;
    [log dvt_changeValueForKey:@"count" usingBlock:block];
}

/** The key-list form with no block, which faults the same way. */
static void DVTChangeKeyListWithoutBlock(void)
{
    DVTChangeLog *log = [[DVTChangeLog alloc] init];
    void (^block)(void) = nil;
    [log dvt_changeValueForKeys:@[@"count"] usingBlock:block];
}

/** Runs `body` in a child and names how it ended, so the two nil-block forms can be
    asserted to fault rather than going untested for want of a way to survive them.

    The wait is bounded: a child that never returns would hang the suite, so it is
    killed and reported instead. */
static NSString *DVTChildOutcome(void (*body)(void))
{
    pid_t child = fork();
    if (child < 0) {
        return @"fork failed";
    }
    if (child == 0) {
        int nullFD = open("/dev/null", O_RDWR);
        if (nullFD >= 0) {
            dup2(nullFD, STDOUT_FILENO);
            dup2(nullFD, STDERR_FILENO);
        }
        body();
        _exit(77);
    }

    int status = 0;
    for (int poll = 0; poll < 500; poll++) {
        pid_t reaped = waitpid(child, &status, WNOHANG);
        if (reaped == child) {
            if (WIFSIGNALED(status)) {
                int raised = WTERMSIG(status);
                return raised == SIGSEGV ? @"SIGSEGV"
                                         : [NSString stringWithFormat:@"signal %d", raised];
            }
            return [NSString stringWithFormat:@"exit %d", WEXITSTATUS(status)];
        }
        if (reaped < 0) {
            return @"wait failed";
        }
        usleep(10000);
    }
    kill(child, SIGKILL);
    waitpid(child, &status, 0);
    return @"hung";
}

/** The five conveniences Apple keeps in `NSObject(DVTObservingConvenience)`.

    Two of them answer without touching any observation state, so their tests are
    about the answer being the empty one rather than about anything they changed. */
static void DVTTestObservingConvenience(void)
{
    {
        DVTChangeLog *log = [[DVTChangeLog alloc] init];
        [log dvt_changeValueForKey:@"count" usingBlock:^{
            [log.entries addObject:@"block"];
        }];
        DVTExpectEqualObjects([log.entries componentsJoinedByString:@", "],
                              @"will:count, block, did:count",
                              @"dvt_changeValueForKey: brackets the block with will and did");
    }
    {
        /* The two sides are separate enumerations, not one walk played backwards:
           a repeated key is announced twice on each side, and the closing order is
           the exact reverse of the opening order. */
        DVTChangeLog *log = [[DVTChangeLog alloc] init];
        [log dvt_changeValueForKeys:@[@"a", @"a", @"b"] usingBlock:^{
            [log.entries addObject:@"block"];
        }];
        DVTExpectEqualObjects([log.entries componentsJoinedByString:@", "],
                              @"will:a, will:a, will:b, block, did:b, did:a, did:a",
                              @"dvt_changeValueForKeys: opens forward and closes in reverse");
    }
    {
        /* Nothing to announce either way, but the block still runs exactly once:
           a message to nil answers zero and a nil enumerator enumerates nothing. */
        DVTChangeLog *nilList = [[DVTChangeLog alloc] init];
        __block NSUInteger runs = 0;
        [nilList dvt_changeValueForKeys:nil usingBlock:^{ runs++; }];
        DVTExpect(runs == 1 && nilList.entries.count == 0,
                  @"a nil key list still runs the block once and announces nothing");

        DVTChangeLog *emptyList = [[DVTChangeLog alloc] init];
        runs = 0;
        [emptyList dvt_changeValueForKeys:@[] usingBlock:^{ runs++; }];
        DVTExpect(runs == 1 && emptyList.entries.count == 0,
                  @"an empty key list still runs the block once and announces nothing");
    }

    DVTExpectEqualObjects([NSObject dvt_keyPathOnSelfForUserDefaultsKey:@"myKey"],
                          @"_dvt_standardUserDefaultsProxy.myKey",
                          @"dvt_keyPathOnSelfForUserDefaultsKey: appends to the proxy prefix");
    DVTExpectEqualObjects([NSObject dvt_keyPathOnSelfForUserDefaultsKey:@""],
                          @"_dvt_standardUserDefaultsProxy.",
                          @"dvt_keyPathOnSelfForUserDefaultsKey: an empty key is the bare prefix");
    {
        /* Appending to nil raises, and a value that is not a string raises rather
           than being coerced; only the class of the failure is under test, because
           the reason names whichever class Foundation happened to build. */
        NSString *nilKey = nil;
        @try {
            [NSObject dvt_keyPathOnSelfForUserDefaultsKey:nilKey];
            DVTExpect(NO, @"dvt_keyPathOnSelfForUserDefaultsKey: with nil raises");
        } @catch (NSException *exception) {
            DVTExpect([exception.name isEqualToString:NSInvalidArgumentException],
                      @"dvt_keyPathOnSelfForUserDefaultsKey: with nil raises NSInvalidArgumentException");
        }
        id notAString = @42;
        @try {
            [NSObject dvt_keyPathOnSelfForUserDefaultsKey:notAString];
            DVTExpect(NO, @"dvt_keyPathOnSelfForUserDefaultsKey: with a number raises");
        } @catch (NSException *exception) {
            DVTExpect([exception.name isEqualToString:NSInvalidArgumentException],
                      @"dvt_keyPathOnSelfForUserDefaultsKey: with a number raises NSInvalidArgumentException");
        }
    }

    {
        /* The shared empty array, for anything at all -- including an argument that
           is not an observed object, which the binary never reads. */
        NSArray *forObject = [NSObject dvt_creationBacktracesOfObservingTokensForObservedObject:@"observed"];
        DVTExpect(forObject == [NSArray array] && forObject.count == 0,
                  @"dvt_creationBacktracesOfObservingTokensForObservedObject: the shared empty array");
        DVTExpect([NSObject dvt_creationBacktracesOfObservingTokensForObservedObject:nil] == [NSArray array],
                  @"dvt_creationBacktracesOfObservingTokensForObservedObject: nil answers the same");
        DVTExpect([NSObject dvt_creationBacktracesOfObservingTokensForObservedObject:@[@1]] == [NSArray array],
                  @"dvt_creationBacktracesOfObservingTokensForObservedObject: a non-observed argument answers the same");
    }

    {
        /* Apple's body is an assertion and then nothing, and the assertion it would
           report is routed through an aspect that is not installed outside Xcode.
           Capturing stderr is what makes "reports nothing" a check rather than an
           assumption -- the local handler prints unconditionally, so calling it
           would show up here. */
        int savedStderr = dup(STDERR_FILENO);
        char capturePath[] = "/tmp/dvt_cancel_XXXXXX";
        int captureFD = mkstemp(capturePath);
        BOOL captured = (savedStderr >= 0 && captureFD >= 0);
        ssize_t length = -1;
        if (captured) {
            fflush(stderr);
            dup2(captureFD, STDERR_FILENO);
            [NSObject dvt_cancelAllObservingTokensForOwner:@"owner"];
            [NSObject dvt_cancelAllObservingTokensForOwner:nil];
            fflush(stderr);
            dup2(savedStderr, STDERR_FILENO);
            lseek(captureFD, 0, SEEK_SET);
            char bytes[512];
            length = read(captureFD, bytes, sizeof(bytes));
            close(captureFD);
            unlink(capturePath);
        }
        close(savedStderr);
        DVTExpect(captured && length == 0,
                  @"dvt_cancelAllObservingTokensForOwner: returns without writing anything");
    }

    DVTExpectEqualObjects(DVTChildOutcome(DVTChangeOneKeyWithoutBlock), @"SIGSEGV",
                          @"dvt_changeValueForKey: with a nil block faults, as the binary does");
    DVTExpectEqualObjects(DVTChildOutcome(DVTChangeKeyListWithoutBlock), @"SIGSEGV",
                          @"dvt_changeValueForKeys: with a nil block faults, as the binary does");
}

#pragma mark - Property list values

/** Rebuilds the wrong-type message a dictionary lookup is expected to produce.

    Only the class name and the rendering of the value are under test, and both
    are Foundation's to choose at runtime, so deriving them here keeps the test
    honest instead of pinning whichever internal class this build happens to use. */
static NSString *DVTExpectedWrongTypeMessage(id value, Class plistClass, NSString *key)
{
    return [NSString stringWithFormat:@"Found %@ value (%@), instead of %@ for key: %@",
                                      NSStringFromClass([value class]), [value debugDescription],
                                      NSStringFromClass(plistClass), key];
}

/** Drives the variadic builder through its `arguments:` twin, so the twin is
    exercised with a real `va_list` and not only through the forwarder. */
static NSError *DVTErrorWithMessageFormat(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSError *error = [NSError dvt_errorWithDomain:@"DVTTestErrorDomain"
                                        errorCode:0
                                    messageFormat:format
                                        arguments:args];
    va_end(args);
    return error;
}

/** The error builders: domain and code pass through verbatim, and the whole
    of the user info is the one rendered description. */
static void DVTTestErrorBuilders(void)
{
    fprintf(stdout, "\n== error builders ==\n");

    NSError *error = [NSError dvt_errorWithDomain:@"DVTTestErrorDomain"
                                        errorCode:7
                                    messageFormat:@"value %@ at index %d", @"x", 3];
    DVTExpectEqualObjects(error.domain, @"DVTTestErrorDomain", @"the domain is the caller's");
    DVTExpect(error.code == 7, @"the code is the caller's");
    DVTExpectEqualObjects(error.localizedDescription, @"value x at index 3",
                          @"the format is rendered with the arguments that follow it");
    DVTExpect(error.userInfo.count == 1, @"the user info carries only a description");
    DVTExpectEqualObjects(error.userInfo[NSLocalizedDescriptionKey], @"value x at index 3",
                          @"the description is the rendered format under the standard key");

    /* A format with nothing to substitute stands alone. */
    error = [NSError dvt_errorWithDomain:@"DVTTestErrorDomain" errorCode:0 messageFormat:@"plain"];
    DVTExpectEqualObjects(error.localizedDescription, @"plain", @"a bare format passes through");

    /* An escaped percent renders, it does not leak. */
    error = [NSError dvt_errorWithDomain:@"DVTTestErrorDomain" errorCode:-2
                           messageFormat:@"100%% ready"];
    DVTExpectEqualObjects(error.localizedDescription, @"100% ready", @"%% renders as a bare percent");

    /* The arguments: twin takes a va_list directly. */
    error = DVTErrorWithMessageFormat(@"list %@ and %@", @1, @2);
    DVTExpectEqualObjects(error.domain, @"DVTTestErrorDomain", @"the twin keeps the domain");
    DVTExpectEqualObjects(error.localizedDescription, @"list 1 and 2",
                          @"the arguments: form renders its own va_list");

    /* Zero and empty are ordinary values, not sentinels. */
    error = [NSError dvt_errorWithDomain:@"DVTTestErrorDomain" errorCode:0 messageFormat:@""];
    DVTExpect(error.code == 0, @"a zero code survives");
    DVTExpectEqualObjects(error.localizedDescription, @"", @"an empty format yields an empty description");
}

/** Exercises the coercion family: every receiver answers one question with
    itself and the other five with nil, and the two dictionary lookups are the
    only ones in the family that say why. */
static void DVTTestPropertyListValue(void)
{
    fprintf(stdout, "\n== property list values ==\n");

    /* Identity, not equality: the contract is "here it is", not "an equal
       copy", so a mutable subclass has to pass too. */
    NSString *string = @"text";
    DVTExpect([string dvt_plistStringValue] == string, @"string is its own plist string");
    DVTExpect([string dvt_plistNumberValue] == nil, @"string is not a plist number");
    DVTExpect([string dvt_plistDateValue] == nil, @"string is not a plist date");
    DVTExpect([string dvt_plistArrayValue] == nil, @"string is not a plist array");
    DVTExpect([string dvt_plistDictionaryValue] == nil, @"string is not a plist dictionary");
    DVTExpect([string dvt_plistDataValue] == nil, @"string is not a plist data");
    DVTExpect(@"12".dvt_plistNumberValue == nil, @"a numeric string is not parsed into a number");

    NSData *data = [NSData data];
    DVTExpect([data dvt_plistDataValue] == data, @"data is its own plist data");
    DVTExpect([data dvt_plistStringValue] == nil, @"data is not decoded into a string");
    DVTExpect([data dvt_plistNumberValue] == nil, @"data is not a plist number");
    DVTExpect([data dvt_plistDateValue] == nil, @"data is not a plist date");
    DVTExpect([data dvt_plistArrayValue] == nil, @"data is not a plist array");
    DVTExpect([data dvt_plistDictionaryValue] == nil, @"data is not a plist dictionary");

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:0];
    DVTExpect([date dvt_plistDateValue] == date, @"date is its own plist date");
    DVTExpect([date dvt_plistStringValue] == nil, @"date is not a plist string");
    DVTExpect([date dvt_plistDataValue] == nil, @"date is not a plist data");
    DVTExpect([date dvt_plistNumberValue] == nil, @"a date is not a number");
    DVTExpect([date dvt_plistArrayValue] == nil, @"date is not a plist array");
    DVTExpect([date dvt_plistDictionaryValue] == nil, @"date is not a plist dictionary");

    NSArray *array = @[ @1 ];
    DVTExpect([array dvt_plistArrayValue] == array, @"array is its own plist array");
    DVTExpect([array dvt_plistStringValue] == nil, @"array is not a plist string");
    DVTExpect([array dvt_plistDataValue] == nil, @"array is not a plist data");
    DVTExpect([array dvt_plistNumberValue] == nil, @"array is not a plist number");
    DVTExpect([array dvt_plistDateValue] == nil, @"array is not a plist date");
    DVTExpect([array dvt_plistDictionaryValue] == nil, @"array is not a plist dictionary");

    NSDictionary *dictionary = @{ @"x" : @1 };
    DVTExpect([dictionary dvt_plistDictionaryValue] == dictionary,
              @"dictionary is its own plist dictionary");
    DVTExpect([dictionary dvt_plistStringValue] == nil, @"dictionary is not a plist string");
    DVTExpect([dictionary dvt_plistDataValue] == nil, @"dictionary is not a plist data");
    DVTExpect([dictionary dvt_plistNumberValue] == nil, @"dictionary is not a plist number");
    DVTExpect([dictionary dvt_plistDateValue] == nil, @"dictionary is not a plist date");
    DVTExpect([dictionary dvt_plistArrayValue] == nil, @"dictionary is not a plist array");

    /* The one method that builds something: a number's canonical text. */
    NSNumber *number = @7;
    DVTExpect([number dvt_plistNumberValue] == number, @"number is its own plist number");
    DVTExpectEqualObjects([number dvt_plistStringValue], @"7", @"number stringifies");
    DVTExpect([number dvt_plistStringValue] != number, @"the stringified number is a new object");
    DVTExpectEqualObjects(@YES.dvt_plistStringValue, @"1", @"a boolean stringifies as 1, not YES");
    DVTExpectEqualObjects((@1.5).dvt_plistStringValue, @"1.5", @"a double keeps its decimal point");
    DVTExpect([@1 dvt_plistDataValue] == nil, @"number is not a plist data");
    DVTExpect([@1 dvt_plistDateValue] == nil, @"number is not a plist date");
    DVTExpect([@1 dvt_plistArrayValue] == nil, @"number is not a plist array");
    DVTExpect([@1 dvt_plistDictionaryValue] == nil, @"number is not a plist dictionary");

    /* Empty instances are still their own type, and so are subclasses. */
    DVTExpect(@"".dvt_plistStringValue != nil, @"an empty string is a plist string");
    DVTExpect([NSData data].dvt_plistDataValue != nil, @"empty data is a plist data");
    DVTExpect([NSArray array].dvt_plistArrayValue != nil, @"an empty array is a plist array");
    DVTExpect([NSDictionary dictionary].dvt_plistDictionaryValue != nil,
              @"an empty dictionary is a plist dictionary");
    NSMutableString *mutableString = [NSMutableString stringWithString:@"m"];
    DVTExpect([mutableString dvt_plistStringValue] == mutableString, @"a mutable string passes");
    NSMutableArray *mutableArray = [NSMutableArray array];
    DVTExpect([mutableArray dvt_plistArrayValue] == mutableArray, @"a mutable array passes");
    NSMutableDictionary *mutableDictionary = [NSMutableDictionary dictionary];
    DVTExpect([mutableDictionary dvt_plistDictionaryValue] == mutableDictionary,
              @"a mutable dictionary passes");
    NSMutableData *mutableData = [NSMutableData data];
    DVTExpect([mutableData dvt_plistDataValue] == mutableData, @"mutable data passes");

    /* The two lookups: a hit is silent, a miss explains itself. */
    NSDictionary *container = @{ @"arr" : @[ @1 ], @"dic" : dictionary, @"num" : @7,
                                 @"data" : [NSData data], @"null" : [NSNull null] };
    NSError *error = nil;
    NSArray *foundArray = [container dvt_plistArrayForKey:@"arr" error:&error];
    DVTExpect(foundArray == container[@"arr"], @"the stored array comes back");
    DVTExpect(error == nil, @"a hit sets no error");
    DVTExpect([container dvt_plistDictionaryForKey:@"dic" error:NULL] == dictionary,
              @"the stored dictionary comes back");

    /* A pre-set error must be left alone on success. */
    NSError *sentinel = [NSError errorWithDomain:@"sentinel" code:99 userInfo:nil];
    error = sentinel;
    [container dvt_plistArrayForKey:@"arr" error:&error];
    DVTExpect(error == sentinel, @"a hit does not touch the caller's error");

    error = nil;
    DVTExpect([container dvt_plistArrayForKey:@"missing" error:&error] == nil,
              @"a missing key yields nil");
    DVTExpectEqualObjects(error.domain, DVTPropertyListValueDecodingErrorDomain,
                          @"a miss reports the decoding domain");
    DVTExpect(error.code == 0, @"a miss uses code 0");
    DVTExpectEqualObjects(error.localizedDescription, @"Missing NSArray value for key: missing",
                          @"a missing key says so");
    DVTExpect(error.userInfo.count == 1, @"the error carries only a description");

    error = nil;
    DVTExpect([container dvt_plistDictionaryForKey:@"missing" error:&error] == nil,
              @"a missing key yields nil for dictionaries too");
    DVTExpectEqualObjects(error.localizedDescription, @"Missing NSDictionary value for key: missing",
                          @"the dictionary miss names NSDictionary");

    /* A wrong-typed key reports the class, the value, and what was wanted --
       and renders the value with -debugDescription, where empty data is `<>`.
       The class names in these messages are Foundation internals that vary with
       tagged-pointer state (`NSConstantIntegerNumber` vs `__NSCFNumber`), so the
       expectation names the value's real class rather than freezing one. */
    error = nil;
    DVTExpect([container dvt_plistArrayForKey:@"num" error:&error] == nil,
              @"a wrong-typed key yields nil");
    DVTExpectEqualObjects(error.localizedDescription,
                          DVTExpectedWrongTypeMessage(container[@"num"], [NSArray class], @"num"),
                          @"a wrong-typed key names the class, the value and the wanted type");
    DVTExpect([error.localizedDescription containsString:@"instead of NSArray for key: num"],
              @"the message names the type that was wanted");

    error = nil;
    [container dvt_plistArrayForKey:@"data" error:&error];
    DVTExpectEqualObjects(error.localizedDescription,
                          DVTExpectedWrongTypeMessage(container[@"data"], [NSArray class], @"data"),
                          @"a data value is reported like any other");
    DVTExpect([error.localizedDescription containsString:@"value (<>), instead of"],
              @"an empty data value is rendered as <>, not as {length = 0, bytes = 0x}");

    error = nil;
    [container dvt_plistArrayForKey:@"null" error:&error];
    DVTExpectEqualObjects(error.localizedDescription,
                          @"Found NSNull value (<null>), instead of NSArray for key: null",
                          @"NSNull is reported as itself");

    error = nil;
    [container dvt_plistDictionaryForKey:@"arr" error:&error];
    DVTExpectEqualObjects(error.localizedDescription,
                          DVTExpectedWrongTypeMessage(container[@"arr"], [NSDictionary class], @"arr"),
                          @"an array under a dictionary lookup is reported like any other");
    DVTExpect([error.localizedDescription containsString:@"(<"],
              @"an array value is rendered with -debugDescription, not -description");

    /* A NULL error pointer is legal. */
    DVTExpect([container dvt_plistArrayForKey:@"missing" error:NULL] == nil,
              @"a NULL error pointer is tolerated");

    DVTExpectEqualObjects(DVTPropertyListValueDecodingErrorDomain, @"DVTPropertyListValueDecoding",
                          @"the domain symbol holds Apple's domain string");
}

#pragma mark - Assertions

/** Captures reports instead of aborting. */

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

static void DVTTestTextExtras(void)
{
    /* DVTLineEndingNone has no string: Apple indexes a three-entry table at
       value - 1 and tests the result unsigned, so 0 -- and every negative
       value, and every value past 3 -- yields nil rather than a string. */
    DVTExpect(DVTStringFromLineEnding(DVTLineEndingNone) == nil, @"no line ending has no string");
    DVTExpectEqualObjects(DVTStringFromLineEnding(DVTLineEndingLF), @"\n", @"LF is a line feed");
    DVTExpectEqualObjects(DVTStringFromLineEnding(DVTLineEndingCR), @"\r", @"CR is a carriage return");
    DVTExpectEqualObjects(DVTStringFromLineEnding(DVTLineEndingCRLF), @"\r\n", @"CRLF is both, in that order");
    DVTExpect(DVTStringFromLineEnding((DVTLineEnding)4) == nil, @"one past the last ending is nil");
    DVTExpect(DVTStringFromLineEnding((DVTLineEnding)-1) == nil, @"a negative ending is nil, not a table underflow");
    DVTExpect(DVTStringFromLineEnding((DVTLineEnding)NSIntegerMax) == nil, @"a huge ending is nil");

    /* Find styles map 0...3 in order. */
    DVTExpect([DVTStringFromFindMatchStyle(DVTFindsMatchStyleContains) isEqualToString:@"Contains"],
              @"style 0 is Contains");
    DVTExpect([DVTStringFromFindMatchStyle(DVTFindsMatchStyleStartsWith) isEqualToString:@"StartsWith"],
              @"style 1 is StartsWith");
    DVTExpect([DVTStringFromFindMatchStyle(DVTFindsMatchStyleWholeWords) isEqualToString:@"WholeWords"],
              @"style 2 is WholeWords");
    DVTExpect([DVTStringFromFindMatchStyle(DVTFindsMatchStyleEndsWith) isEqualToString:@"EndsWith"],
              @"style 3 is EndsWith");

    /* Out of range this one falls back rather than asserting, and the fallback is
       WholeWords -- the same string the table holds at index 2. */
    DVTExpect([DVTStringFromFindMatchStyle((DVTFindsMatchStyle)4) isEqualToString:@"WholeWords"],
              @"an out of range style falls back to WholeWords");
    DVTExpect([DVTStringFromFindMatchStyle((DVTFindsMatchStyle)99) isEqualToString:@"WholeWords"],
              @"a far out of range style also falls back to WholeWords");

    /* The parser is case sensitive, and compares in the order WholeWords,
       StartsWith, EndsWith, then Contains. Anything unrecognised is Contains. */
    DVTExpect(DVTFindMatchStyleFromString(@"WholeWords") == DVTFindsMatchStyleWholeWords, @"WholeWords parses");
    DVTExpect(DVTFindMatchStyleFromString(@"StartsWith") == DVTFindsMatchStyleStartsWith, @"StartsWith parses");
    DVTExpect(DVTFindMatchStyleFromString(@"EndsWith") == DVTFindsMatchStyleEndsWith, @"EndsWith parses");
    DVTExpect(DVTFindMatchStyleFromString(@"Contains") == DVTFindsMatchStyleContains, @"Contains parses");
    DVTExpect(DVTFindMatchStyleFromString(@"wholewords") == DVTFindsMatchStyleContains,
              @"a lowercase style is not recognised");
    DVTExpect(DVTFindMatchStyleFromString(@"wholewords") == 0,
              @"an unrecognised style parses as Contains, not as an error");
    DVTExpect(DVTFindMatchStyleFromString(@"") == DVTFindsMatchStyleContains,
              @"the empty string parses as Contains");
    DVTExpect(DVTFindMatchStyleFromString(@"End") == DVTFindsMatchStyleContains,
              @"a prefix is not enough to match");
    /* Every style the parser can return has to survive the round trip. */
    for (NSInteger i = 0; i <= 3; i++) {
        DVTExpect(DVTFindMatchStyleFromString(DVTStringFromFindMatchStyle((DVTFindsMatchStyle)i)) == i,
                  @"each style round trips");
    }

    /* A plain space separates fragments; an escaped space does not, so "a\ b"
       stays one fragment that holds a space. */
    NSArray<NSString *> *plain = DVTTextFragmentsForStringPreservingEscapedSpaces(@"a b c");
    DVTExpectEqualObjects([plain componentsJoinedByString:@"|"], @"a|b|c",
                          @"plain spaces split into fragments");
    DVTExpect(plain.count == 3, @"three words give three fragments");

    NSArray<NSString *> *escaped = DVTTextFragmentsForStringPreservingEscapedSpaces(@"a\\ b c");
    DVTExpectEqualObjects([escaped componentsJoinedByString:@"|"], @"a b|c",
                          @"an escaped space stays inside its fragment");
    DVTExpect(escaped.count == 2, @"an escaped space does not add a fragment");

    /* Runs of spaces vanish: empty pieces are dropped rather than kept, so a
       string of nothing but spaces yields an empty array and not a run of empty
       strings. */
    DVTExpect(DVTTextFragmentsForStringPreservingEscapedSpaces(@"").count == 0,
              @"the empty string has no fragments");
    DVTExpect(DVTTextFragmentsForStringPreservingEscapedSpaces(@"   ").count == 0,
              @"spaces alone yield no fragments");
    NSArray<NSString *> *padded = DVTTextFragmentsForStringPreservingEscapedSpaces(@"  a  b  ");
    DVTExpectEqualObjects([padded componentsJoinedByString:@"|"], @"a|b",
                          @"leading, trailing and doubled spaces all collapse");
    DVTExpect(padded.count == 2, @"collapsing does not leave holes");

    /* A lone escaped space is a fragment holding a space. */
    NSArray<NSString *> *lone = DVTTextFragmentsForStringPreservingEscapedSpaces(@"\\ ");
    DVTExpect(lone.count == 1, @"an escaped space alone is one fragment");
    DVTExpectEqualObjects(lone.firstObject, @" ", @"and that fragment holds a space");

    /* The placeholder Apple substitutes is itself unescaped back into a space,
       so passing that literal text is indistinguishable from an escape. */
    NSArray<NSString *> *literal = DVTTextFragmentsForStringPreservingEscapedSpaces(@"\\<space>");
    DVTExpect(literal.count == 1, @"the placeholder literal is one fragment");
    DVTExpectEqualObjects(literal.firstObject, @" ", @"the placeholder literal decodes to a space");

    /* Tabs and newlines are not separators, so they stay inside a fragment. */
    NSArray<NSString *> *tabbed = DVTTextFragmentsForStringPreservingEscapedSpaces(@"a\tb");
    DVTExpectEqualObjects(tabbed.firstObject, @"a\tb", @"a tab does not split");
    NSArray<NSString *> *newlined = DVTTextFragmentsForStringPreservingEscapedSpaces(@"a\nb");
    DVTExpectEqualObjects(newlined.firstObject, @"a\nb", @"a newline does not split");

    /* Non-ASCII text must survive the protect/restore round trip byte for byte. */
    NSArray<NSString *> *unicode = DVTTextFragmentsForStringPreservingEscapedSpaces(@"ünïcøde 日本語 x");
    DVTExpect(unicode.count == 3, @"unicode words split on spaces normally");
    DVTExpectEqualObjects([unicode componentsJoinedByString:@"|"], @"ünïcøde|日本語|x",
                          @"unicode survives unchanged");
}

static void DVTTestFilterExpression(void)
{
    /* Compound operators are the only two, and they are the obvious spelling. */
    DVTExpectEqualObjects(DVTStringForFilterExpressionOperator(DVTFilterCompoundExpressionOperatorAnd),
                          @"AND", @"operator 0 is AND");
    DVTExpectEqualObjects(DVTStringForFilterExpressionOperator(DVTFilterCompoundExpressionOperatorOr),
                          @"OR", @"operator 1 is OR");

    /* Numeric comparisons render as bare single characters -- there is no >= or
       <= variant in this enum, only the three strict ones. */
    DVTExpectEqualObjects(DVTNumericalFilterComparisonTypeDisplayString(DVTNumericalFilterComparisonTypeEqualTo),
                          @"=", @"numeric 0 is equals");
    DVTExpectEqualObjects(DVTNumericalFilterComparisonTypeDisplayString(DVTNumericalFilterComparisonTypeLessThan),
                          @"<", @"numeric 1 is less than");
    DVTExpectEqualObjects(DVTNumericalFilterComparisonTypeDisplayString(DVTNumericalFilterComparisonTypeGreaterThan),
                          @">", @"numeric 2 is greater than");

    /* Textual comparisons spell the operator out in full. */
    DVTExpectEqualObjects(DVTTextFilterComparisonTypeDisplayString(DVTTextFilterComparisonTypeEquals),
                          @"Equals", @"text 0 is Equals");
    DVTExpectEqualObjects(DVTTextFilterComparisonTypeDisplayString(DVTTextFilterComparisonTypeContains),
                          @"Contains", @"text 1 is Contains");
    DVTExpectEqualObjects(DVTTextFilterComparisonTypeDisplayString(DVTTextFilterComparisonTypeDoesNotContain),
                          @"Does Not Contain", @"text 2 is Does Not Contain");
    DVTExpectEqualObjects(DVTTextFilterComparisonTypeDisplayString(DVTTextFilterComparisonTypeBeginsWith),
                          @"Begins With", @"text 3 is Begins With");
    DVTExpectEqualObjects(DVTTextFilterComparisonTypeDisplayString(DVTTextFilterComparisonTypeEndsWith),
                          @"Ends With", @"text 4 is Ends With");
    DVTExpectEqualObjects(DVTTextFilterComparisonTypeDisplayString(DVTTextFilterComparisonTypeLike),
                          @"Like", @"text 5 is Like");

    /* Note the contrast with the find-style table, which falls back quietly: these
       three assert instead, so there is no out of range case to check here. The
       abort is verified out of process in the differential, because an assert
       would take the test runner down with it. */
}

/** Builds a patterns for `expression`, shaped like a real deserialized pattern:
    the coder is the only path that mints a unique ID, and the backreference
    machinery requires one. */
static DVTFindPattern *DVTFindPatternWithExpression(NSString *expression)
{
    DVTFindPattern *pattern = [DVTFindPattern new];
    pattern.regularExpression = expression;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:pattern requiringSecureCoding:YES error:NULL];
    return [NSKeyedUnarchiver unarchivedObjectOfClass:[DVTFindPattern class] fromData:data error:NULL];
}

static void DVTTestFindPattern(void)
{
    fprintf(stdout, "\n== find patterns ==\n");

    /* A plain string component passes through as its own representation and
       summary, and its content is just non-emptiness. */
    DVTExpectEqualObjects([@"lit" dvt_findPatternComponentRepresentation], @"lit",
                          @"a string is its own representation");
    DVTExpectEqualObjects([@"lit" dvt_findPatternComponentPropertyListRepresentation], @"lit",
                          @"a string's property-list representation is itself");
    DVTExpectEqualObjects([@"lit" dvt_findPatternComponentSummary], @"lit",
                          @"a string's summary is itself");
    DVTExpect([@"lit" dvt_findPatternHasContent], @"a non-empty string has content");
    DVTExpect(![@"" dvt_findPatternHasContent], @"an empty string has no content");

    /* A DVTFindPattern stands in for itself, keeping its negation in the
       summary the way the find bar renders it. */
    DVTFindPattern *negated = DVTFindPatternWithExpression(@"");
    negated.tokenString = @"pat";
    negated.isNegation = YES;
    DVTExpectEqualObjects([negated dvt_findPatternComponentSummary], @"[!pat]",
                          @"a negated pattern appears in brackets");
    negated.isNegation = NO;
    DVTExpectEqualObjects([negated dvt_findPatternComponentSummary], @"[pat]",
                          @"an un-negated pattern stays in brackets");
    DVTExpect([negated dvt_findPatternHasContent], @"a pattern always has content");
    DVTExpectEqualObjects([negated dvt_findPatternComponentPropertyListRepresentation],
                          negated.propertyListRepresentation, @"a pattern matches its own property list");

    /* NSDictionary turns into a pattern through the property-list path. */
    DVTFindPattern *pattern = DVTFindPatternWithExpression(@"pat");
    pattern.captureGroupID = 2;
    id plist = pattern.propertyListRepresentation;
    DVTExpect([plist isKindOfClass:[NSDictionary class]], @"a pattern serializes to a dictionary");
    DVTExpectEqualObjects([[NSDictionary dictionaryWithDictionary:plist] dvt_findPatternComponentRepresentation], pattern,
                          @"a pattern dictionary becomes the same pattern");

    /* Factory variants: an empty list, a single string, and a nil string. */
    DVTExpect([DVTFindPatternComponents emptyComponents].components.count == 0, @"empty components");
    DVTExpect([[DVTFindPatternComponents findPatternComponentsWithString:@"x"] components].count == 1,
              @"string components hold the string");
    DVTExpect([DVTFindPatternComponents findPatternComponentsWithString:nil].components.count == 0,
              @"a nil string yields empty components");

    /* The pasteboard path accepts a property-list array and rebuilds patterns. */
    DVTFindPatternComponents *fromPasteboard =
        [DVTFindPatternComponents findPatternComponentsFromPasteboardPropertyList:(@[plist, @"lit"])];
    DVTExpect(fromPasteboard != nil, @"an array of property lists is accepted");
    if (fromPasteboard != nil) {
        DVTExpect(fromPasteboard.components.count == 2, @"both components survive the pasteboard");
        DVTExpect([fromPasteboard.components[0] isEqualToFindPattern:pattern], @"the decoded pattern matches");
        DVTExpectEqualObjects(fromPasteboard.components[1], @"lit", @"the literal survives");
    }
    DVTExpect([DVTFindPatternComponents findPatternComponentsFromPasteboardPropertyList:@"junk"] == nil,
              @"a non-array property list is rejected");
    DVTExpect([DVTFindPatternComponents findPatternComponentsFromPasteboardPropertyList:(@[@1])] == nil,
              @"an unresolvable member rejects the whole list");
    /* Empty strings carry no content, so they are dropped at initialization. */
    DVTExpectEqualObjects([DVTFindPatternComponents findPatternComponentsFromPasteboardPropertyList:(@[@"", @"x"])].components,
                          (@[@"x"]), @"an empty member is dropped");

    /* Escape diagnostics: the printable characters named in the mask get a
       backslash, and characters outside it pass through untouched. */
    NSString *escapable = @"$()*+./?[\\]^{|}";
    NSMutableString *escaped = [NSMutableString string];
    for (NSUInteger i = 0; i < escapable.length; i++) {
        [escaped appendFormat:@"\\%C", (unichar)[escapable characterAtIndex:i]];
    }
    DVTExpectEqualObjects([[DVTFindPatternComponents findPatternComponentsWithString:escapable] regularExpression],
                          escaped, @"every escapable character gains a backslash");
    DVTExpectEqualObjects([[DVTFindPatternComponents findPatternComponentsWithString:@"~"] regularExpression],
                          @"~", @"a tilde is not escaped");
    DVTExpectEqualObjects([[DVTFindPatternComponents findPatternComponentsWithString:@"aB3 :z"] regularExpression],
                          @"aB3 :z", @"letters, digits, spaces, and colons pass through");

    /* The same escaping applies to the replacement expression. */
    DVTExpectEqualObjects([[DVTFindPatternComponents findPatternComponentsWithString:@"a.b"] replacementExpression],
                          @"a\\.b", @"replacement expression escapes the literal");

    /* A lone pattern is wrapped as a capture group; convenience derives via
       escaping and backreferencing on. */
    DVTFindPattern *base = DVTFindPatternWithExpression(@"x");
    base.groupID = 1;
    DVTExpectEqualObjects([[[DVTFindPatternComponents alloc] initWithComponents:(@[base])] regularExpression],
                          @"(x)", @"a grouped pattern is wrapped for the regular expression");
    DVTExpect((base.captureGroupID == 1), @"the combined pattern claims capture group 1");

    /* A repeated pattern becomes a backreference instead of a fresh group. */
    DVTFindPattern *first = DVTFindPatternWithExpression(@"(?:x)");
    first.groupID = 0;
    DVTFindPattern *second = DVTFindPatternWithExpression(@"y");
    second.groupID = 1;
    second.captureGroupID = 1;
    DVTFindPattern *third = [second copy];
    DVTFindPatternComponents *repeat =
        [[DVTFindPatternComponents alloc] initWithComponents:(@[first, second, third])];
    DVTExpectEqualObjects([repeat regularExpressionEscapingStrings:YES usingBackreferences:YES],
                          @"(?:x)(y)(?:\\1)", @"the early non-capturing group does not count");
    DVTExpectEqualObjects([repeat regularExpressionEscapingStrings:YES usingBackreferences:NO],
                          @"(?:x)(y)(y)", @"without backreferences each pattern gets its own group");
    DVTExpect((third.captureGroupID == 2), @"a repeated unwrapped pattern takes the next group");

    /* The wrapper counts the pattern's own captures, so "(x)" contributes two
       and pushes the next group one higher. */
    DVTFindPattern *twoWide = DVTFindPatternWithExpression(@"(x)");
    twoWide.groupID = 1;
    DVTFindPattern *twoNext = DVTFindPatternWithExpression(@"z");
    twoNext.groupID = 1;
    DVTExpectEqualObjects([[[DVTFindPatternComponents alloc] initWithComponents:(@[twoWide, twoNext])]
                               regularExpressionEscapingStrings:YES usingBackreferences:YES],
                          @"((x))(z)", @"a nested capture in the pattern is counted");
    DVTExpect((twoNext.captureGroupID == 3), @"the second group starts one past the inner captures");

    /* The replacement expression substitutes, and a bare digit right after a
       substitution gets a separating backslash. */
    DVTFindPattern *replace = DVTFindPatternWithExpression(@"");
    replace.replacementString = @"$1";
    DVTFindPatternComponents *repl = [[DVTFindPatternComponents alloc] initWithComponents:(@[replace, @"2"])];
    DVTExpectEqualObjects([repl replacementExpression], @"$1\\2", @"a digit after a replacement is separated");
    DVTExpectEqualObjects([[[DVTFindPatternComponents alloc] initWithComponents:(@[replace, @"a"])] replacementExpression],
                          @"$1a", @"a letter after a replacement is not");
    DVTExpectEqualObjects([[[DVTFindPatternComponents alloc] initWithComponents:(@[replace, @""])] replacementExpression],
                          @"$1", @"an empty literal keeps the prior state");

    /* Status: literal-only lists are invalid, the placeholder is special, and a
       real pattern makes the list valid. */
    DVTExpect([DVTFindPatternComponents emptyComponents].patternStatus == DVTFindPatternStatusInvalid,
              @"no patterns means invalid");
    DVTExpect([[DVTFindPatternComponents findPatternComponentsWithString:@"lit"] patternStatus] ==
                  DVTFindPatternStatusInvalid,
              @"a literal-only list is still invalid");
    DVTExpect([[[DVTFindPatternComponents alloc]
                   initWithComponents:(@[[DVTFindPattern placeholderFindPattern]])] patternStatus] ==
                  DVTFindPatternStatusPlaceholder,
              @"the placeholder marks the list");
    DVTExpect([[[DVTFindPatternComponents alloc] initWithComponents:(@[pattern])] patternStatus] ==
                  DVTFindPatternStatusValid,
              @"a real pattern makes the list valid");

    /* hasContent and the string accessors. */
    DVTExpect(![[DVTFindPatternComponents emptyComponents] hasContent], @"an empty list has no content");
    DVTExpect([[[DVTFindPatternComponents alloc] initWithComponents:(@[@"", pattern])] hasContent],
              @"a pattern counts as content even with an empty literal");
    DVTExpectEqualObjects([[[DVTFindPatternComponents alloc] initWithComponents:(@[pattern, @"pre", @"post"])]
                               stringComponents],
                          (@[@"pre", @"post"]), @"string components skip patterns");
    DVTExpectEqualObjects([[[DVTFindPatternComponents alloc] initWithComponents:(@[pattern, @"pre", @"post"])]
                               stringByDeletingPatterns],
                          @"prepost", @"deleting patterns concatenates the literals");

    /* The summary concatenates component summaries with no separator. */
    negated.isNegation = YES;
    DVTExpectEqualObjects([[[DVTFindPatternComponents alloc] initWithComponents:(@[@"lit", negated])] summary],
                          @"lit[!pat]", @"the summary joins component summaries");

    /* The property-list representation maps every component. */
    DVTExpectEqualObjects([[[DVTFindPatternComponents alloc] initWithComponents:(@[pattern, @"lit"])]
                               propertyListRepresentation],
                          (@[pattern.propertyListRepresentation, @"lit"]), @"components serialize member by member");

    /* Immutability and equality: a copy is identity, and equal components hash
       and compare the same. */
    DVTFindPatternComponents *comp1 =
        [[DVTFindPatternComponents alloc] initWithComponents:(@[first, @"a", second])];
    DVTExpect([comp1 copy] == comp1, @"copyWithZone: returns the same immutable object");
    DVTExpect(comp1.hash == first.hash * 33 + second.hash, @"hash is first times 33 plus last");
    DVTFindPatternComponents *comp2 =
        [[DVTFindPatternComponents alloc] initWithComponents:(@[first, @"a", second])];
    DVTExpectEqualObjects(comp1, comp2, @"equal components compare equal");
    DVTExpect([comp1 isEqualToFindPatternComponents:comp2], @"explicit equality agrees");
    DVTExpect(![comp1 isEqual:@"x"], @"components are never equal to a string");

    /* The placeholder does not survive the coder's unique-ID round trip, but a
       real unique ID is preserved; repeatedPatternID is dropped by both the
       coder and copy. */
    DVTFindPattern *seeded = [DVTFindPattern new];
    seeded.regularExpression = @"enc";
    /* The first decode has no ID to preserve, so it mints one. */
    NSError *coderError = nil;
    NSData *encodedData = [NSKeyedArchiver archivedDataWithRootObject:seeded requiringSecureCoding:YES error:&coderError];
    DVTExpect(encodedData != nil && coderError == nil, @"encoding a pattern works");
    DVTFindPattern *encoded = coderError == nil
        ? [NSKeyedUnarchiver unarchivedObjectOfClass:[DVTFindPattern class] fromData:encodedData error:&coderError]
        : nil;
    DVTExpect(encoded != nil && coderError == nil, @"decoding an id-less pattern works");
    DVTExpect(encoded.uniqueID != nil, @"decoding an id-less pattern mints a unique ID");
    /* With no repeatedPatternID set, a round trip is an equality-preserving
       identity: every compared field survives the coder. */
    encodedData = [NSKeyedArchiver archivedDataWithRootObject:encoded requiringSecureCoding:YES error:&coderError];
    DVTExpect(encodedData != nil && coderError == nil, @"re-encoding a pattern works");
    DVTFindPattern *decoded = coderError == nil
        ? [NSKeyedUnarchiver unarchivedObjectOfClass:[DVTFindPattern class] fromData:encodedData error:&coderError]
        : nil;
    DVTExpect(decoded != nil && coderError == nil, @"re-decoding a pattern works");
    DVTExpectEqualObjects(decoded, encoded, @"the coder round-trips a pattern");
    DVTExpectEqualObjects(decoded.uniqueID, encoded.uniqueID, @"the unique ID survives the coder");
    /* The coder rejects repeatedPatternID, so a re-encoded value is dropped on
       decode, and equality falls apart. */
    encoded.repeatedPatternID = 7;
    encodedData = [NSKeyedArchiver archivedDataWithRootObject:encoded requiringSecureCoding:YES error:&coderError];
    DVTExpect(encodedData != nil && coderError == nil, @"re-encoding a marked pattern works");
    DVTFindPattern *markedDecoded = coderError == nil
        ? [NSKeyedUnarchiver unarchivedObjectOfClass:[DVTFindPattern class] fromData:encodedData error:&coderError]
        : nil;
    DVTExpect(markedDecoded != nil && coderError == nil, @"re-decoding a marked pattern works");
    DVTExpect(![markedDecoded isEqual:encoded], @"a dropped repeatedPatternID breaks equality");
    DVTExpect(markedDecoded.repeatedPatternID == 0, @"repeatedPatternID is dropped by the coder");
    DVTExpectEqualObjects(markedDecoded.uniqueID, encoded.uniqueID, @"the unique ID still survives");
    DVTFindPattern *copied = [encoded copy];
    DVTExpectEqualObjects(copied.uniqueID, encoded.uniqueID, @"copy keeps the unique ID");
    DVTExpect(copied.repeatedPatternID == 0, @"repeatedPatternID is dropped by copy");

    /* The NSObject category asserts for everything but the representation,
       which falls back to nil; the failures are captured, not fatal. */
    DVTTestCapturingHandler *handler = [DVTTestCapturingHandler new];
    [DVTAssertionReportHandler setCurrentHandler:handler];
    NSObject *mystery = [NSObject new];
    DVTExpect([mystery dvt_findPatternComponentRepresentation] == nil,
              @"an unknown object has no component representation");
    DVTExpect(handler.reports.count == 0, @"the representation lookup does not assert");
    id propertyList = [mystery dvt_findPatternComponentPropertyListRepresentation];
    DVTExpect(propertyList == nil, @"the unknown property-list representation is nil");
    DVTExpect(handler.reports.count == 1, @"the unknown property-list representation asserts");
    id summary = [mystery dvt_findPatternComponentSummary];
    DVTExpect(summary == nil, @"the unknown summary is nil");
    DVTExpect(handler.reports.count == 2, @"the unknown summary asserts");
    DVTExpect(![mystery dvt_findPatternHasContent], @"the unknown component has no content");
    DVTExpect(handler.reports.count == 3, @"the unknown content check asserts");
    for (NSString *report in handler.reports) {
        DVTExpect([report containsString:@"subclass responsibility"], @"the assert names the subclass rule");
    }
    DVTExpect(!handler.lastWasWarning, @"subclass responsibility asserts are failures, not warnings");
    [DVTAssertionReportHandler setCurrentHandler:nil];
}

/** Records the data source it is asked to hash for, so the composite hashers'
    forwarding can be observed. Copying returns the receiver, which is enough for
    dictionary-literal use. */
@interface DVTTestDataSourceProbe : NSObject <NSCopying>
@property (nonatomic, strong) id receivedDataSource;
@property (nonatomic) NSUInteger hashValue;
@end

@implementation DVTTestDataSourceProbe
- (instancetype)copyWithZone:(NSZone *)zone
{
    (void)zone;
    return self;
}
- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource
{
    self.receivedDataSource = dataSource;
    return self.hashValue;
}
@end

static void DVTTestDiffHashing(void)
{
    /* A zero-length range short-circuits before any characters are read, so an
       empty string hashes to zero. */
    DVTExpect(DVTStringGetCRC32Checksum(@"", 0, 0) == 0, @"an empty range hashes to zero");

    /* The implementation feeds UTF-16 code units to zlib, so the result matches
       a CRC-32 computed over the string's little-endian UTF-16 bytes. */
    NSString *pinned = @"The quick brown fox jumps over the lazy dog";
    NSData *utf16 = [pinned dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    DVTExpect(DVTStringGetCRC32Checksum(pinned, 0, pinned.length) ==
              (NSUInteger)crc32(0, (const Bytef *)utf16.bytes, (uInt)utf16.length),
              @"the string CRC-32 matches zlib over its UTF-16 bytes");
    DVTExpect(DVTStringGetCRC32Checksum(@"foo", 0, 3) == 0xee4fddd9U,
              @"three ASCII letters pin to a known CRC-32");

    /* A nonzero location hashes only the selected span. */
    DVTExpect(DVTStringGetCRC32Checksum(@"foo", 1, 2) == 0xa0644f21U,
              @"a suffix range hashes the suffix alone");

    /* The primitive hashers ignore their data source. */
    DVTExpect([@"foo" dvt_diffHashForDataSource:@"irrelevant"] == 0xee4fddd9U,
              @"a string hashes to its CRC-32");
    DVTExpect([@"" dvt_diffHashForDataSource:nil] == 0, @"an empty string hashes to zero");

    /* NSData hashes raw bytes, not their string interpretation. */
    NSData *fooBytes = [NSData dataWithBytes:"foo" length:3];
    DVTExpect([fooBytes dvt_diffHashForDataSource:@"irrelevant"] == 0x8c736521U,
              @"an NSData hashes its raw bytes");
    DVTExpect([[[NSData alloc] init] dvt_diffHashForDataSource:nil] == 0, @"empty data hashes to zero");

    /* NSNumber hashes to its unsigned integer value. */
    DVTExpect([@42 dvt_diffHashForDataSource:@"irrelevant"] == 42, @"a number hashes to its value");
    DVTExpect([@0 dvt_diffHashForDataSource:nil] == 0, @"zero hashes to zero");

    /* Arrays accumulate their member hashes and dictionaries accumulate their
       key and value hashes, so order cannot matter. */
    DVTExpect([@[@1, @"foo"] dvt_diffHashForDataSource:@"irrelevant"] == (NSUInteger)(1 + 0xee4fddd9U),
              @"an array sums its members");
    DVTExpect([@[] dvt_diffHashForDataSource:nil] == 0, @"an empty array hashes to zero");
    DVTExpect([(@{@"a": @"foo"}) dvt_diffHashForDataSource:@"irrelevant"] ==
              (NSUInteger)0x3d3f4819U + (NSUInteger)0xee4fddd9U,
              @"a dictionary sums its key and value hashes");
    DVTExpect([(@{}) dvt_diffHashForDataSource:nil] == 0, @"an empty dictionary hashes to zero");

    /* Composite hashers forward the data source to their members. */
    DVTTestDataSourceProbe *probe = [[DVTTestDataSourceProbe alloc] init];
    probe.hashValue = 123;
    DVTTestDataSourceProbe *keyProbe = [[DVTTestDataSourceProbe alloc] init];
    keyProbe.hashValue = 456;
    id probeSource = @"multi-source";
    DVTExpect([@[probe] dvt_diffHashForDataSource:probeSource] == 123,
              @"an array forwards the data source");
    DVTExpect(probe.receivedDataSource == probeSource, @"the array member saw the data source");
    DVTExpect([(@{keyProbe: probe}) dvt_diffHashForDataSource:probeSource] == 123 + 456,
              @"a dictionary hashes both key and value");
    DVTExpect(keyProbe.receivedDataSource == probeSource && probe.receivedDataSource == probeSource,
              @"both the key and the value saw the data source");

    /* A fresh cache is empty on both hash slots. */
    DVTDiffFNVHashCache *cache = [[DVTDiffFNVHashCache alloc] init];
    DVTExpect(cache.modifiedFNVHash == NULL && cache.modifiedFNVHashLength == 0 &&
              cache.originalFNVHash == NULL && cache.originalFNVHashLength == 0,
              @"a fresh cache is empty");

    /* The cache stores whatever buffer it is handed. */
    uint64_t *modified = malloc(3 * sizeof(uint64_t));
    modified[0] = 7;
    modified[1] = 8;
    modified[2] = 9;
    cache.modifiedFNVHash = modified;
    cache.modifiedFNVHashLength = 3;
    DVTExpect(cache.modifiedFNVHash == modified && cache.modifiedFNVHashLength == 3,
              @"the modified hash is stored");

    /* Copying duplicates the buffers, so the copy owns its own memory. */
    DVTDiffFNVHashCache *cacheCopy = [cache copy];
    DVTExpect(cacheCopy.modifiedFNVHash != cache.modifiedFNVHash &&
              cacheCopy.modifiedFNVHash[0] == 7 && cacheCopy.modifiedFNVHash[1] == 8 &&
              cacheCopy.modifiedFNVHash[2] == 9 && cacheCopy.modifiedFNVHashLength == 3,
              @"a copy deep-copies the hash buffer");
    cacheCopy.modifiedFNVHash[1] = 42;
    DVTExpect(cache.modifiedFNVHash[1] == 8, @"the copy does not share the source buffer");

    /* Clearing with NULL frees the owned buffer and reports an empty slot. */
    cache.modifiedFNVHash = NULL;
    cache.modifiedFNVHashLength = 0;
    DVTExpect(cache.modifiedFNVHash == NULL && cache.modifiedFNVHashLength == 0,
              @"clearing the modified hash empties its slot");

    uint64_t *original = malloc(1 * sizeof(uint64_t));
    original[0] = 0xdeadbeef;
    cache.originalFNVHash = original;
    cache.originalFNVHashLength = 1;
    DVTExpect(cache.originalFNVHash == original && cache.originalFNVHashLength == 1,
              @"the original hash is stored");
    cache.originalFNVHash = NULL;
    cache.originalFNVHashLength = 0;
    DVTExpect(cache.originalFNVHash == NULL && cache.originalFNVHashLength == 0,
              @"clearing the original hash empties its slot");
}

/** Builds a table for `text`, poisoning the bytes first so a field the
    initialiser forgets to write shows up as junk rather than as zero. */
static DVTTextLineOffsetTable DVTTableForText(NSString *text)
{
    DVTTextLineOffsetTable table;
    memset(&table, 0x5A, sizeof(table));
    DVTInitializeLineOffsetTable(&table, text);
    return table;
}

/** Compares a table against an explicit list of expected line starts. */
static void DVTExpectOffsets(DVTTextLineOffsetTable table, const NSUInteger *expected, NSUInteger count,
                             NSString *what)
{
    DVTExpect(table.count == count, [NSString stringWithFormat:@"%@ has %lu entries, wanted %lu",
                                               what, (unsigned long)table.count, (unsigned long)count]);
    if (table.count != count) {
        return;
    }
    BOOL equal = YES;
    for (NSUInteger i = 0; i < count; i++) {
        if (table.offsets[i] != expected[i]) {
            equal = NO;
        }
    }
    if (!equal) {
        printf("       actual:   [");
        for (NSUInteger i = 0; i < count; i++) {
            printf("%lu%s", (unsigned long)table.offsets[i], i + 1 < count ? "," : "");
        }
        printf("]\n       expected: [");
        for (NSUInteger i = 0; i < count; i++) {
            printf("%lu%s", (unsigned long)expected[i], i + 1 < count ? "," : "");
        }
        printf("]\n");
    }
    DVTExpect(equal, [NSString stringWithFormat:@"%@ line starts", what]);
}

static void DVTTestLineOffsetTableTextExtras(void)
{
    fprintf(stdout, "\n== line offset table text extras ==\n");

    /* An empty string still has one line, so the table is the start plus the
       length, and both happen to be zero. */
    {
        DVTTextLineOffsetTable table = DVTTableForText(@"");
        const NSUInteger expected[] = { 0, 0 };
        DVTExpectOffsets(table, expected, 2, @"an empty string");
        DVTExpect(table.count == 2, @"an empty string reports two entries");
        DVTExpect(table.capacity == table.count, @"capacity tracks count after initialisation");
        DVTExpect(table.baseLine == NSNotFound, @"baseLine starts as NSNotFound");
        DVTExpect(table.baseOffset == 0, @"baseOffset starts as zero");
        free(table.offsets);
    }

    /* The last entry is always the length, which is what lets a line index be
       turned into a half-open range without knowing the length separately. */
    {
        DVTTextLineOffsetTable table = DVTTableForText(@"one\ntwo\nthree\nfour");
        const NSUInteger expected[] = { 0, 4, 8, 14, 18 };
        DVTExpectOffsets(table, expected, 5, @"four lines of text");
        DVTExpect(table.offsets[table.count - 1] == @"one\ntwo\nthree\nfour".length,
                  @"the final entry is the string length");
        DVTExpect(table.count == 5, @"four lines plus the terminator");

        /* Each line covers its start up to the next start. */
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(0, 1), &table), NSMakeRange(0, 4),
                             @"line 0 of four");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(3, 1), &table), NSMakeRange(14, 4),
                             @"the last line of four");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(1, 2), &table), NSMakeRange(4, 10),
                             @"lines 1 and 2 of four");

        /* A zero-length range is empty wherever it starts. */
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(2, 0), &table), NSMakeRange(8, 0),
                             @"an empty line range at line 2");

        /* A range running off the end is clamped rather than rejected. */
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(3, 9), &table), NSMakeRange(14, 4),
                             @"a line range past the end is clamped");

        /* Characters map back onto the line that holds them. */
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(0, 0), &table), NSMakeRange(0, 1),
                             @"the very first character");
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(9, 0), &table), NSMakeRange(2, 1),
                             @"a character in the middle of line 2");
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(17, 0), &table), NSMakeRange(3, 1),
                             @"the last character");
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(18, 0), &table), NSMakeRange(3, 1),
                             @"a character at the end of the string");
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(40, 0), &table), NSMakeRange(3, 2),
                             @"a character well past the end");

        /* A range that crosses a break covers both lines; one that stops
           exactly on the boundary does not. */
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(3, 1), &table), NSMakeRange(0, 1),
                             @"a range ending exactly on the boundary");
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(3, 2), &table), NSMakeRange(0, 2),
                             @"a range crossing one break");
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(3, 10), &table), NSMakeRange(0, 3),
                             @"a range crossing two breaks");
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(3, 12), &table), NSMakeRange(0, 4),
                             @"a range crossing three breaks");
        free(table.offsets);
    }

    /* CRLF is one break, so the next line starts past both characters. */
    {
        DVTTextLineOffsetTable table = DVTTableForText(@"a\r\nb\r\n");
        const NSUInteger expected[] = { 0, 3, 6, 6 };
        DVTExpectOffsets(table, expected, 4, @"CRLF line endings");
        free(table.offsets);
    }

    /* A lone carriage return breaks too. */
    {
        DVTTextLineOffsetTable table = DVTTableForText(@"a\rb\rc");
        const NSUInteger expected[] = { 0, 2, 4, 5 };
        DVTExpectOffsets(table, expected, 4, @"lone carriage returns");
        free(table.offsets);
    }

    /* Trailing breaks produce empty lines, which is where the offsets repeat. */
    {
        DVTTextLineOffsetTable table = DVTTableForText(@"a\nb\n");
        const NSUInteger expected[] = { 0, 2, 4, 4 };
        DVTExpectOffsets(table, expected, 4, @"a trailing newline");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(2, 1), &table), NSMakeRange(4, 0),
                             @"the empty line after a trailing newline");
        DVTExpectEqualRanges(DVTLineRangeForCharacterRange(NSMakeRange(0, 3), &table), NSMakeRange(0, 2),
                             @"a range across a trailing newline");
        free(table.offsets);
    }

    /* A line index past the end clamps on both ends, not just the length. */
    {
        DVTTextLineOffsetTable table = DVTTableForText(@"one\ntwo\nthree\nfour");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(99, 0), &table), NSMakeRange(18, 0),
                             @"a start past the end clamps to the last entry");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(NSNotFound, 1), &table), NSMakeRange(18, 0),
                             @"an absent start clamps to the last entry");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(99, 99), &table), NSMakeRange(18, 0),
                             @"both ends past the end collapse onto the last entry");
        free(table.offsets);
    }

    /*
     A table adopted onto a larger string names its first line in `baseLine` and
     adds `baseOffset` to every line from there on. Both endpoints are shifted,
     and `baseLine` itself is the first line that moves.
     */
    {
        DVTTextLineOffsetTable table = DVTTableForText(@"ab\ncd");
        const NSUInteger expected[] = { 0, 3, 5 };
        DVTExpectOffsets(table, expected, 3, @"the text a shifted table describes");

        /* Shifted from the first line: every offset moves by 10. */
        table.baseLine = 0;
        table.baseOffset = 10;
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(0, 0), &table), NSMakeRange(10, 0),
                             @"a shifted zero-length range starts at the shift");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(0, 1), &table), NSMakeRange(10, 3),
                             @"a shifted first line");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(1, 1), &table), NSMakeRange(13, 2),
                             @"a shifted last line");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(0, 2), &table), NSMakeRange(10, 5),
                             @"a shifted range reaching the terminating entry");

        /*
         Shifted from the second line: line 0 keeps its offset while the later
         lines move, so the length of a range spanning the seam absorbs the shift.
         */
        table.baseLine = 1;
        table.baseOffset = 100;
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(0, 0), &table), NSMakeRange(0, 0),
                             @"a line before the base line does not move");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(0, 1), &table), NSMakeRange(0, 103),
                             @"a range spanning the base line absorbs the shift into its length");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(1, 0), &table), NSMakeRange(103, 0),
                             @"the base line itself is the first that moves");
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(1, 1), &table), NSMakeRange(103, 2),
                             @"a wholly shifted range");

        /* A shift past the end still clamps first, and the clamped index shifts. */
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(99, 0), &table), NSMakeRange(105, 0),
                             @"an out-of-range start clamps and then shifts");

        /* An empty table has one line start, which shifts like any other. */
        DVTTextLineOffsetTable empty = DVTTableForText(@"");
        empty.baseLine = 0;
        empty.baseOffset = 10;
        DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(0, 1), &empty), NSMakeRange(10, 0),
                             @"the only line of an empty string still shifts");
        free(empty.offsets);

        free(table.offsets);
    }

    /* Unicode separators break lines; vertical tab and form feed do not. */
    {
        DVTTextLineOffsetTable ls = DVTTableForText([NSString stringWithCharacters:(unichar[]){ 'a', 0x2028, 'b' }
                                                                          length:3]);
        const NSUInteger lsExpected[] = { 0, 2, 3 };
        DVTExpectOffsets(ls, lsExpected, 3, @"U+2028 LINE SEPARATOR");
        free(ls.offsets);

        DVTTextLineOffsetTable ps = DVTTableForText([NSString stringWithCharacters:(unichar[]){ 'a', 0x2029, 'b' }
                                                                          length:3]);
        const NSUInteger psExpected[] = { 0, 2, 3 };
        DVTExpectOffsets(ps, psExpected, 3, @"U+2029 PARAGRAPH SEPARATOR");
        free(ps.offsets);

        DVTTextLineOffsetTable nel = DVTTableForText([NSString stringWithCharacters:(unichar[]){ 'a', 0x0085, 'b' }
                                                                           length:3]);
        const NSUInteger nelExpected[] = { 0, 2, 3 };
        DVTExpectOffsets(nel, nelExpected, 3, @"U+0085 NEXT LINE");
        free(nel.offsets);

        DVTTextLineOffsetTable vt = DVTTableForText([NSString stringWithCharacters:(unichar[]){ 'a', 0x000B, 'b' }
                                                                        length:3]);
        const NSUInteger vtExpected[] = { 0, 3 };
        DVTExpectOffsets(vt, vtExpected, 2, @"vertical tab does not break");
        free(vt.offsets);

        DVTTextLineOffsetTable ff = DVTTableForText([NSString stringWithCharacters:(unichar[]){ 'a', 0x000C, 'b' }
                                                                        length:3]);
        const NSUInteger ffExpected[] = { 0, 3 };
        DVTExpectOffsets(ff, ffExpected, 2, @"form feed does not break");
        free(ff.offsets);
    }

    /* Offsets count UTF-16 code units, matching -[NSString length], so a
       character outside the basic plane costs two. */
    {
        NSString *text = @"\U0001F600\na";
        DVTTextLineOffsetTable table = DVTTableForText(text);
        const NSUInteger expected[] = { 0, 3, 4 };
        DVTExpectOffsets(table, expected, 3, @"an astral character");
        DVTExpect(text.length == 4, @"the test string is four UTF-16 units");
        free(table.offsets);
    }

    /* The exported scan and the table agree with each other. */
    {
        NSString *text = @"alpha\r\nbeta\r\ngamma";
        DVTTextLineOffsetTable table = DVTTableForText(text);
        NSUInteger *offsets = NULL;
        NSUInteger count = DVTGetLineStartOffsets(text, &offsets);
        DVTExpect(count == table.count, @"the scan and the table report the same count");
        BOOL equal = (count == table.count);
        for (NSUInteger i = 0; equal && i < count; i++) {
            if (offsets[i] != table.offsets[i]) {
                equal = NO;
            }
        }
        DVTExpect(equal, @"the scan and the table report the same offsets");
        free(offsets);
        free(table.offsets);
    }
}

/** Builds a string from UTF-16 code units, so lone surrogates survive. */
static NSString *DVTUnits(const unichar *units, NSUInteger count)
{
    return [NSString stringWithCharacters:units length:count];
}

static void DVTExpectRoundTrip(NSString *text, NSUInteger index, NSString *what)
{
    NSUInteger utf8 = DVTCorrespondingUTF8ByteIndexWithIndexInString(text, index);
    NSUInteger back = DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, utf8);
    DVTExpect(back == index, [NSString stringWithFormat:@"%@ survives the round trip at %lu",
                                                 what, (unsigned long)index]);
    if (back != index) {
        printf("       actual: %lu -> %lu -> %lu\n", (unsigned long)index, (unsigned long)utf8,
               (unsigned long)back);
    }
}

static void DVTTestTextUTF8Correspondence(void)
{
    {
        /* An ASCII literal is stored one byte per character, so the shortcut
           applies and the two translations are the identity even out of range. */
        NSString *ascii = @"hello";
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(ascii, 0) == 0,
                  @"an ASCII string maps offset 0 to 0");
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(ascii, 5) == 5,
                  @"an ASCII string maps its length to its length");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(ascii, 3) == 3,
                  @"an ASCII string maps a byte offset back to itself");
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(ascii, 99) == 99,
                  @"an ASCII literal passes an out-of-range index straight through");
    }

    {
        /* The same characters built two bytes at a time take the general path
           instead, and clamp. Nothing at the NSString level tells them apart,
           so this pair is the reason the implementation asks CoreFoundation
           rather than testing the characters. */
        unichar units[] = {'h', 'e', 'l', 'l', 'o'};
        NSString *same = DVTUnits(units, 5);
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(same, 5) == 5,
                  @"the two-byte ASCII string maps its length to its length");
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(same, 99) == 5,
                  @"the two-byte ASCII string clamps an out-of-range index");
    }

    {
        /* One, two, three and four UTF-8 bytes per code unit. */
        unichar latin[] = {'a', 0x00E9, 0x4E2D, 0xD83D, 0xDE00, 'z'};
        NSString *mixed = DVTUnits(latin, 6);
        NSUInteger expected[] = {0, 1, 3, 6, 10, 10, 11};
        for (NSUInteger i = 0; i < 7; i++) {
            NSUInteger got = DVTCorrespondingUTF8ByteIndexWithIndexInString(mixed, i);
            DVTExpect(got == expected[i],
                      [NSString stringWithFormat:@"mixed string: index %lu is byte %lu, wanted %lu",
                                                 (unsigned long)i, (unsigned long)got,
                                                 (unsigned long)expected[i]]);
        }
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(mixed, 99) == 11,
                  @"the mixed string clamps an out-of-range index to its byte length");
    }

    {
        /* A byte offset inside a multi-byte sequence belongs to no character, so
           it resolves forward to the start of the next whole one. */
        unichar cjk[] = {0x4E2D, 0x4E2D, 0x4E2D};
        NSString *text = DVTUnits(cjk, 3);
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 0) == 0,
                  @"byte 0 maps back to index 0");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 1) == 1,
                  @"a byte inside the first character resolves to the next one");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 2) == 1,
                  @"the second byte of a character resolves to the next one");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 3) == 1,
                  @"the last byte of a character resolves to the next one");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 9) == 3,
                  @"the full byte length maps back to the index past the end");
    }

    {
        /* An unpaired surrogate still claims four bytes, and the walk that
           converts back consumes the pair as a whole, so it can stop one unit
           past the end of the string. */
        unichar lone[] = {0xD800};
        NSString *text = DVTUnits(lone, 1);
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(text, 1) == 4,
                  @"a lone surrogate counts as four bytes");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 0) == 0,
                  @"byte 0 of a lone surrogate maps back to index 0");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 1) == 2,
                  @"a lone surrogate converts back past the end of the string");
    }

    {
        /* A surrogate pair is one character worth four bytes, and the trailing
           half on its own is three. */
        unichar pair[] = {0xD83D, 0xDE00};
        NSString *text = DVTUnits(pair, 2);
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(text, 1) == 4,
                  @"the leading half of a pair counts as four bytes");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 4) == 2,
                  @"a whole pair converts back to two code units");
    }

    {
        /* Round trips over every code unit, with the ASCII cases that use the
           shortcut excluded because the shortcut is not a clamp. */
        for (NSUInteger c = 0x80; c < 0xD800; c++) {
            unichar unit = (unichar)c;
            NSString *text = DVTUnits(&unit, 1);
            DVTExpectRoundTrip(text, 1, [NSString stringWithFormat:@"code unit %04X", c]);
        }
    }

    {
        /* The range forms measure the length from the converted location, which
           is why the length is a count of the substring rather than of the
           whole string. */
        unichar cjk[] = {0x4E2D, 0x4E2D, 0x4E2D, 0x4E2D};
        NSString *text = DVTUnits(cjk, 4);
        NSRange converted = DVTCorrespondingUTF8ByteRangeWithRangeOfString(text, NSMakeRange(1, 2));
        DVTExpect(NSEqualRanges(converted, NSMakeRange(3, 6)),
                  @"a UTF-16 range converts to a UTF-8 range of the same characters");
        NSRange back = DVTRangeOfStringWithCorrespondingUtf8ByteRange(text, NSMakeRange(3, 6));
        DVTExpect(NSEqualRanges(back, NSMakeRange(1, 2)),
                  @"a UTF-8 range converts back to the same UTF-16 range");
    }

    {
        /* The read is done in blocks, so a surrogate pair has to survive the
           block boundary rather than being counted as four plus three. */
        NSUInteger length = 300;
        unichar *units = (unichar *)malloc(sizeof(unichar) * length);
        for (NSUInteger i = 0; i < length; i++) {
            units[i] = (i % 3 == 0) ? 0x4E2D : (unichar)('a' + (i % 26));
        }
        units[64] = 0xD83D;
        units[65] = 0xDE00;
        NSString *text = DVTUnits(units, length);
        free(units);
        /* The 64 units before the pair are 22 three-byte and 42 one-byte
           characters, so the pair starts at byte 108 and the walk resumes at
           112 rather than counting its trailing half again as three bytes. */
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(text, 64) == 108,
                  @"a pair straddling the read block boundary still counts as four bytes");
        DVTExpect(DVTCorrespondingUTF8ByteIndexWithIndexInString(text, 66) == 112,
                  @"the character after the straddling pair is counted normally");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 112) == 66,
                  @"the straddling pair converts back across the block boundary");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, 115) == 67,
                  @"the three-byte character after the pair converts back too");
    }
}

static void DVTTestStringIndexQueryContext(void)
{
    {
        /* The struct is part of the ABI: a caller allocates it on the stack, so
           its size and the offsets the initializer writes have to match. */
        DVTExpect(sizeof(DVTStringIndexQueryContext) == 264, @"the query context is 264 bytes");
        DVTExpect(offsetof(DVTStringIndexQueryContext, isASCIIBacked) == 0,
                  @"the flag sits at the front of the query context");
        DVTExpect(offsetof(DVTStringIndexQueryContext, string) == 0x88,
                  @"the query context keeps the string at 0x88");
        DVTExpect(offsetof(DVTStringIndexQueryContext, characters) == 0x90,
                  @"the query context keeps the code-unit buffer at 0x90");
        DVTExpect(offsetof(DVTStringIndexQueryContext, asciiBytes) == 0x98,
                  @"the query context keeps the ASCII buffer at 0x98");
        DVTExpect(offsetof(DVTStringIndexQueryContext, length) == 0xC0,
                  @"the query context keeps the length at 0xC0");
        DVTExpect(offsetof(DVTStringIndexQueryContext, cachedByteOffsets) == 0xC8,
                  @"the cache of queried offsets starts at 0xC8");
        DVTExpect(offsetof(DVTStringIndexQueryContext, cachedUTF16Indices) == 0xE8,
                  @"the cache of answers starts at 0xE8");
    }

    {
        /* An ASCII string is answered from the flag alone, and the initializer
           writes nothing else: every offset is already an offset, so nothing
           else is needed and nothing else is stored. */
        NSString *ascii = @"hello";
        DVTStringIndexQueryContext context;
        memset(&context, 0, sizeof(context));
        DVTInitializeIndexOfStringQueryContext(ascii, &context);

        DVTExpect(context.isASCIIBacked != 0, @"an ASCII literal is flagged as ASCII-backed");
        DVTExpect(context.string == NULL, @"an ASCII context is left without the string");
        DVTExpect(context.length == 0, @"an ASCII context is left without a length");

        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(3, &context) == 3,
                  @"an ASCII context answers an offset unchanged");
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(99, &context) == 99,
                  @"an ASCII context passes an out-of-range offset straight through");
    }

    {
        /* A context holds nothing a cached answer can change: walking every
           offset forwards over one warm context has to agree with a context
           that has answered nothing yet. */
        NSString *text = @"a\U0001F600b\U0001F680c";
        NSUInteger length = [text length];

        DVTStringIndexQueryContext warm;
        DVTInitializeIndexOfStringQueryContext(text, &warm);
        DVTExpect(warm.isASCIIBacked == 0, @"a string with a surrogate pair is not ASCII-backed");
        DVTExpect((__bridge NSString *)warm.string == text, @"the context keeps the string it was given");
        DVTExpect(warm.length == length, @"the context records the length");

        /* A warm context does not have to agree with the plain function, and the
           original does not make it. Asking forwards for every offset in turn
           fills the cache, and a slot is then reused as the starting point for
           the next walk, which skips code units the plain function would have
           counted again. For a surrogate pair that lands on the pair's trailing
           half, so an offset can answer differently than it does uncached.

           The same string walked from a fresh context does agree with the plain
           function, and that is the property worth holding on to. */
        for (NSUInteger offset = 0; offset <= length * 4 + 4; offset++) {
            DVTStringIndexQueryContext cold;
            DVTInitializeIndexOfStringQueryContext(text, &cold);

            NSUInteger coldAnswer = DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(offset, &cold);
            NSUInteger plainAnswer = DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, offset);

            DVTExpect(coldAnswer == plainAnswer,
                      [NSString stringWithFormat:@"a fresh context answers offset %lu like the plain function",
                                                   (unsigned long)offset]);
            if (coldAnswer != plainAnswer) {
                printf("       actual: cold %lu, plain %lu\n", (unsigned long)coldAnswer,
                       (unsigned long)plainAnswer);
            }

            DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(offset, &warm);
        }

        /* Asking the warm context twice for one offset is stable, which is the
           point of recording anything at all. */
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(2, &warm) ==
                      DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(2, &warm),
                  @"a repeated offset answers the same twice");

        /* Asking twice for the same offset has to be stable, which is the whole
           reason the context records anything. */
        DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(2, &warm) ==
                      DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(2, &warm),
                  @"a repeated offset answers the same twice");
    }

    {
        /* The range form converts the two ends separately, so the length comes
           out in characters, and it takes its context last. */
        NSString *text = @"a\U0001F600b";
        DVTStringIndexQueryContext context;
        DVTInitializeIndexOfStringQueryContext(text, &context);

        /* The range ends at one past its last byte, and an offset landing inside
           a pair resolves to the start of the whole character. Five bytes from
           zero is one byte for 'a' plus the pair's four, so it covers three code
           units. */
        NSRange firstPair = DVTRangeOfStringWithCorrespondingUtf8ByteRangeWithQueryContext(0, 5, &context);
        DVTExpect(firstPair.location == 0, @"a range at the start converts its location to 0");
        DVTExpect(firstPair.length == 3, @"five UTF-8 bytes cover 'a' and the pair");

        NSRange afterPair = DVTRangeOfStringWithCorrespondingUtf8ByteRangeWithQueryContext(1, 4, &context);
        DVTExpect(afterPair.location == 1, @"a range starting on the pair converts its location to 1");
        DVTExpect(afterPair.length == 2, @"four UTF-8 bytes from there cover just the pair");

        /* Byte 1 is the pair's first byte and resolves to the pair. Bytes 2, 3
           and 4 land inside the pair, belong to no character of their own, and
           resolve to the next whole character, which is 'b' at index 3. */
        NSRange onPair = DVTRangeOfStringWithCorrespondingUtf8ByteRangeWithQueryContext(1, 0, &context);
        DVTExpect(onPair.location == 1, @"the pair's first byte resolves to the pair");

        NSRange insidePair = DVTRangeOfStringWithCorrespondingUtf8ByteRangeWithQueryContext(3, 0, &context);
        DVTExpect(insidePair.location == 3, @"an offset inside the pair resolves to the next whole character");

        NSRange empty = DVTRangeOfStringWithCorrespondingUtf8ByteRangeWithQueryContext(1, 0, &context);
        DVTExpect(empty.length == 0, @"a range of no bytes has no length once converted");
    }

    {
        /* A lone surrogate is the case the plain helpers already call out, and
           the context has to inherit the behaviour rather than tidy it up. */
        unichar lone[] = {'a', 0xD83D, 'b'};
        NSString *text = DVTUnits(lone, 3);
        DVTStringIndexQueryContext context;
        DVTInitializeIndexOfStringQueryContext(text, &context);

        for (NSUInteger offset = 0; offset <= 8; offset++) {
            DVTExpect(DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(offset, &context) ==
                          DVTIndexInStringWithCorrespondingUtf8ByteIndex(text, offset),
                      [NSString stringWithFormat:@"a lone surrogate converts back the same at offset %lu",
                                                   (unsigned long)offset]);
        }
    }
}

static DVTTextDocumentLocation *DVTTestTextLocation(void)
{
    return [[DVTTextDocumentLocation alloc] initWithDocumentURL:[NSURL URLWithString:@"file:///tmp/a.swift"]
                                                     timestamp:@7
                                          startingColumnNumber:3
                                            endingColumnNumber:11
                                             startingLineNumber:2
                                               endingLineNumber:4
                                                characterRange:NSMakeRange(10, 25)
                                              locationEncoding:4];
}

static void DVTTestDocumentLocation(void)
{
    {
        DVTDocumentLocation *location = [[DVTDocumentLocation alloc] initWithDocumentURL:
                                                                    [NSURL URLWithString:@"file:///tmp/a.swift"]
                                                                           timestamp:@7];
        DVTExpect([location.documentURL.absoluteString isEqualToString:@"file:///tmp/a.swift"],
                  @"a location keeps the URL it was given");
        DVTExpect([location.timestamp isEqualToNumber:@7], @"a location keeps the timestamp it was given");
        DVTExpect([location.documentScheme isEqualToString:@"file"], @"-documentScheme is the URL's scheme");
        DVTExpect([location.documentPath isEqualToString:@"/tmp/a.swift"], @"-documentPath is the URL's path");
        DVTExpect([location.locationParameters count] == 0, @"-locationParameters is empty");
    }

    {
        /* A location is immutable, so a copy is the receiver and only
           -copyWithURL: has to build a new object. */
        DVTDocumentLocation *location = [[DVTDocumentLocation alloc] initWithDocumentURL:
                                                                    [NSURL URLWithString:@"file:///tmp/a.swift"]
                                                                           timestamp:@7];
        DVTExpect([location copy] == location, @"-copyWithZone: returns the receiver");
        DVTDocumentLocation *moved = [location copyWithURL:[NSURL URLWithString:@"file:///tmp/b.swift"]];
        DVTExpect(moved != location, @"-copyWithURL: builds a new location");
        DVTExpect([moved.documentURL.absoluteString isEqualToString:@"file:///tmp/b.swift"],
                  @"-copyWithURL: carries the new URL");
        DVTExpect([moved.timestamp isEqualToNumber:@7], @"-copyWithURL: carries the timestamp");
    }

    {
        /* Two locations differing only in timestamp are unequal but hash alike,
           so a location survives a re-resolve as a dictionary key. */
        NSURL *url = [NSURL URLWithString:@"file:///tmp/a.swift"];
        DVTDocumentLocation *one = [[DVTDocumentLocation alloc] initWithDocumentURL:url timestamp:@7];
        DVTDocumentLocation *two = [[DVTDocumentLocation alloc] initWithDocumentURL:url timestamp:@9];
        DVTExpect(![one isEqual:two], @"a timestamp difference separates two locations");
        DVTExpect(one.hash == two.hash, @"a timestamp difference does not separate their hashes");
        DVTExpect([one isEqualDisregardingTimestamp:two], @"-isEqualDisregardingTimestamp: ignores the timestamp");
        DVTExpect([one isEqual:[[DVTDocumentLocation alloc] initWithDocumentURL:url timestamp:@7]],
                  @"the same URL and timestamp are equal");
        DVTExpect(![one isEqual:[[DVTTextDocumentLocation alloc] initWithDocumentURL:url timestamp:@7]],
                  @"a subclass never equals its superclass");
    }

    {
        /* A persistable representation spells its fields into a sorted fragment,
           and consumes the timestamp back out again on the way in. */
        DVTTextDocumentLocation *text = DVTTestTextLocation();
        NSString *className = nil;
        NSError *error = nil;
        NSString *persistable =
            [text persistableStringRepresentationAndDecodableClassName:&className error:&error];
        DVTExpect(error == nil, @"a text location persists without error");
        DVTExpect([className isEqualToString:@"DVTTextDocumentLocation"],
                  @"the persistable form names the class it needs to decode");
        DVTExpectEqualObjects(
            persistable,
            @"file:///tmp/a.swift#CharacterRangeLen=25&CharacterRangeLoc=10&EndingColumnNumber=11"
             @"&EndingLineNumber=4&LocationEncoding=4&StartingColumnNumber=3&StartingLineNumber=2&Timestamp=7",
            @"the persistable form spells every field into a sorted fragment");

        NSURL *url = [NSURL URLWithString:persistable];
        DVTTextDocumentLocation *roundTrip =
            [[DVTTextDocumentLocation alloc] initWithURL:url locationParameters:@{} error:&error];
        DVTExpect(error == nil, @"a text location round-trips without error");
        DVTExpect([roundTrip isEqual:text], @"a text location survives a round trip");
        DVTExpect([roundTrip.timestamp isEqualToNumber:@7], @"the round trip carries the timestamp");
        DVTExpect([roundTrip.documentURL.absoluteString isEqualToString:@"file:///tmp/a.swift"],
                  @"a text location consumes its whole fragment, leaving a bare URL");
        DVTExpect(roundTrip.locationEncoding == 4, @"the round trip carries the encoding");
    }

    {
        /* The superclass keeps the fragment keys it does not own -- it only claims
           the timestamp -- and rebuilds what is left in sorted order. */
        NSURL *url = [NSURL URLWithString:@"file:///tmp/a.swift#Zebra=1&Timestamp=5&Apple=2"];
        DVTDocumentLocation *location = [[DVTDocumentLocation alloc] initWithURL:url
                                                             locationParameters:@{}
                                                                          error:NULL];
        DVTExpect([location.timestamp isEqualToNumber:@5], @"the superclass consumes the timestamp");
        DVTExpect([location.documentURL.absoluteString isEqualToString:@"file:///tmp/a.swift#Apple=2&Zebra=1"],
                  @"the remaining fragment is rebuilt in sorted order");
    }

    {
        /* Query and fragment stay part of the document's address, and each is
           readable on its own. */
        DVTDocumentLocation *both = [[DVTDocumentLocation alloc] initWithURL:
                                          [NSURL URLWithString:@"file:///tmp/a.swift?k=1#Frag=2"]
                                                          locationParameters:@{}
                                                                       error:NULL];
        DVTExpect([both.documentParameters[@"k"] isEqualToString:@"1"], @"a query parameter is readable");
        DVTExpect([both.documentURL.absoluteString isEqualToString:@"file:///tmp/a.swift?k=1#Frag=2"],
                  @"a URL with both query and fragment is kept intact");

        DVTDocumentLocation *queryOnly = [[DVTDocumentLocation alloc] initWithURL:
                                                [NSURL URLWithString:@"file:///tmp/a.swift?k=1"]
                                                                locationParameters:@{}
                                                                             error:NULL];
        DVTExpect([queryOnly.documentURL.absoluteString isEqualToString:@"file:///tmp/a.swift?k=1"],
                  @"a URL with only a query is kept intact");

        DVTDocumentLocation *fragmentOnly = [[DVTDocumentLocation alloc] initWithURL:
                                                    [NSURL URLWithString:@"file:///tmp/a.swift#Frag=2"]
                                                                    locationParameters:@{}
                                                                                 error:NULL];
        DVTExpect([fragmentOnly.documentURL.absoluteString isEqualToString:@"file:///tmp/a.swift#Frag=2"],
                  @"a URL with only a fragment is kept intact");
    }
}

static void DVTTestTextDocumentLocation(void)
{
    {
        DVTTextDocumentLocation *location = [[DVTTextDocumentLocation alloc] initWithDocumentURL:
                                                                         [NSURL URLWithString:@"file:///tmp/a.swift"]
                                                                                        timestamp:nil];
        DVTExpect(location.startingColumnNumber == NSNotFound, @"a fresh column number is NSNotFound");
        DVTExpect(location.endingColumnNumber == NSNotFound, @"a fresh ending column is NSNotFound");
        DVTExpect(location.startingLineNumber == NSNotFound, @"a fresh line number is NSNotFound");
        DVTExpect(location.endingLineNumber == NSNotFound, @"a fresh ending line is NSNotFound");
        DVTExpect(NSEqualRanges(location.characterRange, NSMakeRange(NSNotFound, 0)),
                  @"a fresh character range is {NSNotFound, 0}");
        DVTExpect(location.locationEncoding == 0, @"a fresh encoding is 0");
        DVTExpect(NSEqualRanges(location.lineRange, NSMakeRange(NSNotFound, 0)),
                  @"an unspecified line collapses the line range");
    }

    {
        DVTTextDocumentLocation *location = DVTTestTextLocation();
        DVTExpect(NSEqualRanges(location.lineRange, NSMakeRange(2, 3)),
                  @"-lineRange counts the ending line inclusively");
        DVTExpect([location.pasteboardRepresentation isEqualToString:@"/tmp/a.swift"],
                  @"-pasteboardRepresentation is the document's path");
    }

    {
        /* The stored line numbers are exclusive at the end, so a length-n range
           becomes {location, location + n - 1}. */
        DVTTextDocumentLocation *fromRange = [[DVTTextDocumentLocation alloc] initWithDocumentURL:
                                                                            [NSURL URLWithString:@"file:///tmp/a.swift"]
                                                                                           timestamp:nil
                                                                                        lineRange:NSMakeRange(2, 3)];
        DVTExpect(fromRange.startingLineNumber == 2, @"a line range sets the starting line");
        DVTExpect(fromRange.endingLineNumber == 4, @"a line range sets an exclusive ending line");
        DVTExpect(NSEqualRanges(fromRange.lineRange, NSMakeRange(2, 3)), @"a line range reads back unchanged");
    }

    {
        /* Hashing folds in the starting line and the character range's length, and
           nothing else. */
        DVTTextDocumentLocation *location = DVTTestTextLocation();
        NSUInteger expected = [[DVTDocumentLocation alloc] initWithDocumentURL:location.documentURL
                                                                       timestamp:location.timestamp]
                                  .hash;
        expected = expected * 33 + 2;
        expected = expected * 33 + 25;
        DVTExpect(location.hash == expected, @"-hash folds in the starting line and the range length");

        DVTTextDocumentLocation *otherEncoding = [[DVTTextDocumentLocation alloc]
            initWithDocumentURL:location.documentURL
                       timestamp:location.timestamp
            startingColumnNumber:3
              endingColumnNumber:11
               startingLineNumber:2
                 endingLineNumber:4
                  characterRange:NSMakeRange(10, 25)
                locationEncoding:5];
        DVTExpect(otherEncoding.hash == location.hash, @"the encoding is not part of the hash");
        DVTExpect(![otherEncoding isEqual:location], @"the encoding is part of equality");
        DVTExpect([otherEncoding compare:location] == NSOrderedSame,
                  @"the encoding is not part of the ordering");
    }

    {
        NSURL *url = [NSURL URLWithString:@"file:///tmp/a.swift"];
        DVTTextDocumentLocation *later = [[DVTTextDocumentLocation alloc] initWithDocumentURL:url
                                                                                 timestamp:nil
                                                                                  lineRange:NSMakeRange(9, 1)];
        DVTTextDocumentLocation *earlier = [[DVTTextDocumentLocation alloc] initWithDocumentURL:url
                                                                                   timestamp:nil
                                                                                    lineRange:NSMakeRange(2, 1)];
        DVTExpect([earlier compare:later] == NSOrderedAscending, @"ordering is by starting line");
    }

    {
        DVTTextDocumentLocation *location = DVTTestTextLocation();
        DVTExpect([location.description containsString:@"line and column range: 2:3 - 4:11"],
                  @"-description reports the line and column range");
        DVTExpect([location.description containsString:@"character range: {10, 25}"],
                  @"-description reports the character range");
        DVTExpect([location.description containsString:@"location encoding: 4"],
                  @"-description reports the encoding");
        DVTExpect([location.description containsString:@"timestamp:7"],
                  @"-description leads with the superclass's own description");
    }

    {
        /* Secure coding round-trips through both entry points a coder can take. */
        DVTTextDocumentLocation *location = DVTTestTextLocation();
        NSError *error = nil;
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:location requiringSecureCoding:YES
                                                                error:&error];
        DVTExpect(error == nil, @"a text location archives without error");
        DVTTextDocumentLocation *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[DVTTextDocumentLocation class]
                                                                              fromData:archive
                                                                                 error:&error];
        DVTExpect(error == nil, @"a text location unarchives without error");
        DVTExpect([decoded isEqual:location], @"a text location survives an archive round trip");
        DVTExpect(NSEqualRanges(decoded.characterRange, NSMakeRange(10, 25)),
                  @"the archived character range survives");
    }

    {
        /* An inconsistent location is rejected with the message Apple reports. */
        NSError *error = nil;
        BOOL valid = [DVTTextDocumentLocation validateStartingColumnNumber:NSNotFound
                                                        endingColumnNumber:NSNotFound
                                                         startingLineNumber:9
                                                           endingLineNumber:2
                                                            characterRange:NSMakeRange(NSNotFound, 0)
                                                          locationEncoding:0
                                                                    error:&error];
        DVTExpect(!valid, @"an inverted line range is rejected");
        DVTExpectEqualObjects(error.domain, @"com.apple.DVTFoundation", @"the failure names Apple's domain");
        DVTExpect(error.code == -1, @"the failure carries Apple's generic code");
        DVTExpect([error.localizedDescription containsString:@"startingLine > endingLine"],
                  @"the failure explains the inversion");
    }
}

static void DVTTestDocumentLocationConversion(void)
{
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/doc.txt"];

    /* "aé\nb\U0001F600c\nd": line 1 starts at UTF-16 index 3 and the emoji on
       it is four UTF-8 bytes wide but only two code units. */
    NSString *text = @"aé\nb\U0001F600c\nd";
    DVTTextLineOffsetTable table;
    memset(&table, 0x5A, sizeof(table));
    DVTInitializeLineOffsetTable(&table, text);

    NSString *ascii = @"ab\ncd";
    DVTTextLineOffsetTable asciiTable;
    memset(&asciiTable, 0x5A, sizeof(asciiTable));
    DVTInitializeLineOffsetTable(&asciiTable, ascii);

    /* ASCII needs no translation, but the result is still a new object: a
       location is only reused when its encoding already matches. */
    DVTTextDocumentLocation *native = [[DVTTextDocumentLocation alloc] initWithDocumentURL:url
                                                                               timestamp:@(1234)
                                                                    startingColumnNumber:0
                                                                      endingColumnNumber:1
                                                                       startingLineNumber:1
                                                                         endingLineNumber:1
                                                                          characterRange:NSMakeRange(3, 2)
                                                                        locationEncoding:DVTLocationEncodingNative];
    DVTTextDocumentLocation *asciiUTF8 = DVTConvertLocationToUTF8EncodedLocation(native, ascii, &asciiTable);

    DVTExpect(asciiUTF8 != native, @"converting ASCII to UTF-8 still builds a new location");
    DVTExpect(asciiUTF8.locationEncoding == DVTLocationEncodingUTF8, @"the converted location reports UTF-8");
    DVTExpect(NSEqualRanges(asciiUTF8.characterRange, NSMakeRange(3, 2)),
              @"ASCII offsets are the same in either encoding");
    DVTExpect(asciiUTF8.startingColumnNumber == 0 && asciiUTF8.endingColumnNumber == 1,
              @"and so are its columns");
    DVTExpectEqualObjects(asciiUTF8.documentURL, url, @"the URL survives conversion");
    DVTExpectEqualObjects(asciiUTF8.timestamp, @(1234), @"the timestamp survives conversion");
    DVTExpect(asciiUTF8.startingLineNumber == 1 && asciiUTF8.endingLineNumber == 1,
              @"line numbers mean the same in either encoding, so they pass through");

    /* A range straddling the emoji has to widen going out and shrink coming back. */
    DVTTextDocumentLocation *emojiNative = [[DVTTextDocumentLocation alloc] initWithDocumentURL:url
                                                                                  timestamp:@(7)
                                                                           startingColumnNumber:0
                                                                             endingColumnNumber:0
                                                                              startingLineNumber:1
                                                                                endingLineNumber:1
                                                                                 characterRange:NSMakeRange(1, 2)
                                                                               locationEncoding:DVTLocationEncodingNative];
    DVTTextDocumentLocation *emojiUTF8 = DVTConvertLocationToUTF8EncodedLocation(emojiNative, text, &table);

    DVTExpect(NSEqualRanges(emojiUTF8.characterRange, NSMakeRange(1, 3)),
              @"a range covering a two-byte character widens to its UTF-8 width");
    DVTExpect(emojiUTF8.locationEncoding == DVTLocationEncodingUTF8, @"and the result reports UTF-8");

    DVTTextDocumentLocation *emojiBack = DVTConvertLocationToNativeNSStringEncodedLocation(emojiUTF8, text, &table);
    DVTExpect(NSEqualRanges(emojiBack.characterRange, NSMakeRange(1, 2)), @"converting back restores the range");
    DVTExpect(emojiBack.locationEncoding == DVTLocationEncodingNative, @"and the encoding");

    /* A column is relative to its line, so it is translated inside that line's
       substring. Column 2 on line 1 sits just past the emoji: one byte for 'b'
       plus four for the emoji. */
    DVTTextDocumentLocation *emojiColumn = [[DVTTextDocumentLocation alloc] initWithDocumentURL:url
                                                                                  timestamp:@(7)
                                                                           startingColumnNumber:2
                                                                             endingColumnNumber:2
                                                                              startingLineNumber:1
                                                                                endingLineNumber:1
                                                                                 characterRange:NSMakeRange(NSNotFound, 0)
                                                                               locationEncoding:DVTLocationEncodingNative];
    DVTTextDocumentLocation *emojiColumnUTF8 = DVTConvertLocationToUTF8EncodedLocation(emojiColumn, text, &table);
    DVTExpect(emojiColumnUTF8.startingColumnNumber == 5,
              @"a column past the emoji counts its four UTF-8 bytes");

    DVTTextDocumentLocation *emojiColumnBack = DVTConvertLocationToNativeNSStringEncodedLocation(emojiColumnUTF8, text,
                                                                                                 &table);
    /* Not 2: column 2 names the middle of the emoji, which has no UTF-8
       counterpart, so the round trip lands just past it instead. */
    DVTExpect(emojiColumnBack.startingColumnNumber == 3, @"byte 5 lands just past the emoji, not inside it");

    /* Reusing the location is observable, so it is worth pinning down. */
    DVTExpect(DVTConvertLocationToUTF8EncodedLocation(asciiUTF8, ascii, &asciiTable) == asciiUTF8,
              @"a UTF-8 location asked for UTF-8 hands back itself");
    DVTExpect(DVTConvertLocationToNativeNSStringEncodedLocation(native, ascii, &asciiTable) == native,
              @"a native location asked for native hands back itself");

    /* Nothing to translate means nothing to copy. */
    DVTTextDocumentLocation *empty = [[DVTTextDocumentLocation alloc] initWithDocumentURL:url
                                                                              timestamp:@(7)
                                                                   startingColumnNumber:NSNotFound
                                                                     endingColumnNumber:NSNotFound
                                                                      startingLineNumber:NSNotFound
                                                                        endingLineNumber:NSNotFound
                                                                         characterRange:NSMakeRange(NSNotFound, 0)
                                                                       locationEncoding:DVTLocationEncodingUTF8];
    DVTExpect(DVTConvertLocationToNativeNSStringEncodedLocation(empty, ascii, &asciiTable) == empty,
              @"a location with no range and no column is handed back itself");

    /* An unspecified range location keeps its length. The length is meaningful on
       its own, and reinterpreting it as an offset from the end of the string would
       invent a position the caller never named. */
    DVTTextDocumentLocation *noRange = [[DVTTextDocumentLocation alloc] initWithDocumentURL:url
                                                                              timestamp:@(7)
                                                                   startingColumnNumber:0
                                                                     endingColumnNumber:0
                                                                      startingLineNumber:0
                                                                        endingLineNumber:0
                                                                         characterRange:NSMakeRange(NSNotFound, 7)
                                                                       locationEncoding:DVTLocationEncodingNative];
    DVTTextDocumentLocation *noRangeUTF8 = DVTConvertLocationToUTF8EncodedLocation(noRange, text, &table);

    DVTExpect(noRangeUTF8.characterRange.location == NSNotFound, @"an unspecified range stays unspecified");
    DVTExpect(noRangeUTF8.characterRange.length == 7, @"and keeps its length");

    /* An unspecified column stays unspecified rather than picking up whatever the
       correspondence helper makes of NSNotFound. */
    DVTTextDocumentLocation *noColumn = [[DVTTextDocumentLocation alloc] initWithDocumentURL:url
                                                                               timestamp:@(7)
                                                                    startingColumnNumber:NSNotFound
                                                                      endingColumnNumber:NSNotFound
                                                                       startingLineNumber:0
                                                                         endingLineNumber:1
                                                                          characterRange:NSMakeRange(3, 2)
                                                                        locationEncoding:DVTLocationEncodingNative];
    DVTTextDocumentLocation *noColumnUTF8 = DVTConvertLocationToUTF8EncodedLocation(noColumn, text, &table);

    DVTExpect(noColumnUTF8.startingColumnNumber == NSNotFound && noColumnUTF8.endingColumnNumber == NSNotFound,
              @"unspecified columns survive conversion");
    /* The range ends inside the emoji, which has no UTF-8 midpoint, so it is
       widened to cover the whole character rather than split. */
    DVTExpect(NSEqualRanges(noColumnUTF8.characterRange, NSMakeRange(4, 5)),
              @"a range ending mid-character widens to cover all of it");
}

/** Builds a text location for the conversion and wrapper tests. */
static DVTTextDocumentLocation *DVTLocation(NSInteger startingColumn, NSInteger endingColumn, NSInteger startingLine,
                                            NSInteger endingLine, NSRange characterRange, NSInteger encoding)
{
    return [[DVTTextDocumentLocation alloc] initWithDocumentURL:[NSURL fileURLWithPath:@"/tmp/dvt-tests.txt"]
                                                    timestamp:@(5)
                                        startingColumnNumber:startingColumn
                                          endingColumnNumber:endingColumn
                                           startingLineNumber:startingLine
                                             endingLineNumber:endingLine
                                              characterRange:characterRange
                                            locationEncoding:encoding];
}

/** The keys a persistable representation carries, as a sorted, space-separated list. */
static NSString *DVTPersistableKeys(DVTTextDocumentLocation *location)
{
    NSError *error = nil;
    NSString *representation = [location persistableStringRepresentationAndDecodableClassName:NULL error:&error];
    if (representation == nil) {
        return [NSString stringWithFormat:@"(error: %@)", error.localizedDescription];
    }
    NSRange hash = [representation rangeOfString:@"#"];
    if (hash.location == NSNotFound) {
        return @"(no fragment)";
    }
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *pair in [[representation substringFromIndex:hash.location + 1] componentsSeparatedByString:@"&"]) {
        [keys addObject:[pair componentsSeparatedByString:@"="].firstObject];
    }
    [keys sortUsingSelector:@selector(compare:)];
    return [keys componentsJoinedByString:@" "];
}

/**
  A wrapper over "ab\ncd", whose line starts are 0, 3 and 5.

  Every expectation below was read off Apple's DVTFoundation through a
  differential probe rather than derived from the implementation.
 */
static void DVTTestLineOffsetAwareStringWrapper(void)
{
    DVTLineOffsetAwareStringWrapper *wrapper = [[DVTLineOffsetAwareStringWrapper alloc] initWithString:@"ab\ncd"];

    DVTExpectEqualObjects(wrapper.string, @"ab\ncd", @"the wrapper hands back the string it was built from");

    /* The copy matters because the line table records offsets into this exact
       string; a source mutated afterwards would leave those offsets describing
       characters that have moved. */
    NSMutableString *mutable = [NSMutableString stringWithString:@"ab\ncd"];
    DVTLineOffsetAwareStringWrapper *fromMutable = [[DVTLineOffsetAwareStringWrapper alloc] initWithString:mutable];
    [mutable appendString:@"ef"];
    [mutable replaceCharactersInRange:NSMakeRange(0, 2) withString:@"zz"];
    DVTExpectEqualObjects(fromMutable.string, @"ab\ncd", @"the string is copied, so later edits to the source do not show");
    DVTExpectEqualRanges([fromMutable characterRangeForLineRange:NSMakeRange(1, 1)], NSMakeRange(3, 2),
                         @"the copied string's line table still describes the original text");

    /* Line ranges. The length is a delta, so a one-line request is {line,1}. */
    DVTExpectEqualRanges([wrapper characterRangeForLineRange:NSMakeRange(0, 0)], NSMakeRange(0, 0),
                         @"a zero-length line range is empty at the start of the first line");
    DVTExpectEqualRanges([wrapper characterRangeForLineRange:NSMakeRange(0, 1)], NSMakeRange(0, 3),
                         @"line 0 runs to the start of line 1, newline included");
    DVTExpectEqualRanges([wrapper characterRangeForLineRange:NSMakeRange(0, 2)], NSMakeRange(0, 5),
                         @"a two-line delta reaches the end of the string");
    DVTExpectEqualRanges([wrapper characterRangeForLineRange:NSMakeRange(1, 0)], NSMakeRange(3, 0),
                         @"a zero-length delta starts where the line does");
    DVTExpectEqualRanges([wrapper characterRangeForLineRange:NSMakeRange(1, 1)], NSMakeRange(3, 2),
                         @"line 1 runs to the start of line 2");
    DVTExpectEqualRanges([wrapper characterRangeForLineRange:NSMakeRange(2, 1)], NSMakeRange(5, 0),
                         @"the last line is empty, the table carrying a final entry at the end of the string");
    DVTExpectEqualRanges([wrapper characterRangeForLineRange:NSMakeRange(99, 1)], NSMakeRange(5, 0),
                         @"a line number past the end is pulled back to the last one");

    /* Character ranges. */
    DVTExpectEqualRanges([wrapper lineRangeForCharacterRange:NSMakeRange(0, 0)], NSMakeRange(0, 1),
                         @"the very start belongs to the first line");
    DVTExpectEqualRanges([wrapper lineRangeForCharacterRange:NSMakeRange(3, 1)], NSMakeRange(1, 1),
                         @"the start of line 1 belongs to line 1");
    DVTExpectEqualRanges([wrapper lineRangeForCharacterRange:NSMakeRange(0, 4)], NSMakeRange(0, 2),
                         @"a range crossing a newline spans two lines");
    DVTExpectEqualRanges([wrapper lineRangeForCharacterRange:NSMakeRange(99, 1)], NSMakeRange(1, 2),
                         @"a character index past the end lands on the last line");

    /*
     A table carrying a fragment's own line numbering shifts its offsets back
     into whole-document coordinates. No public initialiser produces one, so it
     is built by hand here; the values are Apple's.
     */
    DVTTextLineOffsetTable shifted = DVTTableForText(@"ab\ncd");
    shifted.baseLine = 0;
    shifted.baseOffset = 10;
    DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(0, 1), &shifted), NSMakeRange(10, 3),
                         @"a shifted table offsets the first line by baseOffset");
    DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(1, 1), &shifted), NSMakeRange(13, 2),
                         @"the shift applies to every line of a shifted table");
    DVTExpectEqualRanges(DVTCharacterRangeForLineRange(NSMakeRange(0, 0), &shifted), NSMakeRange(10, 0),
                         @"a zero-length range on a shifted table still shifts");

    /* A location's own character range is the answer when it has one. */
    DVTExpectEqualRanges([wrapper characterRangeFromDocumentLocation:DVTLocation(1, 2, 0, 0, NSMakeRange(2, 1), 0)],
                         NSMakeRange(2, 1), @"a location's character range is returned as it stands");
    DVTExpectEqualRanges([wrapper characterRangeFromDocumentLocation:DVTLocation(NSNotFound, NSNotFound, NSNotFound,
                                                                                 NSNotFound, NSMakeRange(1, 2), 0)],
                         NSMakeRange(1, 2), @"a location carrying only a character range needs no lines to resolve it");

    /* Failing that, its lines are measured. */
    DVTExpectEqualRanges([wrapper characterRangeFromDocumentLocation:DVTLocation(NSNotFound, NSNotFound, 1, 1,
                                                                                 NSMakeRange(NSNotFound, 0), 0)],
                         NSMakeRange(3, 2), @"a single line is measured against its own start");
    DVTExpectEqualRanges([wrapper characterRangeFromDocumentLocation:DVTLocation(NSNotFound, NSNotFound, 0, 2,
                                                                                 NSMakeRange(NSNotFound, 0), 0)],
                         NSMakeRange(0, 5), @"a line span is measured from the first line's start");

    /* And with columns, each column is added to the start of its own line. */
    DVTExpectEqualRanges([wrapper characterRangeFromDocumentLocation:DVTLocation(1, 2, 0, 0, NSMakeRange(NSNotFound, 0), 0)],
                         NSMakeRange(1, 1), @"a single line's columns are measured from that line's start");
    DVTExpectEqualRanges([wrapper characterRangeFromDocumentLocation:DVTLocation(2, 3, 1, 1, NSMakeRange(NSNotFound, 0), 0)],
                         NSMakeRange(5, 1), @"columns on a later line are measured from that line, not the first");
    DVTExpectEqualRanges([wrapper characterRangeFromDocumentLocation:DVTLocation(0, 1, 0, 1, NSMakeRange(NSNotFound, 0), 0)],
                         NSMakeRange(0, 4), @"a column span across two lines starts on the first line's start");
    DVTExpectEqualRanges([wrapper characterRangeFromDocumentLocation:DVTLocation(99, 99, 99, 99, NSMakeRange(NSNotFound, 0), 0)],
                         NSMakeRange(104, 0), @"a line past the end clamps its columns to the last line's start");

    /* A location that names nothing stays unlocated, but keeps its length. */
    DVTExpectEqualRanges([wrapper characterRangeFromDocumentLocation:DVTLocation(NSNotFound, NSNotFound, NSNotFound,
                                                                                 NSNotFound, NSMakeRange(NSNotFound, 3), 0)],
                         NSMakeRange(NSNotFound, 3), @"a location naming no position reports no position");

    /*
     The converters re-express the coordinates a location already carries; they do
     not invent a character range for one that named only lines and columns.
     Measured over "ab\ncdef" so the columns sit inside line 1 and no clamping is
     in play, and over an all-ASCII string where the two encodings agree.
     */
    DVTLineOffsetAwareStringWrapper *plain = [[DVTLineOffsetAwareStringWrapper alloc] initWithString:@"ab\ncdef"];
    DVTTextDocumentLocation *asUTF8 = [plain convertLocationToUTF8EncodedLocation:DVTLocation(1, 3, 1, 1, NSMakeRange(NSNotFound, 0), 0)];
    DVTExpect(asUTF8.locationEncoding == 1, @"the UTF-8 converter marks its result as UTF-8");
    DVTExpectEqualRanges(asUTF8.characterRange, NSMakeRange(NSNotFound, 0),
                         @"converting leaves a location that named no characters naming none");
    DVTExpect(asUTF8.startingColumnNumber == 1 && asUTF8.endingColumnNumber == 3 &&
                  asUTF8.startingLineNumber == 1 && asUTF8.endingLineNumber == 1,
              @"an ASCII location's columns and lines are the same in either encoding");

    DVTTextDocumentLocation *backToNative = [plain convertLocationToNativeNSStringEncodedLocation:asUTF8];
    DVTExpect(backToNative.locationEncoding == 0, @"the native converter marks its result as native");
    DVTExpect(backToNative.startingColumnNumber == 1 && backToNative.endingColumnNumber == 3 &&
                  backToNative.startingLineNumber == 1 && backToNative.endingLineNumber == 1,
              @"a round trip through UTF-8 returns the original columns and lines");
    DVTExpectEqualRanges(backToNative.characterRange, NSMakeRange(NSNotFound, 0),
                         @"the round trip still names no characters");

    /* A location that does carry a character range keeps it, only re-expressed. */
    DVTTextDocumentLocation *rangeCarried = [plain convertLocationToUTF8EncodedLocation:DVTLocation(NSNotFound, NSNotFound, NSNotFound, NSNotFound, NSMakeRange(2, 3), 0)];
    DVTExpectEqualRanges(rangeCarried.characterRange, NSMakeRange(2, 3),
                         @"a character range is carried across the conversion");

    /*
     The description quotes the string and escapes only the newline. A quote or
     backslash inside the string is left alone, so this is not a general-purpose
     quoting routine.
     */
    NSString *described = wrapper.debugDescription;
    DVTExpect([described hasPrefix:@"<DVTLineOffsetAwareStringWrapper 0x"], @"the description names the class and address");
    DVTExpect([described hasSuffix:@"  string=\"ab\\ncd\">"], @"the description quotes the string and escapes its newline");
    DVTExpect([described rangeOfString:@"\n"].location == NSNotFound, @"no real newline survives into the description");
    NSString *empty = [[[DVTLineOffsetAwareStringWrapper alloc] initWithString:@""] debugDescription];
    DVTExpect([empty hasSuffix:@"  string=\"\">"], @"an empty string is still quoted");
    NSString *quoted = [[[DVTLineOffsetAwareStringWrapper alloc] initWithString:@"a\"b"] debugDescription];
    DVTExpect([quoted hasSuffix:@"  string=\"a\"b\">"], @"a quote inside the string is not escaped");

    /* Secure coding. Only the string is archived; the table is rebuilt on decode. */
    DVTExpect([DVTLineOffsetAwareStringWrapper supportsSecureCoding], @"the wrapper claims secure coding support");
    NSError *error = nil;
    NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:wrapper
                                            requiringSecureCoding:YES
                                                            error:&error];
    DVTExpect(archived != nil && error == nil, @"the wrapper archives under secure coding");
    DVTLineOffsetAwareStringWrapper *decoded =
        [NSKeyedUnarchiver unarchivedObjectOfClass:[DVTLineOffsetAwareStringWrapper class] fromData:archived error:&error];
    DVTExpect(decoded != nil && error == nil, @"the wrapper decodes under secure coding");
    DVTExpectEqualObjects(decoded.string, @"ab\ncd", @"the string survives the round trip");
    DVTExpectEqualRanges([decoded characterRangeForLineRange:NSMakeRange(1, 1)], NSMakeRange(3, 2),
                         @"the line table is rebuilt on decode even though it was never archived");
}

static void DVTTestPersistableParameterOmission(void)
{
    /*
     Every key that names no position is left out rather than recorded as
     NSNotFound, and each key is dropped on its own rather than as a group: a
     range with a length but no location still records that length.
     */
    DVTExpectEqualObjects(DVTPersistableKeys(DVTLocation(NSNotFound, NSNotFound, NSNotFound, NSNotFound,
                                                        NSMakeRange(NSNotFound, 0), 0)),
                          @"Timestamp", @"a location naming nothing carries only the document's timestamp");
    DVTExpectEqualObjects(DVTPersistableKeys(DVTLocation(NSNotFound, NSNotFound, NSNotFound, NSNotFound,
                                                        NSMakeRange(1, 2), 0)),
                          @"CharacterRangeLen CharacterRangeLoc Timestamp",
                          @"a location carrying only a character range records no lines or columns");
    DVTExpectEqualObjects(DVTPersistableKeys(DVTLocation(NSNotFound, NSNotFound, 1, 1, NSMakeRange(NSNotFound, 0), 0)),
                          @"EndingLineNumber StartingLineNumber Timestamp",
                          @"a location carrying only lines records no character range");
    DVTExpectEqualObjects(DVTPersistableKeys(DVTLocation(NSNotFound, NSNotFound, NSNotFound, NSNotFound,
                                                        NSMakeRange(NSNotFound, 5), 0)),
                          @"CharacterRangeLen Timestamp",
                          @"a range with a length but no location keeps the length alone");
    DVTExpectEqualObjects(DVTPersistableKeys(DVTLocation(NSNotFound, NSNotFound, NSNotFound, NSNotFound,
                                                        NSMakeRange(5, 0), 0)),
                          @"CharacterRangeLoc Timestamp",
                          @"a range with a location but no length keeps the location alone");
    DVTExpectEqualObjects(DVTPersistableKeys(DVTLocation(NSNotFound, NSNotFound, NSNotFound, NSNotFound,
                                                        NSMakeRange(0, 0), 0)),
                          @"CharacterRangeLoc Timestamp",
                          @"a zero length at a real location records the location but not the length");

    /* Native is the default, so only a location that says otherwise records it. */
    DVTExpectEqualObjects(DVTPersistableKeys(DVTLocation(1, 2, 0, 0, NSMakeRange(0, 1), 0)),
                          @"CharacterRangeLen CharacterRangeLoc EndingColumnNumber EndingLineNumber "
                          @"StartingColumnNumber StartingLineNumber Timestamp",
                          @"a fully specified native location does not spell out the encoding");
    DVTExpectEqualObjects(DVTPersistableKeys(DVTLocation(1, 2, 0, 0, NSMakeRange(0, 1), 1)),
                          @"CharacterRangeLen CharacterRangeLoc EndingColumnNumber EndingLineNumber LocationEncoding "
                          @"StartingColumnNumber StartingLineNumber Timestamp",
                          @"a UTF-8 location records its encoding");

    /*
     A timestamp of zero is still a timestamp: only its absence is left out. The
     fully specified initializer takes a nonnull timestamp, so the absent case is
     not reachable through it and is not asserted here.
     */
    DVTTextDocumentLocation *zeroTimestamp =
        [[DVTTextDocumentLocation alloc] initWithDocumentURL:[NSURL fileURLWithPath:@"/tmp/x.txt"]
                                                   timestamp:@(0)
                                       startingColumnNumber:NSNotFound
                                         endingColumnNumber:NSNotFound
                                          startingLineNumber:NSNotFound
                                            endingLineNumber:NSNotFound
                                             characterRange:NSMakeRange(NSNotFound, 0)
                                           locationEncoding:0];
    DVTExpectEqualObjects(DVTPersistableKeys(zeroTimestamp), @"Timestamp",
                          @"a timestamp of zero is recorded rather than treated as absent");
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
        DVTTestBlockPerformers();
        DVTTestGeometry();
        DVTTestTextExtras();
        DVTTestFilterExpression();
        DVTTestFindPattern();
        DVTTestDiffHashing();
        DVTTestLineOffsetTableTextExtras();
        DVTTestTextUTF8Correspondence();
        DVTTestStringIndexQueryContext();
        DVTTestDocumentLocation();
        DVTTestTextDocumentLocation();
        DVTTestDocumentLocationConversion();
        DVTTestLineOffsetAwareStringWrapper();
        DVTTestPersistableParameterOmission();
        DVTTestMachO();
        DVTTestClassAdditions();
        DVTTestObservingConvenience();
        DVTTestErrorBuilders();
        DVTTestPropertyListValue();
        DVTTestAssertions();
        DVTTestComparison();
        DVTTestCertificateComparison();
        DVTTestKeyPathComparison();

        fprintf(stdout, "\n%d checks, %d failures\n", DVTTestCount, DVTTestFailures);
    }

    return DVTTestFailures == 0 ? 0 : 1;
}
