/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - The flexible element array is an NSArray.
 *  - Both -dvt_evaluateAs... methods need a DVTMacroExpansionScope, which
 *    belongs to a later stage of the port, so they raise
 *    NSInvalidArgumentException.
 *  - Assertion failures are raised as NSInvalidArgumentException instead of
 *    going through DVTAssertionFailureHandler.
 */

#import "DVTMacroExpansionStringList_NonLiteral.h"

#import "DVTMacroExpansionOperator.h"

@implementation DVTMacroExpansionStringList_NonLiteral

+ (id)newWithStringForm:(id)form elements:(NSArray *)elements
{
	return ([[self alloc] initWithStringForm:form elements:elements]);
}

- (id)initWithStringForm:(id)form elements:(NSArray *)elements
{
	self = [super init];
	if (self != nil) {
		_stringForm = [form copy];
		if (elements == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be an array, but it is nil", @"elements"];
		}
		_elements = [elements copy];
		_numElements = [_elements count];
	}
	return (self);
}

- (BOOL)dvt_isLiteral
{
	return (NO);
}

- (id)dvt_stringForm
{
	return (_stringForm);
}

- (NSUInteger)hash
{
	NSUInteger result = _numElements;
	if (result == 0) {
		return (0);
	}
	for (id element in _elements) {
		result = result * 13 + [element hash];
	}
	return (result);
}

- (BOOL)isEqual:(id)equal
{
	if (equal == nil) {
		return (NO);
	}
	if (equal == self) {
		return (YES);
	}
	if (![equal isKindOfClass:[NSArray class]]) {
		return (NO);
	}
	if ([equal count] != _numElements) {
		return (NO);
	}
	NSUInteger index;
	for (index = 0; index < _numElements; index++) {
		if (![[_elements objectAtIndex:index] isEqual:[equal objectAtIndex:index]]) {
			return (NO);
		}
	}
	return (YES);
}

- (NSUInteger)count
{
	return (_numElements);
}

- (id)objectAtIndex:(NSUInteger)index
{
	return ([_elements objectAtIndex:index]);
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)buffer count:(NSUInteger)len
{
	return ([_elements countByEnumeratingWithState:state objects:buffer count:len]);
}

- (id)description
{
	NSMutableString *result = [NSMutableString string];
	for (id element in _elements) {
		[result appendString:[element description]];
	}
	return (result);
}

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	[NSException raise:NSInvalidArgumentException
		    format:@"-[%@ dvt_evaluateAsStringInScope:withState:] requires a macro expansion scope",
			   NSStringFromClass([self class])];
	return (nil);
}

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	[NSException raise:NSInvalidArgumentException
		    format:@"-[%@ dvt_evaluateAsStringListInScope:withState:] requires a macro expansion scope",
			   NSStringFromClass([self class])];
	return (nil);
}

- (void)dvt_assertInternalConsistency
{
	[super dvt_assertInternalConsistency];
	if (_elements == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an array, but it is nil", @"_elements"];
	}
	if (_numElements != [_elements count]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"_numElements does not match the number of elements"];
	}
}

- (id)dvt_debugDescription
{
	NSMutableString *result = [NSMutableString stringWithFormat:@"【%@:",
		DVTMacroExpansionItalicizedString(@"NonliteralArray")];
	BOOL first = YES;
	for (id element in _elements) {
		if (!first) {
			[result appendString:@","];
		}
		first = NO;
		[result appendString:[element dvt_debugDescription]];
	}
	[result appendString:@"】"];
	return (result);
}

@end
