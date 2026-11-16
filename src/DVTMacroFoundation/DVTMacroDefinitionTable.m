/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroDefinitionTable and of its private helper types
 * DVTMacroValueAssignment and DVTMacroValueAssignmentMapTable.
 *
 * Deviations from Apple's implementation:
 *
 *  - DVTMacroValueAssignmentMapTable is an Objective-C object built on top of
 *    NSMutableDictionary instead of the open-addressed C++ hash table Apple
 *    uses.  The observable semantics are reproduced: assignments are kept in
 *    descending condition-set precedence order with the unconditional entry
 *    last, values are copied into the table, nil values delete a matching
 *    assignment, and the enumeration orders match.
 *  - Assignments are immutable objects; replacing a value installs a new
 *    assignment object instead of mutating one in place.  Apple's map table
 *    mutates the value pointer in place, which is not observable as long as
 *    the assignment itself is not exposed (it never is).
 *  - Values are copied with -copy on insertion, exactly like Apple's
 *    DVTMacroValueAssignment constructor; because the DVTMacroExpansion
 *    literal classes return themselves from -copy this is transparent.
 *  - _cacheLock is an NSLock instead of the inline os_unfair_lock Apple uses.
 *  - -dealloc is omitted because ARC releases the instance variables.  Apple's
 *    -dealloc only releases the label and backtrace and discards the caches,
 *    none of which is observable from outside.
 *  - +newWithLabel: and the literal factories use [[self alloc] ...] instead
 *    of DVTAllocateObject().
 *  - Creation backtraces are never recorded: DVTStackBacktrace is only
 *    forward declared and -creationBacktrace always returns nil.  Recording a
 *    backtrace requires DVTShouldRecordMacroDefinitionTableBacktraceStatistics()
 *    to be true, which needs a private logging aspect at log level 3.
 *  - -parseAndSetValue: and DVTSetMacroNameAndValue() would parse their string
 *    arguments with DVTMacroExpressionByParsingString(AsList).  That
 *    expression parser belongs to a later stage of the port, so both fall
 *    back to the literal DVTMacroExpansion classes here.  Every other path of
 *    those two methods (conforming values, nil, non-string/array values) is
 *    reproduced exactly.
 *  - DVTCachedConformsToProtocol() is replaced by -conformsToProtocol:; Apple
 *    caches the answer in a global table, which is not observable.
 *  - -dictionaryRepresentation and the change broadcasts use NSMutableDictionary
 *    instead of DVT::StringBuilder and +dvt_dictionaryWithKeysAndValues:.
 *  - Internal assertion failures with an empty message are raised as
 *    NSInvalidArgumentException with the assertion condition as the reason.
 *    Apple's DVTAssertionFailureHandler is not part of this port, and it
 *    terminates the process in the probe environment, so its exact
 *    presentation is not observable.
 */

#import "DVTMacroDefinitionTable.h"

#import "DVTMacroExpressionParser.h"
#import "DVTMacroNameRegistry.h"

#import <CoreFoundation/CoreFoundation.h>

#import "DVTFoundationClassAdditions.h"
#import "NSObject+DVTAssertionSupport.h"
#import "DVTMacroDefinitionConditionSet.h"
#import "DVTMacroExpansion-Protocol.h"
#import "DVTMacroExpansionString_Literal.h"
#import "DVTMacroExpansionStringList_Literal.h"
#import "NSArray+DVTMacroExpansion.h"
#import "NSString+DVTMacroExpansion.h"

enum {
	DVTMapTableEnumerationOrderUnsorted = 0,
	DVTMapTableEnumerationOrderSorted = 1,
	DVTMapTableEnumerationOrderReverseSorted = 2
};
typedef NSInteger DVTMapTableEnumerationOrder;

static NSString * const DVTMacroDefinitionTableValueDidChangeBroadcast = @"DVTMacroDefinitionTable_ValueDidChangeBroadcast";

static void
DVTMacroDefinitionTableRaiseInternalAssertion(NSString *condition)
{
	[NSException raise:NSInvalidArgumentException format:@"%@", condition];
}

static void
DVTMacroDefinitionTableCheckMacroName(id macroName)
{
	if (macroName == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it is nil", @"macroName"];
	}
	if (CFGetTypeID((__bridge CFTypeRef)macroName) != CFStringGetTypeID()) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it is %@",
				   @"macroName", [macroName descriptionForAssertionMessage]];
	}
	/* Apple checks the type twice before checking for an empty string. */
	if (CFGetTypeID((__bridge CFTypeRef)macroName) != CFStringGetTypeID()) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it is %@",
				   @"macroName", [macroName descriptionForAssertionMessage]];
	}
	if ([macroName isEqualToString:@""]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it's an empty string", @"macroName"];
	}
}

static void
DVTMacroDefinitionTableCheckConditionSet(id conditionSet)
{
	if (conditionSet != nil && ![conditionSet isKindOfClass:[DVTMacroDefinitionConditionSet class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"conditionSet",
				   NSStringFromClass([DVTMacroDefinitionConditionSet class]),
				   [conditionSet descriptionForAssertionMessage]];
	}
}

static id
DVTMacroDefinitionTableLiteralValueForString(NSString *string)
{
	id literalValue = [string dvt_literalValueOfCommonString];
	if (literalValue != nil) {
		return (literalValue);
	}
	return ([DVTMacroExpansionString_Literal newWithLiteralString:string]);
}

static id
DVTMacroDefinitionTableLiteralValueForArray(NSArray *array)
{
	NSString *stringForm = [array dvt_stringByConcatenatingAsCommandLineArguments];
	return ([DVTMacroExpansionStringList_Literal newWithStringForm:stringForm literalStrings:array]);
}

/* Declared here rather than in DVTFoundation's public header: the broadcast
 * methods forward to DVTBroadcastCenter, which is not part of this port yet.
 * The table only reaches this method when -postsChangeNotifications is on, and
 * nothing enables that today. */
@interface NSObject (DVTMacroDefinitionTableBroadcast)
- (void)dvt_broadcast:(id)notification userInfo:(id)userInfo;
@end

@interface DVTMacroValueAssignment : NSObject <NSCopying> {
@public
	DVTMacroDefinitionConditionSet *_conditionSet;
	id _value;
}
- (id)initWithConditionSet:(DVTMacroDefinitionConditionSet *)conditionSet value:(id)value;
@end

@implementation DVTMacroValueAssignment

- (id)initWithConditionSet:(DVTMacroDefinitionConditionSet *)conditionSet value:(id)value
{
	self = [super init];
	if (self != nil) {
		_conditionSet = [conditionSet copy];
		_value = [value copy];
	}
	return (self);
}

- (id)copyWithZone:(NSZone *)zone
{
	return ([[[self class] allocWithZone:zone] initWithConditionSet:_conditionSet value:_value]);
}

@end

@interface DVTMacroValueAssignmentMapTable : NSObject <NSCopying> {
	NSMutableDictionary *_assignmentsByName;
	NSMutableArray *_insertionOrder;
	unsigned long long _definitionCount;
	unsigned long long _slotCount;
}
- (id)initWithCapacity:(unsigned long long)capacity;
- (unsigned long long)numberOfMacroNames;
- (unsigned long long)numberOfDefinitions;
- (BOOL)compareValuesForKey:(id)macroName otherTable:(DVTMacroValueAssignmentMapTable *)otherTable;
- (id)valueForKey:(id)macroName conditionSet:(DVTMacroDefinitionConditionSet *)conditionSet;
- (void)setValue:(id)value forKey:(id)macroName conditionSet:(DVTMacroDefinitionConditionSet *)conditionSet;
- (void)enumerateValuesForKey:(id)macroName usingBlock:(void (^)(DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop))block;
- (NSArray *)macroNamesWithOrder:(DVTMapTableEnumerationOrder)order;
- (void)enumerateKeysWithOrder:(DVTMapTableEnumerationOrder)order usingBlock:(void (^)(NSString *macroName, BOOL *stop))block;
- (void)enumerateKeysAndValuesWithOrder:(DVTMapTableEnumerationOrder)order usingBlock:(void (^)(NSString *macroName, DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop))block;
- (void)removeAllValues;
@end

@implementation DVTMacroValueAssignmentMapTable

- (id)initWithCapacity:(unsigned long long)capacity
{
	self = [super init];
	if (self != nil) {
		_assignmentsByName = [[NSMutableDictionary alloc] initWithCapacity:(NSUInteger)capacity];
		_insertionOrder = [[NSMutableArray alloc] initWithCapacity:(NSUInteger)capacity];
		_slotCount = (capacity < 16) ? 16 : capacity;
	}
	return (self);
}

- (id)copyWithZone:(NSZone *)zone
{
	DVTMacroValueAssignmentMapTable *copy = [[[self class] allocWithZone:zone] initWithCapacity:[_assignmentsByName count]];
	for (NSString *macroName in _assignmentsByName) {
		NSArray *assignments = [_assignmentsByName objectForKey:macroName];
		NSMutableArray *copiedAssignments = [[NSMutableArray alloc] initWithCapacity:[assignments count]];
		for (DVTMacroValueAssignment *assignment in assignments) {
			[copiedAssignments addObject:[assignment copyWithZone:zone]];
		}
		[copy->_assignmentsByName setObject:copiedAssignments forKey:macroName];
	}
	[copy->_insertionOrder addObjectsFromArray:_insertionOrder];
	copy->_definitionCount = _definitionCount;
	copy->_slotCount = _slotCount;
	return (copy);
}

- (unsigned long long)numberOfMacroNames
{
	return ((unsigned long long)[_assignmentsByName count]);
}

- (unsigned long long)numberOfDefinitions
{
	return (_definitionCount);
}

- (id)valueForKey:(id)macroName conditionSet:(DVTMacroDefinitionConditionSet *)conditionSet
{
	NSArray *assignments = [_assignmentsByName objectForKey:macroName];
	for (DVTMacroValueAssignment *assignment in assignments) {
		if (assignment->_conditionSet == conditionSet) {
			return (assignment->_value);
		}
		if (assignment->_conditionSet != nil && conditionSet != nil && [assignment->_conditionSet isEqual:conditionSet]) {
			return (assignment->_value);
		}
	}
	return (nil);
}

- (void)setValue:(id)value forKey:(id)macroName conditionSet:(DVTMacroDefinitionConditionSet *)conditionSet
{
	NSMutableArray *assignments = [_assignmentsByName objectForKey:macroName];
	NSUInteger assignmentCount = [assignments count];
	for (NSUInteger index = 0; index < assignmentCount; index++) {
		DVTMacroValueAssignment *assignment = [assignments objectAtIndex:index];
		BOOL matches = (assignment->_conditionSet == conditionSet);
		if (!matches && assignment->_conditionSet != nil && conditionSet != nil) {
			matches = [assignment->_conditionSet isEqual:conditionSet];
		}
		if (matches) {
			if (value == nil) {
				[assignments removeObjectAtIndex:index];
				_definitionCount--;
				if ([assignments count] == 0) {
					[_assignmentsByName removeObjectForKey:macroName];
					[_insertionOrder removeObjectIdenticalTo:macroName];
				}
			} else {
				DVTMacroValueAssignment *replacement = [[DVTMacroValueAssignment alloc] initWithConditionSet:conditionSet value:value];
				[assignments replaceObjectAtIndex:index withObject:replacement];
			}
			return;
		}
	}
	if (value == nil) {
		return;
	}
	if (assignments == nil) {
		assignments = [[NSMutableArray alloc] init];
		[_assignmentsByName setObject:assignments forKey:macroName];
	}
	NSUInteger insertionIndex = 0;
	NSUInteger existingCount = [assignments count];
	while (insertionIndex < existingCount) {
		DVTMacroValueAssignment *assignment = [assignments objectAtIndex:insertionIndex];
		if (assignment->_conditionSet == nil) {
			break;
		}
		if (conditionSet != nil && [assignment->_conditionSet compare:conditionSet] == -1) {
			break;
		}
		insertionIndex++;
	}
	DVTMacroValueAssignment *assignment = [[DVTMacroValueAssignment alloc] initWithConditionSet:conditionSet value:value];
	[assignments insertObject:assignment atIndex:insertionIndex];
	_definitionCount++;
	if (existingCount == 0) {
		[_insertionOrder addObject:macroName];
		if ([_assignmentsByName count] > _slotCount) {
			_slotCount *= 2;
		}
	}
}

- (void)enumerateValuesForKey:(id)macroName usingBlock:(void (^)(DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop))block
{
	NSArray *assignments = [_assignmentsByName objectForKey:macroName];
	BOOL stop = NO;
	for (DVTMacroValueAssignment *assignment in assignments) {
		if (stop) {
			break;
		}
		block(assignment->_conditionSet, assignment->_value, &stop);
	}
}

- (NSArray *)_macroNamesInSlotOrder
{
	/* Apple's map table iterates its hash buckets in ascending slot order.
	 * Slot order is not a documented contract, but reproducing it keeps
	 * -enumerateMacroNamesAndValuesUsingBlock: in the same order as the
	 * original for tables that fit in the initial slot vector. */
	unsigned long long slotCount = _slotCount;
	NSArray *insertionOrder = _insertionOrder;
	return ([insertionOrder sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
		unsigned long long leftSlot = (unsigned long long)[left hash] & (slotCount - 1);
		unsigned long long rightSlot = (unsigned long long)[right hash] & (slotCount - 1);
		if (leftSlot < rightSlot) {
			return (NSOrderedAscending);
		}
		if (leftSlot > rightSlot) {
			return (NSOrderedDescending);
		}
		NSUInteger leftIndex = [insertionOrder indexOfObjectIdenticalTo:left];
		NSUInteger rightIndex = [insertionOrder indexOfObjectIdenticalTo:right];
		if (leftIndex < rightIndex) {
			return (NSOrderedAscending);
		}
		if (leftIndex > rightIndex) {
			return (NSOrderedDescending);
		}
		return (NSOrderedSame);
	}]);
}

- (NSArray *)macroNamesWithOrder:(DVTMapTableEnumerationOrder)order
{
	NSArray *macroNames = nil;
	if (order == DVTMapTableEnumerationOrderUnsorted) {
		macroNames = [self _macroNamesInSlotOrder];
	} else {
		macroNames = [[_assignmentsByName allKeys] sortedArrayUsingSelector:@selector(compare:)];
	}
	if (order == DVTMapTableEnumerationOrderReverseSorted) {
		macroNames = [[macroNames reverseObjectEnumerator] allObjects];
	}
	return (macroNames);
}

- (void)enumerateKeysWithOrder:(DVTMapTableEnumerationOrder)order usingBlock:(void (^)(NSString *macroName, BOOL *stop))block
{
	BOOL stop = NO;
	for (NSString *macroName in [self macroNamesWithOrder:order]) {
		if (stop) {
			break;
		}
		block(macroName, &stop);
	}
}

- (void)enumerateKeysAndValuesWithOrder:(DVTMapTableEnumerationOrder)order usingBlock:(void (^)(NSString *macroName, DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop))block
{
	BOOL stop = NO;
	for (NSString *macroName in [self macroNamesWithOrder:order]) {
		NSArray *assignments = [_assignmentsByName objectForKey:macroName];
		for (DVTMacroValueAssignment *assignment in assignments) {
			if (stop) {
				return;
			}
			block(macroName, assignment->_conditionSet, assignment->_value, &stop);
		}
	}
}

- (BOOL)compareValuesForKey:(id)macroName otherTable:(DVTMacroValueAssignmentMapTable *)otherTable
{
	NSArray *assignments = [_assignmentsByName objectForKey:macroName];
	NSArray *otherAssignments = [otherTable->_assignmentsByName objectForKey:macroName];
	if (assignments == nil || otherAssignments == nil) {
		return (NO);
	}
	if ([assignments count] != [otherAssignments count]) {
		return (NO);
	}
	NSUInteger count = [assignments count];
	for (NSUInteger index = 0; index < count; index++) {
		DVTMacroValueAssignment *assignment = [assignments objectAtIndex:index];
		DVTMacroValueAssignment *otherAssignment = [otherAssignments objectAtIndex:index];
		if (assignment->_conditionSet != otherAssignment->_conditionSet) {
			if (assignment->_conditionSet == nil || otherAssignment->_conditionSet == nil) {
				return (NO);
			}
			if (![assignment->_conditionSet isEqual:otherAssignment->_conditionSet]) {
				return (NO);
			}
		}
		if (assignment->_value != otherAssignment->_value) {
			if (assignment->_value == nil || otherAssignment->_value == nil) {
				return (NO);
			}
			if (![assignment->_value isEqual:otherAssignment->_value]) {
				return (NO);
			}
		}
	}
	return (YES);
}

- (void)removeAllValues
{
	[_assignmentsByName removeAllObjects];
	_definitionCount = 0;
}

@end

#pragma mark -

@interface DVTMacroDefinitionTable ()
- (void)raiseImmutableAssertion;
@end

@implementation DVTMacroDefinitionTable

static void
DVTSetMacroNameAndValue(DVTMacroDefinitionTable *table, id macroName, id value, BOOL valueIsAlreadyAnExpansion)
{
	if (table == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is nil",
				   @"self", NSStringFromClass([DVTMacroDefinitionTable class])];
	}
	if (![table isKindOfClass:[DVTMacroDefinitionTable class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"self", NSStringFromClass([DVTMacroDefinitionTable class]),
				   [table descriptionForAssertionMessage]];
	}
	DVTMacroDefinitionTableCheckMacroName(macroName);
	NSString *baseMacroName = macroName;
	DVTMacroDefinitionConditionSet *conditionSet = [DVTMacroDefinitionConditionSet conditionSetFromStringRepresentation:macroName getBaseMacroName:&baseMacroName error:NULL];
	id storedValue = value;
	if (value != nil && !valueIsAlreadyAnExpansion) {
		CFTypeID typeID = CFGetTypeID((__bridge CFTypeRef)value);
		if (typeID == CFStringGetTypeID()) {
			storedValue = DVTMacroExpressionByParsingStringAsList(value);
		} else if (typeID == CFArrayGetTypeID()) {
			storedValue = DVTMacroExpressionByParsingStringArrayAsList(value);
		}
	}
	[table setValue:storedValue forMacroName:baseMacroName conditionSet:conditionSet];
}

+ (id)newWithLabel:(id)label
{
	return ([[self alloc] initWithLabel:label]);
}

+ (id)empty
{
	static DVTMacroDefinitionTable *emptyTable = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		emptyTable = [[self alloc] initWithLabel:nil];
		[emptyTable makeImmutable];
	});
	return (emptyTable);
}

+ (id)macroNameRegistry
{
	return (nil);
}

- (id)initWithLabel:(id)label creationBacktrace:(id)backtrace
{
	(void)backtrace;
	self = [super init];
	if (self != nil) {
		_mapTable = [[DVTMacroValueAssignmentMapTable alloc] initWithCapacity:16];
		_label = [label copy];
		_creationBacktrace = nil;
		_cacheLock = [[NSLock alloc] init];
	}
	return (self);
}

- (id)init
{
	return ([self initWithLabel:nil]);
}

- (id)initWithLabel:(id)label
{
	return ([self initWithLabel:label creationBacktrace:nil]);
}

- (NSString *)label
{
	return (_label);
}

- (void)setLabel:(NSString *)label
{
	[self raiseImmutableAssertion];
	_label = [label copy];
}

- (_Bool)postsChangeNotifications
{
	return (_postsChangeNotifications);
}

- (void)setPostsChangeNotifications:(_Bool)postsChangeNotifications
{
	_postsChangeNotifications = postsChangeNotifications;
}

- (id)willSetValueBlock
{
	return (_willSetValueBlock);
}

- (void)setWillSetValueBlock:(id)block
{
	[self raiseImmutableAssertion];
	_willSetValueBlock = [block copy];
}

- (id)didSetValueBlock
{
	return (_didSetValueBlock);
}

- (void)setDidSetValueBlock:(id)block
{
	[self raiseImmutableAssertion];
	_didSetValueBlock = [block copy];
}

- (void)raiseImmutableAssertion
{
	if (_isImmutable) {
		DVTMacroDefinitionTableRaiseInternalAssertion(@"_isImmutable == __objc_no");
	}
}

- (void)discardCaches
{
	[_cacheLock lock];
	_cachedDictRep = nil;
	_cachedMacroNameSet = nil;
	_cachedHash = 0;
	[_cacheLock unlock];
}

- (NSUInteger)hash
{
	[_cacheLock lock];
	NSUInteger cachedHash = (NSUInteger)_cachedHash;
	if (cachedHash == 0) {
		__block unsigned long long accumulator = [_mapTable numberOfDefinitions];
		[_mapTable enumerateKeysAndValuesWithOrder:DVTMapTableEnumerationOrderUnsorted usingBlock:^(NSString *macroName, DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop) {
			(void)stop;
			unsigned long long macroNameHash = [macroName hash];
			unsigned long long valueHash = [value hash];
			unsigned long long conditionSetHash = (conditionSet != nil) ? [conditionSet hash] : 0;
			unsigned long long combinedHash = macroNameHash ^ valueHash ^ conditionSetHash;
			if (combinedHash == 0) {
				combinedHash = 1;
			}
			accumulator ^= combinedHash;
		}];
		_cachedHash = (accumulator <= 1) ? 1 : accumulator;
		cachedHash = (NSUInteger)_cachedHash;
	}
	[_cacheLock unlock];
	return (cachedHash);
}

- (BOOL)isEqual:(id)other
{
	if (other == self) {
		return (YES);
	}
	if (other == nil) {
		return (NO);
	}
	if (![other isKindOfClass:[DVTMacroDefinitionTable class]]) {
		return (NO);
	}
	DVTMacroDefinitionTable *otherTable = other;
	if (_mapTable == otherTable->_mapTable) {
		return (YES);
	}
	if ([self numberOfMacros] != [otherTable numberOfMacros]) {
		return (NO);
	}
	if ([self numberOfDefinitions] != [otherTable numberOfDefinitions]) {
		return (NO);
	}
	__block BOOL result = YES;
	[_mapTable enumerateKeysWithOrder:DVTMapTableEnumerationOrderSorted usingBlock:^(NSString *macroName, BOOL *stop) {
		if (![_mapTable compareValuesForKey:macroName otherTable:otherTable->_mapTable]) {
			*stop = YES;
			result = NO;
		}
	}];
	return (result);
}

- (unsigned long long)count
{
	return ([self numberOfMacros]);
}

- (unsigned long long)numberOfMacros
{
	return ([_mapTable numberOfMacroNames]);
}

- (unsigned long long)numberOfDefinitions
{
	return ([_mapTable numberOfDefinitions]);
}

- (void)setValue:(id)value forMacroName:(id)macroName conditionSet:(id)conditionSet
{
	[self raiseImmutableAssertion];
	DVTMacroDefinitionTableCheckMacroName(macroName);
	DVTMacroDefinitionTableCheckConditionSet(conditionSet);
	id currentValue = [_mapTable valueForKey:macroName conditionSet:conditionSet];
	BOOL isUnchanged = (currentValue == value);
	if (!isUnchanged && value != nil && currentValue != nil) {
		isUnchanged = [currentValue isEqual:value];
	}
	if (isUnchanged) {
		return;
	}
	if (_willSetValueBlock != nil) {
		void (^willSetValue)(id, id, id) = (__bridge void (^)(id, id, id))(__bridge void *)_willSetValueBlock;
		willSetValue(macroName, conditionSet, value);
	}
	[_mapTable setValue:value forKey:macroName conditionSet:conditionSet];
	[self discardCaches];
	if (_didSetValueBlock != nil) {
		void (^didSetValue)(id, id, id) = (__bridge void (^)(id, id, id))(__bridge void *)_didSetValueBlock;
		didSetValue(macroName, conditionSet, value);
	}
	if (_postsChangeNotifications) {
		NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
		[userInfo setObject:macroName forKey:@"macroName"];
		if (value != nil) {
			[userInfo setObject:value forKey:@"value"];
		}
		[self dvt_broadcast:DVTMacroDefinitionTableValueDidChangeBroadcast userInfo:userInfo];
	}
}

- (id)valueForMacroName:(id)macroName conditionSet:(id)conditionSet
{
	DVTMacroDefinitionTableCheckMacroName(macroName);
	DVTMacroDefinitionTableCheckConditionSet(conditionSet);
	return ([_mapTable valueForKey:macroName conditionSet:conditionSet]);
}

- (void)_setLiteralValue:(id)value forMacroName:(id)macroName conditionSet:(id)conditionSet wantsCheckForDVTMacroExpansionConformance:(_Bool)conformance
{
	if (value == nil) {
		[self setValue:nil forMacroName:macroName conditionSet:conditionSet];
		return;
	}
	if (conformance && [value conformsToProtocol:@protocol(DVTMacroExpansion)]) {
		[self setValue:value forMacroName:macroName conditionSet:conditionSet];
		return;
	}
	CFTypeID typeID = CFGetTypeID((__bridge CFTypeRef)value);
	if (typeID == CFStringGetTypeID()) {
		[self setValue:DVTMacroDefinitionTableLiteralValueForString(value) forMacroName:macroName conditionSet:conditionSet];
		return;
	}
	if (typeID == CFArrayGetTypeID()) {
		[self setValue:DVTMacroDefinitionTableLiteralValueForArray(value) forMacroName:macroName conditionSet:conditionSet];
		return;
	}
	[NSException raise:NSInvalidArgumentException
		    format:@"value must be nil, string or array, but is %@", [value descriptionForAssertionMessage]];
}

- (void)setStringValue:(id)value forMacroName:(id)macroName conditionSet:(id)conditionSet
{
	[self _setLiteralValue:value forMacroName:macroName conditionSet:conditionSet wantsCheckForDVTMacroExpansionConformance:NO];
}

- (void)setLiteralValue:(id)value forMacroName:(id)macroName conditionSet:(id)conditionSet
{
	[self _setLiteralValue:value forMacroName:macroName conditionSet:conditionSet wantsCheckForDVTMacroExpansionConformance:YES];
}

- (void)parseAndSetValue:(id)value forMacroName:(id)macroName conditionSet:(id)conditionSet
{
	if (value == nil) {
		[self setValue:nil forMacroName:macroName conditionSet:conditionSet];
		return;
	}
	if ([value conformsToProtocol:@protocol(DVTMacroExpansion)]) {
		[self setValue:value forMacroName:macroName conditionSet:conditionSet];
		return;
	}
	CFTypeID typeID = CFGetTypeID((__bridge CFTypeRef)value);
	if (typeID == CFStringGetTypeID()) {
		[self setValue:DVTMacroExpressionByParsingStringAsList(value) forMacroName:macroName conditionSet:conditionSet];
		return;
	}
	if (typeID == CFArrayGetTypeID()) {
		id registry = [[self class] macroNameRegistry];
		if (registry != nil && ![registry macroIsListType:macroName]) {
			DVTMacroDefinitionTableRaiseInternalAssertion(@"[macroNameRegistry macroIsListType:macroName]");
			return;
		}
		[self setValue:DVTMacroExpressionByParsingStringArrayAsList(value) forMacroName:macroName conditionSet:conditionSet];
		return;
	}
	[NSException raise:NSInvalidArgumentException
		    format:@"value must be nil, string or array, but is %@", [value descriptionForAssertionMessage]];
}

- (void)enumerateValuesForMacroName:(id)macroName usingBlock:(id)block
{
	DVTMacroDefinitionTableCheckMacroName(macroName);
	[_mapTable enumerateValuesForKey:macroName usingBlock:^(DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop) {
		void (^valuesBlock)(id, id, id, BOOL *) = (__bridge void (^)(id, id, id, BOOL *))(__bridge void *)block;
		valuesBlock(macroName, conditionSet, value, stop);
	}];
}

- (void)enumerateMacroNamesAndValuesUsingBlock:(id)block
{
	[_mapTable enumerateKeysAndValuesWithOrder:DVTMapTableEnumerationOrderUnsorted usingBlock:(void (^)(NSString *, DVTMacroDefinitionConditionSet *, id, BOOL *))block];
}

- (void)removeAllConditionSetsForMacroName:(id)macroName
{
	DVTMacroDefinitionTableCheckMacroName(macroName);
	NSMutableArray *conditionSets = [[NSMutableArray alloc] init];
	[_mapTable enumerateValuesForKey:macroName usingBlock:^(DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop) {
		(void)value;
		(void)stop;
		if (conditionSet != nil) {
			[conditionSets addObject:conditionSet];
		}
	}];
	for (DVTMacroDefinitionConditionSet *conditionSet in conditionSets) {
		[self setLiteralValue:nil forMacroName:macroName conditionSet:conditionSet];
	}
}

- (void)removeMacroName:(id)macroName
{
	DVTSetMacroNameAndValue(self, macroName, nil, YES);
}

- (void)removeMacroNames:(id)macroNames arguments:(char *)arguments
{
	/* The public header types the va_list as a char pointer (which is what
	 * va_list is on both supported architectures' calling convention). */
	va_list argumentsList;
	va_copy(argumentsList, *(va_list *)&arguments);
	id macroName = macroNames;
	while (macroName != nil) {
		DVTSetMacroNameAndValue(self, macroName, nil, YES);
		macroName = va_arg(argumentsList, id);
	}
	va_end(argumentsList);
}

- (void)removeMacroNames:(id)macroNames
{
	/* The public header does not declare this method variadic, so only the
	 * single name it is given is removed.  Multi-name callers use
	 * -removeMacroNames:arguments:. */
	DVTSetMacroNameAndValue(self, macroNames, nil, YES);
}

- (void)removeAllMacros
{
	if (_willSetValueBlock != nil) {
		[self enumerateMacroNamesAndValuesUsingBlock:^(id macroName, id conditionSet, id value, BOOL *stop) {
			(void)stop;
			void (^willSetValue)(id, id, id) = (__bridge void (^)(id, id, id))(__bridge void *)self->_willSetValueBlock;
			willSetValue(macroName, conditionSet, value);
		}];
	}
	[_mapTable removeAllValues];
	/* Apple enumerates the (already emptied) table a second time here, so the
	 * didSet block can never be invoked from -removeAllMacros.  Reproduced. */
	if (_didSetValueBlock != nil) {
		[self enumerateMacroNamesAndValuesUsingBlock:^(id macroName, id conditionSet, id value, BOOL *stop) {
			(void)stop;
			void (^didSetValue)(id, id, id) = (__bridge void (^)(id, id, id))(__bridge void *)self->_didSetValueBlock;
			didSetValue(macroName, conditionSet, value);
		}];
	}
	[self discardCaches];
}

- (id)dictionaryRepresentation
{
	[_cacheLock lock];
	if (_cachedDictRep == nil) {
		NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithCapacity:(NSUInteger)[_mapTable numberOfDefinitions]];
		[_mapTable enumerateKeysAndValuesWithOrder:DVTMapTableEnumerationOrderUnsorted usingBlock:^(NSString *macroName, DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop) {
			(void)stop;
			NSString *key = macroName;
			if (conditionSet != nil) {
				key = [macroName stringByAppendingString:[conditionSet subscriptRepresentation]];
			}
			[dictionary setObject:value forKey:key];
		}];
		_cachedDictRep = [dictionary copy];
	}
	id dictionary = _cachedDictRep;
	[_cacheLock unlock];
	return (dictionary);
}

- (id)allMacroNames
{
	[_cacheLock lock];
	if (_cachedMacroNameSet == nil) {
		NSMutableSet *macroNames = [[NSMutableSet alloc] initWithCapacity:(NSUInteger)[_mapTable numberOfMacroNames]];
		[_mapTable enumerateKeysWithOrder:DVTMapTableEnumerationOrderUnsorted usingBlock:^(NSString *macroName, BOOL *stop) {
			(void)stop;
			[macroNames addObject:macroName];
		}];
		_cachedMacroNameSet = [macroNames copy];
	}
	id macroNames = _cachedMacroNameSet;
	[_cacheLock unlock];
	return (macroNames);
}

- (void)setMacroNamesAndValuesFromDictionary:(id)dictionary
{
	if (dictionary != nil && CFGetTypeID((__bridge CFTypeRef)dictionary) != CFDictionaryGetTypeID()) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a dictionary, but it is %@",
				   @"dict", [dictionary descriptionForAssertionMessage]];
	}
	[dictionary enumerateKeysAndObjectsUsingBlock:^(id macroName, id value, BOOL *stop) {
		(void)stop;
		DVTSetMacroNameAndValue(self, macroName, value, NO);
	}];
}

- (void)setMacroNamesAndValuesFromMacroDefinitionTable:(id)table
{
	if (table != nil && ![table isKindOfClass:[DVTMacroDefinitionTable class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an instance inheriting from %@, but it is %@",
				   @"table", NSStringFromClass([DVTMacroDefinitionTable class]),
				   [table descriptionForAssertionMessage]];
	}
	[table enumerateMacroNamesAndValuesUsingBlock:^(id macroName, id conditionSet, id value, BOOL *stop) {
		(void)stop;
		[self setValue:value forMacroName:macroName conditionSet:conditionSet];
	}];
}

- (id)copyWithZone:(struct _NSZone *)zone
{
	if (_isImmutable) {
		return (self);
	}
	DVTMacroDefinitionTable *copy = [self mutableCopyWithZone:zone];
	[copy makeImmutable];
	return (copy);
}

- (id)copyWithLabel:(id)label
{
	DVTMacroDefinitionTable *copy;
	if (_isImmutable) {
		copy = [[[self class] alloc] initWithLabel:label creationBacktrace:_creationBacktrace];
		copy->_mapTable = _mapTable;
		copy->_originalTable = self;
	} else {
		copy = [self mutableCopyWithZone:NULL];
		/* Apple copies its own label here and ignores the argument, which is
		 * almost certainly a bug.  Reproduced. */
		copy->_label = [_label copy];
	}
	[copy makeImmutable];
	return (copy);
}

- (id)mutableCopyWithZone:(struct _NSZone *)zone
{
	DVTMacroDefinitionTable *copy = [[[self class] allocWithZone:zone] initWithLabel:_label creationBacktrace:_creationBacktrace];
	copy->_mapTable = [_mapTable copy];
	copy->_declaredMutable = _declaredMutable;
	return (copy);
}

- (_Bool)isImmutable
{
	return (_isImmutable);
}

- (void)makeImmutable
{
	if (_isImmutable) {
		return;
	}
	_isImmutable = YES;
	_declaredMutable = NO;
	_willSetValueBlock = nil;
	_didSetValueBlock = nil;
	_postsChangeNotifications = NO;
}

- (void)declareMutable
{
	_declaredMutable = YES;
}

- (id)valueForKey:(id)key
{
	return ([self valueForMacroName:key conditionSet:nil]);
}

- (id)objectForKeyedSubscript:(id)subscript
{
	DVTMacroDefinitionTableCheckMacroName(subscript);
	NSString *baseMacroName = subscript;
	DVTMacroDefinitionConditionSet *conditionSet = [DVTMacroDefinitionConditionSet conditionSetFromStringRepresentation:subscript getBaseMacroName:&baseMacroName error:NULL];
	return ([self valueForMacroName:baseMacroName conditionSet:conditionSet]);
}

- (void)setObject:(id)object forKeyedSubscript:(id)subscript
{
	DVTMacroDefinitionTableCheckMacroName(subscript);
	NSString *baseMacroName = subscript;
	DVTMacroDefinitionConditionSet *conditionSet = [DVTMacroDefinitionConditionSet conditionSetFromStringRepresentation:subscript getBaseMacroName:&baseMacroName error:NULL];
	[self setLiteralValue:object forMacroName:baseMacroName conditionSet:conditionSet];
}

- (void)assertInternalConsistency
{
	__block unsigned long long macroCount = 0;
	__block unsigned long long definitionCount = 0;
	[_mapTable enumerateKeysWithOrder:DVTMapTableEnumerationOrderUnsorted usingBlock:^(NSString *macroName, BOOL *stop) {
		(void)stop;
		macroCount++;
		[_mapTable enumerateValuesForKey:macroName usingBlock:^(DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop) {
			(void)conditionSet;
			(void)value;
			(void)stop;
			definitionCount++;
		}];
	}];
	if (macroCount != [_mapTable numberOfMacroNames]) {
		DVTMacroDefinitionTableRaiseInternalAssertion(@"");
	}
	if (definitionCount != [_mapTable numberOfDefinitions]) {
		DVTMacroDefinitionTableRaiseInternalAssertion(@"");
	}
}

- (id)descriptionWithLocale:(id)locale indent:(unsigned long long)indent
{
	NSMutableString *description = [[NSMutableString alloc] init];
	for (unsigned long long index = 0; index < indent; index++) {
		[description appendString:@"   "];
	}
	[description appendString:@"{"];
	if (_label != nil) {
		[description appendString:@" // "];
		[description appendString:_label];
	}
	[description appendString:@" ("];
	[description appendString:(_isImmutable ? @"immutable" : @"mutable")];
	[description appendString:@")\n"];
	[_mapTable enumerateKeysWithOrder:DVTMapTableEnumerationOrderSorted usingBlock:^(NSString *macroName, BOOL *stop) {
		(void)stop;
		for (unsigned long long index = 0; index <= indent; index++) {
			[description appendString:@"   "];
		}
		[description appendString:macroName];
		[description appendString:@" = "];
		__block BOOL isFirstValue = YES;
		[_mapTable enumerateValuesForKey:macroName usingBlock:^(DVTMacroDefinitionConditionSet *conditionSet, id value, BOOL *stop) {
			(void)stop;
			if (!isFirstValue) {
				[description appendString:@" \u2794 "];
			}
			isFirstValue = NO;
			if (conditionSet != nil) {
				[description appendString:[conditionSet subscriptRepresentation]];
			}
			[description appendString:[value dvt_debugDescription]];
		}];
		[description appendString:@"\n"];
	}];
	for (unsigned long long index = 0; index < indent; index++) {
		[description appendString:@"   "];
	}
	[description appendString:@"}"];
	return (description);
}

- (id)description
{
	return ([self descriptionWithLocale:nil indent:0]);
}

@end
