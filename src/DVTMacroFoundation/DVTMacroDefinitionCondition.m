/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - The uniquing table is an NSMapTable created with
 *    +[NSMapTable strongToWeakObjectsMapTable] rather than DVTFoundation's
 *    -[NSMapTable dvt_strongObjectToWeakObjectTable]; the resulting semantics
 *    (strong key with object personality, weak value) are the same.
 *  - -copyWithZone: returns self.  Instances are uniqued, so a copy would be
 *    indistinguishable from the original anyway.
 *  - -evaluateInScope: is not implemented yet: it needs the macro expansion
 *    scope that is added in the next stage of the macro foundation.
 */

#import "DVTMacroDefinitionCondition.h"

#import <fnmatch.h>
#import <os/lock.h>

#import "DVTMacroDefinitionConditionIdentityKey.h"

@interface DVTMacroDefinitionCondition () {
	DVTMacroDefinitionConditionParameter *_parameter;
	NSString *_valuePattern;
}
@end

static os_unfair_lock DVTMacroDefinitionConditionUniquingLock = OS_UNFAIR_LOCK_INIT;
static NSMapTable *DVTMacroDefinitionConditionUniquingTable = nil;

/* Apple caches a fingerprint of the value pattern in _requiredLiteralPrefix:
 * when the pattern starts with at least four identifier characters there can
 * be no glob metacharacter in that prefix, so two patterns that start with a
 * different character cannot possibly match the same value.  The fingerprint
 * is the first byte, combined with the top bit of the OR of the next three
 * bytes, sign extended.  The next stage does not depend on the value; only
 * "non-zero and different" is interpreted. */
static BOOL
DVTMacroDefinitionConditionIsWordCharacter(unsigned char character)
{
	return (character == '_' || (character >= '0' && character <= '9') || ((character | 0x20) >= 'a' && (character | 0x20) <= 'z'));
}

static unsigned int
DVTMacroDefinitionConditionLiteralPrefix(const char *bytes)
{
	unsigned char rest;
	unsigned char first;

	if (strlen(bytes) < 4) {
		return (0);
	}
	if (!DVTMacroDefinitionConditionIsWordCharacter((unsigned char)bytes[0]) ||
	    !DVTMacroDefinitionConditionIsWordCharacter((unsigned char)bytes[1]) ||
	    !DVTMacroDefinitionConditionIsWordCharacter((unsigned char)bytes[2]) ||
	    !DVTMacroDefinitionConditionIsWordCharacter((unsigned char)bytes[3])) {
		return (0);
	}
	first = (unsigned char)bytes[0];
	rest = (unsigned char)((unsigned char)bytes[1] | (unsigned char)bytes[2] | (unsigned char)bytes[3]);
	return ((unsigned int)(signed char)(unsigned char)(first | ((rest >> 7) & 1)));
}

@implementation DVTMacroDefinitionCondition

+ (DVTMacroDefinitionCondition *)conditionWithParameterName:(NSString *)name valuePattern:(NSString *)pattern
{
	DVTMacroDefinitionConditionParameter *parameter = [DVTMacroDefinitionConditionParameter conditionParameterNamed:name];
	DVTMacroDefinitionConditionIdentityKey *key;
	DVTMacroDefinitionCondition *condition;

	if (parameter == nil) {
		return (nil);
	}

	os_unfair_lock_lock(&DVTMacroDefinitionConditionUniquingLock);
	if (DVTMacroDefinitionConditionUniquingTable == nil) {
		DVTMacroDefinitionConditionUniquingTable = [NSMapTable strongToWeakObjectsMapTable];
	}
	key = [[DVTMacroDefinitionConditionIdentityKey alloc] initWithParameter:parameter valuePattern:pattern];
	condition = [DVTMacroDefinitionConditionUniquingTable objectForKey:key];
	if (condition == nil) {
		condition = [[DVTMacroDefinitionCondition alloc] initWithParameter:parameter
								      valuePattern:pattern
				    onlyCallableFromWithinCreateUniquedInstance:YES];
		[DVTMacroDefinitionConditionUniquingTable setObject:condition forKey:key];
	}
	os_unfair_lock_unlock(&DVTMacroDefinitionConditionUniquingLock);

	return (condition);
}

- (id)initWithParameter:(DVTMacroDefinitionConditionParameter *)parameter valuePattern:(NSString *)pattern onlyCallableFromWithinCreateUniquedInstance:(BOOL)onlyCallable
{
	(void)onlyCallable;

	if (parameter == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is nil",
				   @"parameter", NSStringFromClass([DVTMacroDefinitionConditionParameter class])];
	}
	if (![parameter isKindOfClass:[DVTMacroDefinitionConditionParameter class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"parameter", NSStringFromClass([DVTMacroDefinitionConditionParameter class]), parameter];
	}
	if (pattern == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is nil",
				   @"valuePattern", NSStringFromClass([NSString class])];
	}
	if (![pattern isKindOfClass:[NSString class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"valuePattern", NSStringFromClass([NSString class]), pattern];
	}

	self = [super init];
	if (self != nil) {
		_parameter = parameter;
		_valuePattern = [pattern copy];
		_valuePatternUTF8Bytes = strdup([pattern UTF8String]);
		_requiredLiteralPrefix = DVTMacroDefinitionConditionLiteralPrefix(_valuePatternUTF8Bytes);
	}
	return (self);
}

- (void)dealloc
{
	free(_valuePatternUTF8Bytes);
#if !__has_feature(objc_arc)
	[_parameter release];
	[_valuePattern release];
	[super dealloc];
#endif
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;

	return (self);
}

- (DVTMacroDefinitionConditionParameter *)parameter
{
	return (_parameter);
}

- (NSString *)valuePattern
{
	return (_valuePattern);
}

#pragma mark Evaluating

- (BOOL)evaluateForParameterValues:(NSDictionary *)values
{
	id value;

	if (values == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a dictionary, but it is nil", @"values"];
	}
	if (![values isKindOfClass:[NSDictionary class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a dictionary, but it is %@", @"values", values];
	}

	value = [values objectForKey:[_parameter name]];
	if (value != nil) {
		if (![value isKindOfClass:[NSString class]]) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a string, but it is %@", @"value", value];
		}
		return (fnmatch(_valuePatternUTF8Bytes, [value UTF8String], 0) == 0);
	}
	return ([_valuePattern isEqualToString:@"*"]);
}

#pragma mark Comparing

- (long long)compare:(id)other
{
	if (other == nil || ![other isKindOfClass:[DVTMacroDefinitionCondition class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"_castedResult", NSStringFromClass([DVTMacroDefinitionCondition class]), other];
	}
	return ([self compareCondition:other]);
}

- (long long)compareCondition:(DVTMacroDefinitionCondition *)condition
{
	long long result = [[self parameter] comparePrecedence:[condition parameter]];

	if (result == 0) {
		/* Faithfully reproduce Apple's behaviour: the pattern comparison is
		 * performed but its result is thrown away, so conditions of the same
		 * parameter always compare as equal here (the condition set compares
		 * patterns through -compareToConditionWithKnowIdenticalParameter:). */
		(void)[self compareToConditionWithKnowIdenticalParameter:condition];
	}
	return (result);
}

- (long long)compareToConditionWithKnowIdenticalParameter:(DVTMacroDefinitionCondition *)condition
{
	if (self == condition) {
		return (0);
	}
	if (_requiredLiteralPrefix != 0 && condition->_requiredLiteralPrefix != 0 &&
	    _requiredLiteralPrefix != condition->_requiredLiteralPrefix) {
		return (0);
	}
	if (fnmatch(_valuePatternUTF8Bytes, condition->_valuePatternUTF8Bytes, 0) == 0) {
		return (-1);
	}
	if (fnmatch(condition->_valuePatternUTF8Bytes, _valuePatternUTF8Bytes, 0) == 0) {
		return (1);
	}
	return (0);
}

#pragma mark Describing

- (NSString *)subscriptRepresentation
{
	return ([NSString stringWithFormat:@"[%@=%@]", [[self parameter] name], _valuePattern]);
}

- (NSString *)description
{
	return ([self subscriptRepresentation]);
}

@end
