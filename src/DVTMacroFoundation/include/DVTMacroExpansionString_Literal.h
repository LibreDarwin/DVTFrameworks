/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionString_Literal: a literal string macro value.  The hash of
 * the original string is cached at initialization time and re-checked on
 * every -hash and -dvt_assertInternalConsistency call.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_LITERAL_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_LITERAL_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

#import "DVTMacroExpansionString.h"

@interface DVTMacroExpansionString_Literal : DVTMacroExpansionString {
	NSUInteger _hashValue;
}

+ (id)newWithLiteralString:(NSString *)string;

- (id)initWithLiteralString:(NSString *)string;
- (BOOL)dvt_isLiteral;
- (NSUInteger)hash;
- (void)dvt_assertInternalConsistency;
- (id)dvt_debugDescription;
- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_LITERAL_H */
