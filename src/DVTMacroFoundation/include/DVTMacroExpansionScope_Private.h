/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Private layout of the macro expansion state and lookup cursor.  Apple only
 * forward declares these structures in its public headers; the implementations
 * of the expansion classes need their field layout, so the port keeps them in
 * this internal header.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSCOPE_PRIVATE_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSCOPE_PRIVATE_H

#import <Foundation/Foundation.h>

struct DVTMacroValueAssignment;

struct DVTMacroNameLookupCursor {
	__unsafe_unretained id x0;
	unsigned long long x1;
	__unsafe_unretained id x2;
	__unsafe_unretained id x3;
	struct DVTMacroValueAssignment *x4;
	__unsafe_unretained id x5;
};

struct DVTNestedMacroExpansionState {
	__unsafe_unretained id macroName;
	unsigned int hash;
	struct DVTMacroNameLookupCursor cursor;
	__unsafe_unretained id fallbackConditionsUsed;
	struct DVTNestedMacroExpansionState *parentState;
};

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSCOPE_PRIVATE_H */
