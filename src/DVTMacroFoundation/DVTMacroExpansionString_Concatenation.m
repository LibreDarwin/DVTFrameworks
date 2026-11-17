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
#import "DVTMacroExpansion-Protocol.h"

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
	NSMutableString *result = [NSMutableString string];

	for (id substring in _substrings) {
		id value = [(id<DVTMacroExpansion>)substring dvt_evaluateAsStringInScope:scope withState:state];
		if (value != nil) {
			[result appendString:value];
		}
	}
	return (result);
}

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	NSMutableArray *result = nil;

	for (id substring in _substrings) {
		id evaluated = [(id<DVTMacroExpansion>)substring dvt_evaluateAsStringListInScope:scope withState:state];
		NSArray *list;

		if (evaluated == nil) {
			continue;
		}
		list = ([evaluated isKindOfClass:[NSArray class]] ? evaluated : [NSArray arrayWithObject:evaluated]);
		if ([list count] == 0) {
			continue;
		}
		if (result == nil || [result count] == 0) {
			result = [NSMutableArray arrayWithArray:list];
		} else {
			NSString *last = [[result lastObject] description];
			NSString *first = [[list objectAtIndex:0] description];
			id merged = [NSString stringWithFormat:@"%@%@", last, first];

			[result replaceObjectAtIndex:([result count] - 1) withObject:merged];
		}
	}
	return ([NSArray arrayWithArray:(result != nil ? result : [NSArray array])]);
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
