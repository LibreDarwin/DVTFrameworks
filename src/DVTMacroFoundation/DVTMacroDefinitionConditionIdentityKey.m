/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 */

#import "DVTMacroDefinitionConditionIdentityKey.h"

@implementation DVTMacroDefinitionConditionIdentityKey

@synthesize parameter = _parameter;
@synthesize valuePattern = _valuePattern;

- (id)initWithParameter:(DVTMacroDefinitionConditionParameter *)parameter valuePattern:(NSString *)pattern
{
	self = [super init];
	if (self != nil) {
		_parameter = parameter;
		_valuePattern = [pattern copy];
	}
	return (self);
}

- (void)dealloc
{
#if !__has_feature(objc_arc)
	[_parameter release];
	[_valuePattern release];
	[super dealloc];
#endif
}

- (BOOL)isEqual:(id)other
{
	if (other == nil || ![other isKindOfClass:[DVTMacroDefinitionConditionIdentityKey class]]) {
		return (NO);
	}
	return ([other isEqualToMacroDefinitionConditionIdentityKey:self]);
}

- (BOOL)isEqualToMacroDefinitionConditionIdentityKey:(DVTMacroDefinitionConditionIdentityKey *)key
{
	if (key == nil) {
		return (NO);
	}
	if (![_parameter isEqual:key->_parameter]) {
		return (NO);
	}
	return ([_valuePattern isEqual:key->_valuePattern]);
}

- (NSUInteger)hash
{
	return ([_valuePattern hash] + 33 * [_parameter hash]);
}

@end
