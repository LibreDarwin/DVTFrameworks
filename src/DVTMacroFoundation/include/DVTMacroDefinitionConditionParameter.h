/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroDefinitionConditionParameter.
 */

#ifndef DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITIONPARAMETER_H
#define DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITIONPARAMETER_H

#import <Foundation/Foundation.h>

/* A parameter that a DVTMacroDefinitionCondition can constrain (for example
 * the build configuration, the SDK, the architecture, ...).  Instances are
 * shared: obtain them from +conditionParameterNamed: rather than creating
 * new ones. */
@interface DVTMacroDefinitionConditionParameter : NSObject {
	NSString *_name;
	unsigned long long _precedence;
	NSString *_displayName;
	NSAttributedString *_displayDescription;
}

@property (readonly) NSString *name;
@property (readonly) unsigned long long precedence;
@property (readonly) NSString *displayName;
@property (readonly) NSAttributedString *displayDescription;

/* Builds the shared parameter table.  Calling it directly has no additional
 * effect. */
+ (void)initialize;

/* All known parameters, keyed by name. */
+ (NSDictionary *)macroDefinitionParameters;

/* The parameter with the given name, or nil when the name is unknown. */
+ (DVTMacroDefinitionConditionParameter *)conditionParameterNamed:(NSString *)name;

/* The parameters that are assigned a value by default ("sdk" and "arch"). */
+ (NSSet *)defaultConditionParameters;

- (id)initWithName:(NSString *)name precedence:(unsigned long long)precedence displayName:(NSString *)displayName displayDescription:(NSAttributedString *)displayDescription;

- (long long)compare:(id)other;
- (long long)comparePrecedence:(DVTMacroDefinitionConditionParameter *)other;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITIONPARAMETER_H */
