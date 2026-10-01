//
//  DVTCertificateComparison.m
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

#import "DVTCertificateComparison.h"

/*
 Declared, never implemented. Apple's binary calls this selector from
 DVTCompareCertificateKindSets but ships no implementation of it, so the message
 raises at runtime; declaring it here is what reproduces that rather than
 quietly sorting and returning an answer the shipped binary never gives.
 */
@interface NSArray (DVTCertificateComparisonMissingSorting)
- (NSArray *)dvt_sortedArrayUsingComparator:(NSComparisonResult (^)(id lhs, id rhs))comparator;
@end

static NSDictionary<NSString *, NSNumber *> *DVTCertificateKindRanks(void)
{
    static NSDictionary<NSString *, NSNumber *> *ranks;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        ranks = @{
            @"1.2.840.113635.100.6.1.2": @0,
            @"1.2.840.113635.100.6.1.4": @1,
            @"1.2.840.113635.100.6.1.12": @2,
            @"1.2.840.113635.100.6.1.7": @3,
            @"1.2.840.113635.100.6.1.8": @4,
            @"1.2.840.113635.100.6.1.13": @5,
            @"1.2.840.113635.100.6.1.14": @6,
        };
    });

    return ranks;
}

/*
 The two fallbacks in DVTCompareCertificateKinds order by address. nil is 0, so
 this also decides the nil-against-a-real-kind cases without a special case, but
 it is a comparison of pointers and nothing else.
 */
static NSComparisonResult DVTCertificateKindOrderByAddress(id lhs, id rhs)
{
    if (lhs == rhs) {
        return NSOrderedSame;
    }

    return (uintptr_t)lhs < (uintptr_t)rhs ? NSOrderedAscending : NSOrderedDescending;
}

NSComparisonResult DVTCompareCertificateKinds(id lhs, id rhs)
{
    if (lhs == rhs) {
        return NSOrderedSame;
    }

    if (lhs == nil || rhs == nil) {
        return DVTCertificateKindOrderByAddress(lhs, rhs);
    }

    id leftRank = DVTCertificateKindRanks()[lhs];
    id rightRank = DVTCertificateKindRanks()[rhs];

    if (leftRank != rightRank) {
        if (leftRank == nil || rightRank == nil) {
            return DVTCertificateKindOrderByAddress(leftRank, rightRank);
        }

        NSComparisonResult result = [leftRank compare:rightRank];
        if (result != NSOrderedSame) {
            return result;
        }
    }

    return [lhs compare:rhs];
}

NSComparisonResult DVTCompareCertificateKindSets(NSArray *lhs, NSArray *rhs)
{
    NSComparisonResult (^comparator)(id, id) = ^NSComparisonResult(id left, id right) {
        return DVTCompareCertificateKinds(left, right);
    };

    id left = [lhs dvt_sortedArrayUsingComparator:comparator].firstObject;
    id right = [rhs dvt_sortedArrayUsingComparator:comparator].firstObject;

    return DVTCompareCertificateKinds(left, right);
}
