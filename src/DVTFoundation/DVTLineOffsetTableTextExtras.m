//
//  DVTLineOffsetTableTextExtras.m
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

#import "DVTLineOffsetTableTextExtras.h"

#import "DVTAssertions.h"

/**
 The UTF-16 code units that terminate a line. Vertical tab and form feed are
 deliberately absent: they are not line breaks for this purpose.
 */
static inline BOOL DVTLOTIsLineBreak(unichar character)
{
    switch (character) {
        case 0x000A: // LINE FEED
        case 0x000D: // CARRIAGE RETURN
        case 0x0085: // NEXT LINE
        case 0x2028: // LINE SEPARATOR
        case 0x2029: // PARAGRAPH SEPARATOR
            return YES;
        default:
            return NO;
    }
}

NSUInteger DVTGetLineStartOffsets(NSString *text, NSUInteger **outOffsets)
{
    DVTAssert(outOffsets != NULL, @"The line offset output pointer must not be NULL", nil, @"%@", @"expected a valid pointer");

    NSUInteger length = text.length;

    /* Every character could be a line break, and we always append the length. */
    NSUInteger *offsets = (NSUInteger *)malloc((length + 2) * sizeof(NSUInteger));
    if (offsets == NULL) {
        *outOffsets = NULL;
        return 0;
    }

    NSUInteger count = 0;
    offsets[count++] = 0;

    NSUInteger index = 0;
    while (index < length) {
        unichar character = [text characterAtIndex:index];
        if (DVTLOTIsLineBreak(character)) {
            /* A CRLF pair is a single break, so the next line starts after both. */
            if (character == 0x000D && (index + 1) < length && [text characterAtIndex:index + 1] == 0x000A) {
                index++;
            }
            offsets[count++] = index + 1;
        }
        index++;
    }

    offsets[count++] = length;

    *outOffsets = offsets;
    return count;
}

void DVTInitializeLineOffsetTable(DVTTextLineOffsetTable *table, NSString *text)
{
    DVTAssert(table != NULL, @"The line offset table must not be NULL", nil, @"%@", @"expected a valid pointer");

    NSUInteger count = DVTGetLineStartOffsets(text, &table->offsets);
    table->count = count;
    table->capacity = count;
    table->baseLine = NSNotFound;
    table->baseOffset = 0;
}

/*
 The offset recorded for one line index, with the table's shift applied.

 `DVTInitializeLineOffsetTable` leaves `baseLine` as `NSNotFound`, so a table
 built for the whole string shifts nothing. A table adopted onto a larger
 string names the first line it covers in `baseLine` and adds `baseOffset` to
 every line from there on, which is what keeps the two endpoints of a range
 expressed in the same units.
 */
static NSUInteger DVTOffsetAtLine(const DVTTextLineOffsetTable *offsetTable, NSUInteger line)
{
    NSUInteger offset = offsetTable->offsets[line];
    if (offsetTable->baseLine != NSNotFound && line >= (NSUInteger)offsetTable->baseLine) {
        offset += offsetTable->baseOffset;
    }
    return offset;
}

NSRange DVTCharacterRangeForLineRange(NSRange lineRange, const DVTTextLineOffsetTable *offsetTable)
{
    DVTAssert(offsetTable->count >= 2, @"A line offset table needs at least two entries", nil, @"%lu",
              (unsigned long)offsetTable->count);

    NSUInteger firstLine = lineRange.location;
    NSUInteger lastLine = firstLine + lineRange.length;

    /* count - 1 is the terminating length entry, so it is the last index we may read. */
    NSUInteger lastIndex = offsetTable->count - 1;
    if (firstLine > lastIndex) {
        firstLine = lastIndex;
    }
    if (lastLine > lastIndex) {
        lastLine = lastIndex;
    }

    NSUInteger start = DVTOffsetAtLine(offsetTable, firstLine);
    return NSMakeRange(start, DVTOffsetAtLine(offsetTable, lastLine) - start);
}

NSRange DVTLineRangeForCharacterRange(NSRange characterRange, const DVTTextLineOffsetTable *offsetTable)
{
    DVTAssert(offsetTable->count >= 2, @"A line offset table needs at least two entries", nil, @"%lu",
              (unsigned long)offsetTable->count);

    NSUInteger character = characterRange.location;
    NSUInteger characterEnd = character + characterRange.length;

    /* Find the last line start that is not past the character. */
    NSUInteger low = 0;
    NSUInteger high = offsetTable->count - 1;
    while (low < high) {
        NSUInteger middle = low + ((high - low + 1) / 2);
        if (offsetTable->offsets[middle] <= character) {
            low = middle;
        } else {
            high = middle - 1;
        }
    }

    /* The terminating entry is not a line, so the search cannot select it. */
    NSUInteger lastLine = offsetTable->count - 2;
    if (low > lastLine) {
        low = lastLine;
    }
    NSUInteger location = low;

    /* Grow the range until it covers every character it was asked about. */
    while ((low + 1) < offsetTable->count && characterEnd > offsetTable->offsets[low + 1]) {
        low++;
    }

    /*
     The result may run one line past where it started, and never further than the
     last addressable line, so a range that only clips the trailing empty line
     does not spill into the terminating entry.
     */
    NSUInteger furthest = lastLine;
    if (lastLine < (location + 1)) {
        furthest = location + 1;
    }
    if (low > furthest) {
        low = furthest;
    }

    return NSMakeRange(location, low - location + 1);
}