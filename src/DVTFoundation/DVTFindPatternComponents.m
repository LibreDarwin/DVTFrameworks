//
//  DVTFindPatternComponents.m
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

#import "DVTFindPatternComponents.h"

#import "DVTAssertions.h"
#import "DVTFoundationClassAdditions.h"

// The characters escaped when a literal string is folded into a regular or
// replacement expression: `$()*+./?[\]^{|}`. Anything else passes through.
static BOOL __characterNeedsEscaping(unichar character)
{
    const uint64_t escapeMask = 0x0780000008000CF1ULL;
    uint32_t index = (uint32_t)(character - 0x24);
    if (index <= 0x3A && (escapeMask & (1ULL << index))) {
        return YES;
    }
    // `{`, `|`, and `}` sit just above the mask's range; `~` does not escape.
    return ((uint32_t)(character - 0x7B)) < 3;
}

// The number of capture groups in `string`: `(` starts a group unless it opens
// a non-capturing `(?:`; a `\` escapes the following character.
static NSUInteger __captureCountOfString(NSString *string)
{
    if (string.length == 0) {
        return 0;
    }
    CFIndex length = (CFIndex)string.length;
    CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, length));
    NSUInteger count = 0;
    for (CFIndex index = 0; index < length; index++) {
        unichar character = CFStringGetCharacterFromInlineBuffer(&buffer, index);
        if (character == '(') {
            if (index + 2 >= length ||
                CFStringGetCharacterFromInlineBuffer(&buffer, index + 1) != '?' ||
                CFStringGetCharacterFromInlineBuffer(&buffer, index + 2) != ':') {
                count++;
            } else {
                index += 2;
            }
        } else if (character == '\\') {
            index++;
        }
    }
    return count;
}

static void __escapeStringIntoMutableString(NSString *string, NSMutableString *result)
{
    CFIndex length = (CFIndex)string.length;
    CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, length));
    for (CFIndex index = 0; index < length; index++) {
        unichar character = CFStringGetCharacterFromInlineBuffer(&buffer, index);
        if (__characterNeedsEscaping(character)) {
            [result appendFormat:@"\\%C", character];
        } else {
            [result appendFormat:@"%C", character];
        }
    }
}

@implementation NSObject (DVTFindPatternComponentTransformation)

- (id)dvt_findPatternComponentRepresentation
{
    return nil;
}

- (id)dvt_findPatternComponentPropertyListRepresentation
{
    DVTAssert(NO, @"0", nil, @"method %@ is a subclass responsibility of %@", [NSString stringWithUTF8String:__func__], NSStringFromClass([self class]));
    return nil;
}

- (NSString *)dvt_findPatternComponentSummary
{
    DVTAssert(NO, @"0", nil, @"method %@ is a subclass responsibility of %@", [NSString stringWithUTF8String:__func__], NSStringFromClass([self class]));
    return nil;
}

- (BOOL)dvt_findPatternHasContent
{
    DVTAssert(NO, @"0", nil, @"method %@ is a subclass responsibility of %@", [NSString stringWithUTF8String:__func__], NSStringFromClass([self class]));
    return NO;
}

@end

@implementation DVTFindPattern (DVTFindPatternComponentTransformation)

- (id)dvt_findPatternComponentPropertyListRepresentation
{
    return self.propertyListRepresentation;
}

- (NSString *)dvt_findPatternComponentSummary
{
    return [NSString stringWithFormat:@"[%@%@]", self.isNegation ? @"!" : @"", self.tokenString];
}

- (BOOL)dvt_findPatternHasContent
{
    return YES;
}

@end

@implementation NSString (DVTFindPatternComponentTransformation)

- (id)dvt_findPatternComponentRepresentation
{
    return self;
}

- (id)dvt_findPatternComponentPropertyListRepresentation
{
    return self;
}

- (NSString *)dvt_findPatternComponentSummary
{
    return self;
}

- (BOOL)dvt_findPatternHasContent
{
    return self.length > 0;
}

@end

@implementation NSDictionary (DVTFindPatternComponentTransformation)

- (id)dvt_findPatternComponentRepresentation
{
    return [[DVTFindPattern alloc] initWithPropertyListRepresentation:self];
}

@end

@implementation DVTFindPatternComponents {
    NSArray *_components;
}

@synthesize components = _components;

- (instancetype)initWithComponents:(NSArray<id> *)components
{
    self = [super init];
    if (!self) {
        return nil;
    }
    _components = [components dvt_arrayByFilteringUsingBlock:^BOOL(id object) {
        return [object dvt_findPatternHasContent];
    }];
    return self;
}

- (NSUInteger)hash
{
    return [_components.firstObject hash] * 33 + [_components.lastObject hash];
}

- (BOOL)isEqualToFindPatternComponents:(DVTFindPatternComponents *)components
{
    return [_components isEqual:components.components];
}

- (BOOL)isEqual:(id)object
{
    DVTFindPatternComponents *components = [object isKindOfClass:[DVTFindPatternComponents class]] ? object : nil;
    return [components isEqualToFindPatternComponents:self];
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    return self;
}

- (NSString *)description
{
    NSString *joined = [[_components dvt_arrayByApplyingBlock:^id(id object) {
        return [NSString stringWithFormat:@"    %@\n", object];
    }] componentsJoinedByString:@""];
    if (joined.length > 0) {
        return [[super description] stringByAppendingFormat:@"[\n%@\n]", joined];
    }
    return [super description];
}

+ (instancetype)emptyComponents
{
    return [[self alloc] initWithComponents:@[]];
}

+ (instancetype)findPatternComponentsWithString:(NSString *)string
{
    return [[self alloc] initWithComponents:string ? @[ string ] : @[]];
}

+ (instancetype)findPatternComponentsFromPasteboardPropertyList:(id)propertyList
{
    if (![propertyList isKindOfClass:[NSArray class]]) {
        return nil;
    }
    NSMutableArray *representations = [NSMutableArray array];
    for (id object in propertyList) {
        id representation = [object dvt_findPatternComponentRepresentation];
        if (!representation) {
            return nil;
        }
        [representations addObject:representation];
    }
    return [[self alloc] initWithComponents:representations];
}

- (id)propertyListRepresentation
{
    return [_components dvt_arrayByApplyingBlock:^id(id object) {
        return [object dvt_findPatternComponentPropertyListRepresentation];
    }];
}

- (NSString *)summary
{
    return [[_components dvt_arrayByApplyingBlock:^id(id object) {
        return [object dvt_findPatternComponentSummary];
    }] componentsJoinedByString:@""];
}

- (BOOL)hasContent
{
    return [_components dvt_anyObjectsPassTest:^BOOL(id object) {
        return [object dvt_findPatternHasContent];
    }];
}

- (NSArray<NSString *> *)stringComponents
{
    return [_components dvt_arrayByFilteringUsingBlock:^BOOL(id object) {
        return [object isKindOfClass:[NSString class]];
    }];
}

- (NSString *)stringByDeletingPatterns
{
    return [[self stringComponents] componentsJoinedByString:@""];
}

- (DVTFindPatternStatus)patternStatus
{
    if ([_components containsObject:[DVTFindPattern placeholderFindPattern]]) {
        return DVTFindPatternStatusPlaceholder;
    }
    return [_components dvt_objectsOfClass:[DVTFindPattern class]].count == 0 ? DVTFindPatternStatusInvalid : DVTFindPatternStatusValid;
}

- (NSString *)regularExpression
{
    return [self regularExpressionEscapingStrings:YES usingBackreferences:YES];
}

- (NSString *)regularExpressionEscapingStrings:(BOOL)escapingStrings usingBackreferences:(BOOL)usingBackreferences
{
    NSMutableArray *seenUniqueIDs = usingBackreferences ? [NSMutableArray array] : nil;
    NSMutableString *result = [NSMutableString string];
    NSUInteger captureCount = 0;

    for (id component in _components) {
        if ([component isKindOfClass:[DVTFindPattern class]]) {
            DVTFindPattern *pattern = component;
            NSString *expression;
            if (pattern.groupID >= 1) {
                if ([seenUniqueIDs containsObject:pattern.uniqueID]) {
                    expression = [pattern backreferenceExpression];
                } else {
                    [pattern setCaptureGroupID:captureCount + 1];
                    [seenUniqueIDs addObject:pattern.uniqueID];
                    expression = [NSString stringWithFormat:@"(%@)", pattern.regularExpression];
                }
            } else {
                expression = [pattern regularExpression];
            }
            [result appendString:expression];
            captureCount += __captureCountOfString(expression);
        } else if ([component isKindOfClass:[NSString class]]) {
            if (escapingStrings) {
                __escapeStringIntoMutableString(component, result);
            } else {
                [result appendString:component];
            }
        }
    }
    return [result copy];
}

- (NSString *)replacementExpression
{
    NSMutableString *result = [NSMutableString string];
    BOOL sawPattern = NO;
    for (id component in _components) {
        if ([component isKindOfClass:[DVTFindPattern class]]) {
            [result appendString:[component replaceExpression]];
            sawPattern = YES;
        } else if ([component isKindOfClass:[NSString class]]) {
            NSUInteger boundary = [result length];
            __escapeStringIntoMutableString(component, result);
            if (sawPattern && [result length] > boundary) {
                if ([[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] characterIsMember:[result characterAtIndex:boundary]]) {
                    [result insertString:@"\\" atIndex:boundary];
                }
                sawPattern = NO;
            }
        }
    }
    return [result copy];
}

@end