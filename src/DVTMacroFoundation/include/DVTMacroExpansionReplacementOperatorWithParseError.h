/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionReplacementOperatorWithParseError: the placeholder operator
 * installed when a substitution uses an unknown "name=value" operator.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONREPLACEMENTOPERATORWITHPARSEERROR_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONREPLACEMENTOPERATORWITHPARSEERROR_H

#import <Foundation/Foundation.h>

#import "DVTMacroExpansionReplacementOperator.h"

@class NSError;

@interface DVTMacroExpansionReplacementOperatorWithParseError : DVTMacroExpansionReplacementOperator {
	NSError *_parseError;
}

+ (id)operatorName;

- (id)initWithReplacementExpression:(id)expression parseError:(id)error;
- (id)parseError;
- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONREPLACEMENTOPERATORWITHPARSEERROR_H */
