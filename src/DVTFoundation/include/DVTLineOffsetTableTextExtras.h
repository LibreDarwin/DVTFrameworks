//
//  DVTLineOffsetTableTextExtras.h
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

#ifndef DVT_LINE_OFFSET_TABLE_TEXT_EXTRAS_H
#define DVT_LINE_OFFSET_TABLE_TEXT_EXTRAS_H

#import <Foundation/Foundation.h>
#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Maps UTF-16 offsets in a string onto line indices.

 `offsets[i]` is the offset at which line `i` begins, so there are
 `count - 1` addressable lines: a string with `n` line breaks yields
 `n + 1` line starts plus a terminating entry, i.e. `count == n + 2`.

 The last entry is always the length of the string, which makes the table
 usable for translating a line index into a half-open character range
 without a separate length. `baseLine` and `baseOffset` are unused by the
 table itself; initialisation leaves `baseLine` as `NSNotFound` and
 `baseOffset` as `0`.

 All offsets are expressed in UTF-16 code units, so they match
 `-[NSString length]` rather than user-perceived character counts.
 */
typedef struct {
    NSUInteger count;
    NSUInteger capacity;
    NSUInteger *_Nullable offsets;
    NSInteger baseLine;
    NSUInteger baseOffset;
} DVTTextLineOffsetTable;

/**
 Computes the start offset of every line in `text`.

 A line break is `\n`, `\r`, `\r\n`, `U+0085` (NEXT LINE), `U+2028` (LINE
 SEPARATOR) or `U+2029` (PARAGRAPH SEPARATOR). `\r\n` counts as a single
 break, and vertical tab and form feed do not break lines.

 @param text The string to scan. May be empty.
 @param outOffsets On return, receives a `malloc`-allocated array owned by the
        caller, who must release it with `free()`.
 @return The number of entries written to `*outOffsets`, always at least `2`.
 */
DVT_EXTERN NSUInteger DVTGetLineStartOffsets(NSString *text, NSUInteger *_Nonnull *_Nonnull outOffsets);

/**
 Fills `table` with the line offsets of `text`.

 Any offsets the table already held are overwritten; the caller owns the
 resulting array and must release it with `free()`.
 */
DVT_EXTERN void DVTInitializeLineOffsetTable(DVTTextLineOffsetTable *table, NSString *text);

/**
  Translates a range of lines into the character range they cover.

  `lineRange.location` selects the first line and `lineRange.length` the
  number of lines; a range that runs past the end of the table is clamped to
  the last addressable line. The length is a line *delta*, not a count, so
  `{0, 1}` is the first line and `{0, 0}` is empty -- which is what makes this
  the inverse of a location's `-lineRange`, itself reported as
  `{startingLineNumber, endingLineNumber - startingLineNumber}`.

  The table is taken by pointer and never modified.
 */
DVT_EXTERN NSRange DVTCharacterRangeForLineRange(NSRange lineRange,
                                                  const DVTTextLineOffsetTable *_Nonnull offsetTable);

/**
  Translates a range of characters into the range of lines it touches.

  The result always starts on the line holding `characterRange.location` and
  is long enough to cover `characterRange.length` characters, so a character
  range that straddles a line break spans both lines.

  The table is taken by pointer and never modified.
 */
DVT_EXTERN NSRange DVTLineRangeForCharacterRange(NSRange characterRange,
                                                  const DVTTextLineOffsetTable *_Nonnull offsetTable);

NS_ASSUME_NONNULL_END

#endif /* DVT_LINE_OFFSET_TABLE_TEXT_EXTRAS_H */