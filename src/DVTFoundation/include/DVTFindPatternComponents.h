//
//  DVTFindPatternComponents.h
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

#ifndef DVT_FIND_PATTERN_COMPONENTS_H
#define DVT_FIND_PATTERN_COMPONENTS_H

#import <Foundation/Foundation.h>

#import "DVTFindPattern.h"

NS_ASSUME_NONNULL_BEGIN

/**
 An ordered list of find-pattern components: literal search strings and
 `DVTFindPattern` tokens, combined into a single regular expression (or a
 replacement expression).

 `DVTFindPatternComponents` is immutable: the combined expression changes only
 by constructing a new instance.
 */
@interface DVTFindPatternComponents : NSObject <NSCopying>

/** The component list; empty components are dropped at initialization time. */
@property(readonly, copy) NSArray<id> *components;

/** Initializes the receiver with the given components, adopting those that have content. */
- (instancetype)initWithComponents:(NSArray<id> *)components;

/** An empty component list. */
+ (instancetype)emptyComponents;

/** A component list holding the single string component `string`, or empty when it is nil. */
+ (instancetype)findPatternComponentsWithString:(nullable NSString *)string;

/**
 Creates a component list from the pasteboard property list; returns nil when it is not a
 property-list representation of a component list.
 */
+ (nullable instancetype)findPatternComponentsFromPasteboardPropertyList:(nullable id)propertyList;

/** The combined regular expression, escaping literals and uniting patterns as capture groups. */
- (NSString *)regularExpression;

/**
 The combined regular expression, with the literal escape and backreference behavior selected.

 `escapingStrings` escapes the literal string components, and `usingBackreferences`
 wraps a repeated pattern in a non-capturing backreference instead of a new group.
 */
- (NSString *)regularExpressionEscapingStrings:(BOOL)escapingStrings usingBackreferences:(BOOL)usingBackreferences;

/** The combined replacement expression, with literal components escaped. */
- (NSString *)replacementExpression;

/** The property-list representation of the receiver. */
- (id)propertyListRepresentation;

/** A compact summary of the receiver's components. */
- (NSString *)summary;

/** Whether any component has content. */
- (BOOL)hasContent;

/** The receiver's string components, in order. */
- (NSArray<NSString *> *)stringComponents;

/** The receiver's string components concatenated. */
- (NSString *)stringByDeletingPatterns;

/** The status of the receiver's patterns: placeholder, valid, or invalid. */
- (DVTFindPatternStatus)patternStatus;

- (BOOL)isEqualToFindPatternComponents:(DVTFindPatternComponents *)components;

@end

/**
 Adds find-pattern component transforms to any object.

 This is the extension point the find-pattern machinery uses to turn an object
 into a component. NSObject's implementations of everything but the
 property-list representation fail, so the interesting behavior lives in the
 NSString, DVTFindPattern, and NSDictionary (property-list) categories declared
 in the implementation of this class.
 */
@interface NSObject (DVTFindPatternComponentTransformation)

/** The receiver as a component's property-list representation, or nil. */
- (nullable id)dvt_findPatternComponentRepresentation;

/** The property-list representation of the component the receiver stands for. */
- (nullable id)dvt_findPatternComponentPropertyListRepresentation;

/** A short summary of the component the receiver stands for. */
- (nullable NSString *)dvt_findPatternComponentSummary;

/** Whether the component the receiver stands for has content. */
- (BOOL)dvt_findPatternHasContent;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_FIND_PATTERN_COMPONENTS_H */