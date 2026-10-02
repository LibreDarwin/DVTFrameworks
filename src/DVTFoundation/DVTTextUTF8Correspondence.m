//
//  DVTTextUTF8Correspondence.m
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

#import "DVTTextUTF8Correspondence.h"

#import <CoreFoundation/CoreFoundation.h>

#import "DVTAssertions.h"

/**
 Apple's shortcut is not a test of the characters but of the storage: it asks
 CoreFoundation for the string's ASCII buffer and takes the shortcut only if
 one already exists. That is worth mirroring rather than approximating, because
 the two answers differ for a real input. `-stringWithCharacters:length:` keeps
 a short all-ASCII string in two bytes per character and has no ASCII buffer, so
 it takes the general path and clamps an out-of-range index, while a literal or
 a copy of one has a buffer and returns the index untouched. Comparing the
 characters instead would silently pick the other answer for one of the two.
 */
static BOOL DVTStringIsASCIIBacked(NSString *string)
{
    return CFStringGetCStringPtr((__bridge CFStringRef)string, kCFStringEncodingASCII) != NULL;
}

/**
 The number of UTF-8 bytes a UTF-16 code unit occupies, or zero to mean the
 unit is the leading half of a surrogate pair and so takes the trailing half
 with it.
 */
static NSUInteger DVTUTF8Width(unichar unit, BOOL *isHighSurrogate)
{
    *isHighSurrogate = NO;

    if (unit <= 0x7F) {
        return 1;
    }
    if (unit <= 0x7FF) {
        return 2;
    }
    if ((unit >> 10) == 0x36) {
        *isHighSurrogate = YES;
        return 4;
    }
    return 3;
}

/**
 The UTF-8 offset of the character at UTF-16 index `index`, counted from
 `from`. Characters are read in blocks, because a string can be stored either
 way round and only one of the two forms can be addressed directly.
 */
static NSUInteger DVTUTF8IndexFromUTF16Index(NSString *string, NSUInteger from, NSUInteger index)
{
    if (DVTStringIsASCIIBacked(string)) {
        return index;
    }

    DVTAssert(from <= [string length], @"The starting index must be inside the string", nil, @"%@",
              @"start index out of range");

    NSUInteger remaining = [string length] - from;
    NSUInteger count = MIN(remaining, index);
    NSUInteger bytes = 0;
    NSUInteger position = 0;
    BOOL skipNext = NO;
    unichar buffer[64];
    NSUInteger blockCapacity = sizeof(buffer) / sizeof(buffer[0]);

    while (position < count) {
        NSUInteger block = MIN(count - position, blockCapacity);
        [string getCharacters:buffer range:NSMakeRange(from + position, block)];

        for (NSUInteger i = 0; i < block; i++) {
            if (skipNext) {
                /* The trailing half of a surrogate pair was already counted as
                   part of the four bytes its leading half announced. A leading
                   half at the end of a block carries the skip into the next
                   block, so the pair is never split across the two. */
                skipNext = NO;
                continue;
            }
            BOOL isHighSurrogate = NO;
            bytes += DVTUTF8Width(buffer[i], &isHighSurrogate);
            skipNext = isHighSurrogate;
        }

        position += block;
    }

    return bytes;
}

/**
 The UTF-16 index of the character covering UTF-8 byte offset `utf8ByteIndex`,
 walking a buffer of code units already extracted from the string.
 */
static NSUInteger DVTUTF16IndexFromUTF8IndexImpl(const unichar *buffer, NSUInteger unitCount, NSUInteger utf8ByteIndex)
{
    if (utf8ByteIndex == 0) {
        return 0;
    }

    NSUInteger units = 0;
    NSUInteger bytes = 0;

    while (units < unitCount) {
        BOOL isHighSurrogate = NO;
        bytes += DVTUTF8Width(buffer[units], &isHighSurrogate);
        if (isHighSurrogate) {
            units++;
        }
        units++;

        /* A surrogate pair is counted whole, so the walk can stop one unit past
           the end of the string. That is what lets an offset just past a lone
           surrogate come back beyond the end, which the caller then trips over
           if it uses the result as a base. */
        if (units >= unitCount || bytes >= utf8ByteIndex) {
            break;
        }
    }

    return units;
}

/** The inverse of `DVTUTF8IndexFromUTF16Index`. */
static NSUInteger DVTUTF16IndexFromUTF8Index(NSString *string, NSUInteger from, NSUInteger utf8ByteIndex)
{
    if (DVTStringIsASCIIBacked(string)) {
        return utf8ByteIndex;
    }

    DVTAssert(from <= [string length], @"The starting index must be inside the string", nil, @"%@",
              @"start index out of range");

    NSUInteger remaining = [string length] - from;
    unichar stackBuffer[64];
    unichar *buffer = stackBuffer;
    if (remaining > (sizeof(stackBuffer) / sizeof(stackBuffer[0]))) {
        buffer = (unichar *)malloc(sizeof(unichar) * remaining);
    }
    [string getCharacters:buffer range:NSMakeRange(from, remaining)];
    NSUInteger result = DVTUTF16IndexFromUTF8IndexImpl(buffer, remaining, utf8ByteIndex);
    if (buffer != stackBuffer) {
        free(buffer);
    }

    return result;
}

NSUInteger DVTCorrespondingUTF8ByteIndexWithIndexInString(NSString *string, NSUInteger index)
{
    return DVTUTF8IndexFromUTF16Index(string, 0, index);
}

NSUInteger DVTIndexInStringWithCorrespondingUtf8ByteIndex(NSString *string, NSUInteger utf8ByteIndex)
{
    return DVTUTF16IndexFromUTF8Index(string, 0, utf8ByteIndex);
}

NSRange DVTCorrespondingUTF8ByteRangeWithRangeOfString(NSString *string, NSRange range)
{
    NSUInteger location = DVTUTF8IndexFromUTF16Index(string, 0, range.location);
    NSUInteger length = DVTUTF8IndexFromUTF16Index(string, range.location, range.length);
    return NSMakeRange(location, length);
}

NSRange DVTRangeOfStringWithCorrespondingUtf8ByteRange(NSString *string, NSRange utf8ByteRange)
{
    NSUInteger location = DVTUTF16IndexFromUTF8Index(string, 0, utf8ByteRange.location);
    NSUInteger length = DVTUTF16IndexFromUTF8Index(string, location, utf8ByteRange.length);
    return NSMakeRange(location, length);
}

/**
  The context stores the string's length and its two code-unit buffers at the
  offsets the original uses, so a caller that initialized the context with one
  implementation can query it with the other. The originals are private types,
  so they are described here rather than imported.

  An ASCII-backed string needs nothing but the flag: every offset is already an
  offset, so the query functions answer without looking at the string. The
  original stops after writing the flag in that case and leaves the rest of the
  context as the caller had it, so this does too.
 */
void DVTInitializeIndexOfStringQueryContext(NSString *string, DVTStringIndexQueryContext *context)
{
    context->isASCIIBacked = DVTStringIsASCIIBacked(string) ? 1 : 0;
    if (context->isASCIIBacked) {
        return;
    }

    context->string = (__bridge void *)string;
    context->characters = CFStringGetCharactersPtr((__bridge CFStringRef)string);
    context->asciiBytes = CFStringGetCStringPtr((__bridge CFStringRef)string, kCFStringEncodingASCII);
    context->reserved2[0] = 0;
    context->reserved2[1] = [string length];
    context->reserved2[2] = 0;
    context->reserved2[3] = 0;
    context->length = [string length];

    memset(context->cachedByteOffsets, 0, sizeof(context->cachedByteOffsets));
    memset(context->cachedUTF16Indices, 0, sizeof(context->cachedUTF16Indices));
}

NSUInteger DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(NSUInteger utf8ByteIndex,
                                                                          DVTStringIndexQueryContext *context)
{
    if (context->isASCIIBacked) {
        return utf8ByteIndex;
    }

    NSString *string = (__bridge NSString *)context->string;
    NSUInteger length = (NSUInteger)context->length;

    /* Reusing a slot means resuming the walk from there, so the answer can
       differ from an uncached one: on a surrogate pair, resuming from the
       pair's trailing half skips the pair's leading half and lands one unit
       further on. The original behaves the same way, which is why a warm
       context is not expected to agree with `DVTIndexInStringWithCorrespondingUtf8ByteIndex`.
       A slot at or before the wanted offset is the only safe one to resume
       from, since the mapping only moves forward.

       `from` counts code units, so the number of bytes to walk is measured from
       the slot rather than from the start of the string: passing the absolute
       offset instead would start the walk already past the target and
       overshoot. */
    NSUInteger from = 0;
    NSUInteger bytesToWalk = utf8ByteIndex;
    NSUInteger slot = 4;

    for (NSUInteger i = 0; i < 4; i++) {
        NSUInteger cachedOffset = (NSUInteger)context->cachedByteOffsets[i];
        NSUInteger cachedIndex = (NSUInteger)context->cachedUTF16Indices[i];

        if (cachedOffset == utf8ByteIndex) {
            return cachedIndex;
        }
        if (cachedOffset <= utf8ByteIndex && cachedIndex <= length && cachedIndex > from) {
            from = cachedIndex;
            bytesToWalk = utf8ByteIndex - cachedOffset;
            slot = i;
        }
    }

    NSUInteger result = from + DVTUTF16IndexFromUTF8Index(string, from, bytesToWalk);

    if (slot == 4) {
        /* No slot qualified as a starting point, so take the next free one and
           otherwise reuse the first. Which slot is written is not observable:
           each slot answers only for the offset recorded beside it. */
        for (NSUInteger i = 0; i < 4; i++) {
            if (context->cachedByteOffsets[i] == 0 && context->cachedUTF16Indices[i] == 0) {
                slot = i;
                break;
            }
        }
        if (slot == 4) {
            slot = 0;
        }
    }
    context->cachedByteOffsets[slot] = utf8ByteIndex;
    context->cachedUTF16Indices[slot] = result;

    return result;
}

NSRange DVTRangeOfStringWithCorrespondingUtf8ByteRangeWithQueryContext(NSUInteger utf8ByteLocation,
                                                                       NSUInteger utf8ByteLength,
                                                                       DVTStringIndexQueryContext *context)
{
    NSUInteger location = DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(utf8ByteLocation, context);
    NSUInteger end =
        DVTIndexInStringWithCorrespondingUtf8ByteIndexWithQueryContext(utf8ByteLocation + utf8ByteLength, context);
    return NSMakeRange(location, end - location);
}
