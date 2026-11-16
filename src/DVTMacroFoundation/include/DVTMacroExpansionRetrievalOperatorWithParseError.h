/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionRetrievalOperatorWithParseError: the placeholder operator
 * installed when a substitution names an operator that is not registered.  It
 * remembers the parse error, applies the identity transformation, and reports
 * the operator name as "<ERROR>".
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONRETRIEVALOPERATORWITHPARSEERROR_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONRETRIEVALOPERATORWITHPARSEERROR_H

#import <Foundation/Foundation.h>

#import "DVTMacroExpansionRetrievalOperator.h"

@class NSError;

@interface DVTMacroExpansionRetrievalOperatorWithParseError : DVTMacroExpansionRetrievalOperator {
	NSError *_parseError;
}

+ (id)operatorName;

- (id)initWithParseError:(id)error;
- (id)parseError;
- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONRETRIEVALOPERATORWITHPARSEERROR_H */
