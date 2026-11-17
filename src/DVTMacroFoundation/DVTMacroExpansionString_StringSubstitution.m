/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - -dvt_evaluateAsStringListInScope:withState: needs a
 *    DVTMacroExpansionScope, which belongs to a later stage of the port, so
 *    it raises NSInvalidArgumentException.
 */

#import "DVTMacroExpansionString_StringSubstitution.h"

#import "DVTMacroExpansionOperator.h"

@implementation DVTMacroExpansionString_StringSubstitution

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	return ([super dvt_evaluateAsStringListInScope:scope withState:state]);
}

- (id)dvt_debugDescription
{
	NSMutableString *result = [NSMutableString stringWithFormat:@"【%@:%@",
		DVTMacroExpansionItalicizedString(@"StringSubstitution"),
		[_macroNameExpr dvt_debugDescription]];
	for (DVTMacroExpansionOperator *op in _operators) {
		[result appendFormat:@":%@", [op dvt_debugDescription]];
	}
	[result appendString:@"】"];
	return (result);
}

@end
