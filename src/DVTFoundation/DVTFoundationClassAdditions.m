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

#import <Foundation/NSEnumerator.h>
#import <Foundation/NSNull.h>
#import <objc/message.h>
#import <stdlib.h>

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
    return result;
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

- (NSUInteger)dvt_numberOfObjectsPassingTest:(BOOL (^)(id object))test
{
    if (test == nil) {
        return self.count;
    }
    NSUInteger matching = 0;
    NSEnumerator *enumerator = [self objectEnumerator];
    id object = nil;
    while ((object = [enumerator nextObject]) != nil) {
        if (test(object)) {
            matching++;
        }
    }
    return matching;
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
    return [self dvt_compactMap:block];
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
        [result addObject:block(object) ?: (id)[NSNull null]];
    }
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
    return result;
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
        [result addObject:block(object) ?: (id)[NSNull null]];
    }
    return result;
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

@implementation NSMutableSet (DVTFoundationClassAdditions)

- (void)dvt_addObjectIfNonNil:(id)object
{
    if (object != nil) {
        [self addObject:object];
    }
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

- (BOOL)dvt_hasContent
{
    return self.count != 0;
}

- (BOOL)dvt_isNonEmpty
{
    return self.count != 0;
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

@end
