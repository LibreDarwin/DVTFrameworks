//
//  DVTDocumentLocationConversion.h
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

#ifndef DVT_DOCUMENT_LOCATION_CONVERSION_H
#define DVT_DOCUMENT_LOCATION_CONVERSION_H

#import <Foundation/Foundation.h>

#import "DVTDefines.h"
#import "DVTDocumentLocation.h"
#import "DVTLineOffsetTableTextExtras.h"
#import "DVTTextDocumentLocation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 The `-locationEncoding` a location measured in the string's own UTF-16 units
 carries, and the one a location measured in UTF-8 bytes carries.

 The two are not interchangeable: `-[NSString length]` counts UTF-16 code units,
 so a location handed to anything that indexes by byte has to be translated
 first.
 */
typedef NS_ENUM(NSInteger, DVTLocationEncoding) {
    /** Offsets are UTF-16 code-unit indices, as `-[NSString length]` counts them. */
    DVTLocationEncodingNative = 0,
    /** Offsets are UTF-8 byte indices. */
    DVTLocationEncodingUTF8 = 1,
};

/**
 Translates `location` from the string's own UTF-16 units into UTF-8 bytes.

 Both the `-characterRange` and the column numbers are translated, and the result
 carries `DVTLocationEncodingUTF8`. `-documentURL`, `-timestamp` and the line
 numbers pass through untouched, because a line number means the same thing in
 either encoding.

 @param location The location to translate.
 @param string The string `location` is measured against. Its line starts have to
        be in `lineOffsetTable`.
 @param lineOffsetTable The line starts of `string`.
 @return A new location, or `location` itself when it already carries
        `DVTLocationEncodingUTF8`.
 */
DVT_EXTERN DVTTextDocumentLocation *DVTConvertLocationToUTF8EncodedLocation(
    DVTTextDocumentLocation *location, NSString *string, const DVTTextLineOffsetTable *lineOffsetTable);

/**
 Translates `location` from UTF-8 bytes into the string's own UTF-16 units.

 The mirror of `DVTConvertLocationToUTF8EncodedLocation`, and the result
 carries `DVTLocationEncodingNative`.

 @param location The location to translate.
 @param string The string `location` is measured against. Its line starts have to
        be in `lineOffsetTable`.
 @param lineOffsetTable The line starts of `string`.
 @return A new location, or `location` itself when it already carries
        `DVTLocationEncodingNative` or names no position at all.
 */
DVT_EXTERN DVTTextDocumentLocation *DVTConvertLocationToNativeNSStringEncodedLocation(
    DVTTextDocumentLocation *location, NSString *string, const DVTTextLineOffsetTable *lineOffsetTable);

/**
  The characters `location` names, read in the string's own UTF-16 units.

  `location` is converted to native offsets first, so one recorded in UTF-8
  bytes is read correctly rather than taken at its word. A location that already
  carries a character range is therefore returned unchanged, and only one that
  carries just lines and columns is measured against `string`.

  @param location The location to read.
  @param string The string `location` is measured against.
  @param lineOffsetTable The line starts of `string`.
  @return The characters `location` names, or a range located at `NSNotFound`
          when it names no position at all.
 */
DVT_EXTERN NSRange DVTCharacterRangeFromDocumentLocation(DVTDocumentLocation *location, NSString *string,
                                                         const DVTTextLineOffsetTable *lineOffsetTable);

NS_ASSUME_NONNULL_END

#endif /* DVT_DOCUMENT_LOCATION_CONVERSION_H */
