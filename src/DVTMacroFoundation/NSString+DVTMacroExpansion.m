/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of the DVTMacroExpansion category methods on
 * NSString.
 */

#import "NSString+DVTMacroExpansion.h"

#import "NSArray+DVTMacroExpansion.h"

@implementation NSString (DVTMacroExpansion)

- (id)dvt_literalValueOfCommonString
{
	NSUInteger length = [self length];

	if (length == 0) {
		return (@"");
	} else if (length == 2 && [self isEqualToString:@"NO"]) {
		return (@"NO");
	} else if (length == 3 && [self isEqualToString:@"YES"]) {
		return (@"YES");
	}
	return (nil);
}

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	return (self);
}

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	return ([NSArray arrayWithObject:self]);
}

- (BOOL)dvt_isLiteral
{
	return (YES);
}

- (id)dvt_stringForm
{
	return (self);
}

- (void)dvt_assertInternalConsistency
{
}

- (id)dvt_debugDescription
{
	return ([NSString stringWithFormat:@"【%@】", self]);
}

@end
