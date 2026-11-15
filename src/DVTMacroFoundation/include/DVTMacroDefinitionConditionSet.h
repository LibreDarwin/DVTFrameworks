/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroDefinitionConditionSet.
 *
 * A condition set is an immutable, sorted collection of
 * DVTMacroDefinitionCondition objects with at most one condition per
 * parameter, plus the textual form that is appended to a macro name
 * ("[arch=arm64][sdk=macosx*]").  Instances are uniqued through
 * +conditionSetWithConditions:, so pointer equality is set equality.
 */

#ifndef DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITIONSET_H
#define DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITIONSET_H

#import <Foundation/Foundation.h>

#import "DVTMacroDefinitionCondition.h"
#import "DVTMacroDefinitionConditionParameter.h"

@interface DVTMacroDefinitionConditionSet : NSObject <NSCopying, NSFastEnumeration> {
	unsigned long long _combinedPrecedence;
	NSString *_subscriptRepresentation;
	NSArray *_parameterNames;
	unsigned long long _count;
	BOOL _hasRepeatedConditionParameters;
	NSArray *_conditions;
}

/* conditions must be an NSSet of DVTMacroDefinitionCondition objects.  The
 * result is uniqued: equal sets return the same instance. */
+ (DVTMacroDefinitionConditionSet *)conditionSetWithConditions:(NSSet *)conditions;
+ (DVTMacroDefinitionConditionSet *)conditionSetWithCondition:(DVTMacroDefinitionCondition *)condition;

/* Parses "[param=pattern][param=pattern]..." after the base macro name.  On
 * success *getBaseMacroName (if non-NULL) receives the base macro name and
 * the parsed set is returned; returns nil when the representation has no
 * conditions.  On failure the parse aborts, *error (if non-NULL) receives a
 * descriptive error and nil is returned. */
+ (DVTMacroDefinitionConditionSet *)conditionSetFromStringRepresentation:(NSString *)representation getBaseMacroName:(NSString **)getBaseMacroName error:(NSError **)error;

/* Designated initialiser; call +conditionSetWithConditions: instead. */
- (id)initWithConditions:(NSSet *)conditions onlyCallableFromWithinCreateUniquedInstance:(BOOL)onlyCallable;

- (unsigned long long)count;

- (DVTMacroDefinitionCondition *)conditionForParameter:(DVTMacroDefinitionConditionParameter *)parameter;
- (DVTMacroDefinitionCondition *)conditionForParameterNamed:(NSString *)parameterName;
- (BOOL)containsCondition:(DVTMacroDefinitionCondition *)condition;
- (BOOL)containsParameter:(DVTMacroDefinitionConditionParameter *)parameter;

/* Ascending precedence order of the parameter names. */
- (NSArray *)parameterNames;

/* Bit mask of the precedences of the contained condition parameters. */
- (unsigned long long)precedence;

- (DVTMacroDefinitionConditionSet *)conditionSetByAddingCondition:(DVTMacroDefinitionCondition *)condition;
- (DVTMacroDefinitionConditionSet *)conditionSetByRemovingParameter:(DVTMacroDefinitionConditionParameter *)parameter;
- (DVTMacroDefinitionConditionSet *)conditionSetByRemovingParameterNamed:(NSString *)parameterName;

- (BOOL)evaluateForParameterValues:(NSDictionary *)values;

- (long long)compare:(id)other;
- (long long)compareConditionSet:(DVTMacroDefinitionConditionSet *)conditionSet;
- (BOOL)isStrictlyOrderedByPrecedent;

/* "[param=pattern][param=pattern]..."; highest precedence parameter first. */
- (NSString *)subscriptRepresentation;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITIONSET_H */
