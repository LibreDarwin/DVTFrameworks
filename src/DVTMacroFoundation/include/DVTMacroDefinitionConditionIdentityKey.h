/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroDefinitionConditionIdentityKey: the hashable key used to unique
 * DVTMacroDefinitionCondition instances.
 */

#ifndef DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITIONIDENTITYKEY_H
#define DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITIONIDENTITYKEY_H

#import <Foundation/Foundation.h>

#import "DVTMacroDefinitionConditionParameter.h"

@interface DVTMacroDefinitionConditionIdentityKey : NSObject {
	DVTMacroDefinitionConditionParameter *_parameter;
	NSString *_valuePattern;
}

- (id)initWithParameter:(DVTMacroDefinitionConditionParameter *)parameter valuePattern:(NSString *)pattern;

@property (retain) DVTMacroDefinitionConditionParameter *parameter;
@property (retain) NSString *valuePattern;

- (BOOL)isEqualToMacroDefinitionConditionIdentityKey:(DVTMacroDefinitionConditionIdentityKey *)key;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACRODEFINITIONCONDITIONIDENTITYKEY_H */
