/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionString_StringSubstitution: a substitution used inside a
 * string list.  It only overrides the list evaluation and the debug
 * description; the storage and parsing behaviour are inherited.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_STRINGSUBSTITUTION_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_STRINGSUBSTITUTION_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

#import "DVTMacroExpansionString_Substitution.h"

@interface DVTMacroExpansionString_StringSubstitution : DVTMacroExpansionString_Substitution

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSTRING_STRINGSUBSTITUTION_H */
