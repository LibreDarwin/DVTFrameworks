//
//  DVTLineOffsetAwareStringWrapper.h
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

#ifndef DVT_LINE_OFFSET_AWARE_STRING_WRAPPER_H
#define DVT_LINE_OFFSET_AWARE_STRING_WRAPPER_H

#import <Foundation/Foundation.h>

#import "DVTDefines.h"
#import "DVTDocumentLocation.h"
#import "DVTLineOffsetTableTextExtras.h"
#import "DVTTextDocumentLocation.h"

NS_ASSUME_NONNULL_BEGIN

/**
  A string paired with its line-offset table.

  Building the table is not free, and an editor asks the same questions of the
  same text over and over: which characters does this line cover, what line is
  this offset on, and how do I read this location in the encoding I have. This
  caches the table so those questions become arithmetic, and it is the object
  form of the `DVTConvertLocation…` functions — each instance method here is the
  same translation with `-string` and the cached table filled in for you.

  The table is derived, never stored: `-initWithString:` copies the string and
  builds the table from the copy, and archiving writes only the string, so the
  table is rebuilt on decode rather than trusted from an archive. That also
  means an archive of a wrapper is an archive of its text.
 */
@interface DVTLineOffsetAwareStringWrapper : NSObject <NSSecureCoding>

/** The text the line offsets were computed from. */
@property (nonatomic, readonly, copy) NSString *string;

/**
  The designated initializer.

  The string is copied, so later mutation of the argument cannot invalidate the
  table.

  @param string The text to measure. May be empty.
 */
- (instancetype)initWithString:(NSString *)string NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/**
  The character range covered by `lineRange`.

  `lineRange.length` is a line delta rather than a count, matching
  `-[DVTDocumentLocation lineRange]`, so `{0, 1}` is the first line. A range
  running past the end of the text is clamped to its last line.

  @param lineRange The lines to measure.
  @return The range of characters they cover.
 */
- (NSRange)characterRangeForLineRange:(NSRange)lineRange;

/**
  The lines `characterRange` touches.

  The inverse of `-characterRangeForLineRange:`: the result starts on the line
  holding `characterRange.location` and is long enough to cover every character
  asked about, so a range straddling a line break spans both lines.

  @param characterRange The characters to measure.
  @return The lines they fall on.
 */
- (NSRange)lineRangeForCharacterRange:(NSRange)characterRange;

/**
  The character range `location` names, read in the string's own UTF-16 units.

  A location that already carries a character range is taken at its word; one
  that carries only lines and columns is measured against the text. The location
  is converted to native offsets first, so a location recorded in UTF-8 bytes is
  read correctly rather than being taken as UTF-16.

  @param location The location to read.
  @return The characters it names, or a range located at `NSNotFound` when the
          location names no position.
 */
- (NSRange)characterRangeFromDocumentLocation:(DVTDocumentLocation *)location;

/** `location` with its range and columns translated into UTF-8 byte offsets. */
- (nullable DVTTextDocumentLocation *)convertLocationToUTF8EncodedLocation:(DVTTextDocumentLocation *)location;

/** `location` with its range and columns translated into UTF-16 offsets. */
- (nullable DVTTextDocumentLocation *)
    convertLocationToNativeNSStringEncodedLocation:(DVTTextDocumentLocation *)location;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_LINE_OFFSET_AWARE_STRING_WRAPPER_H */
