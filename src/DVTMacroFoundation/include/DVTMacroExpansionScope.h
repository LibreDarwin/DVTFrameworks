/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's DVTMacroExpansionScope:
 * an immutable snapshot of a macro definition table at a given definition
 * level, linked to its parent scope.  A scope resolves macro names by walking
 * definition levels from 0 upwards and selecting the first value assignment
 * whose condition set matches the scope's condition parameter values.
 *
 * Deviations from Apple's header:
 *
 *  - The DVTStringBuilder-based append methods take an opaque pointer; the
 *    private builder class is not part of this port.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONSCOPE_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONSCOPE_H

#import <Foundation/Foundation.h>

#import "DVTMacroDefinitionTable.h"

@class NSDictionary, NSString;

struct DVTMacroNameLookupCursor;

@interface DVTMacroExpansionScope : NSObject <NSCopying> {
	DVTMacroExpansionScope *_parentScope;
	DVTMacroDefinitionTable *_macroDefnTable;
	NSDictionary *_condParamValues;
	NSDictionary *_allCondParamValues;
	NSDictionary *_condParamFallbackValues;
	NSDictionary *_allCondParamFallbackValues;
	unsigned int _expansionOptions:8;
	unsigned int _defnLevel:8;
	unsigned int _highestDefnLevel:8;
	unsigned int _unused:8;
	__unsafe_unretained id *_nextScopeByDefnLevel;
}

@property (readonly) _Bool preserveUnresolvedReferences;

+ (id)newWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values conditionParameterFallbackValues:(id)fallbackValues expansionOptions:(unsigned long long)options;
+ (id)newWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values expansionOptions:(unsigned long long)options;
+ (id)newWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values;
+ (id)newWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level;
+ (id)stringForDefinitionLevel:(long long)level;
+ (id)newWithParentScope:(id)scope macros:(id)macros definitionLevel:(long long)level conditionParameterValues:(id)values preserveUnresolvedReferences:(_Bool)references;
+ (id)newWithParentScope:(id)scope macros:(id)macros definitionLevel:(long long)level conditionParameterValues:(id)values;
+ (id)newWithParentScope:(id)scope macros:(id)macros definitionLevel:(long long)level;
+ (id)newWithParentScope:(id)scope definitionLevelsToClear:(id)clear macroDefinitionTables:(id)tables conditionParameterValues:(id)values options:(unsigned long long)options knownStringMapping:(id)mapping;
+ (id)newWithParentScope:(id)scope macroDefinitionTables:(id)tables conditionParameterValues:(id)values options:(unsigned long long)options;
+ (id)newWithParentScope:(id)scope macroDefinitionTables:(id)tables conditionParameterValues:(id)values;
+ (id)newWithParentScope:(id)scope macroDefinitionTables:(id)tables;

- (id)lookupValueForMacroName:(id)name hash:(unsigned int)hash withCursor:(struct DVTMacroNameLookupCursor *)cursor;
- (id)evaluatedStringValueForMacroNamed:(id)named returningFallbackConditionsUsed:(id *)used;
- (id)evaluatedStringValueForMacroNamed:(id)named;
- (id)evaluatedStringListValueForMacroNamed:(id)named;
- (_Bool)evaluatedBooleanValueForMacroNamed:(id)named;
- (id)evaluatedStringValueForMacroExpression:(id)expression;
- (id)evaluatedStringListValueForMacroExpression:(id)expression;
- (_Bool)evaluatedBooleanValueForMacroExpression:(id)expression;
- (id)evaluateMacroExpression:(id)expression asStringForLiteralStringValue:(id)value;
- (id)evaluateMacroExpression:(id)expression asStringListForLiteralStringValue:(id)value;
- (id)initWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values conditionParameterFallbackValues:(id)fallbackValues expansionOptions:(unsigned long long)options;
- (id)initWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values expansionOptions:(unsigned long long)options;
- (id)init;
- (id)copyWithZone:(struct _NSZone *)zone;
- (id)copy;
- (id)longDescription;
- (id)parentScope;
- (unsigned long long)options;
- (id)macroDefinitionTable;
- (long long)definitionLevel;
- (id)valueForConditionParameter:(id)parameter;
- (id)allConditionParameterValues;
- (id)allMacroNames;
- (void)appendAdditionalContentToStringBuilder:(void *)builder indent:(unsigned long long)indent;
- (id)descriptionWithLocale:(id)locale indent:(unsigned long long)indent;
- (id)description;
- (id)longDescriptionInMacroLookupOrder;
- (id)longDescriptionInScopeAncestryOrder;
- (id)longDescriptionInSortedMacroNameOrder;
- (id)sortedLongDescription;
- (id)scopeByRemovingAllTablesAtDefinitionLevel:(long long)level;
- (id)nextScopeForOwnDefinitionLevel;
- (void)appendDebugDescriptionToStringBuilder:(void *)builder indent:(unsigned long long)indent;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONSCOPE_H */
