/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - The conditions are stored in an NSArray instead of an inline C array of
 *    object pointers; the observable ordering and membership are the same and
 *    memory management is simpler under ARC.
 *  - The uniquing table is an NSMapTable created with
 *    +[NSMapTable strongToWeakObjectsMapTable] rather than DVTFoundation's
 *    custom pointer functions; the semantics (keyed by the condition set,
 *    values not retained) are the same.
 *  - The parser copies the string's UTF-8 bytes with -UTF8String instead of
 *    the CFStringGetCStringPtr/CFStringGetFileSystemRepresentation dance; the
 *    parsed results and error messages are identical.
 *  - -copyWithZone: returns self.  Instances are uniqued, so a copy would be
 *    indistinguishable from the original anyway.
 *  - -evaluateInScope: is not implemented yet: it needs the macro expansion
 *    scope that is added in the next stage of the macro foundation.
 */

#import "DVTMacroDefinitionConditionSet.h"

#import <os/lock.h>

static os_unfair_lock DVTMacroDefinitionConditionSetUniquingLock = OS_UNFAIR_LOCK_INIT;
static NSMapTable *DVTMacroDefinitionConditionSetUniquingTable = nil;

static NSError *
DVTConditionSetErrorWithDescription(NSString *description)
{
	return ([NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]]);
}

static NSError *
DVTMalformedConditionSetRepresentationError(NSString *representation, NSString *detail)
{
	return (DVTConditionSetErrorWithDescription([NSString stringWithFormat:@"macro string representation '%@' isn't well formed: %@", representation, detail]));
}

static NSComparisonResult
DVTConditionSetSortResult(DVTMacroDefinitionCondition *first, DVTMacroDefinitionCondition *second)
{
	/* Conditions are ordered by decreasing precedence, so the sort is the
	 * opposite of the condition comparison. */
	long long result = -[first compareCondition:second];

	if (result < 0) {
		return (NSOrderedAscending);
	}
	if (result > 0) {
		return (NSOrderedDescending);
	}
	return (NSOrderedSame);
}

static DVTMacroDefinitionConditionSet *
DVTUniqueConditionSet(NSSet *conditions)
{
	DVTMacroDefinitionConditionSet *conditionSet;

	os_unfair_lock_lock(&DVTMacroDefinitionConditionSetUniquingLock);
	if (DVTMacroDefinitionConditionSetUniquingTable == nil) {
		DVTMacroDefinitionConditionSetUniquingTable = [NSMapTable strongToWeakObjectsMapTable];
	}
	conditionSet = [DVTMacroDefinitionConditionSetUniquingTable objectForKey:conditions];
	if (conditionSet == nil) {
		conditionSet = [[DVTMacroDefinitionConditionSet alloc] initWithConditions:conditions
					   onlyCallableFromWithinCreateUniquedInstance:YES];
		[DVTMacroDefinitionConditionSetUniquingTable setObject:conditionSet forKey:conditions];
	}
	os_unfair_lock_unlock(&DVTMacroDefinitionConditionSetUniquingLock);

	return (conditionSet);
}

@implementation DVTMacroDefinitionConditionSet

+ (DVTMacroDefinitionConditionSet *)conditionSetWithConditions:(NSSet *)conditions
{
	if (conditions == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is nil",
				   @"conditions", NSStringFromClass([NSSet class])];
	}
	if (![conditions isKindOfClass:[NSSet class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"conditions", NSStringFromClass([NSSet class]), conditions];
	}

	return (DVTUniqueConditionSet(conditions));
}

+ (DVTMacroDefinitionConditionSet *)conditionSetWithCondition:(DVTMacroDefinitionCondition *)condition
{
	if (condition == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is nil",
				   @"condition", NSStringFromClass([DVTMacroDefinitionCondition class])];
	}
	if (![condition isKindOfClass:[DVTMacroDefinitionCondition class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"condition", NSStringFromClass([DVTMacroDefinitionCondition class]), condition];
	}

	return ([self conditionSetWithConditions:[NSSet setWithObject:condition]]);
}

+ (DVTMacroDefinitionConditionSet *)conditionSetFromStringRepresentation:(NSString *)representation getBaseMacroName:(NSString **)getBaseMacroName error:(NSError **)error
{
	const char *bytes;
	const char *cursor;
	NSMutableSet *conditions;

	if (representation == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is nil",
				   @"representation", NSStringFromClass([NSString class])];
	}
	if (![representation isKindOfClass:[NSString class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"representation", NSStringFromClass([NSString class]), representation];
	}
	if ([representation length] == 0) {
		if (error != NULL) {
			*error = DVTConditionSetErrorWithDescription(@"macro string representation is an empty string, with no name or condition parameters");
		}
		return (nil);
	}

	bytes = [representation UTF8String];
	cursor = bytes;
	while (*cursor != '\0' && *cursor != '[') {
		cursor++;
	}
	if (*cursor == '\0') {
		if (getBaseMacroName != NULL) {
			*getBaseMacroName = [representation copy];
		}
		return (nil);
	}
	if (getBaseMacroName != NULL) {
		*getBaseMacroName = [[NSString alloc] initWithBytes:bytes length:(NSUInteger)(cursor - bytes) encoding:NSUTF8StringEncoding];
	}

	conditions = [NSMutableSet set];
	while (*cursor == '[') {
		const char *parameterNameStart;
		const char *parameterNameEnd;
		const char *valuePatternStart;
		const char *valuePatternEnd;
		NSString *parameterName;
		NSString *valuePattern;
		DVTMacroDefinitionCondition *condition;

		parameterNameStart = ++cursor;
		while (*cursor != '\0' && *cursor != '=' && *cursor != ']') {
			cursor++;
		}
		if (*cursor != '=') {
			if (error != NULL) {
				*error = DVTMalformedConditionSetRepresentationError(representation, @"parameter name is empty");
			}
			return (nil);
		}
		parameterNameEnd = cursor;
		valuePatternStart = ++cursor;
		while (*cursor != '\0' && *cursor != ']') {
			cursor++;
		}
		if (*cursor != ']') {
			if (error != NULL) {
				*error = DVTMalformedConditionSetRepresentationError(representation, @"no ']' found after '='");
			}
			return (nil);
		}
		valuePatternEnd = cursor;
		if (parameterNameEnd == parameterNameStart) {
			if (error != NULL) {
				*error = DVTMalformedConditionSetRepresentationError(representation, @"parameter name is empty");
			}
			return (nil);
		}

		parameterName = [[NSString alloc] initWithBytes:parameterNameStart length:(NSUInteger)(parameterNameEnd - parameterNameStart) encoding:NSUTF8StringEncoding];
		valuePattern = [[NSString alloc] initWithBytes:valuePatternStart length:(NSUInteger)(valuePatternEnd - valuePatternStart) encoding:NSUTF8StringEncoding];
		condition = [DVTMacroDefinitionCondition conditionWithParameterName:parameterName valuePattern:valuePattern];
		if (condition == nil) {
			if (error != NULL) {
				*error = DVTMalformedConditionSetRepresentationError(representation, @"couldn't resolve the parameter name");
			}
			return (nil);
		}
		[conditions addObject:condition];
		cursor++;	/* skip ']' */
	}
	if (*cursor != '\0') {
		if (error != NULL) {
			*error = DVTMalformedConditionSetRepresentationError(representation, @"junk found after ']'");
		}
		return (nil);
	}

	return ([self conditionSetWithConditions:conditions]);
}

- (id)initWithConditions:(NSSet *)conditions onlyCallableFromWithinCreateUniquedInstance:(BOOL)onlyCallable
{
	NSMutableArray *sortedConditions;
	NSMutableArray *parameterNames;
	NSMutableString *subscriptRepresentation;
	NSUInteger index;
	NSUInteger count;

	(void)onlyCallable;

	count = [conditions count];
	for (id condition in conditions) {
		if (![condition isKindOfClass:[DVTMacroDefinitionCondition class]]) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be an instance inheriting from %@, but it is %@",
					   @"condition", NSStringFromClass([DVTMacroDefinitionCondition class]), condition];
		}
	}

	self = [super init];
	if (self != nil) {
		sortedConditions = [[conditions allObjects] mutableCopy];
		[sortedConditions sortUsingComparator:^NSComparisonResult(id first, id second) {
			return (DVTConditionSetSortResult(first, second));
		}];
		_conditions = [sortedConditions copy];
		_count = count;

		_combinedPrecedence = 0;
		for (DVTMacroDefinitionCondition *condition in _conditions) {
			_combinedPrecedence |= [[condition parameter] precedence];
		}

		/* Highest precedence parameter first. */
		subscriptRepresentation = [NSMutableString string];
		index = _count;
		while (index-- > 0) {
			DVTMacroDefinitionCondition *condition = [_conditions objectAtIndex:index];
			[subscriptRepresentation appendFormat:@"[%@=%@]", [[condition parameter] name], [condition valuePattern]];
		}
		_subscriptRepresentation = [subscriptRepresentation copy];

		/* Ascending precedence order, i.e. the reverse of the stored order. */
		parameterNames = [NSMutableArray arrayWithCapacity:count];
		index = _count;
		while (index-- > 0) {
			[parameterNames addObject:[[[_conditions objectAtIndex:index] parameter] name]];
		}
		_parameterNames = [parameterNames copy];

		_hasRepeatedConditionParameters = NO;
		for (index = 0; index + 1 < count; index++) {
			if ([[parameterNames objectAtIndex:index + 1] isEqual:[parameterNames objectAtIndex:index]]) {
				_hasRepeatedConditionParameters = YES;
				break;
			}
		}
	}
	return (self);
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;

	return (self);
}

#pragma mark Accessing

- (unsigned long long)count
{
	return (_count);
}

- (unsigned long long)precedence
{
	return (_combinedPrecedence);
}

- (NSArray *)parameterNames
{
	return (_parameterNames);
}

- (NSString *)subscriptRepresentation
{
	return (_subscriptRepresentation);
}

- (DVTMacroDefinitionCondition *)conditionForParameter:(DVTMacroDefinitionConditionParameter *)parameter
{
	for (DVTMacroDefinitionCondition *condition in _conditions) {
		if ([condition parameter] == parameter) {
			return (condition);
		}
	}
	return (nil);
}

- (DVTMacroDefinitionCondition *)conditionForParameterNamed:(NSString *)parameterName
{
	for (DVTMacroDefinitionCondition *condition in _conditions) {
		if ([[[condition parameter] name] isEqualToString:parameterName]) {
			return (condition);
		}
	}
	return (nil);
}

- (BOOL)containsCondition:(DVTMacroDefinitionCondition *)condition
{
	for (DVTMacroDefinitionCondition *candidate in _conditions) {
		if (candidate == condition) {
			return (YES);
		}
	}
	return (NO);
}

- (BOOL)containsParameter:(DVTMacroDefinitionConditionParameter *)parameter
{
	for (DVTMacroDefinitionCondition *condition in _conditions) {
		if ([condition parameter] == parameter) {
			return (YES);
		}
	}
	return (NO);
}

#pragma mark Deriving

- (DVTMacroDefinitionConditionSet *)conditionSetByAddingCondition:(DVTMacroDefinitionCondition *)condition
{
	NSMutableSet *conditions;

	if (condition == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is nil",
				   @"condition", NSStringFromClass([DVTMacroDefinitionCondition class])];
	}
	if (![condition isKindOfClass:[DVTMacroDefinitionCondition class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"condition", NSStringFromClass([DVTMacroDefinitionCondition class]), condition];
	}

	conditions = [NSMutableSet setWithCapacity:(NSUInteger)(_count + 1)];
	for (DVTMacroDefinitionCondition *existingCondition in _conditions) {
		if ([existingCondition parameter] != [condition parameter]) {
			[conditions addObject:existingCondition];
		}
	}
	[conditions addObject:condition];

	return ([[self class] conditionSetWithConditions:conditions]);
}

- (DVTMacroDefinitionConditionSet *)conditionSetByRemovingParameter:(DVTMacroDefinitionConditionParameter *)parameter
{
	NSMutableSet *conditions;

	if (parameter == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is nil",
				   @"outcastParameter", NSStringFromClass([DVTMacroDefinitionConditionParameter class])];
	}
	if (![parameter isKindOfClass:[DVTMacroDefinitionConditionParameter class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"outcastParameter", NSStringFromClass([DVTMacroDefinitionConditionParameter class]), parameter];
	}

	if (![self containsParameter:parameter]) {
		return (self);
	}

	conditions = [NSMutableSet setWithCapacity:(NSUInteger)(_count - 1)];
	for (DVTMacroDefinitionCondition *condition in _conditions) {
		if ([condition parameter] != parameter) {
			[conditions addObject:condition];
		}
	}

	return ([[self class] conditionSetWithConditions:conditions]);
}

- (DVTMacroDefinitionConditionSet *)conditionSetByRemovingParameterNamed:(NSString *)parameterName
{
	DVTMacroDefinitionConditionParameter *parameter = [DVTMacroDefinitionConditionParameter conditionParameterNamed:parameterName];

	if (parameter == nil) {
		return (self);
	}
	return ([self conditionSetByRemovingParameter:parameter]);
}

#pragma mark Evaluating

- (BOOL)evaluateForParameterValues:(NSDictionary *)values
{
	if (values == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a dictionary, but it is nil", @"values"];
	}
	if (![values isKindOfClass:[NSDictionary class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a dictionary, but it is %@", @"values", values];
	}

	for (DVTMacroDefinitionCondition *condition in _conditions) {
		if (![condition evaluateForParameterValues:values]) {
			return (NO);
		}
	}
	return (YES);
}

#pragma mark Comparing

- (long long)compare:(id)other
{
	if (other == nil || ![other isKindOfClass:[DVTMacroDefinitionConditionSet class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"_castedResult", NSStringFromClass([DVTMacroDefinitionConditionSet class]), other];
	}
	return ([self compareConditionSet:other]);
}

- (long long)compareConditionSet:(DVTMacroDefinitionConditionSet *)conditionSet
{
	NSUInteger index;

	if (conditionSet == nil) {
		return (1);
	}
	if (_combinedPrecedence != conditionSet->_combinedPrecedence) {
		return (_combinedPrecedence > conditionSet->_combinedPrecedence ? 1 : -1);
	}
	if (_count == 0) {
		return (0);
	}

	if (!_hasRepeatedConditionParameters && !conditionSet->_hasRepeatedConditionParameters) {
		/* The stored order is by decreasing precedence, so both sets line up
		 * condition by condition. */
		for (index = 0; index < _count; index++) {
			long long result = [[_conditions objectAtIndex:index] compareToConditionWithKnowIdenticalParameter:[conditionSet->_conditions objectAtIndex:index]];
			if (result != 0) {
				return (result);
			}
		}
		return (0);
	}

	for (index = 0; index < _count; index++) {
		DVTMacroDefinitionCondition *condition = [_conditions objectAtIndex:index];
		long long result = [condition compareCondition:[conditionSet conditionForParameter:[condition parameter]]];
		if (result != 0) {
			return (result);
		}
	}
	return (0);
}

- (BOOL)isStrictlyOrderedByPrecedent
{
	NSUInteger index;

	if (_count < 2) {
		return (YES);
	}
	for (index = 1; index < _count; index++) {
		if ([[_conditions objectAtIndex:index - 1] compareCondition:[_conditions objectAtIndex:index]] != 1) {
			return (NO);
		}
	}
	return (YES);
}

#pragma mark Describing

- (NSString *)description
{
	return (_subscriptRepresentation);
}

#pragma mark Enumerating

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)length
{
	NSUInteger index = state->state;
	NSUInteger copied = 0;

	if (index >= _count) {
		return (0);
	}
	state->itemsPtr = buffer;
	if (length == 0) {
		state->mutationsPtr = (unsigned long *)&_count;
		return (0);
	}
	while (index < _count && copied < length) {
		buffer[copied++] = [_conditions objectAtIndex:index++];
	}
	state->state = index;
	state->mutationsPtr = (unsigned long *)&_count;

	return (copied);
}

@end
