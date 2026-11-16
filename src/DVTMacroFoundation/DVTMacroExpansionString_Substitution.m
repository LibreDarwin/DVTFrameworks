/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - The flexible operator array is an NSArray.
 *  - Evaluations need a DVTMacroExpansionScope, which belongs to a later
 *    stage of the port, so both -dvt_evaluateAs... methods raise
 *    NSInvalidArgumentException instead of resolving the substitution.
 *  - Assertion failures are raised as NSInvalidArgumentException instead of
 *    going through DVTAssertionFailureHandler.
 */

#import "DVTMacroExpansionString_Substitution.h"

#import "DVTMacroExpansionOperator.h"
#import "NSObject+DVTAssertionSupport.h"

@implementation DVTMacroExpansionString_Substitution

+ (id)newWithOriginalString:(NSString *)string macroNameExpression:(id)expression preserveOriginalStringIfUnresolved:(BOOL)preserve operators:(NSArray *)operators
{
	return ([[self alloc] initWithOriginalString:string macroNameExpression:expression preserveOriginalStringIfUnresolved:preserve operators:operators]);
}

- (id)initWithOriginalString:(NSString *)string macroNameExpression:(id)expression preserveOriginalStringIfUnresolved:(BOOL)preserve operators:(NSArray *)operators
{
	self = [super initWithOriginalString:string];
	if (self != nil) {
		if (expression == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a macro expansion expression, but it is nil", @"expression"];
		}
		if (![expression isKindOfClass:[NSString class]]) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a macro expansion expression, but it is %@",
					   @"expression", [expression description]];
		}
		_macroNameExpr = expression;
		_alwaysPreserve = preserve;
		_operators = [operators copy];
		_numOperators = [_operators count];
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
	if (_macroNameExpr == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a macro expansion expression, but it is nil", @"_macroNameExpr"];
	}
	if (_operators == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an array, but it is nil", @"_operators"];
	}
	if (_numOperators != [_operators count]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"_numOperators does not match the number of operators"];
	}
}

- (id)dvt_debugDescription
{
	NSMutableString *result = [NSMutableString stringWithFormat:@"【%@:%@",
		DVTMacroExpansionItalicizedString(@"Substitution"),
		[_macroNameExpr dvt_debugDescription]];
	for (DVTMacroExpansionOperator *op in _operators) {
		[result appendFormat:@":%@", [op dvt_debugDescription]];
	}
	[result appendString:@"】"];
	return (result);
}

@end
