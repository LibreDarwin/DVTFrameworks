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

  `DVTCharacterRangeForLineRange` already expresses this as a one-line delta,
  and going through it rather than re-deriving the clamping is what keeps a
  column resolved against the same span the standalone helpers report.

  @param line The line number, as `-startingLineNumber` reports it.
  @param lineOffsetTable The line starts of the string.
  @return The range, or a range located at `NSNotFound` when the table has too few
          entries to describe a line at all.
 */
static NSRange DVTCharacterRangeForLine(NSUInteger line, const DVTTextLineOffsetTable *lineOffsetTable)
{
    return DVTCharacterRangeForLineRange(NSMakeRange(line, 1), lineOffsetTable);
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

NSRange DVTCharacterRangeFromDocumentLocation(DVTDocumentLocation *location, NSString *string,
                                              const DVTTextLineOffsetTable *lineOffsetTable)
{
    /*
     Read the location in the string's own units first. A location recorded in
     UTF-8 bytes has offsets this string cannot be indexed with, so taking its
     character range at its word would report a position somewhere else in the
     text entirely.
     */
    DVTTextDocumentLocation *native =
        DVTConvertLocationToNativeNSStringEncodedLocation((DVTTextDocumentLocation *)location, string, lineOffsetTable);

    NSRange characterRange = native.characterRange;
    if (characterRange.location != NSNotFound) {
        return characterRange;
    }

    NSRange lineRange = native.lineRange;
    if (lineRange.location == NSNotFound) {
        /* No range and no lines: nothing was ever named. The length is kept,
           since it is meaningful on its own. */
        return NSMakeRange(NSNotFound, characterRange.length);
    }

    if (native.startingColumnNumber == NSNotFound) {
        return DVTCharacterRangeForLineRange(lineRange, lineOffsetTable);
    }

    /*
     With columns to work from, anchor on the line the starting column is on and
     reach for the ending column's line only when the range spans more than one.
     Measuring from the start of each line keeps a column meaningful: adding it
     to the start of the range's own first line would be wrong as soon as the
     range began mid-line.
     */
    NSUInteger startOffset = DVTCharacterRangeForLineRange(NSMakeRange(lineRange.location, 1), lineOffsetTable).location;
    NSUInteger endOffset = startOffset;
    if (lineRange.length >= 2) {
        endOffset =
            DVTCharacterRangeForLineRange(NSMakeRange(lineRange.location + lineRange.length - 1, 1), lineOffsetTable)
                .location;
    }

    NSUInteger start = startOffset + native.startingColumnNumber;
    NSUInteger end = endOffset + native.endingColumnNumber;
    return NSMakeRange(start, end - start);
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
