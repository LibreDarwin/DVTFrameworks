/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionReplacementOperator: the abstract base class of operators
 * that combine the macro value with a replacement expression (name=value).
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONREPLACEMENTOPERATOR_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONREPLACEMENTOPERATOR_H

#import <Foundation/Foundation.h>

#import "DVTMacroExpansion-Protocol.h"
#import "DVTMacroExpansionOperator.h"

@class NSString;

@interface DVTMacroExpansionReplacementOperator : DVTMacroExpansionOperator {
	NSString<DVTMacroExpansion> *_replExpr;
}

- (id)initWithReplacementExpression:(id)expression;
- (id)replacementExpression;
- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope;
- (id)stringListByApplyingOperatorToStringList:(id)list inMacroExpansionScope:(id)scope;
- (id)dvt_debugDescription;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONREPLACEMENTOPERATOR_H */
