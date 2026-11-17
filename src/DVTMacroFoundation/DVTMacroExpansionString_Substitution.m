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
#import "DVTMacroExpansionScope.h"
#import "DVTMacroExpansionScope_Private.h"
#import <string.h>
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

static BOOL
DVTNestedMacroExpansionStateContainsName(const struct DVTNestedMacroExpansionState *state, NSString *name)
{
	while (state != NULL) {
		if (state->macroName != nil && [state->macroName isEqual:name]) {
			return (YES);
		}
		state = state->parentState;
	}
	return (NO);
}

static BOOL
DVTSubstitutionShouldPreserve(id scope)
{
	if ([scope respondsToSelector:@selector(preserveUnresolvedReferences)]) {
		return ([scope preserveUnresolvedReferences]);
	}
	return (NO);
}

- (id)_requestedMacroNameInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	id name = [_macroNameExpr dvt_evaluateAsStringInScope:scope withState:state];

	if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
		return (nil);
	}
	return (name);
}

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	NSString *name = [self _requestedMacroNameInScope:scope withState:state];
	id value = nil;
	id result = nil;
	struct DVTMacroNameLookupCursor cursor;

	memset(&cursor, 0, sizeof(cursor));
	if (name != nil && !DVTNestedMacroExpansionStateContainsName(state, name)) {
		value = [scope lookupValueForMacroName:name hash:(unsigned int)[name hash] withCursor:&cursor];
	}
	if (value == nil) {
		if (_alwaysPreserve || DVTSubstitutionShouldPreserve(scope)) {
			return (_origString);
		}
		result = @"";
	} else {
		struct DVTNestedMacroExpansionState childState;

		memset(&childState, 0, sizeof(childState));
		childState.macroName = name;
		childState.hash = (unsigned int)[name hash];
		childState.cursor = cursor;
		childState.parentState = (struct DVTNestedMacroExpansionState *)state;
		result = [(id<DVTMacroExpansion>)value dvt_evaluateAsStringInScope:scope withState:&childState];
		if (childState.cursor.x5 != nil && state != NULL) {
			((struct DVTNestedMacroExpansionState *)state)->cursor.x5 = childState.cursor.x5;
		}
	}
	if (result == nil) {
		result = @"";
	}
	for (DVTMacroExpansionOperator *op in _operators) {
		result = [op stringByApplyingOperatorToString:result inMacroExpansionScope:scope];
		if (result == nil) {
			result = @"";
		}
	}
	return (result);
}

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	NSString *name = [self _requestedMacroNameInScope:scope withState:state];
	id value = nil;
	NSMutableArray *result;
	struct DVTMacroNameLookupCursor cursor;

	memset(&cursor, 0, sizeof(cursor));
	if (name != nil && !DVTNestedMacroExpansionStateContainsName(state, name)) {
		value = [scope lookupValueForMacroName:name hash:(unsigned int)[name hash] withCursor:&cursor];
	}
	if (value == nil) {
		if (_alwaysPreserve || DVTSubstitutionShouldPreserve(scope)) {
			return ([NSArray arrayWithObject:_origString]);
		}
		result = [NSMutableArray array];
	} else {
		struct DVTNestedMacroExpansionState childState;
		id list;

		memset(&childState, 0, sizeof(childState));
		childState.macroName = name;
		childState.hash = (unsigned int)[name hash];
		childState.cursor = cursor;
		childState.parentState = (struct DVTNestedMacroExpansionState *)state;
		list = [(id<DVTMacroExpansion>)value dvt_evaluateAsStringListInScope:scope withState:&childState];
		if ([list isKindOfClass:[NSArray class]]) {
			result = [NSMutableArray arrayWithArray:list];
		} else {
			result = [NSMutableArray array];
		}
		if (childState.cursor.x5 != nil && state != NULL) {
			((struct DVTNestedMacroExpansionState *)state)->cursor.x5 = childState.cursor.x5;
		}
	}
	if ([result count] == 0) {
		for (DVTMacroExpansionOperator *op in _operators) {
			if ([op applyToEmptyResult]) {
				[result addObject:@""];
				break;
			}
		}
	}
	for (DVTMacroExpansionOperator *op in _operators) {
		id applied = [op stringListByApplyingOperatorToStringList:result inMacroExpansionScope:scope];
		if ([applied isKindOfClass:[NSArray class]]) {
			result = [NSMutableArray arrayWithArray:applied];
		} else {
			result = [NSMutableArray array];
		}
	}
	return ([NSArray arrayWithArray:result]);
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
