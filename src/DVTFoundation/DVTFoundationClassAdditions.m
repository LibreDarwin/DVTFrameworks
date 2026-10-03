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

#import <Foundation/NSEnumerator.h>
#import <Foundation/NSNull.h>

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

@end

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

@end

@implementation NSSet (DVTNSSetAdditions)

- (BOOL)dvt_allObjectsPassTest:(BOOL (^)(id object))test
{
    return DVTAllObjectsPassTest(self, test);
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

- (void)dvt_addObjectIfNonNil:(id)object
{
    if (object != nil) {
        [self addObject:object];
    }
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

@end
