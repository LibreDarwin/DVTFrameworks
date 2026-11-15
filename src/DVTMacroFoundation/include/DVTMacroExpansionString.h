/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionString: the abstract NSString subclass that all string
 * macro expansion values derive from.  -dvt_isLiteral, -dvt_debugDescription
 * and both -dvt_evaluateAs... methods are the responsibility of subclasses.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

#import "DVTMacroExpansion-Protocol.h"

@class NSString;

@interface DVTMacroExpansionString : NSString <DVTMacroExpansion> {
	NSString *_origString;
}

+ (id)allocWithZone:(NSZone *)zone;

- (id)initWithOriginalString:(NSString *)string;

- (id)copyWithZone:(NSZone *)zone;
- (id)copy;
- (BOOL)dvt_isLiteral;
- (id)dvt_stringForm;
- (BOOL)isEqual:(id)equal;
- (NSUInteger)length;
- (unichar)characterAtIndex:(NSUInteger)index;
- (void)getCharacters:(unichar *)characters range:(NSRange)range;
- (id)replacementObjectForCoder:(NSCoder *)coder;
- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (void)dvt_assertInternalConsistency;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_H */
