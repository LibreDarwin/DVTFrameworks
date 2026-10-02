//
//  DVTTextDocumentLocation.h
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

#ifndef DVT_TEXT_DOCUMENT_LOCATION_H
#define DVT_TEXT_DOCUMENT_LOCATION_H

#import <Foundation/Foundation.h>
#import "DVTDefines.h"
#import "DVTDocumentLocation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 A `DVTDocumentLocation` that also says *where* in the document it points.

 A text location carries two independent coordinate systems -- a line and column
 range, and a character range into the document's text -- plus a
 `locationEncoding`. Only one of them has to be specified: an unspecified
 coordinate is `NSNotFound`, which is also what every field defaults to, so a
 location built by `-initWithDocumentURL:timestamp:` names a document but no
 position within it.

 ## Validation

 A location is valid when its line and column numbers are either both specified
 or both unspecified, and when the start precedes the end:

 - exactly one of `-startingLineNumber` / `-endingLineNumber` equal to `NSNotFound`
   is an error;
 - exactly one of `-startingColumnNumber` / `-endingColumnNumber` equal to `NSNotFound`
   is an error;
 - `-startingLineNumber > -endingLineNumber` is an error;
 - within a single line, `-startingColumnNumber > -endingColumnNumber` is an error.

 `-characterRange` is not validated; a location may carry an arbitrary range
 alongside an unspecified line and column range.

 The initializers validate and *assert*, so passing an inconsistent location
 raises rather than quietly producing a nonsensical object. Use
 `+validateStartingColumnNumber:...error:` to find out first: it reports the same
 problems as an `NSError` in the `com.apple.DVTFoundation` domain with code `-1`.
 */
@interface DVTTextDocumentLocation : DVTDocumentLocation

/**
 The first column of the location, or `NSNotFound`.

 Columns are counted from zero, and are meaningless unless the line numbers are
 specified.
 */
@property(readonly) NSInteger startingColumnNumber;

/**
 The column just past the end of the location, or `NSNotFound`.

 The end is exclusive, so a location covering the whole of line 3 has a starting
 column of `0` and an ending column equal to that line's length.
 */
@property(readonly) NSInteger endingColumnNumber;

/**
 The first line of the location, or `NSNotFound`.

 Lines are counted from zero.
 */
@property(readonly) NSInteger startingLineNumber;

/**
 The line just past the end of the location, or `NSNotFound`.

 The end line is exclusive.
 */
@property(readonly) NSInteger endingLineNumber;

/**
 The location expressed as a range of lines.

 `{ -startingLineNumber, -endingLineNumber - -startingLineNumber + 1 }`, and
 `{ NSNotFound, 0 }` when either line number is unspecified. The length is
 therefore one for a single-line location, and the range is never empty for a
 fully specified one.
 */
@property(readonly) NSRange lineRange;

/**
 The location expressed as a range of characters in the document's text.

 Independent of the line and column range: a location may specify one, the other,
 or both.
 */
@property(readonly) NSRange characterRange;

/**
 How the line and column numbers should be interpreted.
 */
@property(readonly) NSInteger locationEncoding;

/**
 An arbitrary object associated with the location by its creator.

 Unretained, and not copied -- it exists only so that a caller can hang state off
 a location, and the location does not keep it alive.
 */
@property(readwrite, nullable, assign) id representedObject;

/**
 Associates `object` with the location without retaining it.
 */
- (void)setRepresentedObject:(nullable id)object;

/**
 A location naming `documentURL` but no position within it.

 Every line and column number is `NSNotFound`, `-characterRange` is
 `{ NSNotFound, 0 }` and `-locationEncoding` is `0`. This is the designated
 initializer for the subclass and the one every other initializer funnels
 through.
 */
- (instancetype)initWithDocumentURL:(nullable NSURL *)documentURL timestamp:(nullable NSNumber *)timestamp;

/**
 The fully specified initializer, taking both coordinate systems at once.

 Validates the arguments and asserts on a location that is not well formed.
 */
- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(id)timestamp
               startingColumnNumber:(NSInteger)startingColumnNumber
                 endingColumnNumber:(NSInteger)endingColumnNumber
                  startingLineNumber:(NSInteger)startingLineNumber
                    endingLineNumber:(NSInteger)endingLineNumber
                     characterRange:(NSRange)characterRange
                   locationEncoding:(NSInteger)locationEncoding;

/**
 The internal counterpart of the fully specified initializer.

 Identical in behaviour, and public only because it is the selector the other
 initializers dispatch through.
 */
- (instancetype)_initWithDocumentURL:(NSURL *)documentURL
                           timestamp:(id)timestamp
                startingColumnNumber:(NSInteger)startingColumnNumber
                  endingColumnNumber:(NSInteger)endingColumnNumber
                   startingLineNumber:(NSInteger)startingLineNumber
                     endingLineNumber:(NSInteger)endingLineNumber
                      characterRange:(NSRange)characterRange
                    locationEncoding:(NSInteger)locationEncoding;

/**
 As the fully specified initializer, with `-characterRange` left unspecified.
 */
- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(id)timestamp
               startingColumnNumber:(NSInteger)startingColumnNumber
                 endingColumnNumber:(NSInteger)endingColumnNumber
                  startingLineNumber:(NSInteger)startingLineNumber
                    endingLineNumber:(NSInteger)endingLineNumber
                   locationEncoding:(NSInteger)locationEncoding;

/**
 As the fully specified initializer, with both `-characterRange` and
 `-locationEncoding` left unspecified.
 */
- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(id)timestamp
               startingColumnNumber:(NSInteger)startingColumnNumber
                 endingColumnNumber:(NSInteger)endingColumnNumber
                  startingLineNumber:(NSInteger)startingLineNumber
                    endingLineNumber:(NSInteger)endingLineNumber;

/**
 As the fully specified initializer, with `-locationEncoding` left unspecified.
 */
- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(id)timestamp
               startingColumnNumber:(NSInteger)startingColumnNumber
                 endingColumnNumber:(NSInteger)endingColumnNumber
                  startingLineNumber:(NSInteger)startingLineNumber
                    endingLineNumber:(NSInteger)endingLineNumber
                     characterRange:(NSRange)characterRange;

/**
 A location covering `lineRange`, with the columns left unspecified.

 The line numbers become `-lineRange.location` and
 `-lineRange.location + -lineRange.length - 1`, so that `-lineRange` reads back
 unchanged.
 */
- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(id)timestamp
                           lineRange:(NSRange)lineRange;

/**
 A location covering `characterRange`, with the columns and lines left
 unspecified.
 */
- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(id)timestamp
                      characterRange:(NSRange)characterRange;

/**
 As `-initWithDocumentURL:timestamp:characterRange:`, with an explicit
 `-locationEncoding`.
 */
- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(id)timestamp
                      characterRange:(NSRange)characterRange
                    locationEncoding:(NSInteger)locationEncoding;

/**
 A description naming the timestamp, URL, both ranges and the encoding.
 */
- (nullable NSString *)description;

/**
 `-isEqualToCounterpartWithIdenticalClass:compareTimestamps:` extended with the
 subclass's own state: the encoding, all four line and column numbers, and the
 character range.
 */
- (BOOL)isEqualToCounterpartWithIdenticalClass:(DVTDocumentLocation *)counterpart
                             compareTimestamps:(BOOL)compareTimestamps;

/**
 Combines `-super`'s hash with `-startingLineNumber` and
 `-characterRange.length`, in that order.

 Each step multiplies the running value by 33 and adds the next input. The
 ending line, the columns, the encoding and the character range's location are
 all left out, so two locations that compare unequal can still hash equally.
 */
- (NSUInteger)hash;

/**
 Orders locations by the same fields `-isEqual:` compares.
 */
- (NSComparisonResult)compare:(nullable id)object;

/**
 A new location covering the same position in `url`.
 */
- (instancetype)copyWithURL:(nullable NSURL *)url;

@end

@interface DVTTextDocumentLocation (DVTTextDocumentLocationConstruction)

/**
 The reason a location is not well formed, or `nil` when it is.

 The returned string is the same text `-validateStartingColumnNumber:...error:`
 puts in the error's localized description, and names the offending fields.
 */
+ (nullable NSString *)validateFailureMessageForStartingColumnNumber:(NSInteger)startingColumnNumber
                                                  endingColumnNumber:(NSInteger)endingColumnNumber
                                                   startingLineNumber:(NSInteger)startingLineNumber
                                                     endingLineNumber:(NSInteger)endingLineNumber
                                                      characterRange:(NSRange)characterRange
                                                    locationEncoding:(NSInteger)locationEncoding;

/**
 Validates a location without asserting.

 Returns `YES` and leaves `error` untouched for a well formed location; otherwise
 returns `NO` and populates `error` with the message from
 `+validateFailureMessageForStartingColumnNumber:...`.
 */
+ (BOOL)validateStartingColumnNumber:(NSInteger)startingColumnNumber
                   endingColumnNumber:(NSInteger)endingColumnNumber
                    startingLineNumber:(NSInteger)startingLineNumber
                      endingLineNumber:(NSInteger)endingLineNumber
                       characterRange:(NSRange)characterRange
                     locationEncoding:(NSInteger)locationEncoding
                               error:(NSError **)error;

/**
 Asserts when the location is not well formed.

 This is what the initializers call, which is why an inconsistent location
 raises instead of being rejected.
 */
+ (void)assertValidityOfStartingColumnNumber:(NSInteger)startingColumnNumber
                          endingColumnNumber:(NSInteger)endingColumnNumber
                           startingLineNumber:(NSInteger)startingLineNumber
                             endingLineNumber:(NSInteger)endingLineNumber
                              characterRange:(NSRange)characterRange
                            locationEncoding:(NSInteger)locationEncoding;

/**
 Text locations are archivable.
 */
+ (BOOL)supportsSecureCoding;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_TEXT_DOCUMENT_LOCATION_H */
