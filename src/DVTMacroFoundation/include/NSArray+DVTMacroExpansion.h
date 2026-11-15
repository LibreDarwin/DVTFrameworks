/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of the DVTMacroExpansion category methods on
 * NSArray.  dvt_arrayByExpandingEntriesWithMacroExpansionScope: is omitted:
 * it belongs to macro expansion scope handling, which is not part of this
 * increment.
 */

#ifndef DVTMACROFOUNDATION_NSARRAY_DVTMACROEXPANSION_H
#define DVTMACROFOUNDATION_NSARRAY_DVTMACROEXPANSION_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

@interface NSArray (DVTMacroExpansion)

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (BOOL)dvt_isLiteral;
- (id)dvt_stringForm;
- (void)dvt_assertInternalConsistency;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_NSARRAY_DVTMACROEXPANSION_H */
