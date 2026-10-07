//
//  DVTFindPattern.m
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

#import "DVTFindPattern.h"

#import "DVTCodingAdditions.h"

static NSString *const NSFindPatternRegularExpressionKey = @"NSFindPatternRegularExpressionKey";
static NSString *const NSFindPatternDisplayStringKey = @"NSFindPatternDisplayStringKey";
static NSString *const NSFindPatternTokenStringKey = @"NSFindPatternTokenStringKey";
static NSString *const NSFindPatternTokenReplacementStringKey = @"NSFindPatternTokenReplacementStringKey";
static NSString *const NSFindPatternTokenGroupIDKey = @"NSFindPatternTokenGroupIDKey";
static NSString *const NSFindPatternTokenCaptureGroupIDKey = @"NSFindPatternTokenCaptureGroupIDKey";
static NSString *const NSFindPatternTokenAllowsBackreferencesKey = @"NSFindPatternTokenAllowsBackreferencesKey";
static NSString *const NSFindPatternTokenIsNegationKey = @"NSFindPatternTokenIsNegationKey";
static NSString *const NSFindPatternTokenUniqueIDKey = @"NSFindPatternTokenUniqueIDKey";

@interface DVTFindPattern ()
- (void)_setUniqueID:(NSString *)uniqueID;
- (void)generateNewUniqueID;
@end

@implementation DVTFindPattern {
    BOOL _allowsBackreferences;
    BOOL _isNegation;
    NSString *_displayString;
    NSString *_regularExpression;
    NSString *_tokenString;
    NSInteger _groupID;
    NSInteger _captureGroupID;
    NSString *_uniqueID;
    NSInteger _repeatedPatternID;
    NSString *_replacementString;
}

@synthesize displayString = _displayString;
@synthesize regularExpression = _regularExpression;
@synthesize tokenString = _tokenString;
@synthesize replacementString = _replacementString;
@synthesize uniqueID = _uniqueID;
@synthesize groupID = _groupID;
@synthesize captureGroupID = _captureGroupID;
@synthesize repeatedPatternID = _repeatedPatternID;
@synthesize allowsBackreferences = _allowsBackreferences;
@synthesize isNegation = _isNegation;

+ (instancetype)placeholderFindPattern {
    static DVTFindPattern *sPlaceholderFindPattern = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        DVTFindPattern *pattern = [[DVTFindPattern alloc] init];
        pattern.displayString = @" ";
        pattern.tokenString = @" ";
        pattern.regularExpression = @"";
        pattern.replacementString = @"";
        pattern.allowsBackreferences = NO;
        pattern.isNegation = NO;
        pattern.groupID = 0;
        pattern.captureGroupID = 0;
        [pattern _setUniqueID:@""];
        sPlaceholderFindPattern = pattern;
    });
    return sPlaceholderFindPattern;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self == nil || ![coder allowsKeyedCoding]) {
        return self;
    }

    _regularExpression = [coder dvt_decodeStringForKey:NSFindPatternRegularExpressionKey] ?: @"";
    _displayString = [coder dvt_decodeStringForKey:NSFindPatternDisplayStringKey] ?: @"";
    _tokenString = [coder dvt_decodeStringForKey:NSFindPatternTokenStringKey] ?: @"";
    _replacementString = [coder dvt_decodeStringForKey:NSFindPatternTokenReplacementStringKey] ?: @"";
    _groupID = [coder decodeIntForKey:NSFindPatternTokenGroupIDKey];
    _captureGroupID = [coder decodeIntForKey:NSFindPatternTokenCaptureGroupIDKey];
    _allowsBackreferences = [coder decodeBoolForKey:NSFindPatternTokenAllowsBackreferencesKey];
    _isNegation = [coder decodeBoolForKey:NSFindPatternTokenIsNegationKey];
    _uniqueID = [coder dvt_decodeStringForKey:NSFindPatternTokenUniqueIDKey];
    if (_uniqueID == nil) {
        [self generateNewUniqueID];
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        return;
    }

    [coder encodeObject:self.regularExpression forKey:NSFindPatternRegularExpressionKey];
    [coder encodeObject:self.displayString forKey:NSFindPatternDisplayStringKey];
    [coder encodeObject:self.tokenString forKey:NSFindPatternTokenStringKey];
    [coder encodeObject:self.replacementString forKey:NSFindPatternTokenReplacementStringKey];
    [coder encodeInteger:self.groupID forKey:NSFindPatternTokenGroupIDKey];
    [coder encodeInteger:self.captureGroupID forKey:NSFindPatternTokenCaptureGroupIDKey];
    [coder encodeBool:self.allowsBackreferences forKey:NSFindPatternTokenAllowsBackreferencesKey];
    [coder encodeBool:self.isNegation forKey:NSFindPatternTokenIsNegationKey];
    [coder encodeObject:self.uniqueID forKey:NSFindPatternTokenUniqueIDKey];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    DVTFindPattern *object = [[[self class] allocWithZone:zone] init];
    if (object != nil) {
        object.displayString = self.displayString;
        object.tokenString = self.tokenString;
        object.regularExpression = self.regularExpression;
        object.allowsBackreferences = self.allowsBackreferences;
        object.isNegation = self.isNegation;
        object.groupID = self.groupID;
        object.captureGroupID = self.captureGroupID;
        object.replacementString = self.replacementString;
        [object _setUniqueID:self.uniqueID];
    }
    return object;
}

#pragma mark - Property-list serialization

- (instancetype)initWithPropertyListRepresentation:(id)propertyListRepresentation {
    DVTFindPattern *object = [[[self class] alloc] init];
    if (object != nil) {
        object->_regularExpression = [[propertyListRepresentation objectForKey:NSFindPatternRegularExpressionKey] copy];
        object->_displayString = [[propertyListRepresentation objectForKey:NSFindPatternDisplayStringKey] copy];
        object->_tokenString = [[propertyListRepresentation objectForKey:NSFindPatternTokenStringKey] copy];
        object->_replacementString = [[propertyListRepresentation objectForKey:NSFindPatternTokenReplacementStringKey] copy];
        object->_groupID = [[propertyListRepresentation objectForKey:NSFindPatternTokenGroupIDKey] intValue];
        object->_captureGroupID = [[propertyListRepresentation objectForKey:NSFindPatternTokenCaptureGroupIDKey] intValue];
        object->_allowsBackreferences = [[propertyListRepresentation objectForKey:NSFindPatternTokenAllowsBackreferencesKey] boolValue];
        object->_isNegation = [[propertyListRepresentation objectForKey:NSFindPatternTokenIsNegationKey] boolValue];
        object->_uniqueID = [[propertyListRepresentation objectForKey:NSFindPatternTokenUniqueIDKey] copy];
    }
    return object;
}

- (id)propertyListRepresentation {
    NSMutableDictionary *propertyListRepresentation = [NSMutableDictionary dictionaryWithCapacity:8];
    if (self.regularExpression != nil) {
        [propertyListRepresentation setObject:self.regularExpression forKey:NSFindPatternRegularExpressionKey];
    }
    if (self.displayString != nil) {
        [propertyListRepresentation setObject:self.displayString forKey:NSFindPatternDisplayStringKey];
    }
    if (self.tokenString != nil) {
        [propertyListRepresentation setObject:self.tokenString forKey:NSFindPatternTokenStringKey];
    }
    if (self.replacementString != nil) {
        [propertyListRepresentation setObject:self.replacementString forKey:NSFindPatternTokenReplacementStringKey];
    }
    [propertyListRepresentation setObject:@(self.groupID) forKey:NSFindPatternTokenGroupIDKey];
    [propertyListRepresentation setObject:@(self.captureGroupID) forKey:NSFindPatternTokenCaptureGroupIDKey];
    [propertyListRepresentation setObject:@(self.allowsBackreferences) forKey:NSFindPatternTokenAllowsBackreferencesKey];
    [propertyListRepresentation setObject:@(self.isNegation) forKey:NSFindPatternTokenIsNegationKey];
    if (self.uniqueID != nil) {
        [propertyListRepresentation setObject:self.uniqueID forKey:NSFindPatternTokenUniqueIDKey];
    }
    return propertyListRepresentation;
}

#pragma mark - Expressions

- (NSString *)replaceExpression {
    if (self.replacementString != nil) {
        return self.replacementString;
    }
    if (self.captureGroupID >= 1) {
        return [NSString stringWithFormat:@"$%ld", (long)self.captureGroupID];
    }
    return @"";
}

- (NSString *)backreferenceExpression {
    if (self.captureGroupID >= 1) {
        return [NSString stringWithFormat:@"(?:\\%ld)", (long)self.captureGroupID];
    }
    return @"";
}

#pragma mark - Equality

- (BOOL)isEqualToFindPattern:(DVTFindPattern *)findPattern {
    if (findPattern == nil) {
        return NO;
    }
    if (self.regularExpression != findPattern.regularExpression && ![self.regularExpression isEqual:findPattern.regularExpression]) {
        return NO;
    }
    if (self.tokenString != findPattern.tokenString && ![self.tokenString isEqual:findPattern.tokenString]) {
        return NO;
    }
    if (self.displayString != findPattern.displayString && ![self.displayString isEqual:findPattern.displayString]) {
        return NO;
    }
    if (self.replacementString != findPattern.replacementString && ![self.replacementString isEqual:findPattern.replacementString]) {
        return NO;
    }
    if (self.uniqueID != findPattern.uniqueID && ![self.uniqueID isEqual:findPattern.uniqueID]) {
        return NO;
    }
    if (self.allowsBackreferences != findPattern.allowsBackreferences) {
        return NO;
    }
    if (self.isNegation != findPattern.isNegation) {
        return NO;
    }
    if (self.groupID != findPattern.groupID) {
        return NO;
    }
    if (self.captureGroupID != findPattern.captureGroupID) {
        return NO;
    }
    if (self.repeatedPatternID != findPattern.repeatedPatternID) {
        return NO;
    }
    return YES;
}

- (BOOL)isEqual:(id)object {
    if (object == nil || ![object isKindOfClass:DVTFindPattern.class]) {
        return NO;
    }
    return [object isEqualToFindPattern:self];
}

- (NSUInteger)hash {
    return self.regularExpression.hash * 33 + self.displayString.hash;
}

#pragma mark - Description

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ {\n\tregularExpression = \"%@\"\n\tuniqueID = \"%@\"\n\trepeatedPatternID = \"%ld\"\n}",
            [super description],
            self.regularExpression,
            self.uniqueID,
            (long)self.repeatedPatternID];
}

#pragma mark - Internal unique-ID management

- (void)_setUniqueID:(NSString *)uniqueID {
    if (uniqueID != _uniqueID) {
        _uniqueID = [uniqueID copy];
    }
}

- (void)generateNewUniqueID {
    [self _setUniqueID:[[NSUUID UUID] UUIDString]];
}

@end
