/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of the DVTMacroExpansion category methods on
 * NSString.  The macro parsing entry points (dvt_parseAsMacroExpansion…,
 * dvt_parseAsMacroAssignments…, macroRegistrationNumber) are deliberately not
 * declared yet: they belong to the macro expression parser, which is not part
 * of this increment.
 */

#ifndef DVTMACROFOUNDATION_NSSTRING_DVTMACROEXPANSION_H
#define DVTMACROFOUNDATION_NSSTRING_DVTMACROEXPANSION_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

@interface NSString (DVTMacroExpansion)

- (id)dvt_literalValueOfCommonString;
- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (BOOL)dvt_isLiteral;
- (id)dvt_stringForm;
- (void)dvt_assertInternalConsistency;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_NSSTRING_DVTMACROEXPANSION_H */
