//
//  DVTFindPattern.h
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

#ifndef DVT_FIND_PATTERN_H
#define DVT_FIND_PATTERN_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The state of a find pattern (or of a component list, on DVTFindPatternComponents).

 `DVTFindPatternStatusInvalid` means the pattern has no usable regular
 expression, `DVTFindPatternStatusPlaceholder` means it is the placeholder
 pattern, and `DVTFindPatternStatusValid` means it has a regular expression.
 */
typedef NS_ENUM(NSInteger, DVTFindPatternStatus) {
    DVTFindPatternStatusInvalid = 0,
    DVTFindPatternStatusPlaceholder = 1,
    DVTFindPatternStatusValid = 2,
};

/**
 A single find-pattern component: a search token paired with its regular
 expression, decoration (negation, backreference participation), and the
 replacement text that is substituted in when the pattern is turned into a
 regular expression.
 */
@interface DVTFindPattern : NSObject <NSSecureCoding, NSCopying>

/** The string shown for the pattern in the UI; empty for automatically numbered patterns. */
@property(readwrite, copy) NSString *displayString;

/** The regular expression text this pattern contributes. */
@property(readwrite, copy) NSString *regularExpression;

/** The literal search text the pattern was created from. */
@property(readwrite, copy) NSString *tokenString;

/** The text used as this pattern's replacement in a combined expression. */
@property(readwrite, copy) NSString *replacementString;

/** A unique identifier for this pattern instance. */
@property(readonly, copy) NSString *uniqueID;

/** The 1-based group index this pattern is assigned in a combine operation. */
@property(readwrite) NSInteger groupID;

/** The capture-group index assigned when the pattern participates in a combined expression. */
@property(readwrite) NSInteger captureGroupID;

/** The group index of the expression this pattern repeats; unused in the lone-pattern case. */
@property(readwrite) NSInteger repeatedPatternID;

/** Whether this pattern participates in backreferencing when combined. */
@property(readwrite) BOOL allowsBackreferences;

/** Whether the pattern negates its match. */
@property(readwrite) BOOL isNegation;

/** The shared placeholder pattern, used to mark an empty slot in a component list. */
+ (instancetype)placeholderFindPattern;

/**
 Initializes from the serialized representation produced by -propertyListRepresentation.

 Missing keys decode as nil (or 0 / NO for scalar fields).
 */
- (instancetype)initWithPropertyListRepresentation:(id)propertyListRepresentation;

/** The serialized property-list representation of the receiver. */
- (id)propertyListRepresentation;

/** The replacement expression; `$n` when the pattern has an assigned capture group. */
- (NSString *)replaceExpression;

/** The backreference expression; `(?:\\n)` when the pattern has an assigned capture group. */
- (NSString *)backreferenceExpression;

- (BOOL)isEqualToFindPattern:(DVTFindPattern *)findPattern;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_FIND_PATTERN_H */