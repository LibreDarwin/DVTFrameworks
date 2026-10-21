//
//  DVTFoundationClassAdditions.m
//  DVTFoundation
//
//  Copyright (C) 2026, LibreDarwin
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its
//     contributors may be used to endorse or promote products derived from
//     this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED.
//

#import "DVTFoundationClassAdditions.h"

#import "DVTAssertions.h"
#import "DVTDispatch.h"
#import "DVTEnvironmentSnapshot.h"
#import "DVTOneShotBlock.h"
#import "DVTSystemActivityToken.h"
#import "DVTVersion.h"
#import "NSProcessInfo+DVTNSProcessInfoAdditions.h"
#import "NSData+DVTNSDataStdIO.h"
#import "NSMutableData+DVTNSDataStdIO.h"
#import "NSUndoManager+DVTNSUndoManagerAdditions.h"
#import "NSLock+DVTFoundationExtensions.h"
#import "NSRecursiveLock+DVTFoundationExtensions.h"
#import "NSCache+DVTNSCacheAdditions.h"

#import <Foundation/NSEnumerator.h>
#import <Foundation/NSNull.h>
#import <errno.h>
#import <limits.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/sysctl.h>

/*
 PureDarwin's Foundation is a subset of Apple's: -firstObject, -indexOfObject:,
 -enumerateObjectsUsingBlock:, -removeObject:, -insertObject:atIndex:,
 -removeObjectsInArray: and -rangeOfCharacterFromSet: are all absent from the
 headers. The helpers below stand in for them so the categories keep working
 against the subset without pulling in anything that is not there.
 */

static id DVTFirstObject(NSArray *array)
{
    return array.count > 0 ? [array objectAtIndex:0] : nil;
}

/** Shared body of `dvt_anyObjectsPassTest:` on the set-like classes. Unlike the
    array spelling, which reaches its answer through `dvt_firstObjectPassingTest:`,
    Apple's `NSSet` and `NSHashTable` each scan directly and stop at the first
    member that passes. */
static BOOL DVTAnyObjectsPassTest(id<NSFastEnumeration> collection, BOOL (^test)(id object))
{
    if (test == nil) {
        /* The array spelling answers a nil block by handing back the first member,
           so it comes out `YES` exactly when there is one. Matching that keeps the
           two spellings of the question agreeing across the three classes. */
        for (id object in collection) {
            (void)object;
            return YES;
        }
        return NO;
    }
    for (id object in collection) {
        if (test(object)) {
            return YES;
        }
    }
    return NO;
}

/** Shared body of `dvt_allObjectsPassTest:`, which carries the same selector on
    `NSArray`, `NSSet` and `NSHashTable`. Running out of elements is a `YES`;
    only an element failing the test ends it early. */
static BOOL DVTAllObjectsPassTest(id<NSFastEnumeration> collection, BOOL (^test)(id object))
{
    if (test == nil) {
        return YES;
    }
    for (id object in collection) {
        if (!test(object)) {
            return NO;
        }
    }
    return YES;
}

/** The raw 32 bits a test block hands back, which is what
    `dvt_numberOfObjectsPassingTest:` adds up.

    Apple's loop accumulates `w0` directly, so a block that returns something
    other than a boolean adds its own value rather than 1 -- three from each of
    three members totals 9, and -1 from each totals 12884901885 rather than
    wrapping. Reading the value as `BOOL` here would silently flatten both to a
    plain count, so the call goes through a differently spelled block type. Only
    a caller who casts a block of another return type can tell the two apart. */
typedef unsigned int (^DVTRawTestReturn)(id object);

static unsigned int DVTRawTestValue(BOOL (^test)(id object), id object)
{
    return ((DVTRawTestReturn)test)(object);
}

static NSUInteger DVTIndexOfObject(NSArray *array, id object)
{
    NSUInteger count = array.count;
    for (NSUInteger index = 0; index < count; index++) {
        if ([[array objectAtIndex:index] isEqual:object]) {
            return index;
        }
    }
    return NSNotFound;
}

/**
 The characters the original framework escapes when rendering command line
 arguments. The original builds this set from a string in its data segment; the
 set below is the conventional shell metacharacter set, which matches the
 observable behaviour of escaping each offending character with a single
 backslash and never quoting.
 */
static NSCharacterSet *DVTCommandLineMetacharacterSet(void)
{
    static NSCharacterSet *characterSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* Read from the literal Apple passes to characterSetWithCharactersInString:
           (cfstring 0x6beae8, length 4). Single quote, space, double quote, tab
           -- notably *not* the rest of the shell metacharacters, and *not*
           backslash, which therefore passes through unescaped. */
        characterSet = [NSCharacterSet characterSetWithCharactersInString:@"' \"\t"];
    });
    return characterSet;
}

/*
 Apple's DVTComparatorForSelector hands back a stack block that captures the
 selector together with objc_msgSend itself. Its invoke function loads both,
 moves the first argument into the receiver slot, leaves the second in the
 argument slot and branches through the captured pointer -- that is, it is
 exactly [first selector second].

 Kept file-static rather than exported: nothing else here needs it, and the
 project's public surface is the method inventory.
 */
static NSComparisonResult (^DVTComparatorForSelector(SEL selector))(id, id)
{
    return ^NSComparisonResult(id first, id second) {
        NSComparisonResult (*send)(id, SEL, id) = (NSComparisonResult (*)(id, SEL, id))objc_msgSend;
        return send(first, selector, second);
    };
}

@implementation NSArray (DVTFoundationClassAdditions)

#pragma mark - Construction

/*
 The answer is a fresh mutable array rather than a copy or the source itself, so
 it is always safe to build into, and a nil source still answers a mutable array
 because enumeration of nil yields nothing rather than failing. Enumeration is
 the fast-enumeration protocol, so mutating the source while it is being walked
 faults the way any fast enumeration does.
 */
+ (NSArray *)dvt_arrayWithEnumeratedObjects:(NSArray *)objects
{
    NSMutableArray *result = [NSMutableArray array];
    for (id object in objects) {
        [result addObject:object];
    }
    return result;
}

+ (NSArray *)dvt_arrayWithObjectIfNonNil:(id)object
{
    if (object == nil) {
        return nil;
    }
    return [NSArray arrayWithObject:object];
}

/*
 The buffer is what makes a nil member a fault for every count but zero: the
 repeats are staged first and the array is built from the staged pointers in one
 pass, so a nil object reaches -initWithObjects:count: instead of being dropped.
 The stack buffer covers the small counts, and the allocation only pays off past
 its capacity.
 */
+ (NSArray *)dvt_arrayWithRepetitions:(NSUInteger)count ofObject:(id)object
{
    __unsafe_unretained id stackBuffer[256];
    __unsafe_unretained id *buffer = stackBuffer;
    if (count > 256) {
        buffer = (__unsafe_unretained id *)calloc(count, sizeof(id));
    }
    for (NSUInteger index = 0; index < count; index++) {
        buffer[index] = object;
    }
    NSArray *result = [[NSArray alloc] initWithObjects:(const id *)buffer count:count];
    if (buffer != stackBuffer) {
        free(buffer);
    }
    return result;
}

/*
 The shorter array bounds the walk, and the answer is the index reached rather
 than a separately tracked count -- so equal answers return the whole of the
 shorter member, and the first disagreement returns the index before it. A nil
 array answers zero through its own missing count rather than through a guard.
 */
+ (NSUInteger)dvt_lengthOfCommonPrefixBetween:(NSArray *)array and:(NSArray *)otherArray
{
    NSUInteger limit = MIN(array.count, otherArray.count);
    NSUInteger index = 0;
    while (index < limit) {
        id object = [array objectAtIndexedSubscript:index];
        id otherObject = [otherArray objectAtIndexedSubscript:index];
        if (object != otherObject && ![object isEqual:otherObject]) {
            break;
        }
        index++;
    }
    return index;
}

#pragma mark - Size and bounds

- (BOOL)dvt_hasContent
{
    return self.count != 0;
}

- (BOOL)dvt_isNonEmpty
{
    return self.count != 0;
}

- (NSIndexSet *)dvt_allIndexes
{
    return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.count)];
}

- (NSRange)dvt_fullRange
{
    return NSMakeRange(0, self.count);
}

- (NSUInteger)dvt_lastIndex
{
    return self.count == 0 ? NSNotFound : self.count - 1;
}

- (id)dvt_secondToLastObject
{
    return self.count < 2 ? nil : [self objectAtIndex:self.count - 2];
}

- (id)dvt_onlyObject
{
    return self.count == 1 ? [self objectAtIndex:0] : nil;
}

- (id)dvt_objectAtIndexIfInBounds:(NSInteger)index
{
    if (index < 0 || (NSUInteger)index >= self.count) {
        return nil;
    }
    return [self objectAtIndex:(NSUInteger)index];
}

- (id)dvt_objectAtWrappedIndex:(NSInteger)index
{
    if (self.count == 0) {
        return nil;
    }
    NSInteger count = (NSInteger)self.count;
    NSInteger wrapped = index % count;
    if (wrapped < 0) {
        wrapped += count;
    }
    return [self objectAtIndex:(NSUInteger)wrapped];
}

- (BOOL)dvt_isIndexInBounds:(NSInteger)index
{
    return index >= 0 && (NSUInteger)index < self.count;
}

- (BOOL)dvt_containsObjectIdenticalTo:(id)object
{
    NSEnumerator *enumerator = [self objectEnumerator];
    id candidate = nil;
    while ((candidate = [enumerator nextObject]) != nil) {
        if (candidate == object) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Filtering and searching

- (NSArray *)dvt_objectsOfClass:(Class)klass
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if ([object isKindOfClass:klass]) {
            [result addObject:object];
        }
    }
    return result;
}

- (NSArray *)dvt_objectsPassingTest:(BOOL (^)(id object))test
{
    if (test == nil) {
        return [self copy];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if (test(object)) {
            [result addObject:object];
        }
    }
    /* Nothing was filtered out, so the answer is the receiver rather than a
       rebuilt one. -copy keeps that shortcut for an immutable receiver while
       still handing a mutable receiver an immutable snapshot, which is the
       distinction a caller can observe. */
    if (result.count == self.count) {
        return [self copy];
    }
    return [result copy];
}

- (id)dvt_firstObjectPassingTest:(BOOL (^)(id object))test
{
    if (test == nil) {
        return DVTFirstObject(self);
    }
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if (test(object)) {
            return object;
        }
    }
    return nil;
}

- (id)dvt_firstMap:(id (^)(id object))block
{
    /* The compact map that stops as soon as it has something: -dvt_compactMap: asks
       about every member and drops the nil answers at the end, whereas this asks
       one member at a time and hands the first usable answer straight back. The
       probe's call log is what shows it -- "a" mapping to nil and "b" to "B" costs
       two calls, and no third is asked about "c".

       There is no early exit for a nil answer, only for an element whose answer is
       good, so a block that always answers nil walks the whole receiver and comes
       back with nil. An empty receiver never reaches the block at all.

       A nil block faults, as Apple loads the invoke pointer unchecked. */
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        id mapped = block(object);
        if (mapped != nil) {
            return mapped;
        }
    }
    return nil;
}

- (id)dvt_onlyObjectPassingTest:(BOOL (^)(id object))test
{
    if (test == nil) {
        return self.dvt_onlyObject;
    }
    id found = nil;
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if (test(object)) {
            if (found != nil) {
                return nil;
            }
            found = object;
        }
    }
    return found;
}

- (BOOL)dvt_anyObjectsPassTest:(BOOL (^)(id object))test
{
    return [self dvt_firstObjectPassingTest:test] != nil;
}

- (BOOL)dvt_allObjectsPassTest:(BOOL (^)(id object))test
{
    return DVTAllObjectsPassTest(self, test);
}

- (NSRange)dvt_rangeOfArray:(NSArray *)array
{
    return [self dvt_rangeOfArray:array inRange:NSMakeRange(0, self.count)];
}

/* A search for `array` as a contiguous run inside `range`, comparing member by
   member with -isEqual: and answering the earliest run that fits. When two runs
   of different lengths start at different places the earlier one wins even if it
   is shorter, so the candidates are tried in order and the first complete match
   is taken rather than the longest.

   The window is honoured by only trying start positions whose whole run lands
   inside it, so a run that begins inside the window but runs past its end is not
   found. Nothing is found when the window is empty, when `array` is empty or
   `nil`, or when no complete run fits at all -- all of which answer the same
   NSNotFound range rather than raising.

   Apple bounds the search the same way and then asserts that the run it found
   lies inside the window. That assertion cannot fire given the loop bounds, and
   it is left out here rather than reproduced as a check on values already
   guaranteed by the loop. */
- (NSRange)dvt_rangeOfArray:(NSArray *)array inRange:(NSRange)range
{
    if (array == nil || self.count == 0 || array.count == 0 || range.length == 0) {
        return NSMakeRange(NSNotFound, 0);
    }
    /* Refuse a window that leaves the receiver, or that is too short to hold the
       run, rather than reading past either end. */
    if (range.location + range.length > self.count || array.count > range.length || range.location > NSMaxRange(range) - array.count) {
        return NSMakeRange(NSNotFound, 0);
    }
    for (NSUInteger start = range.location; start + array.count <= NSMaxRange(range); start++) {
        NSUInteger offset = 0;
        while (offset < array.count &&
               [[self objectAtIndex:start + offset] isEqual:[array objectAtIndex:offset]]) {
            offset++;
        }
        if (offset == array.count) {
            return NSMakeRange(start, array.count);
        }
    }
    return NSMakeRange(NSNotFound, 0);
}

/* The last member passing `test`, found by asking for the first one that passes
   while walking the receiver backwards. nil when none passes.

   Apple hands its reversed enumerator straight to a private helper that scans it
   in bulk; going through this port's own `dvt_firstObjectPassingTest:` answers
   the same question over the reversed order. */
- (id)dvt_lastObjectPassingTest:(BOOL (^)(id object))test
{
    return [[[self reverseObjectEnumerator] allObjects] dvt_firstObjectPassingTest:test];
}

- (id)dvt_objectBeforeFirstOccurenceOfObject:(id)object
{
    /* The member before the first occurrence, so nil both when the occurrence is
       the receiver's first member and when the receiver holds no such object --
       those are the two values -indexOfObject: can hand back that have nothing
       in front of them. */
    NSUInteger index = [self indexOfObject:object];
    if (index == 0 || index == NSNotFound) {
        return nil;
    }
    return [self objectAtIndex:index - 1];
}

/* Both are bare forwards in the binary, so they stay forwards here rather than
   growing their own copy of the logic. */

- (BOOL)dvt_areAllObjectsPassingTest:(BOOL (^)(id object))test
{
    return [self dvt_allObjectsPassTest:test];
}

- (BOOL)dvt_areAnyObjectsPassingTest:(BOOL (^)(id object))test
{
    return [self dvt_anyObjectsPassTest:test];
}

- (NSInteger)dvt_numberOfObjectsPassingTest:(BOOL (^)(id object))test
{
    if (test == nil) {
        /* Apple reaches the block without checking it and faults here. Guarding it
           is a documented deviation, kept like the nil-test guards on the
           all/any predicates. */
        return (NSInteger)self.count;
    }
    /* Sums the raw returns rather than counting the truthy answers, which is what
       Apple's copy does on all three classes carrying this selector. See
       DVTRawTestValue. Signed, not unsigned: Apple's encoding is `q`. */
    NSInteger total = 0;
    for (id object in self) {
        total += (NSUInteger)DVTRawTestValue(test, object);
    }
    return total;
}

#pragma mark - Mapping

- (NSArray *)dvt_compactMap:(id (^)(id object))block
{
    if (block == nil) {
        return [self copy];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        id mapped = block(object);
        if (mapped != nil) {
            [result addObject:mapped];
        }
    }
    return result;
}

- (NSArray *)dvt_flatMap:(id (^)(id object))block
{
    if (block == nil) {
        return [self copy];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        id mapped = block(object);
        if ([mapped isKindOfClass:[NSArray class]]) {
            [result addObjectsFromArray:mapped];
        } else if (mapped != nil) {
            [result addObject:mapped];
        }
    }
    return result;
}

- (NSArray *)dvt_arrayByApplyingBlock:(id (^)(id object))block
{
    /* -dvt_compactMap: is the loose body with the same dropped nils, but it hands
       back the mutable array it built. Apple answers an immutable one, and the
       class ladder an empty, one-member and three-member answer lands on is that
       of a copy rather than of the build. */
    return [[self dvt_compactMap:block] copy];
}

- (NSArray *)dvt_arrayByApplyingBlockStrictly:(id (^)(id object))block
{
    if (block == nil) {
        return [self copy];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        id mapped = block(object);
        /* Strictly means a nil answer sinks the whole result. Apple stops at the
           first nil -- the block runs once, not once per member -- so this
           returns immediately rather than finishing the scan. */
        if (mapped == nil) {
            return nil;
        }
        [result addObject:mapped];
    }
    return [result copy];
}

- (NSArray *)dvt_arrayByApplyingSelector:(SEL)selector
{
    /* The untyped twin of dvt_arrayByApplyingBlock:, with the same dropped nils and
       the same immutable answer.

       Repeats are kept here, which is what separates it from -dvt_setByApplyingSelector:
       an array that maps two elements to the same object has two of it, where the set
       has one.

       Apple gathers the answers into a 256-slot stack buffer and only calls out to
       malloc once the receiver passes 256 members, then builds the array with
       -initWithObjects:count: -- which is why a one-element answer is a
       __NSSingleObjectArrayI here rather than the plain __NSArrayI a -copy of the
       build would give. The buffer is not observable, but the class is, so the
       answers are handed to +arrayWithObjects:count: at the end.

       Two inputs abort Apple's method and are answered differently here, both
       documented as deviations: a member that does not carry the selector takes it
       to an assertion, where this walk skips the member, and a nil selector does
       the same, where this answers an empty array. A selector that returns
       something other than an object faults in both -- Apple retains the answer as
       an object, and so does the send below. */
    if (selector == NULL) {
        return [NSArray array];
    }
    NSMutableArray *answers = [NSMutableArray arrayWithCapacity:self.count];
    for (id object in self) {
        if (![object respondsToSelector:selector]) {
            continue;
        }
        id mapped = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if (mapped != nil) {
            [answers addObject:mapped];
        }
    }
    NSUInteger count = answers.count;
    if (count == 0) {
        return [NSArray array];
    }
    void *buffer = calloc(count, sizeof(id));
    CFArrayGetValues((__bridge CFArrayRef)answers, CFRangeMake(0, (CFIndex)count), buffer);
    NSArray *result = [NSArray arrayWithObjects:(const __unsafe_unretained id *)buffer count:count];
    free(buffer);
    return result;
}

- (NSArray *)dvt_arrayByApplyingBlockWithIndex:(id (^)(id object, NSUInteger index))block
{
    if (block == nil) {
        return [self copy];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    NSUInteger count = self.count;
    for (NSUInteger index = 0; index < count; index++) {
        id mapped = block([self objectAtIndex:index], index);
        if (mapped != nil) {
            [result addObject:mapped];
        }
    }
    return result;
}

- (NSArray *)dvt_arrayByFilteringUsingBlock:(BOOL (^)(id object))block
{
    return [self dvt_objectsPassingTest:block];
}

- (NSArray *)dvt_arrayByGroupingAdjacentObjectsUsingBlock:(BOOL (^)(id previous, id current))block
{
    NSUInteger count = self.count;
    if (count == 0) {
        return nil;
    }
    if (count == 1) {
        /* Apple copies the receiver on this path instead of taking a subarray of it, so
           the single run is a copy -- which for an immutable receiver is the receiver
           itself, and for a mutable one a fresh immutable array. The longer path below
           always hands back a distinct subarray, so the copy stays. */
        return [NSArray arrayWithObject:[self copy]];
    }
    NSMutableArray *runs = [NSMutableArray arrayWithCapacity:count];
    NSUInteger runStart = 0;
    NSUInteger runLength = 1;
    for (NSUInteger index = 1; index < count; index++) {
        if (block([self objectAtIndex:index - 1], [self objectAtIndex:index])) {
            runLength++;
            continue;
        }
        [runs addObject:[self subarrayWithRange:NSMakeRange(runStart, runLength)]];
        runStart = index;
        runLength = 1;
    }
    [runs addObject:[self subarrayWithRange:NSMakeRange(runStart, runLength)]];
    /* Apple builds the answer with -initWithObjects:count: over a stack buffer, which is
       what lands a one-run answer on __NSSingleObjectArrayI rather than the plain
       __NSArrayI a -copy of this build would give. The buffer is not observable, the
       class ladder is. */
    NSUInteger runCount = runs.count;
    void *buffer = calloc(runCount, sizeof(id));
    CFArrayGetValues((__bridge CFArrayRef)runs, CFRangeMake(0, (CFIndex)runCount), buffer);
    NSArray *result = [NSArray arrayWithObjects:(const __unsafe_unretained id *)buffer count:runCount];
    free(buffer);
    return result;
}

- (NSArray *)dvt_unorderedArrayByGroupingObjectsUsingKeys:(id (^)(id object))block
{
    /* The key is the whole answer the block gives, not its members, so a block that
       answers an array keys on that array. Members sharing a key keep receiver order
       inside the group; the groups themselves come back in dictionary order, which is
       why the answer is unordered and the groups come from -allValues. */
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    for (id object in self) {
        id key = block(object);
        DVTAssert([key dvt_isNonEmpty], @"key.dvt_isNonEmpty", nil, @"%@", key);
        NSMutableArray *group = groups[key];
        if (group == nil) {
            group = [NSMutableArray arrayWithCapacity:1];
            groups[key] = group;
        }
        [group addObject:object];
    }
    return groups.allValues;
}

static id DVTMissingKeyPathSentinel(void)
{
    /* Apple reaches for a shared sentinel when a member has no value for a key path,
       which keeps every such member in one group instead of raising on the empty key
       the block form asserts about. It is a singleton, so the members share a key. A
       fresh object per member would give each its own group. */
    static id sentinel = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sentinel = [[NSObject alloc] init];
    });
    return sentinel;
}

- (NSArray *)dvt_unorderedArrayByGroupingObjectsUsingKeyPaths:(id)keyPaths
{
    DVTAssert([keyPaths dvt_isNonEmpty], @"keyPaths.dvt_isNonEmpty", nil, @"%@", keyPaths);
    id sentinel = DVTMissingKeyPathSentinel();
    return [self dvt_unorderedArrayByGroupingObjectsUsingKeys:^id(id object) {
        return [keyPaths dvt_arrayByApplyingBlock:^id(id keyPath) {
            id value = [object valueForKeyPath:keyPath];
            return value != nil ? value : sentinel;
        }];
    }];
}

- (NSString *)dvt_componentsJoinedByString:(NSString *)separator
                  finalComponentJoinString:(NSString *)finalComponentJoinString
{
    NSString *join = separator != nil ? separator : @"";
    NSUInteger count = self.count;
    switch (count) {
        case 0:
            return @"";
        case 1:
            /* A lone member is described rather than returned, so a member that is not
               itself a string does not survive the trip. */
            return [[self objectAtIndex:0] description];
        case 2:
            return [NSString stringWithFormat:@"%@ %@ %@", [self objectAtIndex:0], finalComponentJoinString,
                                              [self objectAtIndex:1]];
        default: {
            NSString *head = [[self subarrayWithRange:NSMakeRange(0, count - 1)] componentsJoinedByString:join];
            return [NSString stringWithFormat:@"%@%@%@ %@", head, join, finalComponentJoinString, [self lastObject]];
        }
    }
}

- (NSSet *)dvt_setByApplyingBlock:(id (^)(id object))block
{
    if (block == nil) {
        return [NSSet setWithArray:self];
    }
    NSMutableSet *result = [[NSMutableSet alloc] initWithCapacity:self.count];
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        id mapped = block(object);
        if (mapped != nil) {
            [result addObject:mapped];
        }
    }
    return [result copy];
}

- (NSSet *)dvt_setByApplyingBlockStrictly:(id (^)(id object))block
{
    if (block == nil) {
        return [NSSet setWithArray:self];
    }
    NSMutableSet *result = [[NSMutableSet alloc] initWithCapacity:self.count];
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        id mapped = block(object);
        /* Strictly means a nil answer sinks the whole result; Apple stops at the
           first nil rather than finishing the scan. */
        if (mapped == nil) {
            return nil;
        }
        [result addObject:mapped];
    }
    return [result copy];
}

- (NSSet *)dvt_setByFilteringUsingBlock:(BOOL (^)(id object))block
{
    return [NSSet setWithArray:[self dvt_objectsPassingTest:block]];
}

#pragma mark - Deriving new arrays

- (NSArray *)dvt_arrayByAddingObjectIfNonNil:(id)object
{
    if (object == nil) {
        return [self copy];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count + 1];
    [result addObjectsFromArray:self];
    [result addObject:object];
    return result;
}

- (NSArray *)dvt_arrayByAddingObjects:(NSArray *)objects
{
    if (objects.count == 0) {
        return [self copy];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count + objects.count];
    [result addObjectsFromArray:self];
    NSEnumerator *enumerator = [objects objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        [result addObject:object];
    }
    return result;
}

- (NSArray *)dvt_arrayByRemovingNSNulls
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if (object != (id)[NSNull null]) {
            [result addObject:object];
        }
    }
    return result;
}

- (NSArray *)dvt_arrayByRemovingObject:(id)object
{
    /* Disassembly of Apple's implementation: the whole method retains the
       argument, builds one block, and tail-calls dvt_objectsPassingTest:. The
       block tests the candidate for pointer identity against the argument
       first and returns NO on a match, otherwise returns !isEqual:.

       So an element goes when it is pointer-identical to the argument *or*
       isEqual: to it, and every match goes, not just the first. Reproduced here
       in the same shape, including the identity test preceding isEqual:. */
    return [self dvt_objectsPassingTest:^BOOL(id candidate) {
        return candidate != object && ![candidate isEqual:object];
    }];
}

- (NSArray *)dvt_arrayByRemovingObjectsInArray:(NSArray *)objects
{
    if (objects.count == 0) {
        return [self copy];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if (DVTIndexOfObject(objects, object) == NSNotFound) {
            [result addObject:object];
        }
    }
    return result;
}

- (NSArray *)dvt_arrayByMovingFirstOccurrenceOfObjectToFrontIfPresent:(id)object
{
    NSUInteger found = DVTIndexOfObject(self, object);
    if (found == NSNotFound || found == 0) {
        return [self copy];
    }

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    [result addObject:[self objectAtIndex:found]];
    NSUInteger count = self.count;
    for (NSUInteger index = 0; index < count; index++) {
        if (index != found) {
            [result addObject:[self objectAtIndex:index]];
        }
    }
    return result;
}

- (NSArray *)dvt_arrayByReversingObjects
{
    return [[self reverseObjectEnumerator] allObjects];
}

- (NSArray *)dvt_arrayByRemovingDuplicatesFromBack
{
    /* Disassembly of Apple's implementation: the method allocates
       [NSMutableSet set], captures it in one block, and tail-calls
       dvt_objectsPassingTest:. The block rejects an object the set already
       holds and otherwise adds it, so the first occurrence of each value
       survives and the original order is preserved. Despite the "FromBack"
       name nothing iterates backwards here. Reproduced in that shape. */
    NSMutableSet *seen = [NSMutableSet set];
    return [self dvt_objectsPassingTest:^BOOL(id candidate) {
        if ([seen containsObject:candidate]) {
            return NO;
        }
        [seen addObject:candidate];
        return YES;
    }];
}

- (NSArray *)dvt_arrayByRemovingDuplicates
{
    /* Apple's entire method is a four-byte tail-call
       (b _objc_msgSend$dvt_arrayByRemovingDuplicatesFromBack), so the two
       selectors are literally the same function and cannot diverge. */
    return [self dvt_arrayByRemovingDuplicatesFromBack];
}

- (NSSet *)dvt_uniqueObjects
{
    /* Apple's method is a single call to +[NSSet setWithArray:]. Note the
       return type: the name reads like an array, but it yields a set. */
    return [NSSet setWithArray:self];
}

- (NSArray *)dvt_subarrayFromIndex:(NSUInteger)index
{
    /* Unchecked, as in Apple: count, then subarrayWithRange: with the range
       built directly as {index, count - index}. An index past the end
       underflows the length and raises NSRangeException from Foundation;
       index == count is still in bounds and yields an empty array. */
    return [self subarrayWithRange:NSMakeRange(index, self.count - index)];
}

- (NSArray *)dvt_subarrayAfterIndex:(NSUInteger)index
{
    /* Likewise unchecked: {index + 1, count - index - 1}, so every
       index >= count underflows the length and raises NSRangeException. */
    return [self subarrayWithRange:NSMakeRange(index + 1, self.count - index - 1)];
}

- (NSArray *)dvt_objectsAtIndexesWithinBounds:(NSIndexSet *)indexes
{
    /* Apple intersects the argument with dvt_fullRange and then reads
       objectsAtIndexes:, so indexes past the end are dropped silently instead
       of raising. Its intersection helper is the private NSIndexSet category
       method dvt_indexesInRange:, which is not part of this framework yet, so
       the intersection is done here with public index enumeration instead. */
    NSRange bounds = self.dvt_fullRange;
    NSMutableIndexSet *inBounds = [NSMutableIndexSet indexSet];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        if (NSLocationInRange(index, bounds)) {
            [inBounds addIndex:index];
        }
    }];
    return [self objectsAtIndexes:inBounds];
}

- (BOOL)dvt_hasPrefix:(NSArray *)prefix
{
    /* Three count calls, two objectAtIndexedSubscript: and one isEqual: per
       element: the lengths are compared first, then the elements are walked
       in lockstep with isEqual:. An empty prefix therefore always matches. */
    if (prefix.count > self.count) {
        return NO;
    }
    for (NSUInteger index = 0; index < prefix.count; index++) {
        if (![self[index] isEqual:prefix[index]]) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - Extremes

- (id)dvt_maximumObject
{
    id best = nil;
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if (best == nil || [object compare:best] == NSOrderedDescending) {
            best = object;
        }
    }
    return best;
}

- (id)dvt_minimumObject
{
    id best = nil;
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if (best == nil || [object compare:best] == NSOrderedAscending) {
            best = object;
        }
    }
    return best;
}

- (id)dvt_minimumObject:(NSComparisonResult (^)(id, id))comparator
{
    /* The same fold as -[NSSet dvt_minimumObjectUsingComparator:], down to the
       argument order that makes it correct: the comparator is asked
       (candidate, incumbent), not (incumbent, candidate), and only an exact
       NSOrderedAscending replaces the incumbent, so NSOrderedSame is a tie that keeps
       it and an out-of-contract -2 leaves it alone.

       Apple walks the receiver with -countByEnumeratingWithState:objects:count: in
       batches of sixteen rather than plain fast enumeration. That is not observable
       from outside: neither form raises when the comparator mutates the receiver
       mid-walk, because Apple's counter is only sampled at the top of each item
       iteration, after the mutation has already been made.

       An empty receiver answers nil before the comparator is reached, and a
       single-member receiver never compares at all, which is what makes a nil
       comparator safe for those two and a fault for anything longer. */
    id incumbent = nil;
    for (id candidate in self) {
        if (incumbent == nil) {
            incumbent = candidate;
            continue;
        }
        if (comparator(candidate, incumbent) == NSOrderedAscending) {
            incumbent = candidate;
        }
    }
    return incumbent;
}

- (id)dvt_maximumObject:(NSComparisonResult (^)(id, id))comparator
{
    /* Not a second fold: this is the minimum method asked with the comparator's
       answer negated. Apple builds a stack block that calls the caller's comparator
       and negates the result, then sends that to dvt_minimumObject: -- a single tail
       call once the block literal is set up -- so the maximum inherits the minimum's
       tie-break, and the negation of NSOrderedSame is still NSOrderedSame. */
    return [self dvt_minimumObject:^NSComparisonResult(id a, id b) {
        return (NSComparisonResult)(-(NSInteger)comparator(a, b));
    }];
}

- (id)dvt_objectByFoldingWithBlock:(id (^)(id, id))block
{
    /* The same fold as -[NSSet dvt_objectByFoldingWithBlock:], and with the same
       re-seed: a nil answer empties the accumulator, so the member after it becomes
       the accumulator without the block being consulted. A fold that answers nil
       for every member therefore hands back the last member, not nil, and the
       block is asked once less than the member count -- two calls for five members.

       The block's arguments are (accumulator, next), so a concatenating block reads
       the other way round from a comparator fold, which asks (candidate,
       incumbent).

       A nil block faults, as Apple loads the invoke pointer unchecked. */
    id accumulator = nil;
    for (id member in self) {
        if (accumulator == nil) {
            accumulator = member;
            continue;
        }
        accumulator = block(accumulator, member);
    }
    return accumulator;
}

#pragma mark - Shuffling

- (id)dvt_shuffledArray
{
    /* Apple's branch is on -count: above one it takes a mutable copy and shuffles
       that, and at one or below it returns -copy with no shuffle at all. The
       low-count branch is observable rather than a shortcut -- -copy hands back
       an immutable receiver as the same object, and a mutable one as an
       immutable array, so the result's mutability depends on the receiver's
       count. */
    if (self.count > 1) {
        NSMutableArray *copy = [self mutableCopy];
        [copy dvt_shuffle];
        return copy;
    }
    return [self copy];
}

- (NSDictionary *)dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:(id (^)(id))block
{
    /* The names of these two are the other way round from where the answer lands.
       Here the element becomes the *key* and the block's answer becomes the value:
       an element "a" with the block uppercasing answers a->A. Apple sends
       -setObject:forKeyedSubscript: with the block's answer in the value slot and
       the element in the key slot, which is what the disassembly shows and the
       probe confirms.

       A nil answer is skipped rather than stored, so nothing reaches the subscript
       setter with a nil in either slot. Collisions are not a special case: the
       elements stay distinct as keys, so a constant answer produces one entry per
       element. An empty receiver answers the shared empty dictionary, since the
       capacity hint is the receiver's count and the build is copied either way.

       -[NSSet dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:] builds the same
       dictionary from its members.

       A nil block faults, as Apple loads the invoke pointer unchecked. */
    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:self.count];
    for (id member in self) {
        id answer = block(member);
        if (answer != nil) {
            result[member] = answer;
        }
    }
    return [result copy];
}

- (NSDictionary *)dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:(id (^)(id))block
{
    /* The mirror image of the method above: the block's answer becomes the key and
       the member becomes the value, so the same uppercasing block answers A->a.
       Collisions now do collapse -- a constant answer leaves one entry whose value
       is the last member enumerated, since each write replaces the previous one.

       A nil block faults, as Apple loads the invoke pointer unchecked. */
    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:self.count];
    for (id member in self) {
        id answer = block(member);
        if (answer != nil) {
            result[answer] = member;
        }
    }
    return [result copy];
}

#pragma mark - Command line rendering

- (NSString *)dvt_stringByConcatenatingAsCommandLineArguments
{
    /* Follows the shape of Apple's implementation: a single space separates
       arguments and is skipped before the first one, an empty argument becomes
       two double quotes, and every metacharacter found is emitted as a
       backslash followed by the character itself. */
    NSUInteger count = self.count;
    if (count == 0) {
        return @"";
    }

    NSCharacterSet *metacharacters = DVTCommandLineMetacharacterSet();
    NSMutableString *result = [NSMutableString stringWithCapacity:64];

    for (NSUInteger index = 0; index < count; index++) {
        id object = [self objectAtIndex:index];
        NSString *value = [object isKindOfClass:[NSString class]] ? object : [object description];

        if (index > 0) {
            [result appendString:@" "];
        }

        if ([value isEqualToString:@""]) {
            [result appendString:@"\"\""];
            continue;
        }

        /* Walk the argument, copying the clean runs between metacharacters
           wholesale rather than one UTF-16 unit at a time, so a surrogate pair
           in a run is never split.

           Apple locates each metacharacter with
           -rangeOfCharacterFromSet:options:range: and NSLiteralSearch, but the
           reduced Internal SDK declares no rangeOfCharacterFromSet: variant at
           all, so the same next-metacharacter search is done here a UTF-16 unit
           at a time. The two agree for an ASCII-only set. */
        NSUInteger position = 0;
        NSUInteger remaining = value.length;
        while (remaining > 0) {
            NSUInteger location = position;
            while (location < value.length &&
                   ![metacharacters characterIsMember:[value characterAtIndex:location]]) {
                location++;
            }
            if (location > position) {
                [result appendString:[value substringWithRange:NSMakeRange(position, location - position)]];
                remaining -= (location - position);
                position = location;
            }
            if (location < value.length) {
                [result appendString:@"\\"];
                [result appendString:[value substringWithRange:NSMakeRange(location, 1)]];
                position += 1;
                remaining -= 1;
            }
        }
    }

    return result;
}

- (NSString *)dvt_stringByConcatenatingAsShellCommandArguments
{
    /* Follows the shape of Apple's implementation: a single space separates
       arguments and is skipped while the result is still empty, an empty
       argument becomes two double quotes, and three literal replacements escape
       a backslash, a space, and a tab as a backslash followed by the character.

       All three replacements are handed the range {0, length} of the *original*
       argument rather than of the string the previous replacement produced, so a
       character that an earlier replacement pushed past that length is left
       unescaped. The quirk is observable and deliberate here: @"\\  " escapes
       only its first space, and @"\\\t " escapes the tab but not the space after
       it, because the doubling backslash pushed both of them past the end of the
       range. Apple quotes neither character and escapes no other metacharacter.

       Elements must be strings, unlike the command line variant, which describes
       them. Apple tests each element with CFGetTypeID against CFStringGetTypeID
       and asserts on a nil element first, so both cases abort. */
    NSUInteger count = self.count;
    if (count == 0) {
        return @"";
    }

    NSMutableString *result = [NSMutableString stringWithCapacity:64];

    for (NSUInteger index = 0; index < count; index++) {
        NSString *string = [self objectAtIndex:index];
        DVTAssert(string != nil, @"(string) != nil", nil, @"%@ should be a string, but it is nil",
                  @"string");
        DVTAssert(CFGetTypeID((__bridge CFStringRef)string) == CFStringGetTypeID(),
                  @"CFGetTypeID((CFStringRef)string) == CFStringGetTypeID()", nil,
                  @"%@ should be a string, but it is %@", @"string", string);

        if (result.length != 0) {
            [result appendString:@" "];
        }

        if (string.length == 0) {
            [result appendString:@"\"\""];
            continue;
        }

        /* The search range deliberately stays pinned to the original length
           across all three replacements. See the comment above. */
        NSRange range = NSMakeRange(0, string.length);
        NSString *escaped =
            [string stringByReplacingOccurrencesOfString:@"\\"
                                              withString:@"\\\\"
                                                 options:NSLiteralSearch
                                                   range:range];
        escaped = [escaped stringByReplacingOccurrencesOfString:@" "
                                                     withString:@"\\ "
                                                        options:NSLiteralSearch
                                                          range:range];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"\t"
                                                     withString:@"\\\t"
                                                        options:NSLiteralSearch
                                                          range:range];
        [result appendString:escaped];
    }

    return result;
}

- (NSInteger)dvt_sortedInsertionIndexForObject:(id)object
                                withComparator:(NSComparisonResult (^)(id first, id second))comparator
{
    /* Apple reads -count and branches to a hard-coded 0 when the receiver is
       empty, so comparator is never called for an empty array. Otherwise it is a
       single binary search over the whole array with the insertion-index option,
       which reports a valid insertion point rather than a match. */
    NSUInteger count = self.count;
    if (count == 0) {
        return 0;
    }
    return [self indexOfObject:object
                inSortedRange:NSMakeRange(0, count)
                       options:NSBinarySearchingInsertionIndex
              usingComparator:comparator];
}

- (NSInteger)dvt_sortedInsertionIndexForObject:(id)object withComparisonSelector:(SEL)selector
{
    /* A straight tail-call through DVTComparatorForSelector. */
    return [self dvt_sortedInsertionIndexForObject:object
                                   withComparator:DVTComparatorForSelector(selector)];
}

#pragma mark - Sorting

- (NSArray *)dvt_objectsSortedByValueBlock:(id (^)(id object))valueBlock
{
    /* Apple loads a null into the third argument and tail-calls, so this is
       exactly the two-argument form with no duplicate handler. */
    return [self dvt_objectsSortedByValueBlock:valueBlock duplicateHandler:nil];
}

- (NSArray *)dvt_objectsSortedByValueBlock:(id (^)(id object))valueBlock
                         duplicateHandler:(NSComparisonResult (^ _Nullable)(id first, id second))duplicateHandler
{
    /* Sorting happens on a private mutable copy and the answer is copied back
       down to an immutable array, so the receiver is never reordered -- not even
       when the receiver is itself mutable.

       At one member or fewer there is nothing to compare, and Apple skips the
       sort entirely rather than sorting a copy it would not change. Two things
       follow from that. The value block is never asked, so a block that returns
       nil is harmless on a short receiver and only asserts once there is a
       comparison to make. And the fast path is -copy, which hands back an
       already-immutable receiver unchanged while still copying a mutable one, so
       the answer is immutable either way.

       The comparator is the one the in-place sort builds, so the ordering is
       driven by the block's output, both derived values are asserted non-nil,
       and the duplicate handler is consulted only on a tie and is handed the two
       members rather than the two values. */
    if (self.count <= 1) {
        return [self copy];
    }
    NSMutableArray *mutableCopy = [self mutableCopy];
    [mutableCopy dvt_sortByValueBlock:valueBlock duplicateHandler:duplicateHandler];
    return [mutableCopy copy];
}

@end

/*
 -rangeAtIndex: is the only member of its category on Apple, and it is a bare
 forwarding to -rangeValue. Both faults come from that forwarding rather than from
 any check of its own: the indexed access raises for an out-of-range index, and
 the send raises for a member that does not answer -rangeValue.
 */
@implementation NSArray (DVTRangeArrayAdditions)

- (NSRange)rangeAtIndex:(NSUInteger)index
{
    return [[self objectAtIndex:index] rangeValue];
}

@end

/*
 Only the three mutable collection classes are emptied, and they are the only
 ones traversed, so -removeAllObjects is reached through a protocol rather than
 a cast to whichever class happened to match.
 */
@protocol DVTCollectionEmptying <NSObject>
- (void)removeAllObjects;
@end

/*
 Apple's _DVTRecursivelyRemoveAllObjects: is an -isKindOfClass: chain over
 NSMutableArray, NSMutableDictionary and NSMutableSet. Each matching branch marks
 the object visited, recurses into its members, and then branches to one shared
 tail that calls -removeAllObjects; the not-taken edge of a test falls through to
 the next test, so the chain is a sequence rather than a choice.

 Two cases skip that tail, which is why the visited test has to return outright
 instead of wrapping the chain:

 - An object already in the visited set. The set is an NSMutableSet, so
   -containsObject: compares by equality rather than identity, which is what
   makes cycles terminate.
 - An object matching none of the three classes. Leaves are stepped over, and so
   are the immutable collections: an NSArray holding a mutable array leaves that
   array untouched, because the immutable one is never descended into.

 Dictionaries are descended through -allValues, so their keys are never visited
 and never emptied.
 */
static void DVTRemoveAllObjectsRecursively(id object, NSMutableSet *visited)
{
    if ([visited containsObject:object]) {
        return;
    }
    if ([object isKindOfClass:[NSMutableArray class]]) {
        [visited addObject:object];
        for (id child in (NSMutableArray *)object) {
            DVTRemoveAllObjectsRecursively(child, visited);
        }
    } else if ([object isKindOfClass:[NSMutableDictionary class]]) {
        [visited addObject:object];
        for (id child in ((NSDictionary *)object).allValues) {
            DVTRemoveAllObjectsRecursively(child, visited);
        }
    } else if ([object isKindOfClass:[NSMutableSet class]]) {
        [visited addObject:object];
        for (id child in (NSMutableSet *)object) {
            DVTRemoveAllObjectsRecursively(child, visited);
        }
    } else {
        return;
    }
    /* A member that is also in the receiver can only have been reached through
       the visited test above, which returns before this point, so mutating the
       receiver here cannot invalidate an enumeration in progress. */
    [(id<DVTCollectionEmptying>)object removeAllObjects];
}

@implementation NSMutableArray (DVTFoundationClassAdditions)

- (void)dvt_addObjectIfNonNil:(id)object
{
    if (object != nil) {
        [self addObject:object];
    }
}

- (void)dvt_addObjectsFromArrayIfAbsent:(NSArray *)objects
{
    if (objects == nil) {
        return;
    }
    NSEnumerator *enumerator = [objects objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if (![self containsObject:object]) {
            [self addObject:object];
        }
    }
}

- (void)dvt_reverseObjects
{
    /* Apple's method reads -count, skips the loop entirely below 2, then walks
       two indices inward (0 and count-1) calling
       -exchangeObjectAtIndex:withObjectAtIndex: count/2 times. */
    NSUInteger count = self.count;
    if (count < 2) {
        return;
    }
    NSUInteger forward = 0;
    NSUInteger backward = count - 1;
    while (forward < count / 2) {
        [self exchangeObjectAtIndex:forward withObjectAtIndex:backward];
        forward++;
        backward--;
    }
}

- (id)dvt_popFirstObject
{
    /* Apple fetches -firstObject and calls -removeObjectAtIndex: 0 only when
       that fetch was non-nil (cbz branches past it), so an empty receiver
       returns nil and raises nothing. */
    id object = self.firstObject;
    if (object != nil) {
        [self removeObjectAtIndex:0];
    }
    return object;
}

- (id)dvt_popLastObject
{
    /* -lastObject followed by -removeLastObject behind the same nil guard. */
    id object = self.lastObject;
    if (object != nil) {
        [self removeLastObject];
    }
    return object;
}

- (void)dvt_truncateToMaxCount:(NSUInteger)maxCount
{
    /* Apple reads -count and skips when count <= maxCount (b.ls); otherwise it
       reads -count a second time and tail-calls -removeObjectsInRange: with
       {maxCount, count - maxCount}. A maxCount at or above the count is a
       no-op. */
    if (self.count <= maxCount) {
        return;
    }
    [self removeObjectsInRange:NSMakeRange(maxCount, self.count - maxCount)];
}

- (void)dvt_removeObjectsIdenticalToObjectsInArray:(NSArray *)objects
{
    /* Apple allocates a mutable index set and then fast-enumerates the
       *argument*, not the receiver: for each argument element it asks the
       receiver for -indexOfObjectIdenticalTo: and records that single index when
       one is found, then calls -removeObjectsAtIndexes: on the receiver.

       Two details the obvious implementation gets wrong, both verified against
       Apple:
         - the test is pointer identity, not -isEqual:, so an equal-but-distinct
           element survives;
         - only the FIRST identical element goes per argument entry, so a
           receiver of [p p z] minus @[p] is left as [p z]. Foundation's own
           -removeObjectIdenticalTo: would leave just [z].
       Duplicate argument entries are harmless: they record the same index
       again. */
    NSMutableIndexSet *doomed = [NSMutableIndexSet indexSet];
    for (id object in objects) {
        NSUInteger index = [self indexOfObjectIdenticalTo:object];
        if (index != NSNotFound) {
            [doomed addIndex:index];
        }
    }
    [self removeObjectsAtIndexes:doomed];
}

- (void)dvt_keepObjectsPassingTest:(BOOL (^)(id object))test
{
    /* Apple allocates a mutable index set, fast-enumerates the *receiver*, and
       records the index of every element the block rejects before calling
       -removeObjectsAtIndexes:. The test therefore runs once per element and
       only the failures are dropped.

       This deviates from Apple, which invokes `test` without checking it and so
       faults on a non-empty receiver with a `nil` block. The guard is kept
       deliberately, matching dvt_allObjectsPassTest:. */
    if (test == nil) {
        return;
    }
    NSMutableIndexSet *doomed = [NSMutableIndexSet indexSet];
    [self enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop) {
        if (!test(object)) {
            [doomed addIndex:index];
        }
    }];
    [self removeObjectsAtIndexes:doomed];
}

- (void)dvt_removeObjectsInSet:(NSSet *)set
{
    /* Apple reads -count on the set and skips the work altogether when it is
       zero, otherwise it calls dvt_keepObjectsPassingTest: with a block that
       rejects any element the set contains. Membership is -containsObject:, so
       this is -isEqual: based rather than identity, and a nil set keeps
       everything. */
    if (set.count == 0) {
        return;
    }
    [self dvt_keepObjectsPassingTest:^BOOL(id object) {
        return ![set containsObject:object];
    }];
}

- (void)dvt_addObjectIfAbsent:(id)object
{
    /* -containsObject:, then -addObject: when that is NO. There is no nil guard,
       so a nil argument reaches -addObject: and raises
       NSInvalidArgumentException, matching Apple. */
    if (![self containsObject:object]) {
        [self addObject:object];
    }
}

- (void)dvt_addObjectsFromSet:(NSSet *)set
{
    /* Apple fast-enumerates the set, with the usual mutation check, appending
       each element in turn. A nil set therefore appends nothing. */
    for (id object in set) {
        [self addObject:object];
    }
}

- (void)dvt_insertObjectIfNonNil:(id)object atIndex:(NSUInteger)index
{
    /* The nil test precedes any bounds work: cbz on the object branches
       straight to the return. So a nil object with an out-of-range index is a
       silent no-op, while a real object past the end raises NSRangeException. */
    if (object == nil) {
        return;
    }
    [self insertObject:object atIndex:index];
}

- (void)dvt_insertObjects:(NSArray *)objects atIndex:(NSUInteger)index
{
    /* Apple reads -count on the argument, builds
       +[NSIndexSet indexSetWithIndexesInRange:] spanning {index, count}, and
       calls -insertObjects:atIndexes:. */
    [self insertObjects:objects
              atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, objects.count)]];
}

- (void)dvt_moveObjectAtIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex
{
    /* Apple compares the two indices first and returns when they are equal
       (cmp x3, x2 ; b.ne ; ret), skipping the remove-and-reinsert pair. That
       guard is observable: a 5 -> 5 move on a two-element array is a silent
       no-op, where the sequence below would raise NSRangeException.

       Otherwise it retains -objectAtIndex:fromIndex, removes that index, and
       re-inserts the object at toIndex. */
    if (fromIndex == toIndex) {
        return;
    }
    id object = [self objectAtIndex:(NSUInteger)fromIndex];
    [self removeObjectAtIndex:(NSUInteger)fromIndex];
    [self insertObject:object atIndex:(NSUInteger)toIndex];
}

- (NSInteger)dvt_sortedInsert:(id)object
{
    /* A tail-call to -dvt_sortedInsert:withComparator: carrying a block whose
       invoke function moves its first argument into the receiver slot and calls
       -compare: with the second, i.e. the default order is plain -compare:. */
    return [self dvt_sortedInsert:object
                    withComparator:^NSComparisonResult(id first, id second) {
                        return [first compare:second];
                    }];
}

- (NSInteger)dvt_sortedInsert:(id)object
                withComparator:(NSComparisonResult (^)(id first, id second))comparator
{
    /* The insertion index is kept in a callee-saved register across the insert
       and is what this method returns, so the return value is the index used
       rather than the index afterwards. */
    NSInteger index = [self dvt_sortedInsertionIndexForObject:object withComparator:comparator];
    [self insertObject:object atIndex:(NSUInteger)index];
    return index;
}

- (NSInteger)dvt_sortedInsert:(id)object withComparisonSelector:(SEL)selector
{
    /* A straight tail-call through DVTComparatorForSelector. */
    return [self dvt_sortedInsert:object withComparator:DVTComparatorForSelector(selector)];
}

- (void)dvt_sortedInsertOfObjects:(NSArray *)objects
                   withComparator:(NSComparisonResult (^)(id first, id second))comparator
{
    /* The argument is sorted first, then every element's insertion index is
       collected into an NSMutableIndexSet, offset by its position in the sorted
       argument, and the whole set is applied with -insertObjects:atIndexes:.

       The offset is what makes this a merge rather than a repeated insert: each
       index is computed against the receiver as it stands *before* the batch, so
       the + index term accounts for the elements already placed ahead of it.
       Collecting into an index set and inserting once also leaves the receiver
       untouched if any single index turns out to be invalid. */
    NSArray *sorted = [objects sortedArrayUsingComparator:comparator];
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    [sorted enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop) {
        [indexes addIndex:(NSUInteger)[self dvt_sortedInsertionIndexForObject:object
                                                               withComparator:comparator] + index];
    }];
    [self insertObjects:sorted atIndexes:indexes];
}

- (BOOL)dvt_uniqueSortedInsert:(id)object
{
    /* A tail-call to -dvt_uniqueSortedInsert:withComparator: with the same
       -compare: block the sorted-insert default uses. */
    return [self dvt_uniqueSortedInsert:object
                         withComparator:^NSComparisonResult(id first, id second) {
                             return [first compare:second];
                         }];
}

- (BOOL)dvt_uniqueSortedInsert:(id)object
                 withComparator:(NSComparisonResult (^)(id first, id second))comparator
{
    /* An empty receiver short-circuits to -addObject:; the binary search is not
       run over a zero-length range.

       Otherwise the search returns an insertion point, and only when that index
       is still inside the receiver is the element there compared against. The
       duplicate test is the comparator result being NSOrderedSame (cbz on the
       call's return), *not* -isEqual:, so objects that compare equal but are
       distinct under -isEqual: are treated as duplicates. */
    NSUInteger count = self.count;
    if (count == 0) {
        [self addObject:object];
        return YES;
    }
    NSUInteger index = [self indexOfObject:object
                           inSortedRange:NSMakeRange(0, count)
                                  options:NSBinarySearchingInsertionIndex
                         usingComparator:comparator];
    if (index < count && comparator(object, [self objectAtIndex:index]) == NSOrderedSame) {
        return NO;
    }
    [self insertObject:object atIndex:index];
    return YES;
}

#pragma mark - Sorting

- (void)dvt_sortByValueBlock:(id (^)(id object))valueBlock
{
    /* Apple loads a null into the second argument and tail-calls, so this is
       exactly the two-argument form with no duplicate handler. */
    [self dvt_sortByValueBlock:valueBlock duplicateHandler:nil];
}

- (void)dvt_sortByValueBlock:(id (^)(id object))valueBlock
           duplicateHandler:(NSComparisonResult (^ _Nullable)(id first, id second))duplicateHandler
{
    /* The comparator Apple builds derives a value from each member, asserts both
       values are non-nil, and compares *those*, so the ordering is driven by the
       block's output rather than by the members themselves. The two assertions name
       the member whose value block came back empty, which is why they differ.

       The duplicate handler is consulted only once the derived values have come
       out equal, and it is handed the two members rather than the two values --
       the disassembly passes the comparator's own arguments straight through --
       so a handler can still order a tie by whatever the value block discarded.
       With no handler a tie stays NSOrderedSame and the sort is left to decide. */
    [self sortUsingComparator:^NSComparisonResult(id first, id second) {
        id firstValue = valueBlock(first);
        DVTAssertNotNil(firstValue, @"projectionBlock(obj1)");
        id secondValue = valueBlock(second);
        DVTAssertNotNil(secondValue, @"projectionBlock(obj2)");
        NSComparisonResult result = [firstValue compare:secondValue];
        if (result != NSOrderedSame) {
            return result;
        }
        if (duplicateHandler == nil) {
            return NSOrderedSame;
        }
        return duplicateHandler(first, second);
    }];
}

#pragma mark - Partitioning

- (void)dvt_stablePartitionObjectsPassingIsSuffixTest:(BOOL (^)(id object))test
{
    /* Apple splits on -count: at five or fewer it sorts the receiver in place with
       NSSortStable, comparing @(test(first)) against @(test(second)) so that the
       members failing the test come first; above five it takes the members that
       pass, removes them, and appends them back at the end.

       Both routes are stable and both leave the suffix last, so which one runs is
       not observable in the result -- only the work done differs. The threshold is
       reproduced because it is what decides that. */
    if (self.count <= 5) {
        [self sortWithOptions:NSSortStable
             usingComparator:^NSComparisonResult(id first, id second) {
                 return [[NSNumber numberWithBool:test(first)]
                     compare:[NSNumber numberWithBool:test(second)]];
             }];
        return;
    }
    /* -indexesOfObjectsPassingTest: wants the index and stop pointer too. Apple's
       wrapper simply forwards the object and ignores the other two, which compiles
       to a tail call into the caller's block -- so the same adapter is written here
       rather than reaching for a different API. */
    NSIndexSet *passing = [self indexesOfObjectsPassingTest:^BOOL(id object, NSUInteger index, BOOL *stop) {
        return test(object);
    }];
    NSArray *suffix = [self objectsAtIndexes:passing];
    [self removeObjectsAtIndexes:passing];
    /* The index range starts at the receiver's post-removal count, which is what
       places the suffix after everything that stayed. */
    [self insertObjects:suffix
             atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(self.count, suffix.count)]];
}

- (NSString *)dvt_uniqueStringToAddToArray:(NSString *)string
{
    /* A string the receiver does not hold is answered unchanged. Otherwise Apple
       appends " <n>" for n = 1, 2, 3, ... and returns the first one the receiver
       does not hold -- so a gap in the middle is filled rather than skipped past.
       Membership goes through a set built from the receiver, which makes it
       -isEqual: rather than -isSame:, so an equal-but-distinct string counts as
       already present. Nothing is inserted. */
    NSSet *existing = [NSSet setWithArray:self];
    if (![existing containsObject:string]) {
        return string;
    }
    for (long suffix = 1;; suffix++) {
        NSString *candidate = [NSString stringWithFormat:@"%@ %ld", string, suffix];
        if (![existing containsObject:candidate]) {
            return candidate;
        }
    }
}

#pragma mark - Recursive removal

- (void)dvt_recursivelyRemoveAllObjects
{
    /* Apple hands its helper a freshly allocated NSMutableSet and nothing else;
       the receiver is reached by the helper's first step. */
    DVTRemoveAllObjectsRecursively(self, [NSMutableSet set]);
}

- (void)dvt_shuffle
{
    /* The whole body is 24 instructions: -count is read once into the
       remainder, a count below two skips the loop outright, and each pass draws
       arc4random_uniform(remaining) to pick a partner for the loop index.

       The remainder shrinks by one per pass and the loop runs while it is not
       1, which makes this a Fisher-Yates walk over the whole array rather than a
       partial one: the last member is reached by elimination instead of by a
       draw of its own. */
    NSUInteger remaining = self.count;
    if (remaining < 2) {
        return;
    }
    NSUInteger index = 0;
    do {
        NSUInteger other = index + arc4random_uniform(remaining);
        [self exchangeObjectAtIndex:index withObjectAtIndex:other];
        index++;
        remaining--;
    } while (remaining != 1);
}

@end

@implementation NSSet (DVTNSSetAdditions)

- (BOOL)dvt_allObjectsPassTest:(BOOL (^)(id object))test
{
    return DVTAllObjectsPassTest(self, test);
}

- (BOOL)dvt_anyObjectsPassTest:(BOOL (^)(id object))test
{
    return DVTAnyObjectsPassTest(self, test);
}

- (BOOL)dvt_hasContent
{
    return self.count != 0;
}

- (BOOL)dvt_isNonEmpty
{
    return self.count != 0;
}

#pragma mark - Sorting

- (NSArray *)dvt_objectsSortedByValueBlock:(id (^)(id object))valueBlock
{
    /* Apple loads a null into the third argument and tail-calls, so this is
       exactly the two-argument form with no duplicate handler. */
    return [self dvt_objectsSortedByValueBlock:valueBlock duplicateHandler:nil];
}

- (NSArray *)dvt_objectsSortedByValueBlock:(id (^)(id object))valueBlock
                         duplicateHandler:(NSComparisonResult (^ _Nullable)(id first, id second))duplicateHandler
{
    /* A set has no order to disturb, so this is the array form asked of the
       members: -allObjects decides which order they are sorted from, and
       everything else -- the short-receiver fast path, the nil-value assertion,
       the member-not-value tie-breaking -- is the array method's.

       The answer's order among members whose derived values tie therefore
       depends on the set's own ordering rather than on anything the caller
       controls. A distinct derived value per member is what makes the answer
       reproducible. */
    return [[self allObjects] dvt_objectsSortedByValueBlock:valueBlock duplicateHandler:duplicateHandler];
}

/* These three are the same shape in the binary: ask -count, take -allObjects,
   and skip the sort entirely below two members, handing back -allObjects as it
   stands. Nothing wraps or copies that answer, so it is whatever -allObjects
   returned. */

- (NSArray *)dvt_sortedArray
{
    /* The argument-free form hard-codes a selector rather than taking one. It is
       compare:, which the numbers in the probe pin down: they come back
       numerically ordered, and equal to sortedArrayUsingSelector: with compare:.
       Forwarding keeps one copy of the short-receiver case. */
    return [self dvt_sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray *)dvt_sortedArrayUsingSelector:(SEL)selector
{
    NSArray *members = [self allObjects];
    if (members.count < 2) {
        return members;
    }
    /* The selector is handed straight over with no check of its own, so a
       selector the members do not understand raises out of the collection sort
       exactly as it would on an array. */
    return [members sortedArrayUsingSelector:selector];
}

- (NSArray *)dvt_sortedArrayUsingComparator:(NSComparisonResult (^)(id first, id second))comparator
{
    NSArray *members = [self allObjects];
    if (members.count < 2) {
        return members;
    }
    /* Apple retains the comparator around this call, which is just ARC holding
       the argument alive across the send; nothing else is done with it. */
    return [members sortedArrayUsingComparator:comparator];
}

#pragma mark - Single members and counts

#pragma mark - Mapping and filtering

/* The mapping bodies on NSSet are the NSArray bodies instruction for
   instruction, so each one is reached by handing the members over as the array
   the same body was written for. That keeps one copy of each answer's shape --
   the Strictly nil behaviour, the dropped nils, the -copy that makes the result
   immutable -- and leaves only -objectsPassingTest: needing its own copy,
   because it answers with a set rather than with an array. */

- (NSArray *)dvt_arrayByApplyingBlock:(id (^)(id object))block
{
    return [[self allObjects] dvt_arrayByApplyingBlock:block];
}

- (NSArray *)dvt_arrayByApplyingBlockStrictly:(id (^)(id object))block
{
    return [[self allObjects] dvt_arrayByApplyingBlockStrictly:block];
}

- (NSSet *)dvt_setByApplyingBlock:(id (^)(id object))block
{
    return [[self allObjects] dvt_setByApplyingBlock:block];
}

- (NSSet *)dvt_setByApplyingBlockStrictly:(id (^)(id object))block
{
    return [[self allObjects] dvt_setByApplyingBlockStrictly:block];
}

- (NSSet *)dvt_setByFilteringUsingBlock:(BOOL (^)(id object))block
{
    /* Asked of a set this answers with the receiver when nothing is filtered
       out, which the array form does not: it has to build a set either way. */
    return [self dvt_objectsPassingTest:block];
}

- (NSSet *)dvt_objectsPassingTest:(BOOL (^)(id object))test
{
    if (test == nil) {
        return [self copy];
    }
    NSMutableSet *result = [[NSMutableSet alloc] initWithCapacity:self.count];
    for (id object in self) {
        if (test(object)) {
            [result addObject:object];
        }
    }
    /* A set that loses nobody comes back as the receiver, and only because of
       -copy does that stay true for a mutable receiver too. */
    if (result.count == self.count) {
        return [self copy];
    }
    return [result copy];
}

#pragma mark - Set algebra

- (Class)dvt_mutableClass
{
    /* The one answer this selector gives is the mutable counterpart of the
       class that declares it, and Apple's body is a load of that class
       reference. Only the set pair carries the selector: an array, a string and
       a dictionary do not answer it, so this cannot be a shared body. */
    return [NSMutableSet class];
}

- (NSSet *)dvt_setByIntersectingSet:(NSSet *)set
{
    /* Disassembly: retain the argument, ask it for its count, and branch. A
       non-empty argument is turned into a block of the form
       "[argument containsObject:o]" handed straight to
       dvt_objectsPassingTest:; an empty one skips the whole walk and answers
       +[NSSet set], which is why subtracting the same empty set is not
       symmetric here -- that one copies the receiver instead.

       A nil argument reads as empty, since asking nil for a count is zero, so
       it lands on the +set branch rather than raising. */
    if (set.count == 0) {
        return [NSSet set];
    }
    return [self dvt_objectsPassingTest:^BOOL(id candidate) {
        return [set containsObject:candidate];
    }];
}

- (NSSet *)dvt_setBySubtractingSet:(NSSet *)set
{
    /* The same three steps as the intersection, with the block's result
       negated and the empty branch reaching for a copy of the receiver rather
       than a new empty set. An empty argument therefore leaves the members --
       and the identity -- alone, where the intersection would empty them. */
    if (set.count == 0) {
        return [self copy];
    }
    return [self dvt_objectsPassingTest:^BOOL(id candidate) {
        return ![set containsObject:candidate];
    }];
}

- (NSSet *)dvt_setByRemovingObject:(id)object
{
    /* Disassembly asks -containsObject: on the receiver first and copies the
       receiver when it is absent, so the block is only built for an object that
       is really there. The block itself is "!isEqual:", with no pointer check
       ahead of it: an equal-but-distinct argument goes just the same, which
       -setByRemovingObjects: cannot promise.

       Apple's call target is the unprefixed -objectsPassingTest: rather than the
       dvt_ spelling the other set bodies use; the answers are the same either
       way, because -containsObject: guarantees the walk removes at least one
       member, so the count-equality shortcut never fires here. */
    if (![self containsObject:object]) {
        return [self copy];
    }
    return [self dvt_objectsPassingTest:^BOOL(id candidate) {
        return ![candidate isEqual:object];
    }];
}

- (NSSet *)dvt_setByApplyingSelector:(SEL)selector
{
    /* The untyped twin of dvt_setByApplyingBlock:, with the same dropped nils and
       the same collapse of repeated answers.

       Apple keeps the answers in a 256-slot stack buffer and only calls out to
       malloc once the receiver passes 256 members, then builds the set with
       -initWithObjects:count:. Neither detail is observable, so the answer is
       gathered in a mutable set here.

       Two inputs abort Apple's method and are answered differently here, both
       documented as deviations: a member that does not carry the selector takes
       it to an assertion, where this walk skips the member, and a nil selector
       does the same, where this answers an empty set. A selector that returns
       something other than an object faults in both -- Apple retains the answer
       as an object, and so does the send below. */
    if (selector == NULL) {
        return [NSSet set];
    }
    NSMutableSet *result = [[NSMutableSet alloc] initWithCapacity:self.count];
    for (id object in self) {
        if (![object respondsToSelector:selector]) {
            continue;
        }
        id mapped = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if (mapped != nil) {
            [result addObject:mapped];
        }
    }
    return [result copy];
}

- (id)dvt_minimumObjectUsingComparator:(NSComparisonResult (^)(id, id))comparator
{
    /* A fold that keeps the first member and only replaces it when the
       comparator answers an exact NSOrderedAscending.

       The order of the two arguments is not interchangeable and is the reason
       this is written out rather than delegated: the comparator is asked
       (candidate, incumbent), not (incumbent, candidate). With
       -[a compare:b] that is what makes the minimum correct -- "b" against a
       held "a" answers 1, so "a" stays -- and the probe's call log shows exactly
       that pairing, (b,a) then (c,a). Only an exact -1 replaces, so the
       out-of-contract -2 leaves the incumbent alone rather than comparing as
       "less"; an answer of NSOrderedSame is a tie and keeps the incumbent,
       which makes first-in-enumeration-order win.

       An empty receiver answers nil without ever reaching the comparator. */
    id incumbent = nil;
    for (id candidate in self) {
        if (incumbent == nil) {
            incumbent = candidate;
            continue;
        }
        if (comparator(candidate, incumbent) == NSOrderedAscending) {
            incumbent = candidate;
        }
    }
    return incumbent;
}

- (id)dvt_maximumObjectUsingComparator:(NSComparisonResult (^)(id, id))comparator
{
    /* Not a second fold: this is the minimum method asked with the comparator's
       answer negated, which is why the two share their tie-break and their
       first-wins rule. Apple wraps the caller's block in a stack block that
       calls it and negates the result, then sends that to
       dvt_minimumObjectUsingComparator: -- visible in the binary as a single
       tail call after the block literal is built. */
    return [self dvt_minimumObjectUsingComparator:^NSComparisonResult(id a, id b) {
        return (NSComparisonResult)-(NSInteger)comparator(a, b);
    }];
}

- (id)dvt_objectByFoldingWithBlock:(id (^)(id, id))block
{
    /* Unlike the minimum fold this one asks (accumulator, next) -- the opposite
       order -- and it does not test the answer for nil before using it.

       That last point is the observable one. A nil answer does not stop the
       fold: the next member finds a nil accumulator and simply becomes the new
       accumulator without the block being called, so a fold that returns nil for
       every member answers the *last* member rather than nil. The call log shows
       it -- a three-member all-nil fold consults the block once rather than twice,
       and a five-member one consults it twice, one call saved per re-seed. An
       empty receiver still answers nil, and a one-member receiver answers that
       member with the block never called at all.

       A nil block faults here as it does in the predicate families, since Apple
       loads the invoke pointer unchecked. */
    id accumulator = nil;
    for (id member in self) {
        if (accumulator == nil) {
            accumulator = member;
            continue;
        }
        accumulator = block(accumulator, member);
    }
    return accumulator;
}

- (NSArray *)dvt_shuffledArray
{
    /* A forward rather than a second shuffle: Apple's body is -allObjects
       followed by dvt_shuffledArray on the result. The array method is the one
       that branches on -count, so this inherits its threshold -- above one
       member the answer is a mutable array, and at one or below it is the copy
       of an already immutable array, hence __NSArrayI_Transfer. Each -allObjects
       call answers its own array even when the receiver is empty, so the empty
       answer is a copy of a fresh empty array rather than one shared instance. */
    return [[self allObjects] dvt_shuffledArray];
}

- (NSDictionary *)dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:(id (^)(id))block
{
    /* The names of these two are the other way round from where the answer
       lands. Here the member becomes the *key* and the block's answer becomes
       the value: a member "a" with the block uppercasing answers a->A. Apple
       sends -setObject:forKeyedSubscript: with the block's answer in the value
       slot and the member in the key slot, which is what the disassembly shows
       and the probe confirms.

       A nil answer is skipped rather than stored, so nothing reaches the
       subscript setter with a nil in either slot. Collisions are not a special
       case: the members stay distinct as keys, so a constant answer produces
       one entry per member, and the answer is immutable either way because the
       mutable dictionary built here is copied before it is returned. */
    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:self.count];
    for (id member in self) {
        id answer = block(member);
        if (answer != nil) {
            result[member] = answer;
        }
    }
    return [result copy];
}

- (NSDictionary *)dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:(id (^)(id))block
{
    /* The mirror image of the method above: the block's answer becomes the key
       and the member becomes the value, so the same uppercasing block answers
       A->a. Collisions now do collapse -- a constant answer leaves one entry
       whose value is the last member enumerated, since each write replaces the
       previous one.

       Apple's capacity hint is the receiver's count here as well, which is why
       an empty receiver answers the shared empty dictionary. */
    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:self.count];
    for (id member in self) {
        id answer = block(member);
        if (answer != nil) {
            result[answer] = member;
        }
    }
    return [result copy];
}

- (id)dvt_onlyObject
{
    /* An empty or multi-member set answers nil, so -anyObject is only reached
       when there is exactly one thing to hand back. */
    return self.count == 1 ? [self anyObject] : nil;
}

- (id)dvt_anyObjectPassingTest:(BOOL (^)(id object))test
{
    /* Answers the member that passes, not whether one did, so the name reads
       like the boolean predicate it is not. The first match in the set's own
       order wins and the rest are never asked. */
    for (id object in self) {
        if (test(object)) {
            return object;
        }
    }
    return nil;
}

- (id)dvt_onlyObjectPassingTest:(BOOL (^)(id object))test
{
    /* Exactly one member has to pass. A second match abandons the walk there and
       answers nil rather than finishing the enumeration to be sure, which is
       observable through how many times the block is asked. */
    id only = nil;
    for (id object in self) {
        if (test(object)) {
            if (only != nil) {
                return nil;
            }
            only = object;
        }
    }
    return only;
}

- (NSInteger)dvt_numberOfObjectsPassingTest:(BOOL (^)(id object))test
{
    /* Sums what the block returns instead of counting the truthy answers, and
       never stops early: every member is asked. See DVTRawTestValue.

       Signed, not unsigned: Apple's encoding is `q`, and the accumulator holds
       the zero-extended 32-bit returns without ever wrapping. */
    NSInteger total = 0;
    for (id object in self) {
        total += (NSUInteger)DVTRawTestValue(test, object);
    }
    return total;
}

@end

@implementation NSSet (DVTFoundationClassAdditions_DEPRECATED)

/* Both are bare forwards in the binary, so they stay forwards here rather than
   growing their own copy of the logic. */

- (BOOL)dvt_areAllObjectsPassingTest:(BOOL (^)(id object))test
{
    return [self dvt_allObjectsPassTest:test];
}

- (BOOL)dvt_areAnyObjectsPassingTest:(BOOL (^)(id object))test
{
    return [self dvt_anyObjectsPassTest:test];
}

@end

@implementation NSMutableSet (DVTNSMutableSetAdditions)

- (void)dvt_addObjectIfNonNil:(id)object
{
    if (object != nil) {
        [self addObject:object];
    }
}

- (void)dvt_recursivelyRemoveAllObjects
{
    /* The helper is the one the mutable array and dictionary reach for; it is
       handed a fresh visited set and the receiver is its first step. */
    DVTRemoveAllObjectsRecursively(self, [NSMutableSet set]);
}

- (id)dvt_popAllObjects
{
    /* Disassembly: -setWithSet: on an immutable set is taken first, then
       -removeAllObjects on the receiver, and the snapshot is answered. The
       members are out of the receiver before the answer is handed back, and the
       snapshot is a distinct immutable set, so later mutation of the receiver
       leaves it unchanged. */
    NSSet *snapshot = [NSSet setWithSet:self];
    [self removeAllObjects];
    return snapshot;
}

- (BOOL)dvt_addReturningDidMutate:(id)object
{
    /* Disassembly: the count before, the nil-guarded add, the count after, and a
       single unsigned comparison of the two. So the answer is whether the count
       grew, not whether anything was added -- an object the set already holds
       leaves it the same size, and answers NO. */
    NSUInteger before = self.count;
    [self dvt_addObjectIfNonNil:object];
    return before < self.count;
}

@end

@implementation NSHashTable (DVTNSHashTableAdditions)

- (BOOL)dvt_allObjectsPassTest:(BOOL (^)(id object))test
{
    return DVTAllObjectsPassTest(self, test);
}

- (BOOL)dvt_anyObjectsPassTest:(BOOL (^)(id object))test
{
    return DVTAnyObjectsPassTest(self, test);
}

- (void)dvt_addObjectIfNonNil:(id)object
{
    if (object != nil) {
        [self addObject:object];
    }
}

@end

@implementation NSHashTable (DVTFoundationClassAdditions_DEPRECATED)

- (BOOL)dvt_areAllObjectsPassingTest:(BOOL (^)(id object))test
{
    return [self dvt_allObjectsPassTest:test];
}

- (BOOL)dvt_areAnyObjectsPassingTest:(BOOL (^)(id object))test
{
    return [self dvt_anyObjectsPassTest:test];
}

@end

/* The emptiness pair, continued. Each of these is a `count != 0` in Apple: five
   instructions, no helper, and the two selectors compile to identical bodies on
   every collection class here. NSMapTable answers `count` too, so it needs no
   special case despite not being a collection in the usual sense. */

@implementation NSDictionary (DVTFoundationClassAdditions)

- (id)dvt_firstKeyPassingTest:(BOOL (^)(id key, id obj))test
{
    /* Apple delegates to -keysOfEntriesPassingTest:, whose block is handed a stop
       pointer the predicate form does not take. The adapter stops on the first
       passing entry, so the resulting set holds at most one key; -anyObject turns
       it back into the single key or nil. No nil-test guard is emitted here -- the
       predicate is passed straight through. */
    return [[self keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
        BOOL passes = test(key, obj);
        if (passes) {
            *stop = YES;
        }
        return passes;
    }] anyObject];
}

- (NSDictionary *)dvt_entriesPassingTest:(BOOL (^)(id key, id obj))test
{
    /* The passing entries are staged into two stack buffers and the dictionary is
       built from them in one pass, which keeps the result ordered to match the
       receiver's enumeration rather than the order of any later hashing. The
       buffers cover 256 entries; past that the storage is heap allocated. */
    DVTAssert(test != nil, @"((test)) != nil", nil, @"%@ should not be nil.", @"(test)");
    __unsafe_unretained id stackKeys[256];
    __unsafe_unretained id stackObjects[256];
    __unsafe_unretained id *keys = stackKeys;
    __unsafe_unretained id *objects = stackObjects;
    NSUInteger count = self.count;
    if (count > 256) {
        keys = (__unsafe_unretained id *)calloc(count, sizeof(id));
        objects = (__unsafe_unretained id *)calloc(count, sizeof(id));
    }
    __block NSUInteger resultCount = 0;
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (test(key, obj)) {
            keys[resultCount] = key;
            objects[resultCount] = obj;
            resultCount++;
        }
    }];
    NSDictionary *result = [NSDictionary dictionaryWithObjects:objects
                                                       forKeys:keys
                                                         count:resultCount];
    if (keys != stackKeys) {
        free(keys);
    }
    if (objects != stackObjects) {
        free(objects);
    }
    return result;
}

- (BOOL)dvt_areAllEntriesPassingTest:(BOOL (^)(id key, id obj))test
{
    DVTAssert(test != nil, @"((test)) != nil", nil, @"%@ should not be nil.", @"(test)");
    __block BOOL allPass = YES;
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (!test(key, obj)) {
            allPass = NO;
            *stop = YES;
        }
    }];
    return allPass;
}

- (BOOL)dvt_areAnyEntriesPassingTest:(BOOL (^)(id key, id obj))test
{
    DVTAssert(test != nil, @"((test)) != nil", nil, @"%@ should not be nil.", @"(test)");
    __block BOOL anyPass = NO;
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (test(key, obj)) {
            anyPass = YES;
            *stop = YES;
        }
    }];
    return anyPass;
}

- (NSDictionary *)dvt_dictionaryByApplyingBlock:(id (^)(id key, id obj))block
{
    /* A block answering nil drops the entry: the staged count is only advanced for
       a non-nil mapped value, so the result is smaller than the receiver. The key
       and the mapped value are staged, not the receiver's value. */
    DVTAssert(block != nil, @"((block)) != nil", nil, @"%@ should not be nil.", @"(block)");
    __unsafe_unretained id stackKeys[256];
    __unsafe_unretained id stackResults[256];
    __unsafe_unretained id *keys = stackKeys;
    __unsafe_unretained id *results = stackResults;
    NSUInteger count = self.count;
    if (count > 256) {
        keys = (__unsafe_unretained id *)calloc(count, sizeof(id));
        results = (__unsafe_unretained id *)calloc(count, sizeof(id));
    }
    __block NSUInteger resultCount = 0;
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        id mapped = block(key, obj);
        if (mapped != nil) {
            keys[resultCount] = key;
            results[resultCount] = mapped;
            resultCount++;
        }
    }];
    NSDictionary *dictionary = [NSDictionary dictionaryWithObjects:results
                                                           forKeys:keys
                                                             count:resultCount];
    if (keys != stackKeys) {
        free(keys);
    }
    if (results != stackResults) {
        free(results);
    }
    return dictionary;
}

- (NSDictionary *)dvt_invertedBijectiveDictionary
{
    if (self.count != 0) {
        return [self dvt_invertedBijectiveDictionaryUsingMutableDictionaryClass:[NSMutableDictionary class]];
    }
    return [[self class] dictionary];
}

- (NSDictionary *)dvt_invertedBijectiveDictionaryUsingMutableDictionaryClass:(Class)mutableDictionaryClass
{
    NSMutableDictionary *inverted = [[mutableDictionaryClass alloc] initWithCapacity:self.count];
    for (id key in self) {
        id value = [self objectForKey:key];
        if ([inverted objectForKey:value] != nil) {
            DVTAssert(![inverted objectForKey:value], @"![inverted objectForKey:value]", nil, @"We can only invert bijective dictionaries.");
        }
        [inverted setObject:key forKey:value];
    }
    return inverted;
}

- (NSDictionary *)dvt_invertedDictionaryOfKeysGroupedByValue
{
    if (self.count != 0) {
        return [self dvt_invertedDictionaryOfKeysGroupedByValueUsingMutableDictionaryClass:[NSMutableDictionary class]];
    }
    return [[self class] dictionary];
}

- (NSDictionary *)dvt_invertedDictionaryOfKeysGroupedByValueUsingMutableDictionaryClass:(Class)mutableDictionaryClass
{
    NSMutableDictionary *inverted = [[mutableDictionaryClass alloc] initWithCapacity:self.count];
    for (id key in self) {
        id value = [self objectForKey:key];
        [inverted dvt_addObject:key toSetForKey:value];
    }
    return inverted;
}

- (BOOL)dvt_validateKey:(id)key
          expectedClass:(Class)expectedClass
              allowNil:(BOOL)allowNil
                 error:(NSError * __autoreleasing *)error
{
    /* Success is tracked independently of the local error, because the failure
       branch still has to assert that an error was produced. A missing value is
       only a fault when nil is disallowed; a present value is only a fault when it
       is not an instance of expectedClass. The out-error is written as an
       autoreleased reference, and only reached when a caller supplied one. */
    id value = [self objectForKey:key];
    BOOL success;
    NSError *___localError = nil;
    if (value == nil) {
        if (allowNil) {
            success = YES;
        } else {
            ___localError = [NSError dvt_errorWithMessage:[NSString stringWithFormat:@"Missing required value for %@", key]];
            success = NO;
        }
    } else if ([value isKindOfClass:expectedClass]) {
        success = YES;
    } else {
        ___localError = [NSError dvt_errorWithMessage:[NSString stringWithFormat:@"Value for %@ should be an instance of %@, not %@ (%@)", key, expectedClass, [value class], value]];
        success = NO;
    }
    if (!success) {
        DVTAssert(___localError, @"___localError", nil, @"A method claimed to have failed but provided no error!");
    }
    if (error != NULL) {
        *error = success ? nil : ___localError;
    }
    return success;
}

- (BOOL)dvt_validateKey:(id)key
     expectedArrayOfClass:(Class)elementClass
               allowNil:(BOOL)allowNil
                  error:(NSError * __autoreleasing *)error
{
    /* The key is first validated as an NSArray, then every member is asked whether
       it is an instance of elementClass. Each path asserts the opposite of the
       other's local-error state, which is why both asserts are emitted. */
    NSError *___localError = nil;
    BOOL success = [self dvt_validateKey:key
                           expectedClass:[NSArray class]
                               allowNil:allowNil
                                  error:&___localError];
    if (success) {
        NSArray *value = [self objectForKey:key];
        if (value != nil && ![value dvt_allObjectsPassTest:^BOOL(id element) {
            return [element isKindOfClass:elementClass];
        }]) {
            ___localError = [NSError dvt_errorWithMessage:[NSString stringWithFormat:@"Value for %@ should be an array of %@, not: %@", key, elementClass, value]];
            success = NO;
        }
    }
    if (success) {
        DVTAssert(!___localError, @"!___localError", nil, @"A method claimed to have succeeded but provided an error! (%@)", ___localError);
    } else {
        DVTAssert(___localError, @"___localError", nil, @"A method claimed to have failed but provided no error!");
    }
    if (error != NULL) {
        *error = success ? nil : ___localError;
    }
    return success;
}

- (BOOL)dvt_hasContent
{
    return self.count != 0;
}

- (BOOL)dvt_isNonEmpty
{
    return self.count != 0;
}

+ (NSDictionary *)dvt_dictionaryWithKeysAndValues:(id)firstKey, ...
{
    /* The variadic pairs are staged into two stack buffers of 256 entries; past that
       the storage moves to the heap and grows by doubling, seeded with calloc and then
       realloc'ed. A nil value drops its pair and the walk reads the next argument as a
       key, so only a nil key ends the run; a nil first key answers an empty dictionary
       through the receiver's own class. */
    if (firstKey == nil) {
        return [self dictionary];
    }
    __unsafe_unretained id stackKeys[256];
    __unsafe_unretained id stackObjects[256];
    __unsafe_unretained id *keys = stackKeys;
    __unsafe_unretained id *objects = stackObjects;
    NSUInteger capacity = 256;
    NSUInteger count = 0;
    va_list arguments;
    va_start(arguments, firstKey);
    id key = firstKey;
    while (key != nil) {
        id object = va_arg(arguments, id);
        if (object == nil) {
            key = va_arg(arguments, id);
            continue;
        }
        if (count == capacity) {
            capacity *= 2;
            if (keys == stackKeys) {
                keys = (__unsafe_unretained id *)calloc(capacity, sizeof(id));
                objects = (__unsafe_unretained id *)calloc(capacity, sizeof(id));
                memcpy(keys, stackKeys, count * sizeof(id));
                memcpy(objects, stackObjects, count * sizeof(id));
            } else {
                keys = (__unsafe_unretained id *)realloc(keys, capacity * sizeof(id));
                objects = (__unsafe_unretained id *)realloc(objects, capacity * sizeof(id));
            }
        }
        keys[count] = key;
        objects[count] = object;
        count++;
        key = va_arg(arguments, id);
    }
    va_end(arguments);
    NSDictionary *result = [self dictionaryWithObjects:objects forKeys:keys count:count];
    if (keys != stackKeys) {
        free(keys);
        free(objects);
    }
    return result;
}

- (NSDictionary *)dvt_dictionaryBySettingObject:(id)object forKey:(id)key
{
    /* The key is asserted before the value, matching the binary. Setting the value the
       receiver already holds at the key is a copy of the receiver itself; anything
       else is a mutable copy with the one entry set, which is why that path answers a
       mutable dictionary and the unchanged path does not. */
    DVTAssert(key != nil, @"((key)) != nil", nil, @"%@ should not be nil.", @"(key)");
    DVTAssert(object != nil, @"((obj)) != nil", nil, @"%@ should not be nil.", @"(obj)");
    if ([self objectForKey:key] == object) {
        return [self copy];
    }
    NSMutableDictionary *dictionary = [self mutableCopy];
    [dictionary setObject:object forKey:key];
    return dictionary;
}

- (NSDictionary *)dvt_dictionaryByAddingEntriesFromDictionary:(NSDictionary *)dictionary
{
    /* Either empty side short-circuits to a copy of the other so no mutable dictionary
       is allocated; only when both carry entries is a mutable copy grown with the
       additions. The receiver is never touched. */
    if ([self count] == 0) {
        return [dictionary copy];
    }
    if ([dictionary count] == 0) {
        return [self copy];
    }
    NSMutableDictionary *result = [self mutableCopy];
    [result addEntriesFromDictionary:dictionary];
    return result;
}

- (NSString *)dvt_stringOrNilForKey:(id)key
{
    /* The class check is the whole of the method: the value is asked whether it is an
       instance of the stated class, and answered as-is or replaced with nil. */
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSData *)dvt_dataOrNilForKey:(id)key
{
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSData class]] ? value : nil;
}

- (NSDictionary *)dvt_dictionaryOrNilForKey:(id)key
{
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSArray *)dvt_arrayOrNilForKey:(id)key
{
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

- (NSDate *)dvt_dateOrNilForKey:(id)key
{
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSDate class]] ? value : nil;
}

- (NSNumber *)dvt_numberOrNilForKey:(id)key
{
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

@end

@implementation NSMutableDictionary (DVTFoundationClassAdditions)

- (void)dvt_setObject:(id)object forKey:(id)key inDictionaryForKey:(id)dictionaryKey
{
    NSMutableDictionary *subdictionary = [self objectForKey:dictionaryKey];
    if (subdictionary != nil) {
        [subdictionary setObject:object forKey:key];
    } else {
        [self setObject:[NSMutableDictionary dictionaryWithObject:object forKey:key]
                 forKey:dictionaryKey];
    }
}

- (void)dvt_addObject:(id)object toArrayForKey:(id)key
{
    [[self dvt_objectForKey:key creatingIfNecessaryFromClass:[NSMutableArray class]] addObject:object];
}

- (void)dvt_addObject:(id)object toArrayForKey:(id)key inDictionaryForKey:(id)dictionaryKey
{
    NSMutableDictionary *subdictionary = [self dvt_objectForKey:dictionaryKey creatingIfNecessaryFromClass:[NSMutableDictionary class]];
    [subdictionary dvt_addObject:object toArrayForKey:key];
}

- (void)dvt_addObject:(id)object toSetForKey:(id)key
{
    [[self dvt_objectForKey:key creatingIfNecessaryFromClass:[NSMutableSet class]] addObject:object];
}

- (void)dvt_addObject:(id)object toSetForKey:(id)key inDictionaryForKey:(id)dictionaryKey
{
    NSMutableDictionary *subdictionary = [self dvt_objectForKey:dictionaryKey creatingIfNecessaryFromClass:[NSMutableDictionary class]];
    [subdictionary dvt_addObject:object toSetForKey:key];
}

- (void)dvt_addObject:(id)object toOrderedSetForKey:(id)key
{
    [[self dvt_objectForKey:key creatingIfNecessaryFromClass:[NSMutableOrderedSet class]] addObject:object];
}

- (void)dvt_removeObject:(id)object fromCollectionForKey:(id)key
{
    /* The collection empty after the removal is dropped from the receiver, so the
       key never survives pointing at an empty collection. A missing key is a
       no-op. */
    id collection = [self objectForKey:key];
    if (collection != nil) {
        [collection removeObject:object];
        if ([collection count] == 0) {
            [self removeObjectForKey:key];
        }
    }
}

- (void)dvt_setInteger:(NSInteger)value forKey:(id)key
{
    [self setValue:[NSNumber numberWithInteger:value] forKey:key];
}

- (void)dvt_setBool:(BOOL)value forKey:(id)key
{
    [self setValue:[NSNumber numberWithBool:value] forKey:key];
}

- (void)dvt_setFloat:(float)value forKey:(id)key
{
    [self setValue:[NSNumber numberWithFloat:value] forKey:key];
}

- (void)dvt_setDouble:(double)value forKey:(id)key
{
    [self setValue:[NSNumber numberWithDouble:value] forKey:key];
}

- (void)dvt_recursivelyRemoveAllObjects
{
    /* The helper is the same one the mutable array reaches for; it is handed a
       fresh visited set and the receiver is its first step. */
    DVTRemoveAllObjectsRecursively(self, [NSMutableSet set]);
}

- (id)dvt_extractObjectForKey:(id)key
{
    id object = [self objectForKey:key];
    if (object != nil) {
        [self removeObjectForKey:key];
    }
    return object;
}

- (id)dvt_objectForKey:(id)key creatingIfNecessaryFromClass:(Class)objectClass
{
    return [self dvt_objectForKey:key creatingIfNecessaryWithBlock:^id {
        return [[objectClass alloc] init];
    }];
}

- (id)dvt_objectForKey:(id)key creatingIfNecessaryWithBlock:(id (^)(void))block
{
    DVTAssert(key != nil, @"((key)) != nil", nil, @"%@ should not be nil.", @"(key)");
    id object = [self objectForKey:key];
    if (object == nil) {
        object = block();
        [self setObject:object forKey:key];
    }
    return object;
}

- (void)dvt_setObjectIfNonNil:(id)object forKey:(id)key
{
    if (object != nil) {
        [self setObject:object forKey:key];
    }
}

- (void)dvt_setObject:(id)object forKeyIfNonNil:(id)key
{
    if (key != nil) {
        [self setObject:object forKey:key];
    }
}

- (void)dvt_intersectKeys:(NSArray *)keys
{
    NSArray *allKeys = [self allKeys];
    for (id key in allKeys) {
        if (![keys containsObject:key]) {
            [self removeObjectForKey:key];
        }
    }
}

@end

id DVTObjectForKey(CFDictionaryRef dictionary, const void *key)
{
    return (__bridge id)CFDictionaryGetValue(dictionary, key);
}

void DVTSetObjectForKey(CFMutableDictionaryRef dictionary, const void *value, const void *key)
{
    CFDictionarySetValue(dictionary, key, value);
}

void DVTRemoveObjectForKey(CFMutableDictionaryRef dictionary, const void *key)
{
    CFDictionaryRemoveValue(dictionary, key);
}

@implementation NSDictionary (DVTFoundationClassAdditions_MRR)

- (void)dvt_getStrongObjects:(id __unsafe_unretained *)objects andStrongKeys:(id __unsafe_unretained *)keys
{
    /* +1 references on every returned object and key: this category exists for
       callers that need ownership before ARC, so the retains are explicit and no
       matching release is emitted. Keys are retained before objects, matching the
       two parallel walks. */
    DVTAssert(keys != NULL, @"keys != ((void*)0)", nil, @"");
    DVTAssert(objects != NULL, @"objects != ((void*)0)", nil, @"");
    NSUInteger count = self.count;
    if (count != 0) {
        [self getObjects:objects andKeys:keys count:count];
        for (NSUInteger index = 0; index < count; index++) {
            keys[index] = (__bridge id)CFBridgingRetain(keys[index]);
            objects[index] = (__bridge id)CFBridgingRetain(objects[index]);
        }
    }
}

@end

@implementation NSMapTable (DVTNSMapTableAdditions)

- (BOOL)dvt_hasContent
{
    return self.count != 0;
}

- (BOOL)dvt_isNonEmpty
{
    return self.count != 0;
}

@end

@implementation NSOrderedSet (DVTNSOrderedSetAdditions)

- (BOOL)dvt_hasContent
{
    return self.count != 0;
}

- (BOOL)dvt_isNonEmpty
{
    return self.count != 0;
}

- (id)dvt_onlyObject
{
    /* Disassembly: ask -count, branch to a nil answer unless it is exactly one, and
       otherwise hand back -objectAtIndex:0. Two elements are not "the only" one, so
       the answer is nil rather than the first of them. */
    return self.count == 1 ? [self objectAtIndex:0] : nil;
}

- (id)dvt_anyObjectPassingTest:(BOOL (^)(id object))test
{
    /* Despite the name this answers the object that passed rather than a flag: the
       binary falls into the shared tail that retains the current member and returns
       it with an autorelease on the way out, and never writes a boolean to the
       return register. The set family's dvt_anyObjectsPassTest: does answer a flag,
       so the two spellings are not interchangeable.

       The test itself is `tbnz w0, #0` on the block's raw answer, which is the low
       bit rather than the whole word: an int-returning block cast over the signature
       answers nil for 2 and the member for 1, 3 and -1. See DVTRawTestValue. */
    if (test == nil) {
        return self.count > 0 ? [self objectAtIndex:0] : nil;
    }
    for (id object in self) {
        if (DVTRawTestValue(test, object) & 1) {
            return object;
        }
    }
    return nil;
}

- (NSOrderedSet *)dvt_objectsPassingTest:(BOOL (^)(id object))test
{
    /* Apple keeps the answers in a 256-slot stack buffer, switches to calloc past 256
       members, and finishes with +orderedSetWithObjects:count:. That last call is why
       the answer is __NSOrderedSetI at every size and never the receiver, which is
       what separates this from NSSet's form of the selector -- that one hands back the
       collection it was sent when nothing is filtered out. The buffer itself is not
       observable, so the answers are gathered in a mutable set and re-offered to the
       same factory call to land on the same class. */
    if (test == nil) {
        return [self copy];
    }
    NSMutableOrderedSet *passing = [[NSMutableOrderedSet alloc] initWithCapacity:self.count];
    for (id object in self) {
        /* The whole raw word is tested here, not its low bit: `cbz w0` over the
           block's answer rather than the `tbnz w0, #0` dvt_anyObjectPassingTest:
           uses, so an int-returning block answers with 2 or 256 keeps everything,
           where the "any" spelling with the same block finds nothing. NSSet's
           dvt_setByFilteringUsingBlock: agrees -- a filter wants a member back, so a
           nonzero answer counts however it got there. */
        if (DVTRawTestValue(test, object) != 0) {
            [passing addObject:object];
        }
    }
    NSArray *members = [passing array];
    NSUInteger count = members.count;
    void *buffer = calloc(count == 0 ? 1 : count, sizeof(id));
    CFArrayGetValues((__bridge CFArrayRef)members, CFRangeMake(0, (CFIndex)count), buffer);
    NSOrderedSet *result = [NSOrderedSet orderedSetWithObjects:(const __unsafe_unretained id *)buffer count:count];
    free(buffer);
    return result;
}

#pragma mark - Mapping

/* The mapping bodies on an ordered set are the NSArray bodies with the members in
   order, so each one is reached by handing the members over as the array the same
   body was written for. -dvt_compactMap: is the exception: Apple answers
   dvt_arrayByApplyingBlock: straight from it -- a single tail call -- so the forward
   goes the other way, and the compact-map name lands on the immutable answer rather
   than on the mutable build NSArray's own compact map hands back. */

- (NSArray *)dvt_arrayByApplyingBlock:(id (^)(id object))block
{
    return [[self array] dvt_arrayByApplyingBlock:block];
}

- (NSArray *)dvt_compactMap:(id (^)(id object))block
{
    return [self dvt_arrayByApplyingBlock:block];
}

- (id)dvt_firstMap:(id (^)(id object))block
{
    /* No early exit for a nil answer, only for an element whose answer is usable: the
       probe's call log is what shows it, two members mapping to nil and X costing two
       calls, and a third member never asked about. A block that always answers nil
       therefore walks the whole receiver.

       No nil guard here, as on NSArray: a nil block faults in both, because Apple
       loads the block's invoke pointer without checking it. */
    for (id object in self) {
        id mapped = block(object);
        if (mapped != nil) {
            return mapped;
        }
    }
    return nil;
}

- (NSOrderedSet *)dvt_orderedSetByApplyingBlock:(id (^)(id object))block
{
    /* Disassembly: the same 256-slot staged buffer the array bodies use, then
       +orderedSetWithObjects:count:. Repeated answers collapse in the factory call,
       which is what makes this differ from dvt_arrayByApplyingBlock:, and the answer
       is built straight from the answers rather than copied out of a mutable set. */
    if (block == nil) {
        return [self copy];
    }
    NSMutableOrderedSet *answers = [[NSMutableOrderedSet alloc] initWithCapacity:self.count];
    for (id object in self) {
        id mapped = block(object);
        if (mapped != nil) {
            [answers addObject:mapped];
        }
    }
    NSArray *members = [answers array];
    NSUInteger count = members.count;
    void *buffer = calloc(count == 0 ? 1 : count, sizeof(id));
    CFArrayGetValues((__bridge CFArrayRef)members, CFRangeMake(0, (CFIndex)count), buffer);
    NSOrderedSet *result = [NSOrderedSet orderedSetWithObjects:(const __unsafe_unretained id *)buffer count:count];
    free(buffer);
    return result;
}

#pragma mark - Ordered set algebra

- (NSOrderedSet *)dvt_orderedSetByAddingObject:(id)object
{
    /* Disassembly: retain the argument, branch to the retained receiver when it is nil
       or when -containsObject: already says yes, and otherwise append to a mutable
       copy and hand back its immutable form. Both shortcuts answer the receiver itself
       rather than a copy of it, which a mutable receiver can observe. */
    if (object == nil || [self containsObject:object]) {
        return self;
    }
    NSMutableOrderedSet *result = [self mutableCopy];
    [result addObject:object];
    return [result copy];
}

- (NSOrderedSet *)dvt_orderedSetByAddingObjectsFromArray:(NSArray *)objects
{
    /* The branch is on the argument's count, so a nil argument answers zero and lands
       on the receiver shortcut rather than raising. */
    if (objects.count == 0) {
        return self;
    }
    NSMutableOrderedSet *result = [self mutableCopy];
    [result addObjectsFromArray:objects];
    return [result copy];
}

- (NSOrderedSet *)dvt_orderedSetByRemovingObject:(id)object
{
    /* The nil check comes before -containsObject:, and either one short-circuits to the
       receiver. Past both it is a mutable copy with the member taken out, handed back
       as its immutable form -- a snapshot, so a receiver changed afterwards does not
       change the answer. */
    if (object == nil || ![self containsObject:object]) {
        return self;
    }
    NSMutableOrderedSet *result = [self mutableCopy];
    [result removeObject:object];
    return [result copy];
}

- (NSOrderedSet *)dvt_orderedSetBySubtractingOrderedSet:(NSOrderedSet *)orderedSet
{
    if (orderedSet.count == 0) {
        return self;
    }
    NSMutableOrderedSet *result = [self mutableCopy];
    [result minusOrderedSet:orderedSet];
    return [result copy];
}

@end

/* The three mutators are declared by Apple on NSMutableOrderedSet, in a category of
   the same name -- so a dump of either binary shows them the same way -- and an
   immutable ordered set answers none of them, raising on the first instead. */
@implementation NSMutableOrderedSet (DVTNSOrderedSetAdditions)

- (void)dvt_addObjectIfNotNil:(id)object
{
    if (object != nil) {
        [self addObject:object];
    }
}

- (BOOL)dvt_addReturningDidMutate:(id)object
{
    /* Disassembly: the count before, the nil-guarded add, the count after, and a
       single unsigned comparison of the two. So the answer is whether the count grew,
       not whether anything was added -- an element the ordered set already holds
       leaves it the same length, and answers NO. */
    NSUInteger before = self.count;
    [self dvt_addObjectIfNotNil:object];
    return before < self.count;
}

- (id)dvt_popLastObject
{
    /* Disassembly: -lastObject, retain, and -removeObject: only when there was one.
       The element is out of the receiver before it is handed back. */
    id last = [self lastObject];
    if (last != nil) {
        [self removeObject:last];
    }
    return last;
}

@end

/* NSString is the one host where the two are *not* the same expression, and the
   difference is invisible from the outside: Apple asks `length != 0` for
   `dvt_hasContent` but `!isEqualToString:@""` for `dvt_isNonEmpty`. Every string
   agrees, so no caller can tell -- but a subclass that overrode one message and
   not the other could, so the split is reproduced rather than smoothed over. */
@implementation NSString (DVTFoundationClassAdditions)

- (BOOL)dvt_hasContent
{
    return self.length != 0;
}

- (BOOL)dvt_isNonEmpty
{
    return ![self isEqualToString:@""];
}

enum {
    DVTStringLetterCasingLowercase = 0,
    DVTStringLetterCasingUppercase = 1,
    DVTStringLetterCasingCapitalized = 2,
};

- (NSString *)dvt_stringWithLetterCasing:(NSUInteger)letterCasing
{
    switch (letterCasing) {
        case DVTStringLetterCasingLowercase:
            return self.lowercaseString;
        case DVTStringLetterCasingUppercase:
            return self.uppercaseString;
        case DVTStringLetterCasingCapitalized:
            return self.capitalizedString;
        default:
            DVTAssert(NO, @"Unknown letter casing", nil, @"Unknown enum value of type DVTStringCasingType: %@", @(letterCasing));
            return self;
    }
}

- (NSString *)dvt_substringFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex
{
    NSInteger stringLength = (NSInteger)self.length;
    DVTAssert(fromIndex <= toIndex, @"fromIndex <= toIndex", nil,
              @"fromIndex must be less than or equal to toIndex");
    DVTAssert(0 <= fromIndex && fromIndex <= stringLength, @"0 <= fromIndex && fromIndex <= stringLength", nil,
              @"fromIndex must be greater than or equal to 0 and less than or equal to the string length");
    DVTAssert(0 <= toIndex && toIndex <= stringLength, @"0 <= toIndex && toIndex <= stringLength", nil,
              @"toIndex must be greater than or equal to 0 and less than or equal to the string length");
    return [self substringWithRange:NSMakeRange((NSUInteger)fromIndex, (NSUInteger)(toIndex - fromIndex))];
}

- (NSString *)dvt_stringByCapitalizingFirstCharacter
{
    if (self.length == 0 || ![[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:[self characterAtIndex:0]]) {
        return self;
    }
    return [[self substringToIndex:1].uppercaseString stringByAppendingString:[self substringFromIndex:1]];
}

- (NSString *)dvt_stringByLowercasingFirstCharacter
{
    if (self.length == 0 || ![[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:[self characterAtIndex:0]]) {
        return self;
    }
    return [[self substringToIndex:1].lowercaseString stringByAppendingString:[self substringFromIndex:1]];
}

/** `YES` when `character` falls in the inclusive ASCII range `low ... high`. */
static inline BOOL DVTCharacterIsInASCIIRange(unichar character, unichar low, unichar high)
{
    return (NSUInteger)(character - low) <= (NSUInteger)(high - low);
}

- (NSArray<NSString *> *)dvt_wordsFromStringWithLetterCasing:(NSUInteger)letterCasing
{
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSUInteger length = self.length;

    void (^appendWord)(NSUInteger, NSUInteger) = ^(NSUInteger wordStart, NSUInteger end) {
        if (wordStart >= end) {
            return;
        }
        NSString *word = [self dvt_substringFromIndex:(NSInteger)wordStart toIndex:(NSInteger)end];
        [words addObject:[word dvt_stringWithLetterCasing:letterCasing]];
    };

    NSUInteger index = 0;
    NSUInteger wordStart = 0;
    // Widening the range to '0' ... ':' is what Apple does, so ':' also continues a digit run. A
    // boundary that repeats leaves an empty range behind, which appendWord skips.
    BOOL precededByDigit = NO;

    for (; index < length; index++) {
        unichar character = [self characterAtIndex:index];
        if (DVTCharacterIsInASCIIRange(character, '0', '9')) {
            if (!precededByDigit) {
                appendWord(wordStart, index);
                wordStart = index;
            }
        } else if (DVTCharacterIsInASCIIRange(character, 'A', 'Z')) {
            appendWord(wordStart, index);
            wordStart = index;
        } else if (!DVTCharacterIsInASCIIRange(character, 'a', 'z')) {
            appendWord(wordStart, index);
            wordStart = index + 1;
        } else if (precededByDigit) {
            appendWord(wordStart, index);
            wordStart = index;
        }
        precededByDigit = DVTCharacterIsInASCIIRange(character, '0', ':');
    }

    appendWord(wordStart, length);
    return words;
}

- (NSArray<NSString *> *)dvt_wordsFromString
{
    return [self dvt_wordsFromStringWithLetterCasing:DVTStringLetterCasingLowercase];
}

- (NSArray<NSString *> *)dvt_capitalizedWordsFromString
{
    return [self dvt_wordsFromStringWithLetterCasing:DVTStringLetterCasingCapitalized];
}

/* Four mangling profiles, plus the C99 Annex D character table that the extended profile needs. The
   profiles are not interchangeable: they disagree about replacement character, about whether the
   receiver is canonical-decomposed, about whether iteration is per UTF-16 unit or per Unicode scalar,
   and about which characters may open the result. Apple keeps one C99 Annex D table with a companion
   list of the characters that are legal only after the first one. */
typedef NS_ENUM(NSUInteger, DVTIdentifierManglingProfile) {
    DVTIdentifierManglingProfileC = 0,
    DVTIdentifierManglingProfileC99Extended = 1,
    DVTIdentifierManglingProfileBundle = 2,
    DVTIdentifierManglingProfileRFC1034 = 3,
};

typedef struct {
    unichar first;
    unichar last;
} DVTIdentifierCharacterRange;

/* C99 Annex D, restricted to the Basic Multilingual Plane: the characters a C99 extended identifier
   may contain, transcribed from Apple's behavior rather than from a published revision of the annex,
   since Apple pins specific range ends (U+1E9B, U+9FA5) that track the Unicode version it shipped. */
static const DVTIdentifierCharacterRange DVTC99ExtendedIdentifierAllowedRanges[] = {
    { 0x0030, 0x0039 }, { 0x0041, 0x005A }, { 0x005F, 0x005F }, { 0x0061, 0x007A }, { 0x00AA, 0x00AA }, { 0x00B5, 0x00B5 },
    { 0x00B7, 0x00B7 }, { 0x00BA, 0x00BA }, { 0x00C0, 0x00D6 }, { 0x00D8, 0x00F6 }, { 0x00F8, 0x01F5 }, { 0x01FA, 0x0217 },
    { 0x0250, 0x02A8 }, { 0x02B0, 0x02B8 }, { 0x02BB, 0x02BB }, { 0x02BD, 0x02C1 }, { 0x02D0, 0x02D1 }, { 0x02E0, 0x02E4 },
    { 0x037A, 0x037A }, { 0x0386, 0x0386 }, { 0x0388, 0x038A }, { 0x038C, 0x038C }, { 0x038E, 0x03A1 }, { 0x03A3, 0x03CE },
    { 0x03D0, 0x03D6 }, { 0x03DA, 0x03DA }, { 0x03DC, 0x03DC }, { 0x03DE, 0x03DE }, { 0x03E0, 0x03E0 }, { 0x03E2, 0x03F3 },
    { 0x0401, 0x040C }, { 0x040E, 0x044F }, { 0x0451, 0x045C }, { 0x045E, 0x0481 }, { 0x0490, 0x04C4 }, { 0x04C7, 0x04C8 },
    { 0x04CB, 0x04CC }, { 0x04D0, 0x04EB }, { 0x04EE, 0x04F5 }, { 0x04F8, 0x04F9 }, { 0x0531, 0x0556 }, { 0x0559, 0x0559 },
    { 0x0561, 0x0587 }, { 0x05B0, 0x05B9 }, { 0x05BB, 0x05BD }, { 0x05BF, 0x05BF }, { 0x05C1, 0x05C2 }, { 0x05D0, 0x05EA },
    { 0x05F0, 0x05F2 }, { 0x0621, 0x063A }, { 0x0640, 0x0652 }, { 0x0660, 0x0669 }, { 0x0670, 0x06B7 }, { 0x06BA, 0x06BE },
    { 0x06C0, 0x06CE }, { 0x06D0, 0x06DC }, { 0x06E5, 0x06E8 }, { 0x06EA, 0x06ED }, { 0x06F0, 0x06F9 }, { 0x0901, 0x0903 },
    { 0x0905, 0x0939 }, { 0x093D, 0x094D }, { 0x0950, 0x0952 }, { 0x0958, 0x0963 }, { 0x0966, 0x096F }, { 0x0981, 0x0983 },
    { 0x0985, 0x098C }, { 0x098F, 0x0990 }, { 0x0993, 0x09A8 }, { 0x09AA, 0x09B0 }, { 0x09B2, 0x09B2 }, { 0x09B6, 0x09B9 },
    { 0x09BE, 0x09C4 }, { 0x09C7, 0x09C8 }, { 0x09CB, 0x09CD }, { 0x09DC, 0x09DD }, { 0x09DF, 0x09E3 }, { 0x09E6, 0x09F1 },
    { 0x0A02, 0x0A02 }, { 0x0A05, 0x0A0A }, { 0x0A0F, 0x0A10 }, { 0x0A13, 0x0A28 }, { 0x0A2A, 0x0A30 }, { 0x0A32, 0x0A33 },
    { 0x0A35, 0x0A36 }, { 0x0A38, 0x0A39 }, { 0x0A3E, 0x0A42 }, { 0x0A47, 0x0A48 }, { 0x0A4B, 0x0A4D }, { 0x0A59, 0x0A5C },
    { 0x0A5E, 0x0A5E }, { 0x0A66, 0x0A6F }, { 0x0A74, 0x0A74 }, { 0x0A81, 0x0A83 }, { 0x0A85, 0x0A8B }, { 0x0A8D, 0x0A8D },
    { 0x0A8F, 0x0A91 }, { 0x0A93, 0x0AA8 }, { 0x0AAA, 0x0AB0 }, { 0x0AB2, 0x0AB3 }, { 0x0AB5, 0x0AB9 }, { 0x0ABD, 0x0AC5 },
    { 0x0AC7, 0x0AC9 }, { 0x0ACB, 0x0ACD }, { 0x0AD0, 0x0AD0 }, { 0x0AE0, 0x0AE0 }, { 0x0AE6, 0x0AEF }, { 0x0B01, 0x0B03 },
    { 0x0B05, 0x0B0C }, { 0x0B0F, 0x0B10 }, { 0x0B13, 0x0B28 }, { 0x0B2A, 0x0B30 }, { 0x0B32, 0x0B33 }, { 0x0B36, 0x0B39 },
    { 0x0B3D, 0x0B43 }, { 0x0B47, 0x0B48 }, { 0x0B4B, 0x0B4D }, { 0x0B5C, 0x0B5D }, { 0x0B5F, 0x0B61 }, { 0x0B66, 0x0B6F },
    { 0x0B82, 0x0B83 }, { 0x0B85, 0x0B8A }, { 0x0B8E, 0x0B90 }, { 0x0B92, 0x0B95 }, { 0x0B99, 0x0B9A }, { 0x0B9C, 0x0B9C },
    { 0x0B9E, 0x0B9F }, { 0x0BA3, 0x0BA4 }, { 0x0BA8, 0x0BAA }, { 0x0BAE, 0x0BB5 }, { 0x0BB7, 0x0BB9 }, { 0x0BBE, 0x0BC2 },
    { 0x0BC6, 0x0BC8 }, { 0x0BCA, 0x0BCD }, { 0x0BE7, 0x0BEF }, { 0x0C01, 0x0C03 }, { 0x0C05, 0x0C0C }, { 0x0C0E, 0x0C10 },
    { 0x0C12, 0x0C28 }, { 0x0C2A, 0x0C33 }, { 0x0C35, 0x0C39 }, { 0x0C3E, 0x0C44 }, { 0x0C46, 0x0C48 }, { 0x0C4A, 0x0C4D },
    { 0x0C60, 0x0C61 }, { 0x0C66, 0x0C6F }, { 0x0C82, 0x0C83 }, { 0x0C85, 0x0C8C }, { 0x0C8E, 0x0C90 }, { 0x0C92, 0x0CA8 },
    { 0x0CAA, 0x0CB3 }, { 0x0CB5, 0x0CB9 }, { 0x0CBE, 0x0CC4 }, { 0x0CC6, 0x0CC8 }, { 0x0CCA, 0x0CCD }, { 0x0CDE, 0x0CDE },
    { 0x0CE0, 0x0CE1 }, { 0x0CE6, 0x0CEF }, { 0x0D02, 0x0D03 }, { 0x0D05, 0x0D0C }, { 0x0D0E, 0x0D10 }, { 0x0D12, 0x0D28 },
    { 0x0D2A, 0x0D39 }, { 0x0D3E, 0x0D43 }, { 0x0D46, 0x0D48 }, { 0x0D4A, 0x0D4D }, { 0x0D60, 0x0D61 }, { 0x0D66, 0x0D6F },
    { 0x0E01, 0x0E3A }, { 0x0E40, 0x0E5B }, { 0x0E81, 0x0E82 }, { 0x0E84, 0x0E84 }, { 0x0E87, 0x0E88 }, { 0x0E8A, 0x0E8A },
    { 0x0E8D, 0x0E8D }, { 0x0E94, 0x0E97 }, { 0x0E99, 0x0E9F }, { 0x0EA1, 0x0EA3 }, { 0x0EA5, 0x0EA5 }, { 0x0EA7, 0x0EA7 },
    { 0x0EAA, 0x0EAB }, { 0x0EAD, 0x0EAE }, { 0x0EB0, 0x0EB9 }, { 0x0EBB, 0x0EBD }, { 0x0EC0, 0x0EC4 }, { 0x0EC6, 0x0EC6 },
    { 0x0EC8, 0x0ECD }, { 0x0ED0, 0x0ED9 }, { 0x0EDC, 0x0EDD }, { 0x0F00, 0x0F00 }, { 0x0F18, 0x0F19 }, { 0x0F20, 0x0F33 },
    { 0x0F35, 0x0F35 }, { 0x0F37, 0x0F37 }, { 0x0F39, 0x0F39 }, { 0x0F3E, 0x0F47 }, { 0x0F49, 0x0F69 }, { 0x0F71, 0x0F84 },
    { 0x0F86, 0x0F8B }, { 0x0F90, 0x0F95 }, { 0x0F97, 0x0F97 }, { 0x0F99, 0x0FAD }, { 0x0FB1, 0x0FB7 }, { 0x0FB9, 0x0FB9 },
    { 0x10A0, 0x10C5 }, { 0x10D0, 0x10F6 }, { 0x1E00, 0x1E9B }, { 0x1EA0, 0x1EF9 }, { 0x1F00, 0x1F15 }, { 0x1F18, 0x1F1D },
    { 0x1F20, 0x1F45 }, { 0x1F48, 0x1F4D }, { 0x1F50, 0x1F57 }, { 0x1F59, 0x1F59 }, { 0x1F5B, 0x1F5B }, { 0x1F5D, 0x1F5D },
    { 0x1F5F, 0x1F7D }, { 0x1F80, 0x1FB4 }, { 0x1FB6, 0x1FBC }, { 0x1FBE, 0x1FBE }, { 0x1FC2, 0x1FC4 }, { 0x1FC6, 0x1FCC },
    { 0x1FD0, 0x1FD3 }, { 0x1FD6, 0x1FDB }, { 0x1FE0, 0x1FEC }, { 0x1FF2, 0x1FF4 }, { 0x1FF6, 0x1FFC }, { 0x203F, 0x2040 },
    { 0x207F, 0x207F }, { 0x2102, 0x2102 }, { 0x2107, 0x2107 }, { 0x210A, 0x2113 }, { 0x2115, 0x2115 }, { 0x2118, 0x211D },
    { 0x2124, 0x2124 }, { 0x2126, 0x2126 }, { 0x2128, 0x2128 }, { 0x212A, 0x2131 }, { 0x2133, 0x2138 }, { 0x2160, 0x2182 },
    { 0x3005, 0x3007 }, { 0x3021, 0x3029 }, { 0x3041, 0x3093 }, { 0x309B, 0x309C }, { 0x30A1, 0x30F6 }, { 0x30FB, 0x30FC },
    { 0x3105, 0x312C }, { 0x4E00, 0x9FA5 }, { 0xAC00, 0xD7A3 },
};

static const size_t DVTC99ExtendedIdentifierAllowedRangeCount =
    sizeof(DVTC99ExtendedIdentifierAllowedRanges) / sizeof(DVTIdentifierCharacterRange);

/* Legal in an extended identifier, but never as its first character. */
static const DVTIdentifierCharacterRange DVTC99ExtendedIdentifierNonInitialRanges[] = {
    { 0x0030, 0x0039 }, { 0x0660, 0x0669 }, { 0x06F0, 0x06F9 }, { 0x0966, 0x096F }, { 0x09E6, 0x09EF }, { 0x0A66, 0x0A6F },
    { 0x0AE6, 0x0AEF }, { 0x0B66, 0x0B6F }, { 0x0BE7, 0x0BEF }, { 0x0C66, 0x0C6F }, { 0x0CE6, 0x0CEF }, { 0x0D66, 0x0D6F },
    { 0x0E50, 0x0E59 }, { 0x0ED0, 0x0ED9 }, { 0x0F20, 0x0F33 },
};

static const size_t DVTC99ExtendedIdentifierNonInitialRangeCount =
    sizeof(DVTC99ExtendedIdentifierNonInitialRanges) / sizeof(DVTIdentifierCharacterRange);

static inline BOOL DVTCharacterIsInIdentifierRanges(unichar character, const DVTIdentifierCharacterRange *ranges, size_t count)
{
    size_t low = 0;
    size_t high = count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (character < ranges[middle].first) {
            high = middle;
        } else if (character > ranges[middle].last) {
            low = middle + 1;
        } else {
            return YES;
        }
    }
    return NO;
}

/** `YES` when `scalar` may appear in an extended identifier, opening it when `isInitial`. */
static inline BOOL DVTCharacterIsLegalC99ExtendedIdentifierScalar(uint32_t scalar, BOOL isInitial)
{
    if (scalar > 0xFFFF) {
        return NO;
    }
    unichar character = (unichar)scalar;
    if (isInitial && DVTCharacterIsInIdentifierRanges(character, DVTC99ExtendedIdentifierNonInitialRanges, DVTC99ExtendedIdentifierNonInitialRangeCount)) {
        return NO;
    }
    return DVTCharacterIsInIdentifierRanges(character, DVTC99ExtendedIdentifierAllowedRanges, DVTC99ExtendedIdentifierAllowedRangeCount);
}

/** `YES` when `character` is legal in `profile`, opening the identifier when `isInitial`. */
static inline BOOL DVTCharacterIsLegalInIdentifierProfile(unichar character, DVTIdentifierManglingProfile profile, BOOL isInitial)
{
    BOOL uppercase = DVTCharacterIsInASCIIRange(character, 'A', 'Z');
    BOOL lowercase = DVTCharacterIsInASCIIRange(character, 'a', 'z');
    BOOL digit = DVTCharacterIsInASCIIRange(character, '0', '9');
    switch (profile) {
        case DVTIdentifierManglingProfileBundle:
            return (uppercase || lowercase || character == '.' || character == '-') || (!isInitial && digit);
        case DVTIdentifierManglingProfileRFC1034:
            return (uppercase || lowercase || character == '-') || (!isInitial && digit);
        case DVTIdentifierManglingProfileC:
        case DVTIdentifierManglingProfileC99Extended:
            return (uppercase || lowercase || character == '_') || (!isInitial && digit);
    }
    return NO;
}

static inline unichar DVTIdentifierManglingReplacement(DVTIdentifierManglingProfile profile)
{
    switch (profile) {
        case DVTIdentifierManglingProfileBundle:
        case DVTIdentifierManglingProfileRFC1034:
            return '-';
        case DVTIdentifierManglingProfileC:
        case DVTIdentifierManglingProfileC99Extended:
            return '_';
    }
    return '_';
}

/**
 Mangles `string` for `profile`.

 Apple short-circuits an empty receiver before touching the character tables, which is why every
 profile returns `@""` unchanged rather than falling through to its own replacement character.
 */
static NSString *DVTMangledIdentifier(NSString *string, DVTIdentifierManglingProfile profile)
{
    if ([string isEqualToString:@""]) {
        return string;
    }

    // Only the extended profile leaves the receiver composed; the other three canonical-decompose,
    // which is what turns a composed accent into a legal base letter plus a rejected combining mark.
    NSString *decomposed = (profile == DVTIdentifierManglingProfileC99Extended)
        ? string
        : string.decomposedStringWithCanonicalMapping;

    NSUInteger length = decomposed.length;
    unichar replacement = DVTIdentifierManglingReplacement(profile);
    NSMutableString *result = [NSMutableString stringWithCapacity:length];

    if (profile == DVTIdentifierManglingProfileC99Extended) {
        // Per scalar, not per UTF-16 unit: a surrogate pair is one character that is either kept whole
        // or replaced by a single underscore, and a base letter plus combining mark is two decisions.
        NSUInteger index = 0;
        while (index < length) {
            NSUInteger start = index;
            uint32_t scalar = (uint32_t)[decomposed characterAtIndex:index];
            if (scalar >= 0xD800 && scalar <= 0xDFFF) {
                uint32_t low = (scalar <= 0xDBFF && index + 1 < length)
                    ? (uint32_t)[decomposed characterAtIndex:index + 1]
                    : 0;
                if (low >= 0xDC00 && low <= 0xDFFF) {
                    scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00);
                    index += 1;
                } else {
                    // An unpaired surrogate and the code unit after it are copied through verbatim,
                    // then the walk resumes. So ' ' + U+D800 + ' ' comes back as '_' + U+D800 + ' ':
                    // the trailing space is never mangled. It also means a high surrogate swallows
                    // whatever follows it, which is why U+1F600 spelled as two high surrogates and a
                    // low one comes back untouched instead of collapsing to an underscore.
                    NSUInteger run = MIN((NSUInteger)2, length - start);
                    [result appendString:[decomposed substringWithRange:NSMakeRange(start, run)]];
                    index += run;
                    continue;
                }
            }
            index += 1;
            if (DVTCharacterIsLegalC99ExtendedIdentifierScalar(scalar, start == 0)) {
                [result appendString:[decomposed substringWithRange:NSMakeRange(start, index - start)]];
            } else {
                [result appendFormat:@"%C", replacement];
            }
        }
        return result;
    }

    for (NSUInteger index = 0; index < length; index++) {
        unichar character = [decomposed characterAtIndex:index];
        // U+FFFF reads back as end-of-string, so the three decomposing profiles stop there and drop the
        // rest: `a<U+FFFF>b` mangles to `a`, not `a_b`. The extended profile is unaffected, because it
        // never decomposes and never takes this path.
        if (character == 0xFFFF) {
            break;
        }
        if (DVTCharacterIsLegalInIdentifierProfile(character, profile, index == 0)) {
            [result appendFormat:@"%C", character];
        } else {
            [result appendFormat:@"%C", replacement];
        }
    }
    return result;
}

- (BOOL)dvt_isLegalCIdentifier
{
    NSUInteger length = self.length;
    if (length == 0) {
        return NO;
    }
    if (!DVTCharacterIsLegalInIdentifierProfile([self characterAtIndex:0], DVTIdentifierManglingProfileC, YES)) {
        return NO;
    }
    for (NSUInteger index = 1; index < length; index++) {
        if (!DVTCharacterIsLegalInIdentifierProfile([self characterAtIndex:index], DVTIdentifierManglingProfileC, NO)) {
            return NO;
        }
    }
    return YES;
}

- (NSString *)dvt_stringByManglingToLegalCIdentifier
{
    return DVTMangledIdentifier(self, DVTIdentifierManglingProfileC);
}

- (NSString *)dvt_stringByManglingToLegalC99ExtendedIdentifier
{
    return DVTMangledIdentifier(self, DVTIdentifierManglingProfileC99Extended);
}

- (NSString *)dvt_stringByManglingToLegalBundleIdentifier
{
    return DVTMangledIdentifier(self, DVTIdentifierManglingProfileBundle);
}

- (NSString *)dvt_stringByManglingToLegalRFC1034Identifier
{
    return DVTMangledIdentifier(self, DVTIdentifierManglingProfileRFC1034);
}

- (NSString *)dvt_stringByManglingToLegalIdentifierOfType:(NSInteger)identifierType
{
    switch (identifierType) {
        case 0:
            return [self dvt_stringByManglingToLegalBundleIdentifier];
        case 1:
            return [self dvt_stringByManglingToLegalRFC1034Identifier];
        default:
            // No assert on an unknown type: Apple falls through to the strict C mangling, so 2, -1
            // and 8 all behave like dvt_stringByManglingToLegalCIdentifier.
            return [self dvt_stringByManglingToLegalCIdentifier];
    }
}

- (NSRange)dvt_interiorRangeAfterTrimmingCharactesFromSet:(NSCharacterSet *)set
{
    NSUInteger length = self.length;
    if (length == 0) {
        return NSMakeRange(0, 0);
    }
    NSUInteger start = 0;
    while (start < length && [set characterIsMember:[self characterAtIndex:start]]) {
        start++;
    }
    NSUInteger end = length;
    while (end > start && [set characterIsMember:[self characterAtIndex:end - 1]]) {
        end--;
    }
    // Trimming everything answers the empty range at the start rather than the fully-trimmed one.
    NSUInteger trimmedLength = end - start;
    return trimmedLength == 0 ? NSMakeRange(0, 0) : NSMakeRange(start, trimmedLength);
}

- (NSRange)dvt_interiorRangeAfterTrimmingCharactesFromSet:(NSCharacterSet *)set preservingRange:(NSRange)preservedRange
{
    if (preservedRange.location == NSNotFound) {
        return [self dvt_interiorRangeAfterTrimmingCharactesFromSet:set];
    }
    NSUInteger length = self.length;
    DVTAssert(NSMaxRange(preservedRange) <= length, @"DVTMaxRange(preservedRange) <= length", nil,
              @"%lu <= %lu", (unsigned long)NSMaxRange(preservedRange), (unsigned long)length);
    if (length == 0) {
        return NSMakeRange(0, 0);
    }
    // Only characters outside `preservedRange` are dropped: leading characters up to its location,
    // trailing characters after its end. The range itself is never trimmed into.
    NSUInteger start = 0;
    while (start < preservedRange.location && [set characterIsMember:[self characterAtIndex:start]]) {
        start++;
    }
    NSUInteger end = length;
    NSUInteger preservedEnd = NSMaxRange(preservedRange);
    while (end > preservedEnd && [set characterIsMember:[self characterAtIndex:end - 1]]) {
        end--;
    }
    DVTAssert(start <= end, @"start <= end", nil, @"%lu <= %lu", (unsigned long)start, (unsigned long)end);
    return NSMakeRange(start, end - start);
}

- (NSRange)dvt_fullRange
{
    return NSMakeRange(0, self.length);
}

- (NSRange)dvt_prefixRangeOfLength:(NSInteger)length
{
    return NSMakeRange(0, length);
}

- (NSRange)dvt_suffixRangeOfLength:(NSInteger)length
{
    return NSMakeRange(self.length - length, length);
}

- (NSRange)dvt_suffixRangeFromIndex:(NSInteger)index
{
    return NSMakeRange(index, self.length - index);
}

@end

@implementation NSObject (DVTObservingConvenience)

- (void)dvt_changeValueForKey:(NSString *)key usingBlock:(void (^)(void))block
{
    /* Disassembly: retain the two arguments, send willChangeValueForKey:, branch
       straight to the block's invoke pointer, release the block, then send
       didChangeValueForKey:. Nothing is checked, so a nil block faults on the load
       of its invoke pointer exactly as the binary does. */
    [self willChangeValueForKey:key];
    block();
    [self didChangeValueForKey:key];
}

- (void)dvt_changeValueForKeys:(NSArray *)keys usingBlock:(void (^)(void))block
{
    /* The binary enumerates `keys` forward for the opening notifications, calls the
       block once, and then enumerates a fresh -reverseObjectEnumerator for the
       closing ones. Two separate enumerations rather than one walk in reverse, so a
       repeated key is announced on both sides and the closing order is the exact
       reverse of the opening order. */
    for (NSString *key in keys) {
        [self willChangeValueForKey:key];
    }
    block();
    for (NSString *key in [keys reverseObjectEnumerator]) {
        [self didChangeValueForKey:key];
    }
}

+ (void)dvt_cancelAllObservingTokensForOwner:(id)owner
{
    /* The body is an assertion and a soft assertion and then nothing: no token is
       cancelled. The warning carries "Unsupported API. There is no replacement." from
       DVTNSKeyValueObserving.m line 937, but Apple's -handleWarningInMethod: logs only
       through +assertionLoggingAspect and returns silently when no aspect is installed,
       which is every process outside Xcode. Routing it through the local handler would
       print a report Apple does not make, so the observable answer is no output at all. */
    (void)owner;
}

+ (NSArray *)dvt_creationBacktracesOfObservingTokensForObservedObject:(id)object
{
    /* The binary loads ___NSArray0__struct and returns without reading the argument. */
    (void)object;
    return @[];
}

+ (NSString *)dvt_keyPathOnSelfForUserDefaultsKey:(NSString *)key
{
    return [@"_dvt_standardUserDefaultsProxy." stringByAppendingString:key];
}

@end

/* The key under which the recovery block supplied to
   +dvt_errorWithDomain:errorCode:message:recoverySuggestion:recoveryOptions:
   andRecoveryBlock: (and its instance twin, -dvt_errorBySettingRecoveryOptions:
   andRecoveryBlock:) is stored. Apple's binary exports the symbol
   (_DVTRecoveryBlockKey), so it is declared in the header and defined here
   rather than hidden away as a translation-unit literal. */
NSString *const DVTRecoveryBlockKey = @"DVTRecoveryBlockKey";

/* The recovery attempter installed under NSRecoveryAttempterErrorKey whenever an
   error carries a recovery block. Apple names it, but privately: it appears in
   the binary only as _OBJC_CLASS_$__DVTErrorRecoveryHandler with these two
   methods, so it is declared and implemented here instead of in the header. */
@interface _DVTErrorRecoveryHandler : NSObject

- (BOOL)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)optionIndex;
- (void)attemptRecoveryFromError:(NSError *)error
                     optionIndex:(NSUInteger)optionIndex
                        delegate:(nullable id)delegate
              didRecoverSelector:(nullable SEL)didRecoverSelector
                     contextInfo:(nullable void *)contextInfo;

@end

@implementation _DVTErrorRecoveryHandler

- (BOOL)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)optionIndex
{
    /* The whole contract: look up the stored block under DVTRecoveryBlockKey and
       invoke it with the error and the chosen option. The block's answer is the
       answer. */
    BOOL (^block)(NSError *, NSUInteger) = error.userInfo[DVTRecoveryBlockKey];
    return block(error, optionIndex);
}

- (void)attemptRecoveryFromError:(NSError *)error
                     optionIndex:(NSUInteger)optionIndex
                        delegate:(id)delegate
              didRecoverSelector:(SEL)didRecoverSelector
                     contextInfo:(void *)contextInfo
{
    /* Recover first, then report. A nil delegate is the ordinary "nobody is
       listening" case and returns quietly; a NULL or unhandled selector is a
       programming error and asserts, at lines 42 and 43 of Apple's
       DVTNSErrorAdditions.m. The delegate callback is a raw message send because
       the selector is supplied by the caller. */
    BOOL recovered = [self attemptRecoveryFromError:error optionIndex:optionIndex];
    if (delegate == nil) {
        return;
    }
    DVTAssert(didRecoverSelector != NULL, @"((didRecoverSelector)) != nil", nil, @"%@ should not be nil.",
              @"(didRecoverSelector)");
    DVTAssert([delegate respondsToSelector:didRecoverSelector],
              @"[delegate respondsToSelector:didRecoverSelector]", nil,
              @"Delegate must respond to provided selector %@", NSStringFromSelector(didRecoverSelector));
    ((void (*)(id, SEL, BOOL, void *))objc_msgSend)(delegate, didRecoverSelector, recovered, contextInfo);
}

@end

@implementation NSError (DVTFoundationClassAdditions)

+ (NSError *)dvt_errorWithDomain:(NSString *)domain
                       errorCode:(NSInteger)errorCode
                   messageFormat:(NSString *)messageFormat, ...
{
    /* A pure forwarder: va_start at the first variadic slot, pass the va_list
       on to the arguments: twin, va_end. The binary's body is those three steps
       and nothing else -- the rendering lives in the twin. */
    va_list args;
    va_start(args, messageFormat);
    NSError *error = [self dvt_errorWithDomain:domain
                                     errorCode:errorCode
                                 messageFormat:messageFormat
                                     arguments:args];
    va_end(args);
    return error;
}

+ (NSError *)dvt_errorWithDomain:(NSString *)domain
                       errorCode:(NSInteger)errorCode
                   messageFormat:(NSString *)messageFormat
                       arguments:(va_list)args
{
    /* The whole of userInfo is one entry: the message rendered from the format
       and the caller's va_list, under NSLocalizedDescriptionKey. The binary
       spells it out as -initWithFormat:arguments:, a one-entry
       dictionaryWithObjects:forKeys:count:, and +errorWithDomain:code:userInfo:,
       in that order. */
    NSString *message = [[NSString alloc] initWithFormat:messageFormat arguments:args];
    return [NSError errorWithDomain:domain
                               code:errorCode
                           userInfo:@{ NSLocalizedDescriptionKey : message }];
}

+ (NSError *)dvt_errorWithMessage:(NSString *)message
{
    /* A fixed private domain and code, with the message as the sole entry under
       NSLocalizedDescriptionKey -- the same one-entry shape the twin builds, just
       with the domain hardcoded rather than supplied. */
    return [NSError errorWithDomain:@"com.apple.DVTFoundation"
                               code:-1
                           userInfo:@{ NSLocalizedDescriptionKey : message }];
}

+ (NSError *)dvt_errorWithFormat:(NSString *)format, ...
{
    /* Render the format with a fresh va_list and hand the string to
       dvt_errorWithMessage:; the binary routes through a one-entry
       -initWithFormat:arguments: and nothing else. */
    va_list args;
    va_start(args, format);
    NSError *error = [NSError dvt_errorWithMessage:[[NSString alloc] initWithFormat:format arguments:args]];
    va_end(args);
    return error;
}

+ (NSError *)dvt_errorWithPOSIXErrorCode:(int)errorCode messageFormat:(NSString *)messageFormat, ...
{
    /* The description is the caller's formatted message; the failure reason is
       strerror(errorCode) for the same code. The binary builds both strings, a
       two-entry dictionaryWithObjects:forKeys:count:, and an NSError in
       NSPOSIXErrorDomain. */
    va_list args;
    va_start(args, messageFormat);
    NSString *message = [[NSString alloc] initWithFormat:messageFormat arguments:args];
    va_end(args);
    NSString *reason = [[NSString alloc] initWithUTF8String:strerror(errorCode)];
    return [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:errorCode
                           userInfo:@{ NSLocalizedDescriptionKey : message,
                                       NSLocalizedFailureReasonErrorKey : reason }];
}

+ (NSError *)dvt_errorWithPOSIXErrorCode:(int)errorCode
{
    /* No message is supplied, so strerror's text stands in for both the
       description and the failure reason -- the same string under both keys. */
    NSString *reason = [[NSString alloc] initWithUTF8String:strerror(errorCode)];
    return [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:errorCode
                           userInfo:@{ NSLocalizedDescriptionKey : reason,
                                       NSLocalizedFailureReasonErrorKey : reason }];
}

+ (NSError *)dvt_errorWithDomain:(NSString *)domain
                       errorCode:(NSInteger)errorCode
                         message:(NSString *)message
              recoverySuggestion:(NSString *)recoverySuggestion
{
    /* A forwarder onto the underlyingError: twin with no underlying error; the
       binary tail-calls it with a nil sixth argument. */
    return [NSError dvt_errorWithDomain:domain
                              errorCode:errorCode
                                message:message
                     recoverySuggestion:recoverySuggestion
                        underlyingError:nil];
}

+ (NSError *)dvt_errorWithDomain:(NSString *)domain
                       errorCode:(NSInteger)errorCode
                         message:(NSString *)message
                   failureReason:(NSString *)failureReason
{
    /* Description and failure reason only. The binary assembles them through
       dvt_dictionaryWithKeysAndValues: and hangs the result off
       +errorWithDomain:code:userInfo:. */
    return [NSError errorWithDomain:domain
                               code:errorCode
                           userInfo:[NSDictionary dvt_dictionaryWithKeysAndValues:
                                     NSLocalizedDescriptionKey, message,
                                     NSLocalizedFailureReasonErrorKey, failureReason, nil]];
}

+ (NSError *)dvt_errorWithDomain:(NSString *)domain
                       errorCode:(NSInteger)errorCode
                         message:(NSString *)message
              recoverySuggestion:(NSString *)recoverySuggestion
                 underlyingError:(nullable NSError *)underlyingError
{
    /* Description, recovery suggestion and the wrapped error, in that key order,
       through dvt_dictionaryWithKeysAndValues: (which drops any nil pair, so a
       nil underlying error simply leaves the key out). */
    return [NSError errorWithDomain:domain
                               code:errorCode
                           userInfo:[NSDictionary dvt_dictionaryWithKeysAndValues:
                                     NSLocalizedDescriptionKey, message,
                                     NSLocalizedRecoverySuggestionErrorKey, recoverySuggestion,
                                     NSUnderlyingErrorKey, underlyingError, nil]];
}

+ (NSError *)dvt_errorWithDomain:(NSString *)domain
                       errorCode:(NSInteger)errorCode
                         message:(NSString *)message
              recoverySuggestion:(NSString *)recoverySuggestion
                   failureReason:(NSString *)failureReason
                 underlyingError:(NSError *)underlyingError
{
    /* The full four-key userInfo: description, failure reason, recovery
       suggestion and underlying error, in that order, through
       dvt_dictionaryWithKeysAndValues: (a nil value simply drops its pair). */
    return [NSError errorWithDomain:domain
                               code:errorCode
                           userInfo:[NSDictionary dvt_dictionaryWithKeysAndValues:
                                     NSLocalizedDescriptionKey, message,
                                     NSLocalizedFailureReasonErrorKey, failureReason,
                                     NSLocalizedRecoverySuggestionErrorKey, recoverySuggestion,
                                     NSUnderlyingErrorKey, underlyingError, nil]];
}

+ (NSError *)dvt_errorWithMessage:(NSString *)message
               recoverySuggestion:(NSString *)recoverySuggestion
                  underlyingError:(NSError *)underlyingError
{
    /* The domainless spelling: the fixed com.apple.DVTFoundation -1 of
       dvt_errorWithMessage:, plus the recovery suggestion and underlying error. */
    return [NSError dvt_errorWithDomain:@"com.apple.DVTFoundation"
                              errorCode:-1
                                message:message
                     recoverySuggestion:recoverySuggestion
                        underlyingError:underlyingError];
}

+ (NSError *)dvt_errorWithDomain:(NSString *)domain
                       errorCode:(NSInteger)errorCode
                         message:(NSString *)message
              recoverySuggestion:(NSString *)recoverySuggestion
                 recoveryOptions:(NSArray *)recoveryOptions
                andRecoveryBlock:(BOOL (^)(NSError *error, NSInteger optionIndex))recoveryBlock
{
    /* The recovery-capable builder: alongside the description and suggestion it
       stores the options under NSLocalizedRecoveryOptionsErrorKey, a copy of the
       block under DVTRecoveryBlockKey, and a fresh _DVTErrorRecoveryHandler under
       NSRecoveryAttempterErrorKey so AppKit has something to message when the
       user picks an option. The binary allocates and initializes the handler
       inline. */
    NSDictionary *userInfo = [NSDictionary dvt_dictionaryWithKeysAndValues:
        NSLocalizedDescriptionKey, message,
        NSLocalizedRecoverySuggestionErrorKey, recoverySuggestion,
        NSLocalizedRecoveryOptionsErrorKey, recoveryOptions,
        DVTRecoveryBlockKey, [recoveryBlock copy],
        NSRecoveryAttempterErrorKey, [[_DVTErrorRecoveryHandler alloc] init],
        nil];
    return [NSError errorWithDomain:domain code:errorCode userInfo:userInfo];
}

- (NSError *)dvt_errorBySettingRecoveryOptions:(NSArray *)recoveryOptions
                              andRecoveryBlock:(BOOL (^)(NSError *error, NSInteger optionIndex))recoveryBlock
{
    /* The instance twin of the builder above: wrap the options, a copied block
       and a handler in a three-entry dictionary and merge it into this error's
       userInfo (the merge, not a rebuild, is why existing entries survive). */
    id objects[] = { [recoveryBlock copy], recoveryOptions, [[_DVTErrorRecoveryHandler alloc] init] };
    id<NSCopying> keys[] = { DVTRecoveryBlockKey, NSLocalizedRecoveryOptionsErrorKey, NSRecoveryAttempterErrorKey };
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjects:objects forKeys:keys count:3];
    return [self dvt_errorByInjectingUserInfoObjects:userInfo];
}

- (NSError *)dvt_errorByInjectingUserInfoObject:(id)object forKey:(id)key
{
    /* Copy with one userInfo entry added (or replaced), preserving domain and
       code. */
    NSDictionary *userInfo = [self.userInfo dvt_dictionaryBySettingObject:object forKey:key];
    return [NSError errorWithDomain:self.domain code:self.code userInfo:userInfo];
}

- (NSError *)dvt_errorByInjectingUserInfoObjects:(NSDictionary *)objects
{
    /* Copy with a whole dictionary merged into the userInfo, the newer entries
       winning. */
    NSDictionary *userInfo = [self.userInfo dvt_dictionaryByAddingEntriesFromDictionary:objects];
    return [NSError errorWithDomain:self.domain code:self.code userInfo:userInfo];
}

- (BOOL)dvt_hasDomain:(NSString *)domain errorCode:(NSInteger)errorCode
{
    /* Domain and code must both match; a nil domain can never be equal to a
       string, so a nil-domain error simply fails the test. */
    return [self.domain isEqualToString:domain] && self.code == errorCode;
}

- (BOOL)dvt_isNoSuchFileError
{
    /* The file-not-found family: NSFileReadNoSuchFileError (260) and
       NSFileNoSuchFileError (4) in NSCocoaErrorDomain, plus ENOENT (2) in
       NSPOSIXErrorDomain. The code is tried as a domain/code pair because the
       same number means different things per domain. */
    if ([self dvt_hasDomain:NSCocoaErrorDomain errorCode:260]) {
        return YES;
    }
    if ([self dvt_hasDomain:NSCocoaErrorDomain errorCode:4]) {
        return YES;
    }
    return [self dvt_hasDomain:NSPOSIXErrorDomain errorCode:2];
}

- (BOOL)dvt_isFileExistsError
{
    /* NSFileWriteFileExistsError (516) is the only spelling the binary accepts
       here. */
    return [self dvt_hasDomain:NSCocoaErrorDomain errorCode:516];
}

+ (NSError *)dvt_userCancelledError
{
    /* The canonical user-cancelled error: NSCocoaErrorDomain, NSUserCancelledError
       (3072), no userInfo. */
    return [NSError errorWithDomain:NSCocoaErrorDomain code:3072 userInfo:nil];
}

- (BOOL)dvt_isUserCancelledError
{
    return [self dvt_hasDomain:NSCocoaErrorDomain errorCode:3072];
}

- (NSDictionary *)dvt_propertyListDictionary
{
    /* A plist-safe projection of the four fields that round-trip through
       dvt_errorFromPropertyList:. The first three are always present; the
       recovery suggestion is only written when non-nil, and the result is
       returned immutable via -copy. */
    id objects[] = { self.domain, @(self.code), self.localizedDescription };
    id<NSCopying> keys[] = { @"domain", @"code", @"description" };
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithDictionary:
        [NSDictionary dictionaryWithObjects:objects forKeys:keys count:3]];
    [dictionary dvt_setObjectIfNonNil:self.localizedRecoverySuggestion forKey:@"recoverySuggestion"];
    return [dictionary copy];
}

+ (NSError *)dvt_errorFromPropertyList:(NSDictionary *)propertyList
{
    /* The inverse of -dvt_propertyListDictionary. Missing string fields default
       to the empty string rather than nil, and a missing code reads as 0 via the
       nil-tolerant dvt_numberOrNilForKey:. */
    NSString *domain = [propertyList dvt_stringOrNilForKey:@"domain"] ?: @"";
    NSInteger code = [[propertyList dvt_numberOrNilForKey:@"code"] integerValue];
    NSString *message = [propertyList dvt_stringOrNilForKey:@"description"] ?: @"";
    NSString *recoverySuggestion = [propertyList dvt_stringOrNilForKey:@"recoverySuggestion"] ?: @"";
    return [NSError dvt_errorWithDomain:domain
                              errorCode:code
                                message:message
                     recoverySuggestion:recoverySuggestion];
}

- (id)dvt_recursivelyRetrieveObjectForUserInfoKey:(id)key
{
    /* Walk this error's userInfo and then, if the key is absent, every
       underlying error's userInfo in turn. The first hit wins; a missing key
       with no underlying error yields nil. */
    id object = self.userInfo[key];
    if (object) {
        return object;
    }
    id underlyingError = self.userInfo[NSUnderlyingErrorKey];
    return [underlyingError dvt_recursivelyRetrieveObjectForUserInfoKey:key];
}

- (BOOL)dvt_selfOrUnderlyingErrorMatchesBlock:(BOOL (^)(NSError *error))block
{
    /* Test this error, then each underlying error, until one matches. The block
       is applied to the error object itself, not to any particular field. */
    if (block(self)) {
        return YES;
    }
    id underlyingError = self.userInfo[NSUnderlyingErrorKey];
    if (underlyingError) {
        return [underlyingError dvt_selfOrUnderlyingErrorMatchesBlock:block];
    }
    return NO;
}

@end

/** Renders one calendar-component difference for
    -dvt_mostSignificantDateComponentStringRelativeToToday. A positive value is
    in the past ("N <unit> ago"); a negative one is in the future ("In N
    <unit>"), spelled with the magnitude. `singular` is used when the magnitude
    is exactly one. */
static NSString *DVTDateComponentString(NSInteger value, NSString *singular, NSString *plural)
{
    NSString *unit = (value == 1 || value == -1) ? singular : plural;
    if (value >= 1) {
        return [NSString stringWithFormat:@"%ld %@ ago", (long)value, unit];
    }
    return [NSString stringWithFormat:@"In %ld %@", (long)(-value), unit];
}

@implementation NSDate (DVTFoundationClassAdditions)

- (NSString *)dvt_dateStringRelativeToTodayWithDateStyle:(NSDateFormatterStyle)style timeStyle:(NSDateFormatterStyle)timeStyle
{
    /* Defaults: capitalize the relative word, and join with " at ". */
    return [self dvt_dateStringRelativeToTodayWithDateStyle:style
                                                  timeStyle:timeStyle
                                      capitalizeFirstLetter:YES];
}

- (NSString *)dvt_dateStringRelativeToTodayWithDateStyle:(NSDateFormatterStyle)style timeStyle:(NSDateFormatterStyle)timeStyle capitalizeFirstLetter:(BOOL)capitalizeFirstLetter
{
    /* Defaults: the " at " join rather than the comma. */
    return [self dvt_dateStringRelativeToTodayWithDateStyle:style
                                                  timeStyle:timeStyle
                                      capitalizeFirstLetter:capitalizeFirstLetter
                                           seperateWithComma:NO];
}

- (NSString *)dvt_dateStringRelativeToTodayWithDateStyle:(NSDateFormatterStyle)style timeStyle:(NSDateFormatterStyle)timeStyle capitalizeFirstLetter:(BOOL)capitalizeFirstLetter seperateWithComma:(BOOL)seperateWithComma
{
    /* Round "now" down to midnight and bracket it by the previous and next
       midnight. A date inside the current day renders as "today", one inside the
       previous day as "yesterday"; both honour the desired capitalization. Any
       other date falls back to the supplied date style. The time is always the
       supplied time style, joined either with a comma or with " at ". */
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    NSDateComponents *nowComponents = [calendar components:(NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear)
                                                 fromDate:now];
    NSDate *todayMidnight = [calendar dateFromComponents:nowComponents];
    NSTimeInterval todayMidnightInterval = [todayMidnight timeIntervalSinceReferenceDate];

    NSDateComponents *offset = [[NSDateComponents alloc] init];
    [offset setDay:-1];
    NSDate *yesterdayMidnight = [calendar dateByAddingComponents:offset toDate:todayMidnight options:0];
    NSTimeInterval yesterdayMidnightInterval = [yesterdayMidnight timeIntervalSinceReferenceDate];

    [offset setDay:2];
    NSDate *tomorrowMidnight = [calendar dateByAddingComponents:offset toDate:yesterdayMidnight options:0];
    NSTimeInterval tomorrowMidnightInterval = [tomorrowMidnight timeIntervalSinceReferenceDate];

    NSTimeInterval selfInterval = [self timeIntervalSinceReferenceDate];

    NSString *dateString;
    if (selfInterval >= todayMidnightInterval && selfInterval < tomorrowMidnightInterval) {
        dateString = capitalizeFirstLetter ? @"Today" : @"today";
    } else if (selfInterval >= yesterdayMidnightInterval && selfInterval < todayMidnightInterval) {
        dateString = capitalizeFirstLetter ? @"Yesterday" : @"yesterday";
    } else {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:style];
        dateString = [dateFormatter stringFromDate:self];
    }

    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
    [timeFormatter setTimeStyle:timeStyle];
    NSString *timeString = [timeFormatter stringFromDate:self];

    return [dateString stringByAppendingFormat:(seperateWithComma ? @", %@" : @" at %@"), timeString];
}

- (NSString *)dvt_descriptionWithDateFormat:(NSString *)format
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:format];
    return [formatter stringFromDate:self];
}

- (NSString *)dvt_mostSignificantDateComponentStringRelativeToToday
{
    /* Today/yesterday/tomorrow are named directly. Otherwise the date is reduced
       to a single calendar component -- year, else month, else week, else day --
       measured between this date and now, and rendered as "N <unit> ago" for a
       past date or "In N <unit>" for a future one. The unit is singular only for
       a magnitude of exactly one; a zero-length difference reads as "Today". */
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];

    if ([calendar isDateInYesterday:self]) {
        return @"Yesterday";
    }
    if ([calendar isDateInTomorrow:self]) {
        return @"Tomorrow";
    }
    if ([calendar isDateInToday:self]) {
        return @"Today";
    }

    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitWeekOfYear | NSCalendarUnitDay)
                                               fromDate:self
                                                 toDate:now
                                                options:0];

    if (components.year != 0) {
        return DVTDateComponentString(components.year, @"year", @"years");
    }
    if (components.month != 0) {
        return DVTDateComponentString(components.month, @"month", @"months");
    }
    if (components.weekOfYear != 0) {
        return DVTDateComponentString(components.weekOfYear, @"week", @"weeks");
    }
    if (components.day != 0) {
        return DVTDateComponentString(components.day, @"day", @"days");
    }
    return @"Today";
}

- (BOOL)dvt_isInThePast
{
    return [self timeIntervalSinceNow] < 0.0;
}

@end

@implementation NSInputStream (DVTFoundationClassAdditions)

- (unsigned long long)dvt_readUnsignedLEB128Integer
{
    unsigned long long result = 0;
    unsigned int shift = 0;
    uint8_t byte;
    while (shift < 64) {
        if ([self read:(uint8_t *)&byte maxLength:1] != 1) {
            break;
        }
        result |= ((unsigned long long)(byte & 0x7F)) << shift;
        if ((byte & 0x80) == 0) {
            return result;
        }
        shift += 7;
    }
    return result;
}

- (long long)dvt_readSignedLEB128Integer
{
    long long result = 0;
    unsigned int shift = 0;
    uint8_t byte;
    while (shift < 64) {
        if ([self read:(uint8_t *)&byte maxLength:1] != 1) {
            break;
        }
        result |= ((long long)(byte & 0x7F)) << shift;
        if ((byte & 0x80) == 0) {
            if ((byte & 0x40) != 0 && shift < 63) {
                result |= (~0LL) << (shift + 7);
            }
            return result;
        }
        shift += 7;
    }
    return result;
}

@end

@implementation NSOutputStream (DVTFoundationClassAdditions)

- (void)dvt_writeUnsignedLEB128Integer:(unsigned long long)value
{
    uint8_t byte;
    do {
        byte = value & 0x7F;
        value >>= 7;
        if (value != 0) {
            byte |= 0x80;
        }
        NSUInteger written = [self write:&byte maxLength:1];
        if (written != 1) {
            DVTAssert(NO, @"failed to write LEB128 byte", nil, @"Failed to write a byte for LEB128 encoding");
            break;
        }
    } while (value != 0);
}

- (void)dvt_writeSignedLEB128Integer:(long long)value
{
    BOOL more;
    do {
        uint8_t byte = value & 0x7F;
        value >>= 7;
        more = !((value == 0 && (byte & 0x40) == 0) || (value == -1 && (byte & 0x40) != 0));
        if (more) {
            byte |= 0x80;
        }
        NSUInteger written = [self write:&byte maxLength:1];
        if (written != 1) {
            DVTAssert(NO, @"failed to write LEB128 byte", nil, @"Failed to write a byte for LEB128 encoding");
            break;
        }
    } while (more);
}

@end

@implementation NSMutableString (DVTFoundationClassAdditions)

- (void)dvt_replaceCharactersFromSet:(NSCharacterSet *)set inRange:(NSRange)range withString:(NSString *)string
{
    if (range.length == 0) {
        return;
    }
    // Repeatedly replace the next run of characters from `set`, advancing past each inserted string
    // so a replacement that itself contains those characters is not replaced again.
    NSUInteger location = range.location;
    NSUInteger end = NSMaxRange(range);
    for (;;) {
        NSRange found = [self rangeOfCharacterFromSet:set options:0 range:NSMakeRange(location, end - location)];
        if (found.location == NSNotFound) {
            break;
        }
        [self replaceCharactersInRange:found withString:string];
        location = found.location + string.length;
        end += string.length - found.length;
        if (location == end) {
            break;
        }
    }
}

- (void)dvt_trimCharactesFromSet:(NSCharacterSet *)set preservingRange:(NSRange)range
{
    NSRange interior = [self dvt_interiorRangeAfterTrimmingCharactesFromSet:set preservingRange:range];
    NSUInteger interiorEnd = NSMaxRange(interior);
    [self deleteCharactersInRange:NSMakeRange(interiorEnd, self.length - interiorEnd)];
    [self deleteCharactersInRange:NSMakeRange(0, interior.location)];
}

/**
 Standardizes the line endings of `self` in `range` to `ending`: `1` is a line feed, `2` a carriage
 return, and `3` a carriage return followed by a line feed; anything else is a no-op.
 */
static void DVTStandardizeLineEnding(NSMutableString *self, unsigned long long ending, NSUInteger location, NSUInteger length)
{
    NSString *replacement = nil;
    switch (ending) {
        case 1:
            replacement = @"\n";
            break;
        case 2:
            replacement = @"\r";
            break;
        case 3:
            replacement = @"\r\n";
            break;
        default:
            return;
    }
    NSUInteger end = location + length;
    if (location >= end) {
        return;
    }
    // Walk one line at a time. Only a line's terminator is compared and replaced, and only when it
    // does not already match `ending` case-insensitively. The running `length` absorbs any change in
    // terminator width so the walk stays aligned.
    NSUInteger replacementLength = replacement.length;
    NSUInteger cursor = location;
    do {
        NSUInteger lineStart = 0;
        NSUInteger lineEnd = 0;
        NSUInteger contentsEnd = 0;
        [self getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(cursor, 1)];
        NSUInteger terminatorLength = lineEnd - contentsEnd;
        if (terminatorLength != 0 &&
            [self compare:replacement options:NSCaseInsensitiveSearch range:NSMakeRange(contentsEnd, terminatorLength) locale:nil] != NSOrderedSame) {
            [self replaceCharactersInRange:NSMakeRange(contentsEnd, terminatorLength) withString:replacement];
            NSUInteger delta = replacementLength - terminatorLength;
            if (delta != 0) {
                lineEnd += delta;
                length += delta;
            }
        }
        cursor = lineEnd;
        end = location + length;
    } while (cursor < end);
}

- (void)dvt_standardizeWithLineEnding:(unsigned long long)ending range:(NSRange)range
{
    if (NSMaxRange(range) > self.length) {
        NSString *proem = [NSString stringWithFormat:@"-[%@ %@]", [self class], NSStringFromSelector(_cmd)];
        [NSException raise:NSRangeException format:@"%@: Range or index out of bounds", proem];
    }
    DVTStandardizeLineEnding(self, ending, range.location, range.length);
}

- (void)dvt_standardizeWithLineEnding:(unsigned long long)ending
{
    [self dvt_standardizeWithLineEnding:ending range:NSMakeRange(0, self.length)];
}

@end

@implementation NSXMLElement (DVTFoundationClassAdditions)

+ (NSXMLElement *)dvt_elementWithXMLStringByPreservingWhitespace:(NSString *)xmlString error:(NSError **)error
{
    /* Parse with NSXMLNodePreserveWhitespace so the document keeps the source
       formatting, then hand back the root element detached from its document.
       A parse failure propagates through `error` and yields nil. */
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:xmlString
                                                              options:NSXMLNodePreserveWhitespace
                                                                error:error];
    if (document == nil) {
        return nil;
    }
    NSXMLElement *root = [document rootElement];
    [root detach];
    return root;
}

- (NSArray *)dvt_elementsApplicableForCurrentRuntimeOSVersion
{
    /* Filter the direct children down to elements (kind 2) whose
       minimumRequiredRuntimeOSVersion attribute the running OS satisfies. */
    return [[self children] dvt_objectsPassingTest:^BOOL(NSXMLElement *element) {
        if ([element kind] != NSXMLElementKind) {
            return NO;
        }
        return [element dvt_isApplicableForCurrentRuntimeOSVersion];
    }];
}

- (NSArray *)dvt_elementsApplicableForCurrentRuntimeOSVersionForName:(NSString *)name
{
    /* Same test as above, but restricted to the named children. */
    return [[self elementsForName:name] dvt_objectsPassingTest:^BOOL(NSXMLElement *element) {
        return [element dvt_isApplicableForCurrentRuntimeOSVersion];
    }];
}

- (BOOL)dvt_isApplicableForCurrentRuntimeOSVersion
{
    /* A lone minimumRequiredRuntimeOSVersion attribute gates applicability: an
       absent attribute, or one whose value parses to 0, means "always". Otherwise
       the value is an availability form integer and the element applies when it is
       not newer than the running system's form. The availability form is the
       DVTVersion encoding used elsewhere for exactly this comparison. */
    NSXMLNode *attribute = [self attributeForName:@"minimumRequiredRuntimeOSVersion"];
    if (attribute == nil) {
        return YES;
    }
    NSInteger minimumRequired = [[attribute stringValue] integerValue];
    if (minimumRequired == 0) {
        return YES;
    }
    return (NSUInteger)minimumRequired <= [[DVTVersion currentSystemVersion] availabilityFormIncludingUpdate:YES];
}

@end

/*
 NSData and NSMutableData can be handed to C code that speaks stdio. Each stream
 is a funopen(3) handle whose cookie is the reader/writer context below: the data
 (owned for the stream's lifetime), a cursor, and the `FILE *` itself. Reading an
 immutable NSData points the FILE's buffer straight at the data's own bytes so no
 copying happens; reading a mutable NSData copies out of it, and writing grows the
 data as needed.
 */

typedef struct DVTNSDataStdIOContext {
    FILE *file;
    __unsafe_unretained NSData *data;
    fpos_t offset;
} DVTNSDataStdIOContext;

/**
 Validates `context` and its invariants, mirroring the checks the callbacks make
 on entry: a null cookie reports `EBADF`, while a context that is missing its FILE
 or data is a programming error and fails an assertion.
 */
static BOOL DVTNSDataStdIOContextIsValid(DVTNSDataStdIOContext *context)
{
    if (context == NULL) {
        errno = EBADF;
        return NO;
    }
    DVTAssert(context->file != NULL, @"context->file != ((void*)0)", nil, @"");
    DVTAssert(context->data != nil, @"context->data != nil", nil, @"");
    return YES;
}

/**
 `funopen` read callback for an immutable NSData. The immutable bytes need no
 copying: the data is exposed to the stream by pointing the FILE's buffer at the
 not-yet-consumed span, so the stdio layer serves reads directly from it.
 */
static int DVTNSDataRead(void *cookie, char *buffer, int size)
{
    DVTNSDataStdIOContext *context = cookie;
    if (!DVTNSDataStdIOContextIsValid(context)) {
        return -1;
    }
    /* `buffer` and `size` are deliberately unused: the data itself becomes the
       stream's buffer, which is why the size is capped rather than the read
       being copied into the caller's buffer. */
    NSUInteger length = context->data.length;
    DVTAssert((NSUInteger)context->offset <= length, @"offset <= length", nil, @"");
    NSUInteger remaining = length - (NSUInteger)context->offset;
    if (remaining == 0) {
        return 0;
    }
    if (remaining > INT_MAX) {
        remaining = INT_MAX;
    }
    int available = (int)remaining;
    if (setvbuf(context->file, (char *)context->data.bytes + context->offset, _IOFBF, remaining) != 0) {
        return -1;
    }
    context->offset += available;
    DVTAssert((NSUInteger)context->offset <= length, @"offset <= length", nil, @"");
    return available;
}

/**
 `funopen` read callback for a mutable NSData, which copies out of the backing
 store into the caller's buffer because its bytes may move as it grows.
 */
static int DVTNSMutableDataRead(void *cookie, char *buffer, int size)
{
    DVTNSDataStdIOContext *context = cookie;
    if (!DVTNSDataStdIOContextIsValid(context)) {
        return -1;
    }
    NSUInteger length = context->data.length;
    NSUInteger offset = (NSUInteger)context->offset;
    DVTAssert(offset <= length, @"offset <= length", nil, @"");
    NSUInteger remaining = length - offset;
    if (remaining == 0) {
        return 0;
    }
    NSUInteger count = (NSUInteger)size;
    if (offset + count > length) {
        count = remaining > INT_MAX ? INT_MAX : remaining;
    }
    [context->data getBytes:buffer range:NSMakeRange(offset, count)];
    context->offset = (fpos_t)(offset + count);
    DVTAssert((NSUInteger)context->offset <= length, @"offset <= length", nil, @"");
    return (int)count;
}

/**
 `funopen` write callback for a mutable NSData. The data is grown when the write
 lands past its end, then the bytes replace the range at the cursor.
 */
static int DVTNSMutableDataWrite(void *cookie, const char *buffer, int size)
{
    DVTNSDataStdIOContext *context = cookie;
    if (!DVTNSDataStdIOContextIsValid(context)) {
        return -1;
    }
    if (size == 0) {
        return 0;
    }
    NSMutableData *data = (NSMutableData *)context->data;
    NSUInteger length = data.length;
    NSUInteger offset = (NSUInteger)context->offset;
    NSUInteger end = offset + (NSUInteger)size;
    NSUInteger limit = length;
    if (end > length) {
        [data setLength:end];
        DVTAssert(data.length == end, @"data.length == end", nil, @"");
        limit = end;
    }
    DVTAssert(end <= limit, @"end <= limit", nil, @"");
    [data replaceBytesInRange:NSMakeRange(offset, (NSUInteger)size) withBytes:buffer length:(NSUInteger)size];
    context->offset = (fpos_t)end;
    DVTAssert((NSUInteger)context->offset <= limit, @"offset <= limit", nil, @"");
    return size;
}

/**
 `funopen` seek callback shared by both streams. A seek is refused with `EINVAL`
 when it would move the cursor outside the data; `SEEK_SET` and `SEEK_END` only
 accept positions strictly inside it.
 */
static fpos_t DVTNSDataSeek(void *cookie, fpos_t offset, int whence)
{
    DVTNSDataStdIOContext *context = cookie;
    if (!DVTNSDataStdIOContextIsValid(context)) {
        return -1;
    }
    NSUInteger length = context->data.length;
    NSUInteger current = (NSUInteger)context->offset;
    DVTAssert(current <= length, @"current <= length", nil, @"");
    NSUInteger position;
    switch (whence) {
        case SEEK_SET:
            if (offset < 0 || (NSUInteger)offset >= length) {
                errno = EINVAL;
                return -1;
            }
            position = (NSUInteger)offset;
            break;
        case SEEK_CUR:
            if (offset > 0) {
                if ((NSUInteger)offset > length - current) {
                    errno = EINVAL;
                    return -1;
                }
            } else if ((NSUInteger)(-offset) > current) {
                errno = EINVAL;
                return -1;
            }
            position = current + (NSUInteger)offset;
            break;
        case SEEK_END:
            if (offset >= 0 || (NSUInteger)(-offset) > length) {
                errno = EINVAL;
                return -1;
            }
            position = length + (NSUInteger)offset;
            break;
        default:
            errno = EINVAL;
            return -1;
    }
    context->offset = (fpos_t)position;
    return (fpos_t)position;
}

/**
 `funopen` close callback. It releases the data the stream retained and frees the
 context; the `FILE *` itself is owned by the caller and closed separately.
 */
static int DVTNSDataClose(void *cookie)
{
    DVTNSDataStdIOContext *context = cookie;
    if (context == NULL) {
        errno = EBADF;
        return -1;
    }
    DVTAssert(context->file != NULL, @"context->file != ((void*)0)", nil, @"");
    DVTAssert(context->data != nil, @"context->data != nil", nil, @"");
    CFRelease((__bridge CFTypeRef)context->data);
    free(context);
    return 0;
}

@implementation NSData (DVTNSDataStdIO)

- (FILE *)dvt_openForReading
{
    DVTNSDataStdIOContext *context = calloc(1, sizeof(DVTNSDataStdIOContext));
    context->data = (__bridge NSData *)CFBridgingRetain(self);
    context->file = funopen(context, DVTNSDataRead, NULL, DVTNSDataSeek, DVTNSDataClose);
    context->offset = 0;
    return context->file;
}

@end

@implementation NSMutableData (DVTNSDataStdIO)

- (FILE *)dvt_openForReading
{
    DVTNSDataStdIOContext *context = calloc(1, sizeof(DVTNSDataStdIOContext));
    context->data = (__bridge NSData *)CFBridgingRetain(self);
    context->file = funopen(context, DVTNSMutableDataRead, NULL, DVTNSDataSeek, DVTNSDataClose);
    context->offset = 0;
    return context->file;
}

- (FILE *)dvt_openForWriting
{
    DVTNSDataStdIOContext *context = calloc(1, sizeof(DVTNSDataStdIOContext));
    context->data = (__bridge NSData *)CFBridgingRetain(self);
    context->file = funopen(context, NULL, DVTNSMutableDataWrite, DVTNSDataSeek, DVTNSDataClose);
    context->offset = 0;
    return context->file;
}

@end

@implementation NSUndoManager (DVTNSUndoManagerAdditions)

- (void)dvt_registerUndoBlock:(void (^)(void))block
{
    /* The block is registered against the class, not the instance, so the undo
       fires the class method below and invokes the stored copy. */
    [self registerUndoWithTarget:[self class]
                        selector:@selector(dvt_applyUndoBlock:)
                          object:[block copy]];
}

+ (void)dvt_applyUndoBlock:(void (^)(void))block
{
    block();
}

@end

/* Both locks get the same pair of methods. The synchronous one takes the lock,
   runs the block under an @try, and releases it in @finally so an exception
   cannot leave the lock held. The asynchronous one just hands the same work to
   a lazily created shared concurrent queue, so callers never block; the lock is
   what serialises the blocks at run time. The queue labels reproduce Apple's
   "ConcurrentQueue: <method>" form, which is only ever read back for
   diagnostics. */

@implementation NSLock (DVTFoundationExtensions)

- (void)dvt_performLockedBlock:(void (^)(void))block
{
    [self lock];
    @try {
        block();
    } @finally {
        [self unlock];
    }
}

- (void)dvt_asyncPerformLockedBlock:(void (^)(void))block
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = DVTDispatchCreateQueue(NO, QOS_CLASS_DEFAULT, 0,
                                       "ConcurrentQueue: -[NSLock(DVTFoundationExtensions) dvt_asyncPerformLockedBlock:]");
    });

    DVTDispatchAsync(queue, ^{
        [self dvt_performLockedBlock:block];
    });
}

@end

@implementation NSRecursiveLock (DVTFoundationExtensions)

- (void)dvt_performLockedBlock:(void (^)(void))block
{
    [self lock];
    @try {
        block();
    } @finally {
        [self unlock];
    }
}

- (void)dvt_asyncPerformLockedBlock:(void (^)(void))block
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = DVTDispatchCreateQueue(NO, QOS_CLASS_DEFAULT, 0,
                                       "ConcurrentQueue: -[NSRecursiveLock(DVTFoundationExtensions) dvt_asyncPerformLockedBlock:]");
    });

    DVTDispatchAsync(queue, ^{
        [self dvt_performLockedBlock:block];
    });
}

@end

@implementation NSCache (DVTNSCacheAdditions)

- (id)dvt_cachedObjectForKey:(id)key creationBlock:(id (^)(void))block
{
    /* Plain read-through: a hit is returned untouched, a miss is created and
       then inserted under the key before being returned. */
    id object = [self objectForKey:key];
    if (!object) {
        object = block();
        [self setObject:object forKey:key];
    }
    return object;
}

@end

@implementation NSScanner (DVTNSScannerAdditions)

- (BOOL)dvt_scanUnsignedIntegerInto:(unsigned long long *)into
{
    /* The scanner only knows about unsigned long long, so the value is read
       into a local and copied out only when the scan actually succeeded. A
       failure leaves the caller's storage untouched. */
    unsigned long long value = 0;
    BOOL scanned = [self scanUnsignedLongLong:&value];
    if (scanned)
        *into = value;
    return scanned;
}

@end

@implementation NSSortDescriptor (DVTNSSortDescriptorAdditions)

+ (id)dvt_sortDescriptorWithTransformBlock:(id (^)(id))block
{
    /* The descriptor sorts on the objects' own transformed values: each side is
       mapped through the block and the two mapped values are compared. Equal
       mapped values compare as equal, and a nil side sorts before a non-nil
       one. Sorting by the "self" key means the descriptor asks for the object
       itself and the comparator does the rest. */
    NSComparator comparator = ^NSComparisonResult(id object1, id object2) {
        id value1 = block(object1);
        id value2 = block(object2);
        if (value1 == value2)
            return NSOrderedSame;
        if (value1 && value2)
            return [value1 compare:value2];
        return value1 ? NSOrderedDescending : NSOrderedAscending;
    };
    return [NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES comparator:comparator];
}

+ (id)dvt_sortDescriptorWithPredicateBlock:(BOOL (^)(id))block
{
    /* An object the block accepts sorts ahead of one it rejects; two objects
       that answer the same way compare as equal. Same "self" key trick as the
       transform variant. */
    NSComparator comparator = ^NSComparisonResult(id object1, id object2) {
        BOOL matched1 = block(object1);
        BOOL matched2 = block(object2);
        if (matched1 == matched2)
            return NSOrderedSame;
        return matched1 ? NSOrderedAscending : NSOrderedDescending;
    };
    return [NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES comparator:comparator];
}

@end

@implementation NSIndexSet (DVTNSIndexSetAdditions)

+ (id)dvt_indexSetWithIndexes:(id)indexes
{
    /* The indexes come as an array of numbers, so the array variant does the work. */
    return [self dvt_indexSetWithIndexArray:indexes];
}

+ (id)dvt_indexSetWithIndexArray:(NSArray<NSNumber *> *)array
{
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NSNumber *number in array) {
        [indexes addIndex:number.unsignedIntegerValue];
    }
    return [indexes copy];
}

- (NSArray *)dvt_allIndexes
{
    return [self dvt_indexArray];
}

- (NSArray *)dvt_indexArray
{
    /* Walks the set with firstIndex/indexGreaterThanIndex: and boxes each index
       into an immutable snapshot. */
    NSMutableArray *indexes = [NSMutableArray arrayWithCapacity:self.count];
    for (NSInteger index = self.firstIndex; index != NSNotFound; index = [self indexGreaterThanIndex:index]) {
        [indexes addObject:[NSNumber numberWithInteger:index]];
    }
    return [indexes copy];
}

- (NSArray *)dvt_arrayByApplyingBlock:(id (^)(NSUInteger index))block
{
    NSUInteger count = self.count;
    if (count == 0) {
        return @[];
    }

    /* A nil result contributes no element, so the array can be shorter than the
       set. The oracle keeps up to 256 results on the stack and spills to the
       heap past that. */
    __strong id stackElements[256] = { nil };
    __strong id *elements = stackElements;
    if (count >= 257) {
        elements = (__strong id *)calloc(count, sizeof(id));
    }

    NSUInteger used = 0;
    for (NSUInteger index = self.firstIndex; index != NSNotFound; index = [self indexGreaterThanIndex:index]) {
        id value = block(index);
        if (value) {
            elements[used++] = value;
        }
    }

    NSArray *result = [NSArray arrayWithObjects:elements count:used];

    if (elements != stackElements) {
        for (NSUInteger i = 0; i < used; i++) {
            elements[i] = nil;
        }
        free(elements);
    }
    return result;
}

- (NSIndexSet *)dvt_indexesInRange:(NSRange)range
{
    /* Fast path: a set that already lies entirely inside the range answers its
       own copy. Otherwise the intersecting ranges are collected. */
    if (self.count != 0 &&
        (self.firstIndex < range.location || self.lastIndex >= NSMaxRange(range))) {
        NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
        [self enumerateRangesInRange:range options:0 usingBlock:^(NSRange subrange, BOOL *stop) {
            [indexes addIndexesInRange:subrange];
        }];
        return [indexes copy];
    }
    return [self copy];
}

- (NSIndexSet *)dvt_indexesPassingTest:(BOOL (^)(NSUInteger index))test
{
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NSUInteger index = self.firstIndex; index != NSNotFound; index = [self indexGreaterThanIndex:index]) {
        if (test(index)) {
            [indexes addIndex:index];
        }
    }
    return [indexes copy];
}

@end

@implementation NSMutableIndexSet (DVTNSMutableIndexSetAdditions)

- (void)dvt_addIndex:(long long)index shiftingLaterIndexes:(BOOL)shifting
{
    /* Inserting into the middle pushes every later index up by one first. */
    if (shifting) {
        [self shiftIndexesStartingAtIndex:(NSUInteger)index by:1];
    }
    [self addIndex:(NSUInteger)index];
}

@end

@implementation NSRegularExpression (DVTNSRegularExpressionAdditions)

- (NSArray *)dvt_matchesInString:(NSString *)string options:(unsigned long long)options
{
    /* The whole string is searched, so the range is always the string's full range. */
    return [self matchesInString:string options:(NSMatchingOptions)options range:string.dvt_fullRange];
}

@end

@implementation NSTextCheckingResult (DVTNSTextCheckingResultAdditions)

- (NSString *)dvt_matchingSubstringInString:(NSString *)string
{
    return [string substringWithRange:self.range];
}

- (NSString *)dvt_matchingSubstringInString:(NSString *)string forCaptureCaptureGroup:(NSString *)group
{
    return [string substringWithRange:[self rangeWithName:group]];
}

@end

@implementation NSIndexPath (DVTNSIndexPathAdditions)

+ (id)dvt_indexPathWithIndexes:(id)indexes
{
    /* The numbers are unboxed into a stack buffer that spills to the heap only
       once it would exceed 256 entries, then handed to the designated
       initializer. */
    NSUInteger count = [indexes count];
    NSUInteger stackIndexes[256];
    NSUInteger *pathIndexes = (count < 257) ? stackIndexes : calloc(count, sizeof(NSUInteger));
    for (NSUInteger i = 0; i < count; i++) {
        pathIndexes[i] = [[indexes objectAtIndex:i] unsignedIntegerValue];
    }

    NSIndexPath *indexPath = [[NSIndexPath alloc] initWithIndexes:pathIndexes length:count];

    if (pathIndexes != stackIndexes) {
        free(pathIndexes);
    }
    return indexPath;
}

- (id)dvt_pathComponents
{
    NSMutableArray *components = [NSMutableArray arrayWithCapacity:self.length];
    for (NSUInteger i = 0; i < self.length; i++) {
        [components addObject:[NSNumber numberWithUnsignedInteger:[self indexAtPosition:i]]];
    }
    return components;
}

- (id)dvt_stringRepresentation
{
    NSMutableString *representation = [NSMutableString string];
    for (NSUInteger i = 0; i < self.length; i++) {
        if (i != 0) {
            [representation appendString:@"/"];
        }
        [representation appendFormat:@"%lu", (unsigned long)[self indexAtPosition:i]];
    }
    return representation;
}

@end

@implementation NSPointerArray (DVTNSPointerArrayAdditions)

- (void)dvt_addObject:(id)object
{
    [self addPointer:(__bridge void *)object];
}

- (id)dvt_objectAtIndex:(unsigned long long)index
{
    return (__bridge id)[self pointerAtIndex:index];
}

- (void)dvt_insertObject:(id)object atIndex:(unsigned long long)index
{
    [self insertPointer:(__bridge void *)object atIndex:index];
}

- (void)dvt_replaceObjectAtIndex:(unsigned long long)index withObject:(id)object
{
    [self replacePointerAtIndex:index withPointer:(__bridge void *)object];
}

- (unsigned long long)dvt_indexOfObjectIdenticalTo:(id)object
{
    /* Pointer array's fast enumeration hands back the raw pointers, so identity
       is a plain ==. */
    unsigned long long index = 0;
    for (id candidate in self) {
        if (candidate == object) {
            return index;
        }
        index++;
    }
    return (unsigned long long)NSNotFound;
}

- (void)dvt_removeFirstObjectIdenticalTo:(id)object
{
    unsigned long long index = [self dvt_indexOfObjectIdenticalTo:object];
    if (index == (unsigned long long)NSNotFound) {
        return;
    }
    [self removePointerAtIndex:index];
}

@end

@implementation NSUserDefaults (DVTNSUserDefaultsAdditions)

- (id)dvt_objectForKey:(id)key inVolatileDomainForName:(id)name
{
    /* A missing domain name falls back to the application's own bundle id; if
       even that is unavailable there is nothing to look in. */
    if (!key) {
        return nil;
    }
    if (!name) {
        name = [[NSBundle mainBundle] bundleIdentifier];
        if (!name) {
            return nil;
        }
    }
    return [[self volatileDomainForName:name] valueForKey:key];
}

- (id)dvt_multipleStringsForKey:(id)key separator:(id)separator
{
    /* An array value is preferred; a plain string is split on the separator. */
    NSArray *strings = [self stringArrayForKey:key];
    if (!strings) {
        strings = [[self stringForKey:key] componentsSeparatedByString:separator];
    }
    return strings;
}

- (BOOL)dvt_objectIsChangedForKey:(id)key
{
    /* Changed means the effective value differs from the one registered in the
       NSRegistrationDomain. A missing key, or a missing registration, is not a
       change. */
    if (!key) {
        return NO;
    }
    id value = [[self dictionaryRepresentation] objectForKey:key];
    if (!value) {
        return NO;
    }
    id registered = [self dvt_objectForKey:key inVolatileDomainForName:NSRegistrationDomain];
    if (!registered) {
        return NO;
    }
    return ![value isEqual:registered];
}

- (void)dvt_setFilePath:(id)path forKey:(id)key
{
    [self setURL:[path fileURL] forKey:key];
}

- (void)dvt_setupDefaultsFromEnvironment
{
    /* Intentionally empty in the oracle. */
}

- (BOOL)dvt_boolForKey:(id)key defaultValue:(BOOL)value
{
    id object = [self objectForKey:key];
    if (object) {
        value = [object boolValue];
    }
    return value;
}

- (double)dvt_doubleForKey:(id)key defaultValue:(double)value
{
    id object = [self objectForKey:key];
    if (object) {
        value = [object doubleValue];
    }
    return value;
}

- (long long)dvt_integerForKey:(id)key defaultValue:(long long)value
{
    id object = [self objectForKey:key];
    if (object) {
        value = [object integerValue];
    }
    return value;
}

- (id)objectForKeyedSubscript:(id)subscript
{
    return [self objectForKey:subscript];
}

- (void)setObject:(id)object forKeyedSubscript:(id)subscript
{
    [self setObject:object forKey:subscript];
}

@end

#pragma mark - NSProcessInfo (DVTNSProcessInfoAdditions)

/*
 Sudden termination is tracked as a reason -> count dictionary, automatic
 termination as a counted set of reasons. Both stores are process-wide.
 Each has its own recursive lock: incrementing or decrementing a count reads
 the current value back through the public accessor while the store is still
 locked, so a non-recursive lock would deadlock.
 */
static NSMutableDictionary<NSString *, NSNumber *> *DVTSuddenTerminationDisablingReasons = nil;
static NSCountedSet<NSString *> *DVTAutomaticTerminationDisablingReasons = nil;
static NSRecursiveLock *DVTSuddenTerminationDisablingReasonsLock = nil;
static NSRecursiveLock *DVTAutomaticTerminationDisablingReasonsLock = nil;
static dispatch_once_t DVTSuddenTerminationDisablingReasonsOnceToken;
static dispatch_once_t DVTAutomaticTerminationDisablingReasonsOnceToken;

static void DVTAccessSuddenTerminationDisablingReasons(void (^block)(NSMutableDictionary<NSString *, NSNumber *> *reasons))
{
    dispatch_once(&DVTSuddenTerminationDisablingReasonsOnceToken, ^{
        DVTSuddenTerminationDisablingReasons = [[NSMutableDictionary alloc] init];
        DVTSuddenTerminationDisablingReasonsLock = [[NSRecursiveLock alloc] init];
    });
    [DVTSuddenTerminationDisablingReasonsLock dvt_performLockedBlock:^{
        block(DVTSuddenTerminationDisablingReasons);
    }];
}

static void DVTAccessAutomaticTerminationDisablingReasons(void (^block)(NSCountedSet<NSString *> *reasons))
{
    dispatch_once(&DVTAutomaticTerminationDisablingReasonsOnceToken, ^{
        DVTAutomaticTerminationDisablingReasons = [[NSCountedSet alloc] init];
        DVTAutomaticTerminationDisablingReasonsLock = [[NSRecursiveLock alloc] init];
    });
    [DVTAutomaticTerminationDisablingReasonsLock dvt_performLockedBlock:^{
        block(DVTAutomaticTerminationDisablingReasons);
    }];
}

/* Every reason-taking termination method validates its argument the same way:
   a nil object, a non-string, and the empty string are all assertion failures
   in the original. */
static void DVTAssertTerminationReason(NSString *reason)
{
    DVTAssert(reason != nil, @"(reason) != nil", nil,
              @"%@ must not be nil", @"reason");
    DVTAssert(CFGetTypeID((__bridge CFStringRef)reason) == CFStringGetTypeID(),
              @"CFGetTypeID((CFStringRef)reason) == CFStringGetTypeID()", nil,
              @"%@ should be a string, but it is %@", @"reason", reason);
    DVTAssert(![reason isEqualToString:@""], @"![reason isEqualToString:@\"\"]", nil,
              @"%@ must not be empty", @"reason");
}

/*
 The original also logs the private Foundation
 `-[NSProcessInfo _suddenTerminationDisablingCount]` after changing a sudden
 termination count. There is no DVTLogAspect in this port and the message has
 no observable effect, so neither the probe nor the logging is carried over.
 */

@implementation NSProcessInfo (DVTNSProcessInfoAdditions)

- (unsigned long long)dvt_numberOfAvailableCPUs
{
    /* HW_AVAILCPU is the number of CPUs the scheduler may use. A failed query
       reads as zero rather than aborting. */
    int availableCPUs = 0;
    size_t length = sizeof(availableCPUs);
    int mib[2] = { CTL_HW, HW_AVAILCPU };
    if (sysctl(mib, 2, &availableCPUs, &length, NULL, 0) < 0) {
        availableCPUs = 0;
    }
    return (unsigned long long)availableCPUs;
}

- (NSString *)dvt_executablePath
{
    /* The first call reports the buffer length with a NULL buffer. The
       original allocates the buffer on the stack; a heap buffer is used here
       so the size is not attacker-influenced stack usage. */
    uint32_t size = 0;
    int result = _NSGetExecutablePath(NULL, &size);
    DVTAssert(result == -1 && size > 0,
              @"_NSGetExecutablePath(NULL, &size) == -1 && size > 0", nil,
              @"Could not determine the size of the executable path buffer");

    char *path = malloc(size);
    result = _NSGetExecutablePath(path, &size);
    DVTAssert(result == 0, @"_NSGetExecutablePath(path, &size) == 0", nil,
              @"Could not read the executable path");

    /* size is the buffer length reported before the second call and includes
       the terminating NUL. Foundation keeps the NUL when it is part of
       `length:`, so the string is built from the C string length instead. */
    NSString *executablePath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path
                                                                                          length:strlen(path)];
    free(path);
    return executablePath;
}

- (BOOL)isXcode
{
    return [[self processName] isEqual:@"Xcode"];
}

- (BOOL)isSwiftPlaygrounds
{
    return [[self processName] isEqual:@"Playgrounds"];
}

- (NSArray<NSString *> *)dvt_suddenTerminationDisablingReasons
{
    __block NSArray<NSString *> *reasons = nil;
    DVTAccessSuddenTerminationDisablingReasons(^(NSMutableDictionary<NSString *, NSNumber *> *dictionary) {
        reasons = [dictionary allKeys];
    });
    return reasons;
}

- (long long)dvt_suddenTerminationDisablingCountForReason:(NSString *)reason
{
    __block long long count = 0;
    DVTAccessSuddenTerminationDisablingReasons(^(NSMutableDictionary<NSString *, NSNumber *> *dictionary) {
        /* The stored NSNumber is an int, so a negative value reads back
           sign-extended. */
        count = [[dictionary objectForKey:reason] intValue];
    });
    return count;
}

- (void)_dvt_setSuddenTerminationDisablingCount:(long long)count forReason:(NSString *)reason
{
    DVTAccessSuddenTerminationDisablingReasons(^(NSMutableDictionary<NSString *, NSNumber *> *dictionary) {
        if (count != 0) {
            [dictionary setObject:[NSNumber numberWithInteger:(NSInteger)count] forKey:reason];
        } else {
            [dictionary removeObjectForKey:reason];
        }
    });
}

- (NSArray<NSString *> *)dvt_automaticTerminationDisablingReasons
{
    __block NSArray<NSString *> *reasons = nil;
    DVTAccessAutomaticTerminationDisablingReasons(^(NSCountedSet<NSString *> *set) {
        reasons = [set allObjects];
    });
    return reasons;
}

- (long long)dvt_automaticTerminationDisablingCountForReason:(NSString *)reason
{
    __block long long count = 0;
    DVTAccessAutomaticTerminationDisablingReasons(^(NSCountedSet<NSString *> *set) {
        count = (long long)[set countForObject:reason];
    });
    return count;
}

- (DVTOneShotBlock *)dvt_disableAutomaticTerminationWithReason:(NSString *)reason
{
    /* The disable happens now; the returned token re-enables the reason when
       its owner is done with it. */
    [self dvt_disableAutomaticTerminationForReason:reason];
    return [DVTOneShotBlock oneShotBlockWithCallback:^{
        [self dvt_enableAutomaticTerminationForReason:reason];
    }];
}

- (void)dvt_disableAutomaticTerminationForReason:(NSString *)reason
{
    DVTAssertTerminationReason(reason);
    DVTAccessAutomaticTerminationDisablingReasons(^(NSCountedSet<NSString *> *reasons) {
        [reasons addObject:reason];
        if ([self respondsToSelector:@selector(disableAutomaticTermination:)]) {
            [self disableAutomaticTermination:reason];
        }
    });
}

- (void)dvt_enableAutomaticTerminationForReason:(NSString *)reason
{
    DVTAssertTerminationReason(reason);
    DVTAccessAutomaticTerminationDisablingReasons(^(NSCountedSet<NSString *> *reasons) {
        if ([reasons containsObject:reason]) {
            [reasons removeObject:reason];
            if ([self respondsToSelector:@selector(enableAutomaticTermination:)]) {
                [self enableAutomaticTermination:reason];
            }
        }
    });
}

- (void)dvt_enableSuddenTerminationForReason:(NSString *)reason
{
    DVTAssertTerminationReason(reason);
    DVTAccessSuddenTerminationDisablingReasons(^(NSMutableDictionary<NSString *, NSNumber *> *reasons) {
        [self enableSuddenTermination];
        long long count = [self dvt_suddenTerminationDisablingCountForReason:reason];
        if (count != 0) {
            [self _dvt_setSuddenTerminationDisablingCount:count - 1 forReason:reason];
        }
    });
}

- (void)dvt_disableSuddenTerminationForReason:(NSString *)reason
{
    DVTAssertTerminationReason(reason);
    DVTAccessSuddenTerminationDisablingReasons(^(NSMutableDictionary<NSString *, NSNumber *> *reasons) {
        [self disableSuddenTermination];
        long long count = [self dvt_suddenTerminationDisablingCountForReason:reason];
        [self _dvt_setSuddenTerminationDisablingCount:count + 1 forReason:reason];
    });
}

- (BOOL)dvt_isNonGraphicalProcess
{
    NSNumber *isNonGraphicalProcess = objc_getAssociatedObject(self, "dvt_isNonGraphicalProcess");
    return [isNonGraphicalProcess boolValue];
}

- (void)dvt_setIsNonGraphicalProcess:(BOOL)isNonGraphicalProcess
{
    objc_setAssociatedObject(self, "dvt_isNonGraphicalProcess",
                             [NSNumber numberWithBool:isNonGraphicalProcess],
                             OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)dvt_shouldDisallowSaving
{
    /* Building through xcodebuild forces saving to be allowed regardless of
       the other state. */
    if (DVTEnvironmentSnapshotBool(@"XCODEBUILD_FORCE_ALLOW_SAVING")) {
        return NO;
    }

    NSNumber *disallowSavingOverride = objc_getAssociatedObject(self, "dvt_disallowSavingOverride");
    if (disallowSavingOverride != nil) {
        return [disallowSavingOverride boolValue];
    }

    return [self dvt_isNonGraphicalProcess];
}

- (void)dvt_setDisallowSavingOverride:(BOOL)disallowSavingOverride
{
    objc_setAssociatedObject(self, "dvt_disallowSavingOverride",
                             [NSNumber numberWithBool:disallowSavingOverride],
                             OBJC_ASSOCIATION_RETAIN);
}

- (DVTSystemActivityToken *)dvt_beginActivityWithOptions:(unsigned long long)options reason:(NSString *)reason
{
    DVTSystemActivityToken *token = [[DVTSystemActivityToken alloc] initWithOptions:options reason:reason];
    [DVTSystemActivityToken _accessSystemActivityTokensWithBlock:^(NSMutableSet<DVTSystemActivityToken *> *tokens) {
        [tokens addObject:token];
    }];
    return token;
}

- (NSArray<DVTSystemActivityToken *> *)dvt_activeSystemActivityTokensMatchingOptions:(unsigned long long)options
{
    /* A token matches when any of its option bits is also in `options`, which
       is how the original asks "is this token in one of these families?". */
    NSMutableArray<DVTSystemActivityToken *> *matchingTokens = [NSMutableArray array];
    [DVTSystemActivityToken _accessSystemActivityTokensWithBlock:^(NSMutableSet<DVTSystemActivityToken *> *tokens) {
        for (DVTSystemActivityToken *token in tokens) {
            if ((token.activityOptions & options) != 0) {
                [matchingTokens addObject:token];
            }
        }
    }];
    return matchingTokens;
}

@end
