/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionString_Concatenation: the concatenation of several string
 * expansion expressions.
 *
 * Deviation from Apple's header: the flexible C array of substrings is
 * replaced by an NSArray, and the initializer takes an NSArray instead of the
 * private DVT::ArrayBuilder.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_CONCATENATION_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_CONCATENATION_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

#import "DVTMacroExpansion-Protocol.h"
#import "DVTMacroExpansionString.h"

@class NSArray, NSString;

@interface DVTMacroExpansionString_Concatenation : DVTMacroExpansionString {
	NSUInteger _numSubstrings;
	NSArray *_substrings;
}

+ (id)newWithOriginalString:(NSString *)string substrings:(NSArray *)substrings;

- (id)initWithOriginalString:(NSString *)string substrings:(NSArray *)substrings;
- (BOOL)dvt_isLiteral;
- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (void)dvt_assertInternalConsistency;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_CONCATENATION_H */
