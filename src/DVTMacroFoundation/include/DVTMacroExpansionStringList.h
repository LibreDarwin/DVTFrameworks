/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionStringList: the abstract NSArray subclass that all string
 * list macro expansion values derive from.  Everything that describes the
 * contents is the responsibility of subclasses.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRINGLIST_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRINGLIST_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

#import "DVTMacroExpansion-Protocol.h"

@class NSArray, NSString;

@interface DVTMacroExpansionStringList : NSArray <DVTMacroExpansion> {
	NSString<DVTMacroExpansion> *_stringForm;
}

+ (id)allocWithZone:(NSZone *)zone;

- (id)copyWithZone:(NSZone *)zone;
- (id)copy;
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

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRINGLIST_H */
