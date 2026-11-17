/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - DVTStringBuilder is not part of this port; the two append methods accept
 *    an opaque builder pointer and do nothing.
 *  - Validation failures are raised as NSInvalidArgumentException instead of
 *    going through DVTAssertionFailureHandler.
 */

#import "DVTMacroExpansionScope.h"

#import <CoreFoundation/CoreFoundation.h>
#import <string.h>

#import "DVTMacroDefinitionConditionSet.h"
#import "DVTMacroExpansion-Protocol.h"
#import "DVTMacroExpansionScope_Private.h"

@interface DVTMacroExpansionScope ()
- (id)_scopeForDefinitionLevel:(NSUInteger)level;
- (id)_longDescriptionInScopeOrder:(NSArray *)scopes;
- (NSArray *)longDescriptionInMacroLookupOrderScopes;
@end

static void
DVTMacroExpansionScopeRaise(id object, NSString *message)
{
	[NSException raise:NSInvalidArgumentException format:@"-[%@ %@]: %@",
		NSStringFromClass([object class]), @"DVTMacroExpansionScope", message];
}

static BOOL
DVTMacroExpansionScopeIsDictionary(id value)
{
	return (value == nil || CFGetTypeID((__bridge CFTypeRef)value) == CFDictionaryGetTypeID());
}

@implementation DVTMacroExpansionScope

+ (id)newWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values conditionParameterFallbackValues:(id)fallbackValues expansionOptions:(unsigned long long)options
{
	return ([[self alloc] initWithParentScope:scope macroDefinitionTable:table definitionLevel:level definitionLevelsToClear:clear conditionParameterValues:values conditionParameterFallbackValues:fallbackValues expansionOptions:options]);
}

+ (id)newWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values expansionOptions:(unsigned long long)options
{
	return ([[self alloc] initWithParentScope:scope macroDefinitionTable:table definitionLevel:level definitionLevelsToClear:clear conditionParameterValues:values conditionParameterFallbackValues:nil expansionOptions:options]);
}

+ (id)newWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values
{
	return ([[self alloc] initWithParentScope:scope macroDefinitionTable:table definitionLevel:level definitionLevelsToClear:clear conditionParameterValues:values conditionParameterFallbackValues:nil expansionOptions:0]);
}

+ (id)newWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level
{
	return ([[self alloc] initWithParentScope:scope macroDefinitionTable:table definitionLevel:level definitionLevelsToClear:nil conditionParameterValues:nil conditionParameterFallbackValues:nil expansionOptions:0]);
}

+ (id)stringForDefinitionLevel:(long long)level
{
	return (level == 0 ? @"default" : @"UNKNOWN");
}

+ (id)newWithParentScope:(id)scope macros:(id)macros definitionLevel:(long long)level conditionParameterValues:(id)values preserveUnresolvedReferences:(_Bool)references
{
	DVTMacroDefinitionTable *table = [DVTMacroDefinitionTable newWithLabel:nil];

	[table setMacroNamesAndValuesFromDictionary:macros];
	return ([[self alloc] initWithParentScope:scope macroDefinitionTable:table definitionLevel:(unsigned long long)level definitionLevelsToClear:nil conditionParameterValues:values conditionParameterFallbackValues:nil expansionOptions:(references ? 1 : 0)]);
}

+ (id)newWithParentScope:(id)scope macros:(id)macros definitionLevel:(long long)level conditionParameterValues:(id)values
{
	return ([self newWithParentScope:scope macros:macros definitionLevel:level conditionParameterValues:values preserveUnresolvedReferences:NO]);
}

+ (id)newWithParentScope:(id)scope macros:(id)macros definitionLevel:(long long)level
{
	return ([self newWithParentScope:scope macros:macros definitionLevel:level conditionParameterValues:nil preserveUnresolvedReferences:NO]);
}

+ (id)newWithParentScope:(id)scope definitionLevelsToClear:(id)clear macroDefinitionTables:(id)tables conditionParameterValues:(id)values options:(unsigned long long)options knownStringMapping:(id)mapping
{
	id current = scope;
	NSUInteger index;
	(void)mapping;

	if (tables == nil) {
		return (current);
	}
	for (index = 0; index < [tables count]; index++) {
		current = [self newWithParentScope:current macroDefinitionTable:[tables objectAtIndex:index] definitionLevel:index definitionLevelsToClear:clear conditionParameterValues:values expansionOptions:options];
	}
	return (current);
}

+ (id)newWithParentScope:(id)scope macroDefinitionTables:(id)tables conditionParameterValues:(id)values options:(unsigned long long)options
{
	return ([self newWithParentScope:scope definitionLevelsToClear:nil macroDefinitionTables:tables conditionParameterValues:values options:options knownStringMapping:nil]);
}

+ (id)newWithParentScope:(id)scope macroDefinitionTables:(id)tables conditionParameterValues:(id)values
{
	return ([self newWithParentScope:scope macroDefinitionTables:tables conditionParameterValues:values options:0]);
}

+ (id)newWithParentScope:(id)scope macroDefinitionTables:(id)tables
{
	return ([self newWithParentScope:scope macroDefinitionTables:tables conditionParameterValues:nil options:0]);
}

- (id)init
{
	return ([self initWithParentScope:nil macroDefinitionTable:nil definitionLevel:0 definitionLevelsToClear:nil conditionParameterValues:nil conditionParameterFallbackValues:nil expansionOptions:0]);
}

- (id)initWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values conditionParameterFallbackValues:(id)fallbackValues expansionOptions:(unsigned long long)options
{
	self = [super init];
	if (self != nil) {
		if (scope != nil && ![scope isKindOfClass:[DVTMacroExpansionScope class]]) {
			DVTMacroExpansionScopeRaise(self, @"parentScope must be a DVTMacroExpansionScope");
		}
		if (clear != nil && ![clear isKindOfClass:[NSIndexSet class]]) {
			DVTMacroExpansionScopeRaise(self, @"definitionLevelsToClear must be an index set");
		}
		if (!DVTMacroExpansionScopeIsDictionary(values)) {
			DVTMacroExpansionScopeRaise(self, @"conditionParameterValues must be a dictionary");
		}
		if (!DVTMacroExpansionScopeIsDictionary(fallbackValues)) {
			DVTMacroExpansionScopeRaise(self, @"conditionParameterFallbackValues must be a dictionary");
		}
		if (options > 2) {
			DVTMacroExpansionScopeRaise(self, @"expansionOptions is out of range");
		}
		_parentScope = scope;
		if (table != nil && ![table isKindOfClass:[DVTMacroDefinitionTable class]]) {
			DVTMacroExpansionScopeRaise(self, @"macroDefinitionTable must be a DVTMacroDefinitionTable");
		}
		DVTMacroExpansionScope *parent = scope;
		_macroDefnTable = [table copy];
		_condParamValues = values;
		_condParamFallbackValues = fallbackValues;
		_expansionOptions = (unsigned int)options;
		_defnLevel = (unsigned int)level;
		_highestDefnLevel = (unsigned int)level;
		if (parent != nil && parent->_highestDefnLevel > _highestDefnLevel) {
			_highestDefnLevel = parent->_highestDefnLevel;
		}
		if (parent != nil) {
			NSMutableDictionary *allValues = [NSMutableDictionary dictionaryWithDictionary:parent->_allCondParamValues];
			NSMutableDictionary *allFallback = [NSMutableDictionary dictionaryWithDictionary:parent->_allCondParamFallbackValues];

			if (values != nil) {
				[allValues addEntriesFromDictionary:values];
			}
			if (fallbackValues != nil) {
				[allFallback addEntriesFromDictionary:fallbackValues];
			}
			_allCondParamValues = [allValues copy];
			_allCondParamFallbackValues = [allFallback copy];
		} else {
			_allCondParamValues = values;
			_allCondParamFallbackValues = fallbackValues;
		}

		NSUInteger count = (NSUInteger)_highestDefnLevel + 1;
		_nextScopeByDefnLevel = (__unsafe_unretained id *)calloc(count, sizeof(id));
		if (parent != nil) {
			NSUInteger parentCount = (NSUInteger)parent->_highestDefnLevel + 1;
			if (parentCount > count) {
				parentCount = count;
			}
			if (parentCount > 0) {
				memcpy(_nextScopeByDefnLevel, parent->_nextScopeByDefnLevel, parentCount * sizeof(id));
			}
			_nextScopeByDefnLevel[parent->_defnLevel] = parent;
		}
		[clear enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
			(void)stop;
			if (index <= self->_highestDefnLevel) {
				self->_nextScopeByDefnLevel[index] = nil;
			}
		}];
	}
	return (self);
}

- (void)dealloc
{
	free(_nextScopeByDefnLevel);
#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

- (id)copyWithZone:(struct _NSZone *)zone
{
	(void)zone;
	return ([[DVTMacroExpansionScope alloc] initWithParentScope:_parentScope
						 macroDefinitionTable:_macroDefnTable
							  definitionLevel:_defnLevel
						  definitionLevelsToClear:nil
						    conditionParameterValues:_condParamValues
					    conditionParameterFallbackValues:_condParamFallbackValues
							    expansionOptions:_expansionOptions]);
}

- (id)copy
{
	return ([[self class] newWithParentScope:_parentScope macroDefinitionTable:_macroDefnTable definitionLevel:_defnLevel definitionLevelsToClear:nil conditionParameterValues:_condParamValues conditionParameterFallbackValues:_condParamFallbackValues expansionOptions:_expansionOptions]);
}

- (_Bool)preserveUnresolvedReferences
{
	return ((_expansionOptions & 1) != 0);
}

- (id)parentScope
{
	return (_parentScope);
}

- (unsigned long long)options
{
	return (_expansionOptions);
}

- (id)macroDefinitionTable
{
	return (_macroDefnTable);
}

- (long long)definitionLevel
{
	return (_defnLevel);
}

- (id)valueForConditionParameter:(id)parameter
{
	NSString *name = parameter;

	if ([parameter respondsToSelector:@selector(name)]) {
		name = [parameter name];
	}
	return ([_allCondParamValues objectForKey:name]);
}

- (id)allConditionParameterValues
{
	return (_allCondParamValues != nil ? _allCondParamValues : [NSDictionary dictionary]);
}

- (id)allMacroNames
{
	NSMutableSet *names = [NSMutableSet set];

	if (_parentScope != nil) {
		[names unionSet:[_parentScope allMacroNames]];
	}
	[names unionSet:[_macroDefnTable allMacroNames]];
	return ([[NSSet alloc] initWithArray:[names allObjects]]);
}

- (id)_scopeForDefinitionLevel:(NSUInteger)level
{
	if (_nextScopeByDefnLevel != NULL && level <= _highestDefnLevel) {
		id scope = _nextScopeByDefnLevel[level];
		if (scope != nil) {
			return (scope);
		}
	}
	if (level == _defnLevel) {
		return (self);
	}
	return (nil);
}

- (id)lookupValueForMacroName:(id)name hash:(unsigned int)hash withCursor:(struct DVTMacroNameLookupCursor *)cursor
{
	NSUInteger level;
	(void)hash;

	if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
		return (nil);
	}
	if (cursor != NULL) {
		cursor->x0 = self;
		cursor->x1 = 0;
		cursor->x2 = nil;
		cursor->x3 = nil;
		cursor->x4 = NULL;
		cursor->x5 = nil;
	}
	for (level = 0; level <= _highestDefnLevel; level++) {
		DVTMacroExpansionScope *scope = [self _scopeForDefinitionLevel:level];
		__block id foundValue = nil;
		__block DVTMacroDefinitionConditionSet *foundSet = nil;

		if (scope == nil) {
			continue;
		}
		[scope->_macroDefnTable enumerateValuesForMacroName:name usingBlock:^(id macroName, id conditionSet, id value, BOOL *stop) {
			(void)macroName;
			if (conditionSet == nil || [conditionSet evaluateForParameterValues:(scope->_allCondParamValues != nil ? scope->_allCondParamValues : [NSDictionary dictionary])]) {
				foundValue = value;
				foundSet = conditionSet;
				*stop = YES;
			}
		}];
		if (foundValue == nil && [scope->_allCondParamFallbackValues count] != 0) {
			NSMutableDictionary *values = [NSMutableDictionary dictionaryWithDictionary:scope->_allCondParamValues];
			NSMutableDictionary *used = [NSMutableDictionary dictionary];

			[values addEntriesFromDictionary:scope->_allCondParamFallbackValues];
			[scope->_macroDefnTable enumerateValuesForMacroName:name usingBlock:^(id macroName, id conditionSet, id value, BOOL *stop) {
				(void)macroName;
				if (conditionSet != nil && [conditionSet evaluateForParameterValues:(values != nil ? values : [NSDictionary dictionary])]) {
					for (NSString *parameterName in [conditionSet parameterNames]) {
						id fallback = [scope->_allCondParamFallbackValues objectForKey:parameterName];
						id actual = [scope->_allCondParamValues objectForKey:parameterName];
						if (fallback != nil && ![fallback isEqual:actual]) {
							[used setObject:fallback forKey:parameterName];
						}
					}
					foundValue = value;
					foundSet = conditionSet;
					*stop = YES;
				}
			}];
			if (foundValue != nil && cursor != NULL && [used count] != 0) {
				__unsafe_unretained id fallbackUsed = [NSDictionary dictionaryWithDictionary:used];
				cursor->x5 = fallbackUsed;
			}
		}
		if (foundValue != nil) {
			if (cursor != NULL) {
				cursor->x0 = scope;
				cursor->x1 = level;
				cursor->x2 = scope;
				cursor->x3 = foundSet;
			}
			return (foundValue);
		}
	}
	return (nil);
}

- (id)initWithParentScope:(id)scope macroDefinitionTable:(id)table definitionLevel:(unsigned long long)level definitionLevelsToClear:(id)clear conditionParameterValues:(id)values expansionOptions:(unsigned long long)options
{
	return ([self initWithParentScope:scope macroDefinitionTable:table definitionLevel:level definitionLevelsToClear:clear conditionParameterValues:values conditionParameterFallbackValues:nil expansionOptions:options]);
}

- (id)evaluatedStringValueForMacroNamed:(id)named returningFallbackConditionsUsed:(id *)used
{
	struct DVTNestedMacroExpansionState state;
	id value;
	id result;

	if (used != NULL) {
		*used = nil;
	}
	if (named == nil) {
		return (nil);
	}
	memset(&state, 0, sizeof(state));
	state.macroName = named;
	state.hash = (unsigned int)[named hash];
	value = [self lookupValueForMacroName:named hash:state.hash withCursor:&state.cursor];
	if (value == nil) {
		return (nil);
	}
	result = [(id<DVTMacroExpansion>)value dvt_evaluateAsStringInScope:self withState:&state];
	if (used != NULL) {
		*used = state.cursor.x5;
	}
	return (result);
}

- (id)evaluatedStringValueForMacroNamed:(id)named
{
	return ([self evaluatedStringValueForMacroNamed:named returningFallbackConditionsUsed:NULL]);
}

- (id)evaluatedStringListValueForMacroNamed:(id)named
{
	struct DVTNestedMacroExpansionState state;
	id value;

	if (named == nil) {
		return (nil);
	}
	memset(&state, 0, sizeof(state));
	state.macroName = named;
	state.hash = (unsigned int)[named hash];
	value = [self lookupValueForMacroName:named hash:state.hash withCursor:&state.cursor];
	if (value == nil) {
		return (nil);
	}
	return ([(id<DVTMacroExpansion>)value dvt_evaluateAsStringListInScope:self withState:&state]);
}

- (_Bool)evaluatedBooleanValueForMacroNamed:(id)named
{
	NSString *string = [self evaluatedStringValueForMacroNamed:named];

	return (string != nil ? [string boolValue] : NO);
}

- (id)evaluateMacroExpression:(id)expression asStringForLiteralStringValue:(id)value
{
	struct DVTNestedMacroExpansionState state;

	if (expression == nil) {
		return (value);
	}
	memset(&state, 0, sizeof(state));
	state.macroName = @"";
	state.hash = 0;
	return ([(id<DVTMacroExpansion>)expression dvt_evaluateAsStringInScope:self withState:&state]);
}

- (id)evaluateMacroExpression:(id)expression asStringListForLiteralStringValue:(id)value
{
	struct DVTNestedMacroExpansionState state;

	if (expression == nil) {
		return (value);
	}
	memset(&state, 0, sizeof(state));
	state.macroName = @"";
	state.hash = 0;
	return ([(id<DVTMacroExpansion>)expression dvt_evaluateAsStringListInScope:self withState:&state]);
}

- (id)evaluatedStringValueForMacroExpression:(id)expression
{
	if (expression == nil) {
		return (nil);
	}
	return ([self evaluateMacroExpression:expression asStringForLiteralStringValue:nil]);
}

- (id)evaluatedStringListValueForMacroExpression:(id)expression
{
	if (expression == nil) {
		return (nil);
	}
	return ([self evaluateMacroExpression:expression asStringListForLiteralStringValue:nil]);
}

- (_Bool)evaluatedBooleanValueForMacroExpression:(id)expression
{
	NSString *string = [self evaluatedStringValueForMacroExpression:expression];

	return (string != nil ? [string boolValue] : NO);
}

- (id)descriptionWithLocale:(id)locale indent:(unsigned long long)indent
{
	NSMutableString *description = [NSMutableString string];
	unsigned long long index;
	NSString *tableDescription;
	NSArray *conditionNames;

	for (index = 0; index < indent; index++) {
		[description appendString:@"   "];
	}
	[description appendFormat:@"<DVTMacroExpansionScope:%p:level = %lld [%@]\n",
		self, (long long)_defnLevel, [[self class] stringForDefinitionLevel:_defnLevel]];
	conditionNames = [[_allCondParamValues allKeys] sortedArrayUsingSelector:@selector(compare:)];
	if ([conditionNames count] == 0) {
		[description appendString:@"  .conditions = { }\n"];
	} else {
		[description appendString:@"  .conditions = {\n"];
		for (NSString *name in conditionNames) {
			[description appendFormat:@"        %@ = %@;\n", name, [_allCondParamValues objectForKey:name]];
		}
		[description appendString:@"    }\n"];
	}
	if ([_macroDefnTable numberOfMacros] == 0) {
		tableDescription = @"{ }";
	} else {
		tableDescription = [_macroDefnTable descriptionWithLocale:locale indent:0];
		tableDescription = [tableDescription stringByReplacingOccurrencesOfString:@"\n" withString:@"\n   "];
	}
	[description appendFormat:@"  .macros = %@\n>", tableDescription];
	return (description);
}

- (id)description
{
	return ([self descriptionWithLocale:nil indent:0]);
}

- (void)appendAdditionalContentToStringBuilder:(void *)builder indent:(unsigned long long)indent
{
	(void)builder;
	(void)indent;
}

- (void)appendDebugDescriptionToStringBuilder:(void *)builder indent:(unsigned long long)indent
{
	(void)builder;
	(void)indent;
}

- (id)_longDescriptionInScopeOrder:(NSArray *)scopes
{
	NSMutableString *result = [NSMutableString stringWithString:@"(\n"];

	for (DVTMacroExpansionScope *scope in scopes) {
		[result appendString:[scope description]];
		[result appendString:@"\n"];
	}
	[result appendString:@")"];
	return (result);
}

- (id)_longDescriptionInScopeOrderWithAngleBrackets:(NSArray *)scopes
{
	NSMutableString *result = [NSMutableString stringWithString:@"<\n"];

	for (DVTMacroExpansionScope *scope in scopes) {
		[result appendString:[scope description]];
		[result appendString:@"\n"];
	}
	[result appendString:@">"];
	return (result);
}

- (NSArray *)longDescriptionInMacroLookupOrderScopes
{
	NSMutableArray *scopes = [NSMutableArray array];

	if (_parentScope != nil) {
		[scopes addObjectsFromArray:[_parentScope longDescriptionInMacroLookupOrderScopes]];
	}
	[scopes addObject:self];
	return (scopes);
}

- (id)longDescriptionInMacroLookupOrder
{
	NSMutableArray *scopes = [NSMutableArray array];

	if (_parentScope != nil) {
		[scopes addObjectsFromArray:[_parentScope longDescriptionInMacroLookupOrderScopes]];
	}
	[scopes addObject:self];
	return ([self _longDescriptionInScopeOrder:scopes]);
}

- (id)longDescriptionInScopeAncestryOrder
{
	NSMutableArray *scopes = [NSMutableArray array];
	DVTMacroExpansionScope *scope = self;

	while (scope != nil) {
		[scopes addObject:scope];
		scope = scope->_parentScope;
	}
	return ([self _longDescriptionInScopeOrderWithAngleBrackets:scopes]);
}

- (id)longDescriptionInSortedMacroNameOrder
{
	NSMutableArray *scopes = [NSMutableArray array];

	if (_parentScope != nil) {
		[scopes addObjectsFromArray:[_parentScope longDescriptionInMacroLookupOrderScopes]];
	}
	[scopes addObject:self];
	return ([self _longDescriptionInScopeOrderWithAngleBrackets:scopes]);
}

- (id)longDescription
{
	return ([self longDescriptionInMacroLookupOrder]);
}

- (id)sortedLongDescription
{
	return ([self longDescriptionInScopeAncestryOrder]);
}

- (id)scopeByRemovingAllTablesAtDefinitionLevel:(long long)level
{
	DVTMacroDefinitionTable *table = _macroDefnTable;

	if (level == (long long)_defnLevel) {
		table = [DVTMacroDefinitionTable empty];
	}
	return ([[DVTMacroExpansionScope alloc] initWithParentScope:_parentScope
						 macroDefinitionTable:table
							  definitionLevel:_defnLevel
						  definitionLevelsToClear:[NSIndexSet indexSetWithIndex:(NSUInteger)level]
						    conditionParameterValues:_condParamValues
					    conditionParameterFallbackValues:_condParamFallbackValues
							    expansionOptions:_expansionOptions]);
}

- (id)nextScopeForOwnDefinitionLevel
{
	NSUInteger next = (NSUInteger)_defnLevel + 1;

	if (_nextScopeByDefnLevel != NULL && next <= _highestDefnLevel) {
		return (_nextScopeByDefnLevel[next]);
	}
	return (nil);
}

@end

