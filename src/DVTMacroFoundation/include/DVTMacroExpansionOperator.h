/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionOperator: the abstract base class of the operators that can
 * be applied to a macro name inside a $(...) substitution.
 *
 * The operator registries map an operator name to the class implementing it.
 * Apple stores them in DVTRegistry objects; this port uses plain mutable
 * dictionaries because Class objects do not conform to DVTRegistrable.  The
 * observable lookup and enumeration results are the same.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONOPERATOR_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONOPERATOR_H

#import <Foundation/Foundation.h>

@interface DVTMacroExpansionOperator : NSObject

+ (void)registerBuiltInOperators;
+ (id)retrievalOperatorRegistry;
+ (void)registerRetrievalOperatorClass:(Class)operatorClass;
+ (id)registeredRetrievalOperatorClasses;
+ (Class)retrievalOperatorClassForOperatorNamed:(NSString *)name;
+ (id)replacementOperatorRegistry;
+ (void)registerReplacementOperatorClass:(Class)operatorClass;
+ (id)registeredReplacementOperatorClasses;
+ (Class)replacementOperatorClassForOperatorNamed:(NSString *)name;
+ (void)initialize;
+ (id)operatorName;

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope;
- (id)stringListByApplyingOperatorToStringList:(id)list inMacroExpansionScope:(id)scope;
- (BOOL)hasParseError;
- (id)parseError;
- (id)dvt_debugDescription;
- (BOOL)applyToEmptyResult;

@end

/* Internal helper shared by the operator -dvt_debugDescription methods. */
NSString *DVTMacroExpansionItalicizedString(NSString *string);

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONOPERATOR_H */
