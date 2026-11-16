/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionString_Substitution: a non-literal string expansion of the
 * form $(NAME:op:op=arg...).  It stores the expression that produces the macro
 * name, whether an unresolved name should preserve the original text, and the
 * operators to apply in order.
 *
 * Deviation from Apple's header: the flexible C array of operators is
 * replaced by an NSArray, and the initializer takes an NSArray instead of the
 * private DVT::ArrayBuilder.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_SUBSTITUTION_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_SUBSTITUTION_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

#import "DVTMacroExpansion-Protocol.h"
#import "DVTMacroExpansionString.h"

@class NSArray, NSString;

@interface DVTMacroExpansionString_Substitution : DVTMacroExpansionString {
	NSString<DVTMacroExpansion> *_macroNameExpr;
	BOOL _alwaysPreserve;
	NSUInteger _numOperators;
	NSArray *_operators;
}

+ (id)newWithOriginalString:(NSString *)string macroNameExpression:(id)expression preserveOriginalStringIfUnresolved:(BOOL)preserve operators:(NSArray *)operators;

- (id)initWithOriginalString:(NSString *)string macroNameExpression:(id)expression preserveOriginalStringIfUnresolved:(BOOL)preserve operators:(NSArray *)operators;
- (BOOL)dvt_isLiteral;
- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (void)dvt_assertInternalConsistency;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_SUBSTITUTION_H */
