/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of the DVTMacroExpansion protocol: the common
 * interface of every value that can be stored in a DVTMacroDefinitionTable.
 *
 * Deviations from Apple's header:
 *
 *  - DVTNestedMacroExpansionState is a private structure of the macro
 *    expansion scope, which is added in a later stage of the macro
 *    foundation, so it is only forward declared here.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSION_PROTOCOL_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSION_PROTOCOL_H

#import <Foundation/Foundation.h>

struct DVTNestedMacroExpansionState;

@protocol DVTMacroExpansion <NSObject, NSCopying>

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state;
- (BOOL)dvt_isLiteral;
- (id)dvt_stringForm;
- (void)dvt_assertInternalConsistency;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSION_PROTOCOL_H */
