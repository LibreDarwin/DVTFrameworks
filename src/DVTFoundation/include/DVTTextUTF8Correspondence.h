//
//  DVTTextUTF8Correspondence.h
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

#import <Foundation/Foundation.h>
#import "DVTDefines.h"

/**
 Translates a UTF-16 index into the offset of the same character in the
 string's UTF-8 encoding, and back.

 The offsets are not a character count. `index` counts UTF-16 code units, so a
 character outside the basic multilingual plane advances it by two, while the
 answer counts UTF-8 bytes, so the same character advances it by four. An
 offset that lands in the middle of a multi-byte sequence belongs to no
 character and resolves to the start of the next whole character.

 An ASCII-backed string is passed straight through, and CoreFoundation decides
 what that means: a string literal or a copy is stored one byte per character
 and returns the index unchanged even when it is past the end, while the same
 characters built with `-stringWithCharacters:length:` are stored two bytes
 each, take the general path, and clamp to the length. Nothing at the
 `NSString` level tells the two apart, so the general path clamps `index` and
 the shortcut does not.

 An unpaired surrogate still counts as a four-byte sequence. On the way back
 the whole pair is consumed, so an offset just past the end of a lone surrogate
 can come back one character beyond the end of the string. Passing such an
 index back in as the location of a range trips an assertion, because the
 range helpers convert the location first and then use the result as the base
 for the length.
 */
DVT_EXTERN NSUInteger DVTCorrespondingUTF8ByteIndexWithIndexInString(NSString *string, NSUInteger index);

/** The inverse of `DVTCorrespondingUTF8ByteIndexWithIndexInString`. */
DVT_EXTERN NSUInteger DVTIndexInStringWithCorrespondingUtf8ByteIndex(NSString *string, NSUInteger utf8ByteIndex);

/** As above, for a range. The length is measured from the converted location. */
DVT_EXTERN NSRange DVTCorrespondingUTF8ByteRangeWithRangeOfString(NSString *string, NSRange range);

/** As above, for a range. The length is measured from the converted location. */
DVT_EXTERN NSRange DVTRangeOfStringWithCorrespondingUtf8ByteRange(NSString *string, NSRange utf8ByteRange);
