/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionRetrievalOperator: the abstract base class of operators
 * that retrieve a projection of a macro value (its path base name, its
 * extension, its identifier form, and so on).
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONRETRIEVALOPERATOR_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONRETRIEVALOPERATOR_H

#import <Foundation/Foundation.h>

#import "DVTMacroExpansionOperator.h"

@interface DVTMacroExpansionRetrievalOperator : DVTMacroExpansionOperator

- (id)init;
- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope;
- (id)stringListByApplyingOperatorToStringList:(id)list inMacroExpansionScope:(id)scope;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONRETRIEVALOPERATOR_H */
