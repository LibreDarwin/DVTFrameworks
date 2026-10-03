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

@end

/** The `NSError` domain for the key lookups below. */
DVT_EXTERN NSString *const DVTPropertyListValueDecodingErrorDomain;

/**
 The same six questions, asked of a dictionary, plus the two lookups a
 dictionary alone can answer.

 **The two `ForKey:` methods are the family's only methods that report *why*
 they failed**, because a dictionary is a container: a missing key and a key
 holding the wrong type are both plausible and need telling apart. Both return
 `nil` on failure and write an `NSError` in `DVTPropertyListValueDecodingErrorDomain`
 with code `0` and only `NSLocalizedDescription` set.
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

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_PROPERTY_LIST_VALUE_H */
