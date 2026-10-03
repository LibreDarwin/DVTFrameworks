//
//  DVTLineOffsetAwareStringWrapper.m
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

#import "DVTLineOffsetAwareStringWrapper.h"

#import "DVTDocumentLocationConversion.h"

/** The only key an archive of a wrapper carries. */
static NSString *const DVTLineOffsetAwareStringWrapperStringKey = @"string";

/*
 The offset table comes first and the string second, so the stored layout matches
 the order Apple's own class lays these out in.
 */
@implementation DVTLineOffsetAwareStringWrapper {
    DVTTextLineOffsetTable _lineOffsets;
    NSString *_string;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithString:(NSString *)string
{
    self = [super init];
    if (self) {
        /*
         The copy is load-bearing rather than defensive: the table below records
         offsets into the string it was built from, so a mutable argument mutated
         afterwards would leave those offsets pointing at the wrong characters.
         */
        _string = [string copy];
        DVTInitializeLineOffsetTable(&_lineOffsets, _string);
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithString:[coder decodeObjectOfClass:NSString.class
                                                    forKey:DVTLineOffsetAwareStringWrapperStringKey]];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    /* Only the string is archived. The table is derived, so writing it would
       mean writing offsets a decoder has no way to trust. */
    [coder encodeObject:_string forKey:DVTLineOffsetAwareStringWrapperStringKey];
}

- (void)dealloc
{
    free(_lineOffsets.offsets);
}

- (NSString *)debugDescription
{
    /*
     `-description`'s shape -- "<DVTLineOffsetAwareStringWrapper 0x...>" -- with
     the string quoted inside it. Only the newline is escaped, because it is the
     only one that would otherwise break the description across lines; a quote
     or backslash in the string is left exactly as it is.
     */
    return [NSString stringWithFormat:@"<%@ %p  string=\"%@\">", NSStringFromClass(self.class), (void *)self,
                                      [_string stringByReplacingOccurrencesOfString:@"\n"
                                                                           withString:@"\\n"]];
}

- (NSString *)string
{
    return _string;
}

- (NSRange)characterRangeForLineRange:(NSRange)lineRange
{
    return DVTCharacterRangeForLineRange(lineRange, &_lineOffsets);
}

- (NSRange)lineRangeForCharacterRange:(NSRange)characterRange
{
    return DVTLineRangeForCharacterRange(characterRange, &_lineOffsets);
}

- (NSRange)characterRangeFromDocumentLocation:(DVTDocumentLocation *)location
{
    return DVTCharacterRangeFromDocumentLocation(location, _string, &_lineOffsets);
}

- (DVTTextDocumentLocation *)convertLocationToUTF8EncodedLocation:(DVTTextDocumentLocation *)location
{
    return DVTConvertLocationToUTF8EncodedLocation(location, _string, &_lineOffsets);
}

- (DVTTextDocumentLocation *)convertLocationToNativeNSStringEncodedLocation:(DVTTextDocumentLocation *)location
{
    return DVTConvertLocationToNativeNSStringEncodedLocation(location, _string, &_lineOffsets);
}

@end
