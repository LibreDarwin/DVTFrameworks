/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - The flexible substring array is an NSArray.
 *  - Both -dvt_evaluateAs... methods need a DVTMacroExpansionScope, which
 *    belongs to a later stage of the port, so they raise
 *    NSInvalidArgumentException.
 */

#import "DVTMacroExpansionString_Concatenation.h"

#import "DVTMacroExpansionOperator.h"

@implementation DVTMacroExpansionString_Concatenation

+ (id)newWithOriginalString:(NSString *)string substrings:(NSArray *)substrings
{
	return ([[self alloc] initWithOriginalString:string substrings:substrings]);
}

- (id)initWithOriginalString:(NSString *)string substrings:(NSArray *)substrings
{
	self = [super initWithOriginalString:string];
	if (self != nil) {
		if (substrings == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be an array, but it is nil", @"substrings"];
		}
		_substrings = [substrings copy];
		_numSubstrings = [_substrings count];
	}
	return (self);
}

- (BOOL)dvt_isLiteral
{
	return (NO);
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
	if (_substrings == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an array, but it is nil", @"_substrings"];
	}
	if (_numSubstrings != [_substrings count]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"_numSubstrings does not match the number of substrings"];
	}
}

- (id)dvt_debugDescription
{
	NSMutableString *result = [NSMutableString stringWithFormat:@"【%@:",
		DVTMacroExpansionItalicizedString(@"Concatenation")];
	BOOL first = YES;
	for (id substring in _substrings) {
		if (!first) {
			[result appendString:@"✚"];
		}
		first = NO;
		[result appendString:[substring dvt_debugDescription]];
	}
	[result appendString:@"】"];
	return (result);
}

@end
