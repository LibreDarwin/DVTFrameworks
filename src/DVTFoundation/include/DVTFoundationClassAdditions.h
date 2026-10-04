//
//  DVTFoundationClassAdditions.h
//  DVTFoundation
//
//  Copyright (C) 2026, LibreDarwin
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its
//     contributors may be used to endorse or promote products derived from
//     this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED.
//

#import <Foundation/Foundation.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSOrderedSet.h>
#import <Foundation/NSIndexSet.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSArray (DVTFoundationClassAdditions)

/** `YES` when the receiver has at least one element. */
@property (nonatomic, readonly) BOOL dvt_hasContent;
/** `YES` when the receiver has at least one element. Alias of `dvt_hasContent`. */
@property (nonatomic, readonly) BOOL dvt_isNonEmpty;
/** The receiver's index set, ordered ascending. Empty array yields an empty set. */
@property (nonatomic, readonly) NSIndexSet *dvt_allIndexes;
/** The full range of the receiver, i.e. `{0, count}`. */
@property (nonatomic, readonly) NSRange dvt_fullRange;
/** The highest valid index, or `NSNotFound` when empty. */
@property (nonatomic, readonly) NSUInteger dvt_lastIndex;
/** The last element, or `nil` when empty. */
@property (nonatomic, readonly) id _Nullable dvt_secondToLastObject;

/** The single element, or `nil` when the receiver is not exactly one element. */
@property (nonatomic, readonly) id _Nullable dvt_onlyObject;

/** The object at `index`, or `nil` when out of bounds. */
- (id _Nullable)dvt_objectAtIndexIfInBounds:(NSInteger)index;
/** `index` wrapped into `0..count-1`, or `nil` when the receiver is empty. */
- (id _Nullable)dvt_objectAtWrappedIndex:(NSInteger)index;

- (BOOL)dvt_isIndexInBounds:(NSInteger)index;

/** `YES` when any element is identical (`==`) to `object`. */
- (BOOL)dvt_containsObjectIdenticalTo:(id)object;

/** Elements of `klass`, in order. */
- (NSArray *)dvt_objectsOfClass:(Class)klass;

/** Elements satisfying `test`, evaluated in order and synchronously. */
- (NSArray *)dvt_objectsPassingTest:(BOOL (^)(id object))test;

/** The first element satisfying `test`, or `nil`. */
- (id _Nullable)dvt_firstObjectPassingTest:(BOOL (^)(id object))test;
/** The only element satisfying `test`, or `nil` when there is not exactly one. */
- (id _Nullable)dvt_onlyObjectPassingTest:(BOOL (^)(id object))test;

/** `YES` when any element satisfies `test`. */
- (BOOL)dvt_anyObjectsPassTest:(BOOL (^)(id object))test;
/**
 `YES` when every element satisfies `test`, stopping at the first that does not.

 An empty receiver is `YES` without ever calling `test`, so this is a vacuous
 truth rather than a failure to find a witness. A `nil` `test` is treated the
 same way, which deviates from Apple: it dereferences the block unchecked and
 faults on a non-empty array.
 */
- (BOOL)dvt_allObjectsPassTest:(BOOL (^)(id object))test;
/** How many elements satisfy `test`. */
- (NSUInteger)dvt_numberOfObjectsPassingTest:(BOOL (^)(id object))test;

/** Maps each element through `block`, dropping `nil` results. */
- (NSArray *)dvt_compactMap:(id _Nullable (^)(id object))block;
/** Maps each element through `block` and flattens one level. */
- (NSArray *)dvt_flatMap:(id _Nullable (^)(id object))block;

/** A copy with `object` appended when it is non-`nil`. */
- (NSArray *)dvt_arrayByAddingObjectIfNonNil:(id _Nullable)object;
/** A copy with every non-`nil` element of `objects` appended. */
- (NSArray *)dvt_arrayByAddingObjects:(NSArray *)objects;

/** A copy with every `NSNull` removed. */
- (NSArray *)dvt_arrayByRemovingNSNulls;
/** A copy with the first `object` removed, using `isEqual:`. */
/** A copy with every element that is identical to, or `isEqual:` to, `object`
 removed. Despite the singular argument this removes all matches, not just the
 first, which is what sets it apart from
 `dvt_arrayByMovingFirstOccurrenceOfObjectToFrontIfPresent:`. */
- (NSArray *)dvt_arrayByRemovingObject:(id)object;
/** A copy with every element of `objects` removed, using `isEqual:`. */
- (NSArray *)dvt_arrayByRemovingObjectsInArray:(NSArray *)objects;
/** A copy with the first occurrence of `object` moved to the front, if present. */
- (NSArray *)dvt_arrayByMovingFirstOccurrenceOfObjectToFrontIfPresent:(id)object;
/** A reversed copy. */
- (NSArray *)dvt_arrayByReversingObjects;

/** A copy keeping the first occurrence of each element; later `isEqual:`
 matches are dropped and the original order is preserved. */
- (NSArray *)dvt_arrayByRemovingDuplicatesFromBack;
/** A copy keeping the first occurrence of each element. Behaviourally
 identical to `dvt_arrayByRemovingDuplicatesFromBack`, which Apple implements
 this selector as a tail-call to. */
- (NSArray *)dvt_arrayByRemovingDuplicates;

/** The distinct elements. Note the return type: the name reads like an array,
 but this yields a set. */
- (NSSet *)dvt_uniqueObjects;

/** The elements from `index` onward. Unchecked, so an `index` past the end
 raises `NSRangeException`; `index == count` is in bounds and yields an empty
 array. */
- (NSArray *)dvt_subarrayFromIndex:(NSUInteger)index;
/** The elements after `index`. Unchecked, so any `index >= count` raises
 `NSRangeException`. */
- (NSArray *)dvt_subarrayAfterIndex:(NSUInteger)index;

/** Elements at `indexes`, silently skipping indexes outside the receiver's
 range rather than raising. */
- (NSArray *)dvt_objectsAtIndexesWithinBounds:(NSIndexSet *)indexes;

/** `YES` when `prefix` matches the receiver's leading elements, compared with
 `isEqual:`. An empty prefix always matches. */
- (BOOL)dvt_hasPrefix:(NSArray *)prefix;

/** Elements mapped through `block`; `nil` results are dropped. */
- (NSArray *)dvt_arrayByApplyingBlock:(id _Nullable (^)(id object))block;
/**
 Like `dvt_arrayByApplyingBlock:`, but a `nil` result becomes `NSNull` so every
 input still occupies a slot and the result keeps the receiver's length.
 */
- (NSArray *)dvt_arrayByApplyingBlockStrictly:(id _Nullable (^)(id object))block;
/** Like `dvt_arrayByApplyingBlock:`, with the element index as a second argument. */
- (NSArray *)dvt_arrayByApplyingBlockWithIndex:(id _Nullable (^)(id object, NSUInteger index))block;
/** Elements satisfying `block`, re-wrapped into an array. */
- (NSArray *)dvt_arrayByFilteringUsingBlock:(BOOL (^)(id object))block;
/** Like `dvt_arrayByApplyingBlock:`, returning a set. */
- (NSSet *)dvt_setByApplyingBlock:(id _Nullable (^)(id object))block;
/** Like `dvt_arrayByApplyingBlockStrictly:`, returning a set. */
- (NSSet *)dvt_setByApplyingBlockStrictly:(id _Nullable (^)(id object))block;
/** Elements satisfying `block`, re-wrapped into a set. */
- (NSSet *)dvt_setByFilteringUsingBlock:(BOOL (^)(id object))block;

/** The object with the highest `compare:` result, or `nil` when empty. */
- (id _Nullable)dvt_maximumObject;
/** The object with the lowest `compare:` result, or `nil` when empty. */
- (id _Nullable)dvt_minimumObject;

/**
  A shuffled copy of the receiver, leaving the receiver in its original order.

  Only a receiver with more than one element is actually shuffled. At one element
  or below the receiver is merely copied, which means an immutable receiver is
  returned as the very same object while a mutable one is returned as an
  immutable array; above one element the result is always a mutable array.
 */
- (id)dvt_shuffledArray;

/**
 Renders the receiver the way a command line would accept it: elements are
 separated by a single space, non-`NSString` elements are described, the empty
 string is emitted as `""`, and an empty receiver yields the empty string.

 Escaping is narrower than the name suggests. Only the four characters in
 `'`, space, `"`, and tab are backslash-escaped, matching the literal Apple
 passes to `+[NSCharacterSet characterSetWithCharactersInString:]`. A backslash
 is therefore already literal and is *not* doubled, and the rest of the shell
 metacharacters (`$`, `*`, `;`, `|`, `&`, `>`, `<`, `~`, `#`, `!`, newline) pass
 through untouched, so the result is not safe to hand to a shell unquoted.
 */
- (NSString *)dvt_stringByConcatenatingAsCommandLineArguments;

/**
 The index at which `object` belongs in the receiver under `comparator`.

 Apple answers `0` for an empty receiver without consulting `comparator`, and
 otherwise binary-searches the whole array with
 `NSBinarySearchingInsertionIndex`. Note what that option reports: the index of
 an equal element when the receiver already holds one, and the insertion point
 only when it does not. The receiver is assumed to be sorted under `comparator`.
 */
- (NSInteger)dvt_sortedInsertionIndexForObject:(id)object
                                 withComparator:(NSComparisonResult (^)(id first, id second))comparator;

/**
 The index at which `object` belongs under `selector`, used as the two-argument
 comparison selector, i.e. the receiver of `selector` is the left element.
 */
- (NSInteger)dvt_sortedInsertionIndexForObject:(id)object withComparisonSelector:(SEL)selector;

@end

@interface NSMutableArray (DVTFoundationClassAdditions)

/** Appends `object` only when it is non-`nil`. */
- (void)dvt_addObjectIfNonNil:(id _Nullable)object;

/** Appends every element of `objects` that is not already present. */
- (void)dvt_addObjectsFromArrayIfAbsent:(NSArray *)objects;

/** Reverses the receiver in place with `exchangeObjectAtIndex:` pairs. */
- (void)dvt_reverseObjects;

/**
 Removes and returns the first element, or returns `nil` and changes nothing
 when the receiver is empty.
 */
- (id _Nullable)dvt_popFirstObject;

/**
 Removes and returns the last element, or returns `nil` and changes nothing when
 the receiver is empty.
 */
- (id _Nullable)dvt_popLastObject;

/**
 Drops everything past `maxCount`. A `maxCount` at or above the current count
 leaves the receiver alone.
 */
- (void)dvt_truncateToMaxCount:(NSUInteger)maxCount;

/**
 Removes elements by *pointer identity* against `objects`, not by equality, and
 removes only the first match for each entry of `objects`.

 So `[p p z]` minus `@[p]` leaves `[p z]`, where `-removeObjectIdenticalTo:`
 would leave `[z]`. `nil` removes nothing.
 */
- (void)dvt_removeObjectsIdenticalToObjectsInArray:(NSArray *_Nullable)objects;

/**
 Removes every element for which `test` returns `NO`, evaluating it once per
 element.

 This deviates from Apple, which faults on a non-empty receiver with a `nil`
 block; the guard is kept deliberately.
 */
- (void)dvt_keepObjectsPassingTest:(BOOL (^_Nullable)(id object))test;

/**
 Removes elements that `set` contains by equality, so this differs from
 `dvt_removeObjectsIdenticalToObjectsInArray:`. An empty or `nil` set removes
 nothing.
 */
- (void)dvt_removeObjectsInSet:(NSSet *_Nullable)set;

/**
 Appends `object` only when the receiver does not already contain it by
 equality. A `nil` argument raises `NSInvalidArgumentException`.
 */
- (void)dvt_addObjectIfAbsent:(id _Nullable)object;

/** Appends each element of `set` in enumeration order. A `nil` set appends nothing. */
- (void)dvt_addObjectsFromSet:(NSSet *_Nullable)set;

/**
 Inserts `object` at `index`, doing nothing when `object` is `nil`.

 The `nil` test runs first, so a `nil` object with an out-of-range `index` is
 still a no-op; a real object past the end raises `NSRangeException`.
 */
- (void)dvt_insertObjectIfNonNil:(id _Nullable)object atIndex:(NSUInteger)index;

/** Inserts every element of `objects` at `index`, in order. */
- (void)dvt_insertObjects:(NSArray *_Nullable)objects atIndex:(NSUInteger)index;

/**
 Moves the element at `fromIndex` to `toIndex`.

 Equal indices are a no-op and never raise, even when both are out of range.
 */
- (void)dvt_moveObjectAtIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;

/**
 Inserts `object` at its sorted position and returns the index used.

 Ordering is by `compare:`, and the receiver is assumed to be sorted already.
 */
- (NSInteger)dvt_sortedInsert:(id)object;

/**
 Inserts `object` at its position under `comparator` and returns the index used.

 The insertion index comes from `dvt_sortedInsertionIndexForObject:withComparator:`,
 so `comparator` is invoked with the receiver's existing elements as its left
 argument.
 */
- (NSInteger)dvt_sortedInsert:(id)object
                withComparator:(NSComparisonResult (^)(id first, id second))comparator;

/** As `dvt_sortedInsert:withComparator:`, ordered by the two-argument `selector`. */
- (NSInteger)dvt_sortedInsert:(id)object withComparisonSelector:(SEL)selector;

/**
 Inserts every element of `objects` at once, each at its own sorted position.

 The argument is sorted with `sortedArrayUsingComparator:` first, so the result
 is a stable merge rather than a series of independent insertions, and the
 receiver is not modified until the whole set is ready.
 */
- (void)dvt_sortedInsertOfObjects:(NSArray *)objects
                   withComparator:(NSComparisonResult (^)(id first, id second))comparator;

/**
 Inserts `object` unless `compare:` reports it as equal to an element already
 present, and returns whether it was inserted.

 Note that "already present" means the comparator returns `NSOrderedSame`, not
 `isEqual:`: two objects can compare equal yet compare differently under
 `isEqual:`, and only the former counts as a duplicate here.
 */
- (BOOL)dvt_uniqueSortedInsert:(id)object;

/** As `dvt_uniqueSortedInsert:`, with the duplicate test done by `comparator`. */
- (BOOL)dvt_uniqueSortedInsert:(id)object
                 withComparator:(NSComparisonResult (^)(id first, id second))comparator;

/**
  Empties the receiver and every mutable collection reachable from it.

  Only `NSMutableArray`, `NSMutableDictionary` and `NSMutableSet` are both
  descended into and emptied. Dictionaries are followed through their values, so
  their keys are left alone, and anything else is stepped over rather than
  traversed: an immutable collection reachable from the receiver keeps its
  contents, including any mutable collections they hold.

  A set of visited collections makes the traversal terminate on cycles, including
  cycles back to the receiver itself.
 */
- (void)dvt_recursivelyRemoveAllObjects;

/**
  Shuffles the receiver in place, leaving the same members in a random order.

  A receiver with fewer than two elements is left alone rather than shuffled. The
  walk picks a partner for each position in turn from the part of the receiver
  that is still unordered, so every permutation is equally likely and the last
  member is settled by elimination rather than by a draw of its own.
 */
- (void)dvt_shuffle;

/**
  Sorts the receiver in place by a value derived from each element.

  `valueBlock` is applied to each element and the resulting values are compared
  with `compare:`, so the ordering follows the block's output rather than the
  elements themselves. A derived value of `nil` trips an assertion rather than
  being compared, as it does in Apple; the assertion names the element whose
  value came back empty.

  Elements whose derived values come out equal are reported as equal, leaving
  their relative order to the sort.
 */
- (void)dvt_sortByValueBlock:(id (^)(id object))valueBlock;

/**
  As `dvt_sortByValueBlock:`, with `duplicateHandler` breaking ties.

  The handler runs only for elements whose derived values have already compared
  equal, and it receives the two elements rather than the two derived values, so
  it can order a tie by whatever `valueBlock` discarded. Its result becomes the
  comparison result. A `nil` handler behaves exactly as in
  `dvt_sortByValueBlock:`.
 */
- (void)dvt_sortByValueBlock:(id (^)(id object))valueBlock
           duplicateHandler:(NSComparisonResult (^ _Nullable)(id first, id second))duplicateHandler;

@end

@interface NSSet (DVTNSSetAdditions)

/**
 `YES` when every member satisfies `test`, stopping at the first that does not.

 An empty set is `YES` without ever calling `test`, and a `nil` `test` is
 treated the same way.

 This deviates from Apple, which dereferences `test` without checking it and so
 faults on a non-empty set with a `nil` block. The guard is kept deliberately.
 */
- (BOOL)dvt_allObjectsPassTest:(BOOL (^)(id object))test;

/** `YES` when the receiver has at least one member. Alias of `dvt_hasContent`. */
@property (nonatomic, readonly) BOOL dvt_hasContent;
@property (nonatomic, readonly) BOOL dvt_isNonEmpty;

@end

@interface NSMutableSet (DVTFoundationClassAdditions)

/** Adds `object` only when it is non-`nil`. */
- (void)dvt_addObjectIfNonNil:(id _Nullable)object;

@end

@interface NSHashTable (DVTNSHashTableAdditions)

/**
 `YES` when every object satisfies `test`, stopping at the first that does not.

 An empty table is `YES` without ever calling `test`, and a `nil` `test` is
 treated the same way, which deviates from Apple as noted on `NSSet`.
 */
- (BOOL)dvt_allObjectsPassTest:(BOOL (^)(id object))test;

/** Adds `object` only when it is non-`nil`. */
- (void)dvt_addObjectIfNonNil:(id _Nullable)object;

@end

/* The emptiness pair below is declared by Apple on six classes -- array,
   dictionary, map table, ordered set, set and string -- but under three
   different category names, so the names here follow the binary rather than the
   file: the two Foundation-collection and string cases live in
   DVTFoundationClassAdditions, and each set-like class gets its own. The names
   are visible in the category metadata, so matching them keeps a class dump of
   either binary readable side by side.

   On all six the two selectors answer the same question and always agree; only
   NSString reaches it a different way, noted on its implementation. */

/** `YES` when the receiver has at least one element. Alias of `dvt_hasContent`. */
@interface NSDictionary (DVTFoundationClassAdditions)

@property (nonatomic, readonly) BOOL dvt_hasContent;
@property (nonatomic, readonly) BOOL dvt_isNonEmpty;

@end

/** `YES` when the receiver is longer than zero characters. */
@interface NSString (DVTFoundationClassAdditions)

@property (nonatomic, readonly) BOOL dvt_hasContent;
@property (nonatomic, readonly) BOOL dvt_isNonEmpty;

/**
 Lowercased, uppercased, or capitalized according to `letterCasing`.

 @param letterCasing `0` for lowercase, `1` for uppercase, `2` for capitalized.
 */
- (NSString *)dvt_stringWithLetterCasing:(NSUInteger)letterCasing;

/**
 Splits the receiver into words, casing each one like `dvt_stringWithLetterCasing:`.

 A word ends at an ASCII uppercase letter, at a run of digits, and at every character that is
 neither a digit, an uppercase letter, nor a lowercase letter; those separators are dropped. So
 `camelCase` yields `camel` and `case`, and `a1b2` yields `a`, `1`, and `b`.

 @param letterCasing `0` for lowercase, `1` for uppercase, `2` for capitalized.
 */
- (NSArray<NSString *> *)dvt_wordsFromStringWithLetterCasing:(NSUInteger)letterCasing;

/** The lowercased words of the receiver. */
- (NSArray<NSString *> *)dvt_wordsFromString;

/** The capitalized words of the receiver. */
- (NSArray<NSString *> *)dvt_capitalizedWordsFromString;

/** The receiver with its first character uppercased, or the receiver when it is not a lowercase letter. */
- (NSString *)dvt_stringByCapitalizingFirstCharacter;

/** The receiver with its first character lowercased, or the receiver when it is not an uppercase letter. */
- (NSString *)dvt_stringByLowercasingFirstCharacter;

/** The characters in `fromIndex ..< toIndex`, asserting that the range lies inside the receiver. */
- (NSString *)dvt_substringFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;

/** `YES` when the receiver is a legal C identifier: ASCII letters and underscores, with digits allowed after the first character. */
- (BOOL)dvt_isLegalCIdentifier;

/**
 Returns the receiver with every character a C identifier cannot use replaced by `_`.

 The receiver is canonical-decomposed first, so a composed `é` turns into the legal `e` followed by
 the rejected combining accent. Anything outside ASCII is rejected one UTF-16 unit at a time, so an
 astral character such as an emoji becomes two underscores.
 */
- (NSString *)dvt_stringByManglingToLegalCIdentifier;

/**
 Returns the receiver with every character C99 does not allow in an extended identifier replaced by `_`.

 Unlike `dvt_stringByManglingToLegalCIdentifier` the receiver is left composed, and C99 Annex D's
 universal character names survive, so `é` is kept. Iteration is per Unicode scalar, which collapses an
 astral character into a single underscore. The Annex D characters that may not open an identifier --
 ASCII digits, and the digit runs of several other scripts -- are still replaced at index 0.
 */
- (NSString *)dvt_stringByManglingToLegalC99ExtendedIdentifier;

/**
 Returns the receiver with every character a bundle identifier cannot use replaced by `-`.

 The receiver is canonical-decomposed first. ASCII letters, digits, `.`, and `-` are kept, and `.` and
 `-` may open the identifier too; everything else, non-ASCII included, becomes a single `-`.
 */
- (NSString *)dvt_stringByManglingToLegalBundleIdentifier;

/**
 Returns the receiver with every character an RFC 1034 label cannot use replaced by `-`.

 The receiver is canonical-decomposed first. ASCII letters, digits, and `-` are kept, and `-` may open
 the label too; everything else -- `.` and non-ASCII included -- becomes a single `-`.
 */
- (NSString *)dvt_stringByManglingToLegalRFC1034Identifier;

/**
 Mangles the receiver for `identifierType`: `0` for a bundle identifier, `1` for an RFC 1034 label, and anything else for a C identifier.

 No assertion fires here. Unknown types fall through to the C identifier mangling rather than failing,
 so `2` and `-1` both behave like `dvt_stringByManglingToLegalCIdentifier`.
 */
- (NSString *)dvt_stringByManglingToLegalIdentifierOfType:(NSInteger)identifierType;

@end

/** `YES` when the receiver has at least one entry. */
@interface NSMapTable (DVTNSMapTableAdditions)

@property (nonatomic, readonly) BOOL dvt_hasContent;
@property (nonatomic, readonly) BOOL dvt_isNonEmpty;

@end

/** `YES` when the receiver has at least one element. */
@interface NSOrderedSet (DVTNSOrderedSetAdditions)

@property (nonatomic, readonly) BOOL dvt_hasContent;
@property (nonatomic, readonly) BOOL dvt_isNonEmpty;

@end

NS_ASSUME_NONNULL_END
