/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroDefinitionCondition.
 */

#ifndef DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITION_H
#define DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITION_H

#import <Foundation/Foundation.h>

#import "DVTMacroDefinitionConditionParameter.h"

/* A single "<parameter> matches <value pattern>" constraint of a conditional
 * macro definition.  Value patterns are glob patterns interpreted with
 * fnmatch(3).
 *
 * Instances are uniqued: +conditionWithParameterName:valuePattern: always
 * returns the same instance for the same (parameter, pattern) pair, so
 * pointer equality is the same as equality of the two strings.  Apple's
 * class does not implement -isEqual: or -hash either, so this is observable. */
@interface DVTMacroDefinitionCondition : NSObject <NSCopying> {
	char *_valuePatternUTF8Bytes;
	unsigned int _requiredLiteralPrefix;
}

@property (readonly) DVTMacroDefinitionConditionParameter *parameter;
@property (readonly, copy) NSString *valuePattern;

/* Returns nil when the parameter name is unknown. */
+ (DVTMacroDefinitionCondition *)conditionWithParameterName:(NSString *)name valuePattern:(NSString *)pattern;

/* Designated initialiser.  Call +conditionWithParameterName:valuePattern:
 * instead; the uniquing invariant is the caller's responsibility. */
- (id)initWithParameter:(DVTMacroDefinitionConditionParameter *)parameter valuePattern:(NSString *)pattern onlyCallableFromWithinCreateUniquedInstance:(BOOL)onlyCallable;

/* Looks up the parameter in -values (keyed by parameter name, string
 * values); a missing value only matches the "*" pattern. */
- (BOOL)evaluateForParameterValues:(NSDictionary *)values;

- (long long)compare:(id)other;
- (long long)compareCondition:(DVTMacroDefinitionCondition *)condition;
- (long long)compareToConditionWithKnowIdenticalParameter:(DVTMacroDefinitionCondition *)condition;

/* "[<parameter name>=<value pattern>]" */
- (NSString *)subscriptRepresentation;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITION_H */
