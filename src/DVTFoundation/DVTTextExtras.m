//
//  DVTTextExtras.m
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

#import "DVTTextExtras.h"

/*
 Apple indexes a three-entry table with `value - 1` and tests the result
 unsigned, so every value outside 1...3 -- including DVTLineEndingNone and any
 negative value -- yields NULL. Reproducing that arithmetic rather than using a
 switch keeps the behaviour for out-of-range input identical.
 */
static NSString *const DVTStringsByLineEnding[3] = {
    @"\n",
    @"\r",
    @"\r\n",
};

NSString *_Nullable DVTStringFromLineEnding(DVTLineEnding lineEnding)
{
    NSUInteger index = (NSUInteger)lineEnding - 1;
    if (index > 2) {
        return nil;
    }
    return DVTStringsByLineEnding[index];
}

/*
 The table is indexed directly, but out-of-range values fall back to the
 WholeWords string rather than asserting -- which is why that one string appears
 twice in Apple: once in the table and once as the fallback.
 */
static NSString *const DVTStringsByFindMatchStyle[4] = {
    @"Contains",
    @"StartsWith",
    @"WholeWords",
    @"EndsWith",
};

NSString *DVTStringFromFindMatchStyle(DVTFindsMatchStyle style)
{
    if ((NSUInteger)style > 3) {
        return DVTStringsByFindMatchStyle[DVTFindsMatchStyleWholeWords];
    }
    return DVTStringsByFindMatchStyle[(NSUInteger)style];
}

DVTFindsMatchStyle DVTFindMatchStyleFromString(NSString *string)
{
    if ([string isEqualToString:DVTStringsByFindMatchStyle[DVTFindsMatchStyleWholeWords]]) {
        return DVTFindsMatchStyleWholeWords;
    }
    if ([string isEqualToString:DVTStringsByFindMatchStyle[DVTFindsMatchStyleStartsWith]]) {
        return DVTFindsMatchStyleStartsWith;
    }
    if ([string isEqualToString:DVTStringsByFindMatchStyle[DVTFindsMatchStyleEndsWith]]) {
        return DVTFindsMatchStyleEndsWith;
    }
    return DVTFindsMatchStyleContains;
}

/*
 The placeholder Apple substitutes for an escaped space. It is a printable
 string with no space in it, so it survives the split below untouched, and it is
 substituted back out of the result afterwards.

 The consequence, which the differential confirms, is that a caller who passes
 the literal text "\<space>" gets the same answer as one who passes an escaped
 space: both produce a single space.
 */
static NSString *const DVTEscapedSpacePlaceholder = @"\\<space>";

NSArray<NSString *> *DVTTextFragmentsForStringPreservingEscapedSpaces(NSString *string)
{
    NSString *protected = [string stringByReplacingOccurrencesOfString:@"\\ "
                                                         withString:DVTEscapedSpacePlaceholder];
    NSArray<NSString *> *pieces = [protected componentsSeparatedByString:@" "];

    NSMutableArray<NSString *> *fragments = [NSMutableArray arrayWithCapacity:pieces.count];
    for (NSString *piece in pieces) {
        /* Apple skips empty pieces rather than keeping them, so runs of spaces
           collapse instead of yielding empty strings. */
        if (piece.length == 0) {
            continue;
        }
        [fragments addObject:[piece stringByReplacingOccurrencesOfString:DVTEscapedSpacePlaceholder
                                                             withString:@" "]];
    }
    /* Copying the mutable array also reproduces the concrete class Apple gets
       for free: an empty array, a single-element array, or an ordinary one. */
    return [fragments copy];
}