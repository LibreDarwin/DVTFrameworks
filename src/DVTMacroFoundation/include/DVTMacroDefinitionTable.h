/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroDefinitionTable.
 *
 * A macro definition table maps macro names to a list of value assignments.
 * Each assignment pairs a DVTMacroDefinitionConditionSet (which may be nil,
 * meaning "unconditional") with a value object conforming to
 * DVTMacroExpansion.  The assignments for a given macro name are kept in
 * descending condition-set precedence order, so the first assignment whose
 * condition set matches the evaluation environment wins.
 *
 * Tables are copy-on-write: -copy and -copyWithLabel: share the underlying
 * assignments until one of the copies is mutated, while -mutableCopy always
 * creates an independent deep copy.
 *
 * Deviations from Apple's header:
 *
 *  - The private C++ DVTMacroValueAssignmentMapTable is replaced by an
 *    Objective-C object of the same name which models the same behaviour on
 *    top of NSMutableDictionary.
 *  - _cacheLock is an NSLock instead of an os_unfair_lock (same locking
 *    discipline, observable behaviour is unchanged).
 *  - DVTStackBacktrace is only forward declared; this port never records
 *    creation backtraces (see the implementation notes).
 */

#ifndef DVTMACROFOUNDATION_DVTMACRODEFINITIONTABLE_H
#define DVTMACROFOUNDATION_DVTMACRODEFINITIONTABLE_H

#import <Foundation/Foundation.h>

@class DVTMacroDefinitionConditionSet, DVTMacroDefinitionTable, DVTStackBacktrace;
@class DVTMacroValueAssignmentMapTable;

@interface DVTMacroDefinitionTable : NSObject <NSCopying, NSMutableCopying> {
	DVTMacroValueAssignmentMapTable *_mapTable;
	id _willSetValueBlock;
	id _didSetValueBlock;
	DVTStackBacktrace *_creationBacktrace;
	DVTMacroDefinitionTable *_originalTable;
	NSString *_label;
	NSDictionary *_cachedDictRep;
	NSSet *_cachedMacroNameSet;
	unsigned long long _cachedHash;
	id _cacheLock;
	BOOL _isImmutable;
	BOOL _postsChangeNotifications;
	BOOL _declaredMutable;
}

@property (copy) NSString *label;
@property _Bool postsChangeNotifications;

/* Both blocks are invoked as
 * ^(NSString *macroName, DVTMacroDefinitionConditionSet *conditionSet,
 *   id<DVTMacroExpansion> value). */
@property (copy) id /* block */ willSetValueBlock;
@property (copy) id /* block */ didSetValueBlock;

+ (id)newWithLabel:(id)label;

/* The shared, immutable, empty table. */
+ (id)empty;

/* Always nil in this port: the macro name registry belongs to a later stage
 * of the macro foundation. */
+ (id)macroNameRegistry;

- (id)initWithLabel:(id)label creationBacktrace:(id)backtrace;
- (id)initWithLabel:(id)label;

/* Number of distinct macro names. */
- (unsigned long long)numberOfMacros;

/* Number of value assignments (a macro name with an unconditional and a
 * conditional definition counts twice). */
- (unsigned long long)numberOfDefinitions;

/* Same as -numberOfMacros. */
- (unsigned long long)count;

- (void)discardCaches;

/* Stores value for the given macro name and condition set; a nil value
 * removes the matching assignment.  The value must already conform to
 * DVTMacroExpansion. */
- (void)setValue:(id)value forMacroName:(id)name conditionSet:(id)set;

/* Parses value as a DVT macro expression before storing it. */
- (void)setStringValue:(id)value forMacroName:(id)name conditionSet:(id)set;

/* Converts strings and arrays of strings into literal DVTMacroExpansion
 * objects before storing them. */
- (void)setLiteralValue:(id)value forMacroName:(id)name conditionSet:(id)set;

- (void)_setLiteralValue:(id)value forMacroName:(id)name conditionSet:(id)set wantsCheckForDVTMacroExpansionConformance:(_Bool)conformance;

- (void)parseAndSetValue:(id)value forMacroName:(id)name conditionSet:(id)set;

- (id)valueForMacroName:(id)name conditionSet:(id)set;

- (void)removeAllConditionSetsForMacroName:(id)name;
- (void)enumerateValuesForMacroName:(id)name usingBlock:(id /* block */)block;
- (void)enumerateMacroNamesAndValuesUsingBlock:(id /* block */)block;

/* Keys are the macro names, optionally followed by the condition set's
 * subscript representation. */
- (id)dictionaryRepresentation;

- (id)allMacroNames;
- (void)setMacroNamesAndValuesFromDictionary:(id)dictionary;
- (void)setMacroNamesAndValuesFromMacroDefinitionTable:(id)table;

- (void)removeMacroName:(id)name;
- (void)removeMacroNames:(id)names arguments:(char *)arguments;
- (void)removeMacroNames:(id)names;
- (void)removeAllMacros;

- (id)copyWithZone:(struct _NSZone *)zone;
- (id)copyWithLabel:(id)label;
- (id)mutableCopyWithZone:(struct _NSZone *)zone;

- (_Bool)isImmutable;
- (void)makeImmutable;
- (void)declareMutable;

- (id)valueForKey:(id)key;
- (id)objectForKeyedSubscript:(id)subscript;
- (void)setObject:(id)object forKeyedSubscript:(id)subscript;

- (void)assertInternalConsistency;

- (id)descriptionWithLocale:(id)locale indent:(unsigned long long)indent;
- (id)description;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACRODEFINITIONTABLE_H */
