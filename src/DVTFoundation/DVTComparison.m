//
//  DVTComparison.m
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

#import "DVTComparison.h"
#import "DVTFoundationClassAdditions.h"

#include <math.h>

NSInteger DVTCompareBools(BOOL lhs, BOOL rhs)
{
    if (lhs == rhs) {
        return 0;
    }
    return lhs ? 1 : -1;
}

NSInteger DVTCompareIntegers(NSInteger lhs, NSInteger rhs)
{
    if (lhs < rhs) {
        return -1;
    }
    if (lhs > rhs) {
        return 1;
    }
    return 0;
}

NSInteger DVTCompareDoubles(double lhs, double rhs)
{
    /*
     An unordered pair still has to produce one of the three values, and the
     original reads the sign bit of whichever operand it does not test for
     NaN. That is what makes the two branches below disagree in polarity, so
     do not fold them together.
     */
    if (isnan(lhs)) {
        if (isnan(rhs)) {
            return 0;
        }
        return signbit(rhs) ? 1 : -1;
    }
    if (isnan(rhs)) {
        return signbit(lhs) ? -1 : 1;
    }
    if (lhs < rhs) {
        return -1;
    }
    if (lhs > rhs) {
        return 1;
    }
    return 0;
}

/*
 The shared tolerance test. Scaling by the smaller magnitude makes the test
 relative rather than absolute, which is what lets it keep working away from
 the origin. The comparison is a plain <= on doubles, so an unordered pair
 (a NaN difference, or a NaN scale) falls through as "not equal", and an
 infinite difference against an infinite scale is ordered by the floating-point
 comparison itself.
 */
static BOOL _DVTDoublesAreWithinEpsilon(double lhs, double rhs, double epsilon)
{
    return fabs(lhs - rhs) <= epsilon * fmin(fabs(lhs), fabs(rhs));
}

BOOL DVTEqualDoublesWithEpsilon(double lhs, double rhs, double epsilon)
{
    return _DVTDoublesAreWithinEpsilon(lhs, rhs, epsilon);
}

NSInteger DVTCompareDoublesWithEpsilon(double lhs, double rhs, double epsilon)
{
    if (_DVTDoublesAreWithinEpsilon(lhs, rhs, epsilon)) {
        return 0;
    }
    /* Every remaining case is 1, including an unordered pair. */
    return lhs < rhs ? -1 : 1;
}

NSInteger DVTCompareArrays(NSArray *_Nullable lhs, NSArray *_Nullable rhs)
{
    /* Sorting first matches the original, which is observable through which
     * exception a mixed array raises. */
    NSArray *left = [lhs sortedArrayUsingSelector:@selector(compare:)];
    NSArray *right = [rhs sortedArrayUsingSelector:@selector(compare:)];

    NSUInteger leftCount = [left count];
    NSUInteger rightCount = [right count];
    if (leftCount != rightCount) {
        return leftCount < rightCount ? -1 : 1;
    }

    for (NSUInteger index = 0; index < leftCount; index++) {
        NSComparisonResult result = [left[index] compare:right[index]];
        if (result != NSOrderedSame) {
            return result;
        }
    }
    return 0;
}

/** `-valueForKeyPath:` is KVC, not a declared method, and the SDK headers used
    to build this framework do not declare it. */
@interface NSObject (DVTKeyValueCoding)
- (id _Nullable)valueForKeyPath:(NSString *)keyPath;
@end

BOOL DVTEqualObjectsUsingKeyPaths(id lhs, id rhs, DVTKeyPathClassMatch mode, id keyPaths)
{
    if (lhs == rhs) {
        return YES;
    }
    if (lhs == nil || rhs == nil) {
        return NO;
    }
    /* The class check runs before any key path is read, so a class mismatch is
       never reported as an exception from a bad key path. */
    switch (mode) {
    case DVTKeyPathClassMatchAllowsSubclass:
        if (![rhs isKindOfClass:[lhs class]]) {
            return NO;
        }
        break;
    case DVTKeyPathClassMatchRequiresIdenticalClass:
        if (![rhs isMemberOfClass:[lhs class]]) {
            return NO;
        }
        break;
    default:
        return NO;
    }
    return [keyPaths dvt_allObjectsPassTest:^BOOL(id keyPath) {
        id left = [lhs valueForKeyPath:keyPath];
        id right = [rhs valueForKeyPath:keyPath];
        /* Identity first, so an object that refuses to be equal to itself is
           still equal to itself. */
        return (left == right) ? YES : [left isEqual:right];
    }];
}
