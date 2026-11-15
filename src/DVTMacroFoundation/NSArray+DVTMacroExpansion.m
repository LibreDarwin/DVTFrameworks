/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of the DVTMacroExpansion category methods on
 * NSArray.
 */

#import "NSArray+DVTMacroExpansion.h"

#import "DVTFoundationClassAdditions.h"

@implementation NSArray (DVTMacroExpansion)

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	return ([self dvt_stringForm]);
}

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	return (self);
}

- (BOOL)dvt_isLiteral
{
	return (YES);
}

- (id)dvt_stringForm
{
	if ([self count] == 0) {
		return (@"");
	}
	return ([self dvt_stringByConcatenatingAsCommandLineArguments]);
}

- (void)dvt_assertInternalConsistency
{
}

- (id)dvt_debugDescription
{
	return ([NSString stringWithFormat:@"【𝗡𝗦𝗔𝗿𝗿𝗮𝘆:%@】", self]);
}

@end
