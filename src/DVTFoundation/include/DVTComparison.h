//
//  DVTComparison.h
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

#ifndef DVT_COMPARISON_H
#define DVT_COMPARISON_H

#import <Foundation/Foundation.h>
#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Three-way comparison of two boolean values, treating each as `NO` or `YES`.

 Returns `-1` when `lhs` is `NO` and `rhs` is `YES`, `1` for the reverse, and
 `0` when the two agree.
 */
DVT_EXTERN NSInteger DVTCompareBools(BOOL lhs, BOOL rhs);

/**
 Three-way comparison of two integers: `-1` for `lhs < rhs`, `1` for
 `lhs > rhs`, and `0` for equality. There is no overflow-sensitive path, so
 `NSIntegerMin` and `NSIntegerMax` compare correctly.
 */
DVT_EXTERN NSInteger DVTCompareIntegers(NSInteger lhs, NSInteger rhs);

/**
 Three-way comparison of two doubles: `-1` for `lhs < rhs`, `1` for
 `lhs > rhs`, and `0` for equality.

 `NaN` is not ordered against anything, yet this function still returns one of
 the three values rather than leaving it to the caller. The original resolves
 each operand by its sign bit, so the two cases are deliberately asymmetric:

 - both operands `NaN` compares equal, because there is no magnitude to
   disagree about;
 - a `NaN` on the left yields `1` when `rhs` is negative and `-1` otherwise,
   including when `rhs` is `-0.0`;
 - a `NaN` on the right yields `-1` when `lhs` is negative and `1` otherwise.

 `-0.0` and `0.0` compare equal, as they do for any ordered operator.
 */
DVT_EXTERN NSInteger DVTCompareDoubles(double lhs, double rhs);

/**
 Compares two doubles for equality within a relative `epsilon`.

 The two operands are treated as equal when their absolute difference is no
 greater than `epsilon` scaled by the smaller of their magnitudes, that is when
 `fabs(lhs - rhs) <= epsilon * fmin(fabs(lhs), fabs(rhs))`. Scaling by the
 smaller magnitude means the test is relative, so it stays meaningful far from
 the origin, and it degenerates to exact equality whenever either operand is
 `0.0`.

 Two infinities of the same sign are equal, because the difference of two equal
 infinities is `NaN`, which compares false, so only the opposite-sign pair is
 caught by the scale: `INFINITY` against `-INFINITY` yields the infinite
 difference, which does not exceed the equally infinite `epsilon * min`. Any
 `NaN` operand yields `NO`.
 */
DVT_EXTERN BOOL DVTEqualDoublesWithEpsilon(double lhs, double rhs, double epsilon);

/**
 Orders two doubles, treating them as equal when `DVTEqualDoublesWithEpsilon`
 accepts the pair.

 Returns `0` for a pair within `epsilon`, and otherwise orders the operands
 with `-1` for `lhs < rhs` and `1` for every remaining case. The last part is
 what distinguishes this from `DVTCompareDoubles`: an unordered pair is not
 reported as a single direction but always as `1`, so a `NaN` on either side
 compares greater, and two equal infinities also compare greater rather than
 equal, since `INFINITY` and `INFINITY` differ by `NaN` and so fail the
 tolerance test.
 */
DVT_EXTERN NSInteger DVTCompareDoublesWithEpsilon(double lhs, double rhs, double epsilon);

/**
 Compares two arrays as unordered collections.

 Both arrays are sorted with `compare:` first, so the order in which the caller
 supplied the elements does not affect the result. The counts are then compared
 before any element, and a longer array compares greater. For equal counts the
 elements are walked in sorted order and the comparison of the first pair that
 differs decides the result; equal arrays return `0`.

 A `nil` array is treated as empty, so `nil` sorts to an empty array and
 compares as one.

 The sort and the element walk both send `compare:` to the elements, so the
 elements have to be mutually comparable. A mixed array such as
 `@[@1, @"1"]` raises from the sort, and `@[@1]` against `@[@"1"]` raises from
 the walk, because `-compare:` is what rejects the pair; the original does not
 guard either case.
 */
DVT_EXTERN NSInteger DVTCompareArrays(NSArray *_Nullable lhs, NSArray *_Nullable rhs);

/**
 How strictly `DVTEqualObjectsUsingKeyPaths` requires the two operands to agree
 on their class before comparing any key path.

 The check is one-directional and is applied as *is the right operand a
 subclass of the left one*, so the operand order matters.
 */
typedef NS_ENUM(NSUInteger, DVTKeyPathClassMatch) {
    /** The right operand only has to be a `kind of` the left one's class. */
    DVTKeyPathClassMatchAllowsSubclass = 0,
    /** The right operand has to be a member of exactly the left one's class. */
    DVTKeyPathClassMatchRequiresIdenticalClass = 1,
};

/**
 `YES` when `lhs` and `rhs` agree on every key path in `keyPaths`, compared with
 `valueForKeyPath:` and then `isEqual:`.

 `mode` selects the class check from `DVTKeyPathClassMatch`; any value other
 than `0` or `1` is not a mode this function knows and always yields `NO`, even
 for two identical objects whose key paths would otherwise match.

 The order of the checks is observable, and none of them can be skipped:

 - Identical operands return `YES` before anything else is examined, so
   `keyPaths` is never touched. Two `nil`s are identical, and therefore equal.
 - A single `nil` operand returns `NO`.
 - The class check runs next, and a failure returns `NO` without reading a single
   key path.
 - Only then is `keyPaths` enumerated, stopping at the first key path that
   disagrees.

 Each value pair is compared by identity first and by `isEqual:` only when the
 two are not the same object, so a pair of objects whose `isEqual:` refuses to
 accept even itself still compares equal to themselves under a key path.

 Exceptions raised while evaluating a key path are not caught: an undefined key
 path raises `NSUnknownKeyException` out of this function, and a `keyPaths`
 that is not one of the collection classes carrying
 `dvt_allObjectsPassTest:` raises `NSInvalidArgumentException`. A `nil`
 `keyPaths` sends the message to `nil`, which yields `nil`, and `nil` is `NO`.
 */
DVT_EXTERN BOOL DVTEqualObjectsUsingKeyPaths(id _Nullable lhs, id _Nullable rhs, DVTKeyPathClassMatch mode, id _Nullable keyPaths);

NS_ASSUME_NONNULL_END

#endif /* DVT_COMPARISON_H */
