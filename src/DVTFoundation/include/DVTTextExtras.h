//
//  DVTTextExtras.h
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

#ifndef DVT_TEXT_EXTRAS_H
#define DVT_TEXT_EXTRAS_H

#import <Foundation/Foundation.h>
#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
 The line-ending styles Xcode knows about.

 The numbering deliberately matches AppKit's own `NSLineEnding` so the two can be
 used interchangeably.
 */
typedef NS_ENUM(NSInteger, DVTLineEnding) {
    DVTLineEndingNone = 0,
    DVTLineEndingLF = 1,
    DVTLineEndingCR = 2,
    DVTLineEndingCRLF = 3,
};

/**
 The span of a string a find operation should match.

 The numeric values do *not* run in the order the names would suggest, and
 `DVTStringFromFindMatchStyle` depends on it: `0` is a substring match and `2` is
 the whole-word one. Match strings are compared case-sensitively, and anything
 unrecognised is reported as a plain `Contains` search, which is the same value
 that style already has — so an unknown string is indistinguishable from
 `Contains`.
 */
typedef NS_ENUM(NSInteger, DVTFindsMatchStyle) {
    DVTFindsMatchStyleContains = 0,
    DVTFindsMatchStyleStartsWith = 1,
    DVTFindsMatchStyleWholeWords = 2,
    DVTFindsMatchStyleEndsWith = 3,
};

/**
 The literal characters for a line-ending style, or `nil` when the value is
 outside the known range.

 `DVTLineEndingNone` is not the empty string; it is `nil`, as is any value above
 `DVTLineEndingCRLF`. Both LF and CR are single characters, so the length alone
 does not tell the two apart.
 */
DVT_EXTERN NSString *_Nullable DVTStringFromLineEnding(DVTLineEnding lineEnding);

/**
 The display name for a find match style.

 Values above `DVTFindsMatchStyleEndsWith` do not assert; they fall back to
 `WholeWords`, the same string the `WholeWords` case returns.
 */
DVT_EXTERN NSString *DVTStringFromFindMatchStyle(DVTFindsMatchStyle style);

/**
 The find match style named by `string`, or `DVTFindsMatchStyleContains` when
 `string` names none of them.

 Matching is case-sensitive: `WholeWords` is recognised but `wholewords` is not.
 */
DVT_EXTERN DVTFindsMatchStyle DVTFindMatchStyleFromString(NSString *string);

/**
 Splits `string` into fragments at its spaces, treating a backslash-escaped space
 as part of the surrounding fragment rather than a separator.

 Escaped spaces are hidden behind the `\<space>` placeholder first, so that they
 survive the split, and restored afterwards. Empty fragments are dropped rather
 than returned as empty strings, so the result has no empty elements and is
 itself empty for a string that is empty or all spaces. Note that the literal
 text `\<space>` in the input is indistinguishable from an escaped space and is
 also decoded to a single space.

 `string` must not be `nil`; the result is autoreleased.
 */
DVT_EXTERN NSArray<NSString *> *DVTTextFragmentsForStringPreservingEscapedSpaces(NSString *string);

NS_ASSUME_NONNULL_END

#endif /* DVT_TEXT_EXTRAS_H */