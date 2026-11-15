/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionStringList_Literal: a literal list macro value wrapping an
 * array of strings plus the command line string form they concatenate to.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRINGLIST_LITERAL_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRINGLIST_LITERAL_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

#import "DVTMacroExpansionStringList.h"

@class NSArray;

@interface DVTMacroExpansionStringList_Literal : DVTMacroExpansionStringList {
	NSArray *_literalStrings;
}

+ (id)newWithStringForm:(id)form literalStrings:(id)strings;

- (id)initWithStringForm:(id)form literalStrings:(id)strings;
- (BOOL)dvt_isLiteral;
- (id)dvt_stringForm;
- (NSUInteger)hash;
- (BOOL)isEqual:(id)equal;
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)index;
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)buffer count:(NSUInteger)len;
- (id)description;
- (void)dvt_assertInternalConsistency;
- (id)dvt_debugDescription;
- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRINGLIST_LITERAL_H */
