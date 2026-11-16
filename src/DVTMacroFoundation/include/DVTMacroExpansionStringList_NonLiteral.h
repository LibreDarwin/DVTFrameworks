/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionStringList_NonLiteral: a string list whose elements are
 * expansion expressions rather than plain literal strings.
 *
 * Deviation from Apple's header: the flexible C array of elements is replaced
 * by an NSArray, and the initializer takes an NSArray instead of the private
 * DVT::ArrayBuilder.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRINGLIST_NONLITERAL_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRINGLIST_NONLITERAL_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

#import "DVTMacroExpansion-Protocol.h"
#import "DVTMacroExpansionStringList.h"

@class NSArray, NSString;

@interface DVTMacroExpansionStringList_NonLiteral : DVTMacroExpansionStringList {
	NSUInteger _numElements;
	NSArray *_elements;
}

+ (id)newWithStringForm:(id)form elements:(NSArray *)elements;

- (id)initWithStringForm:(id)form elements:(NSArray *)elements;
- (BOOL)dvt_isLiteral;
- (id)dvt_stringForm;
- (NSUInteger)hash;
- (BOOL)isEqual:(id)equal;
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)index;
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)buffer count:(NSUInteger)len;
- (id)description;
- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (void)dvt_assertInternalConsistency;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRINGLIST_NONLITERAL_H */
