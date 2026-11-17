/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - +newWithLiteralString: allocates with +alloc instead of calling
 *    DVTAllocateObject(); the resulting instance is identical.
 *  - The assertion failures are raised as NSInvalidArgumentException instead
 *    of going through DVTAssertionFailureHandler.
 */

#import "DVTMacroExpansionString_Literal.h"

#import <CoreFoundation/CoreFoundation.h>

#import "NSObject+DVTAssertionSupport.h"

@implementation DVTMacroExpansionString_Literal

+ (id)newWithLiteralString:(NSString *)string
{
	return ([[self alloc] initWithLiteralString:string]);
}

- (id)initWithLiteralString:(NSString *)string
{
	self = [super initWithOriginalString:string];
	if (self != nil) {
		if (string == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a string, but it is nil", @"string"];
		}
		if (CFGetTypeID((__bridge CFTypeRef)string) != CFStringGetTypeID()) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a string, but it is %@", @"string", [string descriptionForAssertionMessage]];
		}
		_hashValue = [_origString hash];
	}
	return (self);
}

- (BOOL)dvt_isLiteral
{
	return (YES);
}

- (NSUInteger)hash
{
	if (_hashValue != [_origString hash]) {
		[NSException raise:NSInvalidArgumentException format:@""];
	}
	return (_hashValue);
}

- (void)dvt_assertInternalConsistency
{
	[super dvt_assertInternalConsistency];
	if (_hashValue != [_origString hash]) {
		[NSException raise:NSInvalidArgumentException format:@""];
	}
}

- (id)dvt_debugDescription
{
	return ([NSString stringWithFormat:@"【𝗟𝗶𝘁𝗲𝗿𝗮𝗹𝗦𝘁𝗿𝗶𝗻𝗴:%@】", _origString]);
}

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	return (_origString);
}

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	return ([NSArray arrayWithObject:_origString]);
}

@end
