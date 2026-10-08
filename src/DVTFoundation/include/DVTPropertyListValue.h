//
//  DVTPropertyListValue.h
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

#ifndef DVT_PROPERTY_LIST_VALUE_H
#define DVT_PROPERTY_LIST_VALUE_H

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSError.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSString.h>

#include "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Coerce an object to one of the six types a property list can hold.

 A property list is a closed set: string, data, date, number, array,
 dictionary. An `NSDictionary` read back from one is therefore not *narrowable* to
 anything, but code that wants a particular type out of a plist-shaped object
 still has to ask for it, and each question has exactly two honest answers --
 "here it is" or "no". These accessors answer that question, returning the
 receiver when it already is the requested type and `nil` when it is not.

 **The answer is the receiver, not an equal copy.** Subclasses pass, so a
 mutable string satisfies `dvt_plistStringValue` and a mutable array satisfies
 `dvt_plistArrayValue`.

 @note These are deliberately not conversions. Nothing parses a string into a
 number or decodes data into a string, because a coercion that could fail has to
 report *how* it failed, and these report only "not this type".
 */

/**
 The contract a class answers to become decodable from a property list value.

 DVTFoundation never implements this initializer: in Apple's binary
 `initWithPropertyListValue:error:` appears only as a call site — the decoding
 selectors below hand plist fragments to it — so the implementing side lives
 with whatever framework defines the class, as it does for Apple. What the
 binary does fix is the shape of the call: one plist value in, one instance or
 `nil` plus a filled-in `error` out. This protocol is that shape, declared here
 so the call sites compile; the form (a protocol rather than, say, an
 `NSObject` category) is an inference, since headers leave no trace in a Mach-O
 method list.
 */
@protocol DVTPropertyListValueDecoding <NSObject>

/**
 Decodes a property list value into a new instance.

 @param value The plist fragment to decode; never `nil` at Apple's call sites.
 @param error Filled in when `value` cannot be decoded. May be `NULL`.
 @return The decoded instance, or `nil` on failure.
 */
- (nullable instancetype)initWithPropertyListValue:(id)value error:(NSError **)error;

@end

@interface NSString (DVTPropertyListValue)

/** The receiver. A string is already a plist string, whatever it contains. */
- (id)dvt_plistStringValue;
/** Always `nil`: a string is not a number. `@"12"` does not become `12`. */
- (nullable id)dvt_plistNumberValue;
/** Always `nil`. */
- (nullable id)dvt_plistDateValue;
/** Always `nil`. */
- (nullable id)dvt_plistArrayValue;
/** Always `nil`. */
- (nullable id)dvt_plistDictionaryValue;
/** Always `nil`. */
- (nullable id)dvt_plistDataValue;

@end

/**
 The same six questions, asked of data.
 */
@interface NSData (DVTPropertyListValue)

/** Always `nil`. Data is not decoded into a string, empty or otherwise. */
- (nullable id)dvt_plistStringValue;
/** The receiver, empty data included. */
- (id)dvt_plistDataValue;
/** Always `nil`. */
- (nullable id)dvt_plistNumberValue;
/** Always `nil`. */
- (nullable id)dvt_plistDateValue;
/** Always `nil`. */
- (nullable id)dvt_plistArrayValue;
/** Always `nil`. */
- (nullable id)dvt_plistDictionaryValue;

@end

/**
 The same six questions, asked of a date.
 */
@interface NSDate (DVTPropertyListValue)

/** Always `nil`. */
- (nullable id)dvt_plistStringValue;
/** Always `nil`. */
- (nullable id)dvt_plistDataValue;
/** Always `nil`. */
- (nullable id)dvt_plistNumberValue;
/** The receiver. */
- (id)dvt_plistDateValue;
/** Always `nil`. */
- (nullable id)dvt_plistArrayValue;
/** Always `nil`. */
- (nullable id)dvt_plistDictionaryValue;

@end

/**
 The same six questions, asked of a number.

 A number is the one type that answers a *different* type's question, and the
 only place in the family where a new object is built: `dvt_plistStringValue`
 returns `stringValue`. A boolean yields `1` rather than `YES`, and a double
 keeps its decimal point, because the answer is `-[NSNumber stringValue]` and not
 a hand-rolled format.
 */
@interface NSNumber (DVTPropertyListValue)

/** The receiver's `stringValue`. Always a new string, never `nil`. */
- (id)dvt_plistStringValue;
/** Always `nil`. */
- (nullable id)dvt_plistDataValue;
/** The receiver. */
- (id)dvt_plistNumberValue;
/** Always `nil`: a number is not a date. */
- (nullable id)dvt_plistDateValue;
/** Always `nil`. */
- (nullable id)dvt_plistArrayValue;
/** Always `nil`. */
- (nullable id)dvt_plistDictionaryValue;

@end

/**
 The same six questions, asked of an array.
 */
@interface NSArray (DVTPropertyListValue)

/** Always `nil`. */
- (nullable id)dvt_plistStringValue;
/** Always `nil`. */
- (nullable id)dvt_plistDataValue;
/** Always `nil`. */
- (nullable id)dvt_plistNumberValue;
/** Always `nil`. */
- (nullable id)dvt_plistDateValue;
/** The receiver, empty array included. */
- (id)dvt_plistArrayValue;
/** Always `nil`. */
- (nullable id)dvt_plistDictionaryValue;

/**
 Decodes every member by handing it to `klass`'s `initWithPropertyListValue:error:`
 and answers the array of the results.

 The whole decode fails when any single member fails: the first member whose
 init returns `nil` (writing into `error`) makes the whole method return `nil`.
 It never returns a shorter array, so a returned array is all `klass` instances
 and a `nil` return means at least one member was not decodable.

 @param klass The class the members are decoded into. Must implement
        `initWithPropertyListValue:error:`.
 @param error Filled in when a member fails to decode; left alone otherwise. May
        be `NULL`. Which member failed is left vague: the block runs through the
        strict mapper, so the failing member's own `error` is what comes back.
 @return One decoded object per receiver member, or `nil` if any member failed.
 */
- (nullable NSArray *)dvt_decodeObjectsOfClass:(Class)klass error:(NSError **)error;

@end

/** The `NSError` domain for the failures reported below. */
DVT_EXTERN NSString *const DVTPropertyListValueDecodingErrorDomain;

/**
 The same six questions, asked of a dictionary, plus the four methods a
 container alone needs: two lookups and two decoders.

 **The two lookup `ForKey:` methods and
 `dvt_decodePlistObjectForKey:ofClass:error:` are the family's only methods
 that build their own failure report**, because a dictionary is a container: a
 missing key and a key holding the wrong type are both plausible and need
 telling apart. The lookups return `nil` on failure and write an `NSError` in
 `DVTPropertyListValueDecodingErrorDomain` with code `0` and only
 `NSLocalizedDescription` set; the decoder claims only the missing-key case,
 leaving a present value's failure to the class being decoded.
 */
@interface NSDictionary (DVTPropertyListValue)

/** Always `nil`. */
- (nullable id)dvt_plistStringValue;
/** Always `nil`. */
- (nullable id)dvt_plistDataValue;
/** Always `nil`. */
- (nullable id)dvt_plistNumberValue;
/** Always `nil`. */
- (nullable id)dvt_plistDateValue;
/** Always `nil`. */
- (nullable id)dvt_plistArrayValue;
/** The receiver, empty dictionary included. */
- (id)dvt_plistDictionaryValue;

/**
 The value at `key` when it is an `NSArray`.

 Reports a missing key and a wrong-typed key differently:

 - missing: `Missing NSArray value for key: <key>`
 - wrong type: `Found <actual class> value (<debug description>), instead of NSArray for key: <key>`

 The value is rendered with `-debugDescription`, so empty data appears as `<>`
 and an array as `<NSConstantArray 0x…>(\n    1\n)`.

 @param key The key to look under.
 @param error Filled in on failure, left alone on success. May be `NULL`.
 @return The array, or `nil` with `error` set.
 */
- (nullable NSArray *)dvt_plistArrayForKey:(NSString *)key error:(NSError **)error;

/**
 The value at `key` when it is an `NSDictionary`, with the same two failure
 messages naming `NSDictionary`.

 @param key The key to look under.
 @param error Filled in on failure, left alone on success. May be `NULL`.
 @return The dictionary, or `nil` with `error` set.
 */
- (nullable NSDictionary *)dvt_plistDictionaryForKey:(NSString *)key error:(NSError **)error;

/**
 Decodes the value at `key` by handing it to `klass`'s
 `initWithPropertyListValue:error:`.

 The method reports exactly one failure itself — a key with no value — and
 leaves every other failure to the decoder: a present value is passed straight
 to `[[klass alloc] initWithPropertyListValue:value error:error]`, whose result
 (success or a `nil` with its own `error`) is the answer. A missing key answers
 `nil` and, when `error` is not `NULL`, writes
 `Missing plist representation of <class> for key: <key>`, where `<class>` is
 `NSStringFromClass(ofClass)` — the class that *wanted* a value, not the class
 that would have held one. With `error == NULL` a miss is a bare `nil`.

 @param key The key to look under.
 @param ofClass The class to decode the value into; must implement
        `initWithPropertyListValue:error:`.
 @param error Filled in on failure, left alone on success. May be `NULL`.
 @return The decoded instance, or `nil` — missing key, or a failed decode.
 */
- (nullable id)dvt_decodePlistObjectForKey:(NSString *)key
                                   ofClass:(Class)ofClass
                                     error:(NSError **)error;

/**
 Decodes the array at `key` member by member.

 Two lookups chained: `dvt_plistArrayForKey:error:` first, so a missing or
 wrong-typed key reports *its* message (`Missing NSArray value for key: …`,
 `Found … instead of NSArray for key: …`) and a `nil` array short-circuits the
 rest — a message to `nil` answers `nil` and `error` keeps the lookup's
 failure. A present array then goes through
 `dvt_decodeObjectsOfClass:error:`, so one undecodable member fails the whole
 call with that member's error.

 @param key The key to look under.
 @param klass The class the members are decoded into.
 @param error Filled in on failure, left alone on success. May be `NULL`.
 @return One decoded object per member, or `nil` with `error` set.
 */
- (nullable NSArray *)dvt_decodePlistArrayForKey:(NSString *)key
                                  objectsOfClass:(Class)klass
                                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_PROPERTY_LIST_VALUE_H */
