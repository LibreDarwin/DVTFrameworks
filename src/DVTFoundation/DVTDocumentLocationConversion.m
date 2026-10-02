//
//  DVTDocumentLocationConversion.m
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

#import "DVTDocumentLocationConversion.h"

#import "DVTAssertions.h"
#import "DVTTextUTF8Correspondence.h"

/**
 The character range of `line` together with the start of the line after it.

 The range deliberately runs to the *next* line's start rather than to this
 line's last character. A column can legitimately name the position just past
 the terminator, and slicing only up to the last character would leave the
 translation helper without the code unit it needs to resolve that position.

 Clamping matters here for the same reason `+DVTGetLineStartOffsets` appends a
 final entry: it records one offset per line start *plus* one at the end of the
 string, so the last nameable line is the last entry and a line number past it
 has to be pulled back rather than used to index off the end of the array.

  @param line The line number, as `-startingLineNumber` reports it.
  @param lineOffsetTable The line starts of the string.
  @return The range, or a range located at `NSNotFound` when the table has too few
         entries to describe a line at all.

  @note A table too short to index is a caller error. Apple traps on it, and so
        does nothing here rather than aborting: every table
        `+DVTGetLineStartOffsets` or `DVTInitializeLineOffsetTable` produces
        carries at least two entries -- even for an empty string -- so this
        cannot be reached by a well-formed table and the two behaviours never
        meet in practice.
 */
static NSRange DVTCharacterRangeForLine(NSUInteger line, const DVTTextLineOffsetTable *lineOffsetTable)
{
    if (lineOffsetTable->capacity <= 1) {
        return NSMakeRange(NSNotFound, 0);
    }

    NSUInteger lastIndex = lineOffsetTable->capacity - 1;
    NSUInteger firstIndex = MIN(line, lastIndex);
    NSUInteger secondIndex = MIN(line + 1, lastIndex);

    NSUInteger start = lineOffsetTable->offsets[firstIndex];
    NSUInteger end = lineOffsetTable->offsets[secondIndex];

    /*
     A table built for a fragment carries the fragment's own line numbering, and
     `baseOffset` shifts its offsets back into the coordinates of the whole
     document. Applies only once the fragment's first line is reached.
     */
    if (lineOffsetTable->baseLine != NSNotFound && lineOffsetTable->baseLine <= (NSInteger)firstIndex) {
        start += lineOffsetTable->baseOffset;
    }
    if (lineOffsetTable->baseLine != NSNotFound && lineOffsetTable->baseLine <= (NSInteger)secondIndex) {
        end += lineOffsetTable->baseOffset;
    }

    return NSMakeRange(start, end - start);
}

/**
 Translates one column number from one encoding to the other.

 @param columnNumber The column to translate. `NSNotFound` is passed through
        rather than translated: a location with no column has to stay without
        one instead of picking up whatever the helper makes of `NSNotFound`.
 @param line The line the column belongs to, or `NSNotFound`.
 @param string The string the location is measured against.
 @param lineOffsetTable The line starts of `string`.
 @param toUTF8 `YES` to convert a UTF-16 column into a UTF-8 byte index, `NO` for
        the reverse.
 @return The converted column, or `columnNumber` unchanged when `line` names no
        line the table knows.
 */
static NSUInteger DVTConvertColumn(NSUInteger columnNumber, NSUInteger line, NSString *string,
                                   const DVTTextLineOffsetTable *lineOffsetTable, BOOL toUTF8)
{
    if (columnNumber == NSNotFound || line == NSNotFound) {
        return columnNumber;
    }

    NSRange lineRange = DVTCharacterRangeForLine(line, lineOffsetTable);
    if (lineRange.location == NSNotFound) {
        return columnNumber;
    }

    NSString *lineText = [string substringWithRange:lineRange];
    if (toUTF8) {
        return DVTCorrespondingUTF8ByteIndexWithIndexInString(lineText, columnNumber);
    }

    return DVTIndexInStringWithCorrespondingUtf8ByteIndex(lineText, columnNumber);
}

/**
 Rebuilds `location` with the character range, both columns and the encoding
 replaced.

 Everything else -- the URL, the timestamp and both line numbers -- is carried
 over untouched, because a line number means the same thing in either encoding
 and the document did not move while the location was translated.
 */
static DVTTextDocumentLocation *DVTLocationByReplacingOffsets(DVTTextDocumentLocation *location, NSRange characterRange,
                                                             NSUInteger startingColumnNumber,
                                                             NSUInteger endingColumnNumber,
                                                             DVTLocationEncoding locationEncoding)
{
    return [[DVTTextDocumentLocation alloc] initWithDocumentURL:location.documentURL
                                                       timestamp:location.timestamp
                                            startingColumnNumber:startingColumnNumber
                                              endingColumnNumber:endingColumnNumber
                                               startingLineNumber:location.startingLineNumber
                                                 endingLineNumber:location.endingLineNumber
                                                  characterRange:characterRange
                                                locationEncoding:locationEncoding];
}

DVTTextDocumentLocation *DVTConvertLocationToUTF8EncodedLocation(
    DVTTextDocumentLocation *location, NSString *string, const DVTTextLineOffsetTable *lineOffsetTable)
{
    if (location.locationEncoding == DVTLocationEncodingUTF8) {
        return location;
    }

    DVTAssert(location.locationEncoding == DVTLocationEncodingNative,
              @"A location can only be converted to UTF-8 from native offsets", nil, @"encoding was %ld",
              (long)location.locationEncoding);

    NSRange characterRange = location.characterRange;
    NSUInteger startingColumnNumber = location.startingColumnNumber;
    NSUInteger endingColumnNumber = location.endingColumnNumber;

    /*
     A location with no range has no bytes to translate, and its range length is
     meaningful on its own -- so keep the pair rather than run `NSNotFound`
     through the correspondence helper, which would reinterpret the length as
     an offset from the end of the string.
     */
    if (characterRange.location != NSNotFound) {
        characterRange = DVTCorrespondingUTF8ByteRangeWithRangeOfString(string, characterRange);
    }

    startingColumnNumber = DVTConvertColumn(startingColumnNumber, location.startingLineNumber, string, lineOffsetTable,
                                            YES);
    endingColumnNumber = DVTConvertColumn(endingColumnNumber, location.endingLineNumber, string, lineOffsetTable, YES);

    return DVTLocationByReplacingOffsets(location, characterRange, startingColumnNumber, endingColumnNumber,
                                         DVTLocationEncodingUTF8);
}

DVTTextDocumentLocation *DVTConvertLocationToNativeNSStringEncodedLocation(
    DVTTextDocumentLocation *location, NSString *string, const DVTTextLineOffsetTable *lineOffsetTable)
{
    if (location.locationEncoding == DVTLocationEncodingNative) {
        return location;
    }

    /*
     A location that names neither a character nor a column has nothing to
     translate, so hand the caller back the location they passed in rather than
     an indistinguishable copy.
     */
    if (location.characterRange.location == NSNotFound && location.startingColumnNumber == NSNotFound) {
        return location;
    }

    DVTAssert(location.locationEncoding == DVTLocationEncodingUTF8,
              @"A location can only be converted to native offsets from UTF-8", nil, @"encoding was %ld",
              (long)location.locationEncoding);

    NSRange characterRange = location.characterRange;
    NSUInteger startingColumnNumber = location.startingColumnNumber;
    NSUInteger endingColumnNumber = location.endingColumnNumber;

    if (characterRange.location != NSNotFound) {
        characterRange = DVTRangeOfStringWithCorrespondingUtf8ByteRange(string, characterRange);
    }

    startingColumnNumber = DVTConvertColumn(startingColumnNumber, location.startingLineNumber, string, lineOffsetTable,
                                            NO);
    endingColumnNumber = DVTConvertColumn(endingColumnNumber, location.endingLineNumber, string, lineOffsetTable, NO);

    return DVTLocationByReplacingOffsets(location, characterRange, startingColumnNumber, endingColumnNumber,
                                         DVTLocationEncodingNative);
}
