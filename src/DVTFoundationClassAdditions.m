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
        characterSet = [NSCharacterSet characterSetWithCharactersInString:
                            @"!\"#$%&'()*+,;<=>?@[\\]^`{|}~ \t\n"];
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
    if (DVTIndexOfObject(self, object) == NSNotFound) {
        return [self copy];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];
    BOOL removed = NO;
    NSUInteger count = self.count;
    for (NSUInteger index = 0; index < count; index++) {
        id candidate = [self objectAtIndex:index];
        if (!removed && [candidate isEqual:object]) {
            removed = YES;
            continue;
        }
        [result addObject:candidate];
    }
    return result;
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
    NSUInteger count = self.count;
    if (count == 0) {
        return @"";
    }

    NSCharacterSet *metacharacters = DVTCommandLineMetacharacterSet();
    NSMutableString *result = [NSMutableString stringWithCapacity:64];

    for (NSUInteger index = 0; index < count; index++) {
        id object = [self objectAtIndex:index];
        NSString *value = [object isKindOfClass:[NSString class]] ? object : [object description];
        if (value == nil) {
            continue;
        }

        if (index > 0) {
            [result appendString:@" "];
        }

        if (value.length == 0) {
            [result appendString:@"''"];
            continue;
        }

        NSUInteger length = value.length;
        for (NSUInteger position = 0; position < length; position++) {
            unichar character = [value characterAtIndex:position];
            if ([metacharacters characterIsMember:character]) {
                [result appendString:@"\\"];
            }
            [result appendFormat:@"%C", character];
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

@implementation NSMutableSet (DVTFoundationClassAdditions)

- (void)dvt_addObjectIfNonNil:(id)object
{
    if (object != nil) {
        [self addObject:object];
    }
}

@end

@implementation NSHashTable (DVTNSHashTableAdditions)

- (void)dvt_addObjectIfNonNil:(id)object
{
    if (object != nil) {
        [self addObject:object];
    }
}

@end
