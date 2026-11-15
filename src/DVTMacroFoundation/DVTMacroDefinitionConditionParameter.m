/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviation from Apple's implementation: the shared parameter table is built
 * from an ordered descriptor array instead of a dictionary, so the order of
 * +[DVTMacroDefinitionConditionParameter macroDefinitionParameters] is
 * deterministic.  Apple derives it from a dictionary, whose order is
 * unspecified.
 */

#import "DVTMacroDefinitionConditionParameter.h"

typedef struct {
	unsigned char isDefault;
	unsigned int precedence;
	const char *name;
	const char *displayName;
	const char *displayDescription;
} DVTMacroDefinitionConditionParameterDescription;

static DVTMacroDefinitionConditionParameterDescription const DVTMacroDefinitionConditionParameterDescriptions[] = {
	{ 0, 0x01, "config", "Configuration", "Name of the configuration" },
	{ 1, 0x02, "sdk", "SDK", "Canonical name of SDK being built against" },
	{ 0, 0x04, "variant", "Variant", "Variant (normal, debug, profile, etc)" },
	{ 1, 0x08, "arch", "Architecture", "Architecture (i386, x86_64, armv6, etc)" },
	{ 0, 0x10, "dialect", "Dialect", "Language dialect" },
	{ 0, 0x20, "target", "Target", "Target name" },
};

static NSDictionary *DVTMacroDefinitionParametersByName = nil;
static NSArray *DVTMacroDefinitionParameters = nil;
static NSArray *DVTMacroDefinitionConditionParameterNames = nil;
static NSSet *DVTMacroDefinitionDefaultConditionParameters = nil;

@implementation DVTMacroDefinitionConditionParameter

+ (void)initialize
{
	static dispatch_once_t onceToken;

	if (self != [DVTMacroDefinitionConditionParameter class]) {
		return;
	}
	dispatch_once(&onceToken, ^{
		NSMutableDictionary *parametersByName = [[NSMutableDictionary alloc] init];
		NSMutableSet *defaultParameters = [[NSMutableSet alloc] init];
		NSUInteger count = sizeof(DVTMacroDefinitionConditionParameterDescriptions) / sizeof(DVTMacroDefinitionConditionParameterDescriptions[0]);
		NSUInteger index;

		for (index = 0; index < count; index++) {
			DVTMacroDefinitionConditionParameterDescription const *description = &DVTMacroDefinitionConditionParameterDescriptions[index];
			NSString *name = [[NSString alloc] initWithUTF8String:description->name];
			NSString *displayName = [[NSString alloc] initWithUTF8String:description->displayName];
			NSAttributedString *displayDescription;
			DVTMacroDefinitionConditionParameter *parameter;

			displayDescription = [[NSAttributedString alloc] initWithString:[[NSString alloc] initWithUTF8String:description->displayDescription]];
			parameter = [[DVTMacroDefinitionConditionParameter alloc] initWithName:name
										 precedence:description->precedence
										displayName:displayName
								     displayDescription:displayDescription];
			[parametersByName setObject:parameter forKeyedSubscript:name];
			if (description->isDefault != 0) {
				[defaultParameters addObject:parameter];
			}
		}

		DVTMacroDefinitionParametersByName = [parametersByName copy];
		DVTMacroDefinitionParameters = [[parametersByName allValues] copy];
		DVTMacroDefinitionConditionParameterNames = [[parametersByName allKeys] copy];
		DVTMacroDefinitionDefaultConditionParameters = [defaultParameters copy];
	});
}

+ (NSDictionary *)macroDefinitionParameters
{
	return (DVTMacroDefinitionParametersByName);
}

+ (DVTMacroDefinitionConditionParameter *)conditionParameterNamed:(NSString *)name
{
	return ([DVTMacroDefinitionParametersByName objectForKey:name]);
}

+ (NSSet *)defaultConditionParameters
{
	return (DVTMacroDefinitionDefaultConditionParameters);
}

- (id)initWithName:(NSString *)name precedence:(unsigned long long)precedence displayName:(NSString *)displayName displayDescription:(NSAttributedString *)displayDescription
{
	self = [super init];
	if (self != nil) {
		_name = [name copy];
		_precedence = precedence;
		_displayName = [displayName copy];
		_displayDescription = [displayDescription copy];
	}
	return (self);
}

- (void)dealloc
{
#if !__has_feature(objc_arc)
	[_name release];
	[_displayName release];
	[_displayDescription release];
	[super dealloc];
#endif
}

- (NSString *)name
{
	return (_name);
}

- (unsigned long long)precedence
{
	return (_precedence);
}

- (NSString *)displayName
{
	return (_displayName);
}

- (NSAttributedString *)displayDescription
{
	return (_displayDescription);
}

#pragma mark Comparing

- (long long)compare:(id)other
{
	if (other == nil || ![other isKindOfClass:[DVTMacroDefinitionConditionParameter class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"_castedResult", NSStringFromClass([DVTMacroDefinitionConditionParameter class]), other];
	}
	return ([self comparePrecedence:other]);
}

- (long long)comparePrecedence:(DVTMacroDefinitionConditionParameter *)other
{
	if (_precedence < other->_precedence) {
		return (-1);
	}
	if (_precedence > other->_precedence) {
		return (1);
	}
	return (0);
}

- (NSString *)description
{
	return ([NSString stringWithFormat:@"<%@:%p:%@>", NSStringFromClass([self class]), self, _name]);
}

@end
