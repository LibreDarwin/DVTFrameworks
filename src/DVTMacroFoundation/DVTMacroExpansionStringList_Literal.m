/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - +newWithStringForm:literalStrings: allocates with +alloc instead of
 *    calling DVTAllocateObject(); the resulting instance is identical.
 *  - The assertion failures are raised as NSInvalidArgumentException instead
 *    of going through DVTAssertionFailureHandler.  Apple's "(a array)" typo in
 *    the literalStrings-nil message is reproduced deliberately.
 */

#import "DVTMacroExpansionStringList_Literal.h"

#import <CoreFoundation/CoreFoundation.h>

#import "NSObject+DVTAssertionSupport.h"

@implementation DVTMacroExpansionStringList_Literal

+ (id)newWithStringForm:(id)form literalStrings:(id)strings
{
	return ([[self alloc] initWithStringForm:form literalStrings:strings]);
}

- (id)initWithStringForm:(id)form literalStrings:(id)strings
{
	self = [super init];
	if (self != nil) {
		_stringForm = [form copy];
		if (strings == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a array, but it is nil", @"literalStrings"];
		}
		if (CFGetTypeID((__bridge CFTypeRef)strings) != CFArrayGetTypeID()) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be an array, but it is %@", @"literalStrings", [strings descriptionForAssertionMessage]];
		}
		for (id string in strings) {
			if (string == nil) {
				[NSException raise:NSInvalidArgumentException
					    format:@"%@ should be a string, but it is nil", @"string"];
			}
			if (CFGetTypeID((__bridge CFTypeRef)string) != CFStringGetTypeID()) {
				[NSException raise:NSInvalidArgumentException
					    format:@"%@ should be a string, but it is %@", @"string", [string descriptionForAssertionMessage]];
			}
		}
		_literalStrings = [strings copy];
	}
	return (self);
}

- (BOOL)dvt_isLiteral
{
	return (YES);
}

- (id)dvt_stringForm
{
	return (_stringForm);
}

- (NSUInteger)hash
{
	return ([_literalStrings hash]);
}

- (BOOL)isEqual:(id)equal
{
	return ([_literalStrings isEqual:equal]);
}

- (NSUInteger)count
{
	return ([_literalStrings count]);
}

- (id)objectAtIndex:(NSUInteger)index
{
	return ([_literalStrings objectAtIndex:index]);
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)buffer count:(NSUInteger)len
{
	return ([_literalStrings countByEnumeratingWithState:state objects:buffer count:len]);
}

- (id)description
{
	return ([_literalStrings description]);
}

- (void)dvt_assertInternalConsistency
{
	[super dvt_assertInternalConsistency];
	if (_literalStrings == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a array, but it is nil", @"_literalStrings"];
	}
	if (CFGetTypeID((__bridge CFTypeRef)_literalStrings) != CFArrayGetTypeID()) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an array, but it is %@", @"_literalStrings", [_literalStrings descriptionForAssertionMessage]];
	}
	for (id string in _literalStrings) {
		if (string == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a string, but it is nil", @"string"];
		}
		if (CFGetTypeID((__bridge CFTypeRef)string) != CFStringGetTypeID()) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a string, but it is %@", @"string", [string descriptionForAssertionMessage]];
		}
	}
}

- (id)dvt_debugDescription
{
	NSMutableString *result = [NSMutableString string];

	for (id string in _literalStrings) {
		if (string == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a string, but it is nil", @"string"];
		}
		if (CFGetTypeID((__bridge CFTypeRef)string) != CFStringGetTypeID()) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a string, but it is %@", @"string", [string descriptionForAssertionMessage]];
		}
		if (![result isEqualToString:@""]) {
			[result appendString:@","];
		}
		[result appendString:[string dvt_debugDescription]];
	}

	return ([NSString stringWithFormat:@"【𝗟𝗶𝘁𝗲𝗿𝗮𝗹𝗔𝗿𝗿𝗮𝘆:%@】", result]);
}

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	return ([_stringForm dvt_evaluateAsStringInScope:scope withState:state]);
}

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	return (_literalStrings);
}

@end
