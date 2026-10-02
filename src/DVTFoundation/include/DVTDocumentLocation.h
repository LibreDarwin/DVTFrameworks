//
//  DVTDocumentLocation.h
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

#ifndef DVT_DOCUMENT_LOCATION_H
#define DVT_DOCUMENT_LOCATION_H

#import <Foundation/Foundation.h>
#import "DVTDefines.h"
#import "DVTSimpleSerialization.h"

NS_ASSUME_NONNULL_BEGIN

@class DVTDocumentLocation;

/**
 The base class for the locations Xcode hands around internally: a document URL,
 the timestamp of the revision that URL was last known to name, and whatever
 else a subclass adds.

 A `DVTDocumentLocation` on its own only carries a URL and a timestamp. The
 interesting subclass is `DVTTextDocumentLocation`, which adds line, column and
 character ranges.

 ## Identity

 Two locations are equal when they are the *same class* and their URLs match and,
 unless asked not to, their timestamps match. Because `-hash` deliberately
 considers only the URL, two locations that differ solely in timestamp hash the
 same while comparing unequal; that is legal, just unhelpful, and callers that
 put locations in hashed containers should use `-isEqualDisregardingTimestamp:`
 when the timestamp is not part of the key.
 */
@interface DVTDocumentLocation : NSObject <NSSecureCoding, NSCopying, DVTSimpleSerialization>

/**
 The URL naming the document.

 Retained, and never changed after initialization. A copy is the receiver itself;
 it is `-copyWithURL:` that has to build a new location, because that one really
 does differ.
 */
@property(readonly) NSURL *documentURL;

/**
 The timestamp of the revision this location was resolved against.

 Retained, and compared by `-isEqual:` unless the caller opts out.
 */
@property(readonly) NSNumber *timestamp;

/**
 `-documentURL.absoluteString`, computed on demand.
 */
- (nullable NSString *)documentURLString;

/**
 The scheme of `-documentURL`, or `nil` when the URL is `nil`.
 */
- (nullable NSString *)documentScheme;

/**
 The path of `-documentURL`, or `nil` when the URL is `nil`.
 */
- (nullable NSString *)documentPath;

/**
 The query of `-documentURL`, or `nil` when there is none.

 Apple exposes this through the `documentParameters` spelling, which reads as
 though it were a dictionary; it is in fact the URL's query.
 */
- (nullable NSDictionary<NSString *, NSString *> *)documentParameters;

/**
 A dictionary describing this location well enough to reconstruct it.

 Populated by `-populateLocationParameters:` and consumed by
 `-initWithURL:locationParameters:error:`.
 */
- (NSDictionary<NSString *, id> *)locationParameters;

/**
 The document's location on the pasteboard.

 For a file URL this is the URL's path rather than its absolute string, so that
 dragging a location into another application yields something usable.
 */
@property(readonly, nonatomic) NSString *pasteboardRepresentation;

/**
 Designated initializer for the base class.

 Both arguments are retained. Subclasses add `-initWithDocumentURL:timestamp:`
 variants that funnel through this one.
 */
- (instancetype)initWithDocumentURL:(nullable NSURL *)documentURL timestamp:(nullable NSNumber *)timestamp;

/**
 Reconstructs a location from a URL and the dictionary produced by
 `-populateLocationParameters:`.

 Returns `nil` and populates `error` when `locationParameters` does not describe
 a valid location.
 */
- (nullable instancetype)initWithURL:(NSURL *)url
                  locationParameters:(NSDictionary<NSString *, id> *)locationParameters
                               error:(NSError **)error;

/**
 A new location of the receiver's class pointing at `url`, keeping the receiver's
 timestamp.

 Anything else about the receiver is preserved by the subclass override.
 */
- (instancetype)copyWithURL:(nullable NSURL *)url;

/**
 `-isEqualToCounterpartWithIdenticalClass:compareTimestamps:`, so that
 `compareTimestamps:` can be forwarded without repeating the class check.
 */
- (BOOL)isEqual:(nullable id)object;

/**
 As `-isEqual:`, but ignoring `-timestamp`.

 This is the comparison to use when the timestamp is incidental -- for instance
 when asking whether an edit still applies to the file on disk.
 */
- (BOOL)isEqualDisregardingTimestamp:(nullable id)object;

/**
 The subclass-overridable core of equality.

 Subclasses call `super` first and then compare their own state. The base
 implementation compares `-documentURL`, and additionally `-timestamp` when
 `compareTimestamps` is `YES`. Pointer equality short-circuits each comparison,
 and a `nil` on either side compares unequal unless both are `nil`.
 */
- (BOOL)isEqualToCounterpartWithIdenticalClass:(DVTDocumentLocation *)counterpart
                             compareTimestamps:(BOOL)compareTimestamps;

/**
 `-documentURL.hash`, and nothing else.

 The timestamp is deliberately excluded, so locations that compare unequal can
 still hash equally.
 */
- (NSUInteger)hash;

/**
 Orders locations for sorting. Derived from the class, the URL and the timestamp.
 */
- (NSComparisonResult)compare:(nullable id)object;

/**
 A human-readable description of the URL and timestamp.
 */
- (nullable NSString *)description;

/**
 Fills `locationParameters` with everything needed to rebuild the location.
 */
- (void)populateLocationParameters:(NSMutableDictionary<NSString *, id> *)locationParameters;

/**
 The subclass-overridable core of `-populateLocationParameters:`.

 Subclasses append their own entries after calling `super`. `error` is `NULL`
 for the common, always-successful case.
 */
- (BOOL)_populateLocationParameters:(NSMutableDictionary<NSString *, id> *)locationParameters
              decodableClassName:(NSString *_Nullable *_Nullable)decodableClassName
                             error:(NSError **)error;

/**
 The URL that best identifies this location, together with the class name needed
 to decode it back.

 Returns `nil` and populates `error` when the location cannot be represented.
 */
- (nullable NSURL *)persistableURLRepresentationAndDecodableClassName:(NSString *_Nullable *_Nullable)decodableClassName
                                                               error:(NSError **)error;

/**
 As `-persistableURLRepresentationAndDecodableClassName:error:`, but producing a
 string rather than a URL.

 Some locations have a string form that outlives the URL's file-system
 reachability.
 */
- (nullable NSString *)persistableStringRepresentationAndDecodableClassName:(NSString *_Nullable *_Nullable)decodableClassName
                                                                     error:(NSError **)error;

@end

/**
 Locations built from a Swift-macro expansion report themselves through this
 category, and everything else returns `nil`.
 */
@interface DVTDocumentLocation (DVTGeneratedSwiftMacroLocationRemapping)

/**
 The outermost location this one expands to, or `nil` when it is not itself a
 macro expansion.
 */
- (nullable DVTDocumentLocation *)rootMacroLocationIfApplicable;

@end

@interface DVTDocumentLocation (DVTDocumentLocationConstruction)

/**
 The concrete location class registered under `name`, loading it if needed.

 This is how a serialized location names the class it needs back, and why
 `-supportsSecureCoding` and its siblings are class methods: the decoder has to
 be able to find the class before it has an instance.
 */
+ (Class)documentLocationClassNamedLoadingIfNeeded:(NSString *)name;

/**
 Builds a location from the parts of a URL, for subclasses that construct
 themselves without an `NSURL`.

 The default implementation reassembles the parts into a URL and calls
 `-initWithURL:locationParameters:error:`.
 */
+ (nullable instancetype)documentLocationWithURLScheme:(NSString *)scheme
                                                  path:(NSString *)path
                                    documentParameters:(nullable id)documentParameters
                                     locationParameters:(nullable NSDictionary<NSString *, id> *)locationParameters;

/**
 Class-level equality that compares two locations of possibly different classes.

 Returns `NO` when the two are not of the same class, so that a `DVTTextDocumentLocation`
 never compares equal to a plain `DVTDocumentLocation`.
 */
+ (BOOL)isDocumentLocation:(nullable DVTDocumentLocation *)location
    equalToDocumentLocation:(nullable DVTDocumentLocation *)otherLocation
         compareTimestamps:(BOOL)compareTimestamps;

/**
 Whether locations of this class can be written with `NSKeyedArchiver`.

 `YES` for every class in this hierarchy that is intended to be archived.
 */
+ (BOOL)supportsSecureCoding;

/**
 Whether `-persistableURLRepresentationAndDecodableClassName:error:` returns a
 URL for this class.

 Subclasses for which a URL is lossy -- because the URL alone cannot rebuild the
 location -- return `NO` and are persisted as strings instead.
 */
+ (BOOL)supportsEncodingToPersistableURL;

/**
 Rebuilds a location from its string form, requiring an exact decode.
 */
+ (nullable instancetype)deserializedDocumentLocationForClassName:(NSString *)className
                                             stringRepresentation:(NSString *)stringRepresentation
                                                           error:(NSError **)error;

/**
 As `-deserializedDocumentLocationForClassName:stringRepresentation:error:`, but
 `allowLossyDecoding` permits a decode that drops fields the class cannot
 recover.
 */
+ (nullable instancetype)deserializedDocumentLocationForClassName:(NSString *)className
                                             stringRepresentation:(NSString *)stringRepresentation
                                              allowLossyDecoding:(BOOL)allowLossyDecoding
                                                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_DOCUMENT_LOCATION_H */
