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

/**
 Elements satisfying `test`, evaluated in order and synchronously.

 When every element passes, the receiver itself comes back rather than a rebuilt
 copy. That identity holds for a mutable receiver as well, because `-copy` of a
 mutable array is a different immutable object; the answer is immutable either
 way. A `test` that rejects any element answers a fresh array instead.

 On `NSSet` the same method answers a set, so the set/array split is the
 receiver's collection rather than the selector's name.
 */
- (NSArray *)dvt_objectsPassingTest:(BOOL (^)(id object))test;

/** The first element satisfying `test`, or `nil`. */
- (id _Nullable)dvt_firstObjectPassingTest:(BOOL (^)(id object))test;
/**
  The first non-`nil` answer `block` gives for an element, or `nil` if there is none.

  Unlike `dvt_compactMap:`, which asks about every element and drops the `nil`
  answers, this stops at the first answer it can use: the elements after it are
  never offered to the block, so the call log is as short as the answer allows. An
  empty receiver answers `nil` without calling the block, and a block that answers
  `nil` throughout leaves the walk to run to the end.

  A `nil` block faults, as Apple loads the block's invoke pointer without checking
  it.
 */
- (id _Nullable)dvt_firstMap:(id _Nullable (^_Nullable)(id object))block;
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

/**
 The range of the first run of `array` found contiguously inside the receiver,
 comparing members with `isEqual:`, or `{NSNotFound, 0}` when there is none.

 Candidates are tried left to right, so when runs of different lengths start in
 different places the earlier one answers even if it is shorter. An empty or
 `nil` `array` finds nothing.
 */
- (NSRange)dvt_rangeOfArray:(NSArray *)array;

/**
 The same search restricted to `range`.

 Only start positions whose whole run lands inside `range` are tried, so a run
 that begins inside the window but would run past its end is not found. When no
 complete run fits inside the window -- because it is empty, shorter than
 `array`, or leaves the receiver -- the answer is `{NSNotFound, 0}` rather than
 an exception.
 */
- (NSRange)dvt_rangeOfArray:(NSArray *)array inRange:(NSRange)range;

/** The last member satisfying `test`, or `nil` when none does. */
- (id _Nullable)dvt_lastObjectPassingTest:(BOOL (^)(id object))test;

/**
 The member immediately before the first occurrence of `object`, or `nil` when
 `object` is absent or is the receiver's first member.

 The selector's spelling is Apple's, misspelling included, and is kept as it is
 so callers written against the binary still match.
 */
- (id _Nullable)dvt_objectBeforeFirstOccurenceOfObject:(id)object;

/**
 Every element is asked, and the answer is the total, so a `test` that always
 returns `YES` over a three element array gives 3.

 The block's return value is added up rather than counted, so a block that
 returns something other than `YES` or `NO` contributes that value: returning 3
 for each of three elements totals 9. A block declared to answer `BOOL`, as this
 one's parameter is, cannot do that. `NSSet` and `NSMutableArray` share this
 behaviour, so it is the one place the selector's name is actively misleading.

 A `nil` test faults on Apple, which reaches the block without checking it. This
 returns the count instead, the same deliberate guard the all/any predicates use.
 */
- (NSInteger)dvt_numberOfObjectsPassingTest:(BOOL (^)(id object))test;

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

/** Elements mapped through `block`; `nil` results are dropped. The answer is immutable. */
- (NSArray *)dvt_arrayByApplyingBlock:(id _Nullable (^)(id object))block;
/**
 Like `dvt_arrayByApplyingBlock:`, except a single `nil` result sinks the answer.

 The whole result becomes `nil` at the first `nil`, and it does so there rather
 than at the end -- `block` is asked about one element and no more. There is no
 `NSNull` placeholder, so the result does not keep the receiver's length.
 */
- (NSArray *_Nullable)dvt_arrayByApplyingBlockStrictly:(id _Nullable (^)(id object))block;
/**
  Like `dvt_arrayByApplyingBlock:`, but the mapping is a selector sent to each
  element rather than a block.

  As with the block form, `nil` answers are dropped and the answer is immutable, so
  this is a `compactMap` spelled with `objc_msgSend`; the elements are visited in
  order and repeated answers are kept, which is the one place it parts company with
  the `NSSet` method of the same name, where repeats collapse.

  `selector` has to answer an object; one that returns a scalar faults, as the
  answer is treated as an object either way. A member that does not carry the
  selector is skipped, and a `nil` `selector` answers an empty array. Both of those
  abort Apple, as noted on the implementation.
 */
- (NSArray *)dvt_arrayByApplyingSelector:(SEL _Nullable)selector;
/** Like `dvt_arrayByApplyingBlock:`, with the element index as a second argument. */
- (NSArray *)dvt_arrayByApplyingBlockWithIndex:(id _Nullable (^)(id object, NSUInteger index))block;
/** Elements satisfying `block`, re-wrapped into an array. */
- (NSArray *)dvt_arrayByFilteringUsingBlock:(BOOL (^)(id object))block;
/**
 Members gathered into the maximal runs `block` calls equal, each run one member.

 `block` is a comparator over the previous and the current member, and is asked once per
 adjacent pair -- `n` members give `n - 1` calls. A new run starts wherever the
 comparator answers false between a member and the one before it, so a run is anywhere
 from one member to the whole receiver. Order, repeats, and member identity survive.

 An empty receiver answers `nil` rather than an empty array. The runs are subarrays of
 the receiver, except when the receiver holds a single member, where the only run is a
 copy of the receiver -- which is the receiver itself when the receiver is immutable,
 and a fresh array when it is not.
 */
- (NSArray *_Nullable)dvt_arrayByGroupingAdjacentObjectsUsingBlock:(BOOL (^)(id previous, id current))block;
/**
 Members grouped under the key `block` gives each, the groups in no particular order.

 `block` is asked once per member and answers the key that member belongs under. The key
 may be any non-empty object -- a string, an array, a number -- and members that share a
 key land in one group, in receiver order.

 The answer is unordered: it is the `allValues` of the dictionary Apple accumulates
 into, so the groups cannot be compared by index across two runs. Each group is a fresh
 mutable array while the answer itself is immutable.

 A key that comes out `nil` or empty aborts, as it has to be stored as a dictionary key.
 */
- (NSArray *)dvt_unorderedArrayByGroupingObjectsUsingKeys:(id _Nullable (^)(id object))block;
/**
 Members grouped by their values for each of `keyPaths`, which is an array of key paths
 rather than a block.

 A member is keyed by the array of the values it has for `keyPaths`, so two members group
 together exactly when those values agree. This is the block form above with the
 per-member key computed for you, and it shares that method's unordered answer and its
 abort on a key that comes out empty.

 `keyPaths` has to be a non-empty array of key paths. An empty array aborts, and a
 string faults, since it is asked for the key path and then sent `dvt_arrayByApplyingBlock:`.

 A member that has no value for a path is keyed by a shared sentinel rather than
 dropped, so such members group together instead of raising on an empty key. They do
 not group with a member whose value happens to be `NSNull`.
 */
- (NSArray *)dvt_unorderedArrayByGroupingObjectsUsingKeyPaths:(id)keyPaths;
/**
 Members joined with `separator`, with the final member introduced differently.

 The shape is the one a command line wants: everything up to the final member is joined
 with `separator`, and the final member is introduced by `finalComponentJoinString`
 instead, so the last member reads as the argument the rest qualify.

 `count` picks between two joins, and they are not the same string:
 - no members: the empty string
 - one member: that member's `description`
 - two members: `first finalComponentJoinString last`
 - three or more: the first `count - 1` joined by `separator`, then `separator`, then
   `finalComponentJoinString`, then a space, then the last member

 A `nil` separator joins with nothing. A `nil` final join string prints as `(null)`.
 */
- (NSString *)dvt_componentsJoinedByString:(NSString *_Nullable)separator
                  finalComponentJoinString:(NSString *_Nullable)finalComponentJoinString;
/**
 Like `dvt_arrayByApplyingBlock:`, returning a set.

 Answers that repeat collapse, so the result can be smaller than the receiver even
 when no answer was `nil`.
 */
- (NSSet *)dvt_setByApplyingBlock:(id _Nullable (^)(id object))block;
/** Like `dvt_arrayByApplyingBlockStrictly:`, returning a set. */
- (NSSet *_Nullable)dvt_setByApplyingBlockStrictly:(id _Nullable (^)(id object))block;
/**
 Elements satisfying `block`, re-wrapped into a set.

 Always a fresh set, even when nothing is filtered out, because the result has to
 be a set regardless. `NSSet`'s form of this selector does return the receiver in
 that case.
 */
- (NSSet *)dvt_setByFilteringUsingBlock:(BOOL (^)(id object))block;

/** The object with the highest `compare:` result, or `nil` when empty. */
- (id _Nullable)dvt_maximumObject;
/** The object with the lowest `compare:` result, or `nil` when empty. */
- (id _Nullable)dvt_minimumObject;

/**
  The object the `comparator` ranks lowest, or `nil` for an empty receiver.

  The comparator is asked `(candidate, incumbent)` and not the other way round, which
  is the same order as `-[NSSet dvt_minimumObjectUsingComparator:]` uses. Only an
  exact `NSOrderedAscending` replaces the incumbent, so an out-of-contract `-2`
  leaves it in place rather than counting as "less", and `NSOrderedSame` is a tie
  that keeps it — which makes the first of equally-ranked members win.

  An empty or single-member receiver never reaches the comparator, so a `nil`
  comparator is safe there; with two or more members it faults, as Apple loads the
  block's invoke pointer without checking it.
 */
- (id _Nullable)dvt_minimumObject:(NSComparisonResult (^_Nullable)(id _Nullable, id _Nullable))comparator;

/**
  The object the `comparator` ranks highest, or `nil` for an empty receiver.

  This is `dvt_minimumObject:` asked with the comparator's answer negated, so the
  tie-break is shared: an equal-ranked member keeps the incumbent and the first one
  enumerated wins.
 */
- (id _Nullable)dvt_maximumObject:(NSComparisonResult (^_Nullable)(id _Nullable, id _Nullable))comparator;

/**
  The elements folded into one object, or `nil` for an empty receiver.

  The block is asked `(accumulator, next)` — the opposite order from a comparator
  fold — starting from the first element, which is returned untouched without the
  block being called. The answer is not checked for `nil`: a `nil` answer leaves the
  accumulator empty, and the following element then becomes the accumulator
  directly, so a block that always answers `nil` yields the *last* element rather
  than `nil`.

  `NSSet`'s form of this selector folds its members with the same rule.

  A `nil` block faults, as Apple loads the block's invoke pointer without checking
  it.
 */
- (id _Nullable)dvt_objectByFoldingWithBlock:(id _Nullable (^_Nullable)(id _Nullable, id _Nullable))block;

/**
  A shuffled copy of the receiver, leaving the receiver in its original order.

  Only a receiver with more than one element is actually shuffled. At one element
  or below the receiver is merely copied, which means an immutable receiver is
  returned as the very same object while a mutable one is returned as an
  immutable array; above one element the result is always a mutable array.
 */
- (id)dvt_shuffledArray;

/**
  A dictionary keyed by each element, valued by the block's answer for it.

  Despite the name, the block's answer is the *value* and the element is the key, so
  an element `"a"` with an uppercasing block answers `a->A`. A `nil` answer is
  skipped rather than stored. The elements stay distinct as keys, so a constant
  answer produces one entry per element. The answer is immutable.

  `NSSet`'s form of this selector builds the same dictionary from its members.

  A `nil` block faults, as Apple loads the block's invoke pointer without checking
  it.
 */
- (NSDictionary *)dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:(id _Nullable (^_Nullable)(id))block;

/**
  A dictionary keyed by the block's answer for each element, valued by the element.

  The mirror image of the method above: the block's answer is the *key* and the
  element is the value, so the same uppercasing block answers `A->a`. Because the
  answers are the keys here, a block answering one constant leaves a single entry
  whose value is the last element enumerated. A `nil` answer is skipped rather than
  stored, and the answer is immutable.

  A `nil` block faults, as Apple loads the block's invoke pointer without checking
  it.
 */
- (NSDictionary *)dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:(id _Nullable (^_Nullable)(id))block;

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
  Renders the receiver as shell command arguments: elements are separated by a
  single space, the empty string is emitted as `""`, and an empty receiver yields
  the empty string.

  This is the shell counterpart of `dvt_stringByConcatenatingAsCommandLineArguments`
  and escapes a different set. Exactly three characters are escaped -- backslash,
  space, and tab -- each as a backslash followed by the character, so a literal
  tab becomes a backslash and a real tab. Quotes, `$`, `*`, `~`, newline and the
  rest of the shell metacharacters pass through untouched.

  Unlike the command line variant, every element must be an `NSString`. Apple
  guards each one with a `CFGetTypeID`/`CFStringGetTypeID` comparison and asserts
  when it fails, so a non-string element aborts instead of being described.

  All three replacements search the range `{0, length}` of the *original*
  argument, not of the string produced by the preceding replacement. A character
  that an earlier replacement pushed past that length is therefore left
  unescaped: `@"\\  "` escapes only its first space, and `@"\\\t "` escapes the tab
  but not the space after it.
 */
- (NSString *)dvt_stringByConcatenatingAsShellCommandArguments;

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

/**
 The receiver sorted by a derived value, answering a new immutable array and
 leaving the receiver untouched even when the receiver is itself mutable.

 `valueBlock` is applied to each element and the resulting values are compared
 with `compare:`, so the ordering follows the block's output rather than the
 elements themselves. A derived value of `nil` trips an assertion rather than
 being compared, as it does in the in-place `dvt_sortByValueBlock:`; the
 assertion names the element whose value came back empty.

 Elements whose derived values come out equal are reported as equal, leaving
 their relative order to the sort.

 With one element or fewer there is nothing to compare, so the sort is skipped
 and `valueBlock` is never asked. That is why a block returning `nil` is
 harmless on a short receiver and only asserts once a comparison is made.
 */
- (NSArray *)dvt_objectsSortedByValueBlock:(id (^)(id object))valueBlock;

/**
 As `dvt_objectsSortedByValueBlock:`, with `duplicateHandler` breaking ties.

 The handler runs only for elements whose derived values have already compared
 equal, and it receives the two elements rather than the two derived values, so
 it can order a tie by whatever `valueBlock` discarded. Its result becomes the
 comparison result. A `nil` handler behaves exactly as in
 `dvt_objectsSortedByValueBlock:`.

 A handler breaks ties rather than removing them, so elements sharing a derived
 value are all kept.
 */
- (NSArray *)dvt_objectsSortedByValueBlock:(id (^)(id object))valueBlock
                         duplicateHandler:(NSComparisonResult (^ _Nullable)(id first, id second))duplicateHandler;

#pragma mark - Construction

/**
 A mutable copy of `objects`, built one member at a time.

 The answer is always mutable even when the source is not, and always a fresh
 object even when the source is empty, so it is safe to hand back for building
 into. A `nil` source enumerates nothing and answers an empty mutable array.
 */
+ (NSArray *)dvt_arrayWithEnumeratedObjects:(NSArray * _Nullable)objects;

/**
 A one-member array holding `object`, or `nil` when `object` is `nil`.

 The `nil` case answers `nil` rather than an empty array, so this is the array
 form of an `if (object)` guard. A `nil`-but-present member such as `NSNull` is
 not `nil` and is kept, which is what separates this from filtering.
 */
+ (NSArray *)dvt_arrayWithObjectIfNonNil:(id _Nullable)object;

/**
 An immutable array holding the same `object` `count` times.

 Zero repetitions answers an empty array. A `nil` `object` is only tolerated at
 zero; with a count of one or more the array cannot hold it and the call fails
 the way any `NSArray` that is handed a `nil` member does.

 The members are staged in a buffer before the array is built, so a `count` at
 or below a few hundred costs no allocation beyond the answer itself.
 */
+ (NSArray *)dvt_arrayWithRepetitions:(NSUInteger)count ofObject:(id)object;

/**
 How many leading members `array` and `otherArray` agree on.

 The shorter of the two is the ceiling, so equal answers the whole receiver and
 a prefix answers the prefix. Comparison stops at the first disagreement and the
 index reached is returned; a `nil` array has no members to agree on and answers
 zero.
 */
+ (NSUInteger)dvt_lengthOfCommonPrefixBetween:(NSArray * _Nullable)array and:(NSArray * _Nullable)otherArray;

@end

@interface NSArray (DVTRangeArrayAdditions)

/**
 The `NSRange` carried by the member at `index`.

 This reads the member rather than treating it as a range, so the element itself
 has to answer `rangeValue`, and an index past the end fails the way any indexed
 access does. It is the inverse of taking `rangeValue` off an `NSValue`.
 */
- (NSRange)rangeAtIndex:(NSUInteger)index;

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

/**
  Moves the receiver's members into a stable partition in place.

  Members for which `test` returns `YES` form the suffix, arriving after every
  member that fails it. Both groups keep their original relative order, so the
  result does not depend on how the partition is carried out.
 */
- (void)dvt_stablePartitionObjectsPassingIsSuffixTest:(BOOL (^)(id object))test;

/**
  Answers a string that is not already in the receiver.

  If the receiver does not hold `string` by equality, it is returned unchanged.
  Otherwise `" <n>"` is appended for `n` counting up from 1 until a variant the
  receiver does not hold is found, which fills a gap in the numbering rather than
  skipping past it. Membership is by equality, so a distinct but equal string
  counts as present. Nothing is added to the receiver.
 */
- (NSString *)dvt_uniqueStringToAddToArray:(NSString *)string;

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

/**
 `YES` when some member satisfies `test`, stopping at the first that does.

 An empty set is `NO` without ever calling `test`. A `nil` `test` is treated as
 the same way it is on `NSArray`, where it answers `YES` for a set that has
 anything in it.
 */
- (BOOL)dvt_anyObjectsPassTest:(BOOL (^)(id object))test;

/** `YES` when the receiver has at least one member. Alias of `dvt_hasContent`. */
@property (nonatomic, readonly) BOOL dvt_hasContent;
@property (nonatomic, readonly) BOOL dvt_isNonEmpty;

/**
 The members sorted by a derived value, as `NSArray`'s
 `dvt_objectsSortedByValueBlock:` applied to `-allObjects`.

 Ordering follows the block's output rather than the members themselves, and a
 derived value of `nil` trips an assertion rather than being compared.

 Members whose derived values tie keep whatever relative order the set's own
 enumeration produced, so the answer is only reproducible when each member
 derives a distinct value, or when `duplicateHandler` breaks the ties itself.
 */
- (NSArray *)dvt_objectsSortedByValueBlock:(id (^)(id object))valueBlock;

/**
 As `dvt_objectsSortedByValueBlock:`, with `duplicateHandler` breaking ties.

 The handler runs only for members whose derived values have already compared
 equal, and receives the two members rather than the two derived values, so it
 can order a tie by whatever `valueBlock` discarded. It breaks ties rather than
 removing them, so members sharing a derived value are all kept.
 */
- (NSArray *)dvt_objectsSortedByValueBlock:(id (^)(id object))valueBlock
                         duplicateHandler:(NSComparisonResult (^ _Nullable)(id first, id second))duplicateHandler;

/**
 The members sorted by `compare:`, as `NSArray`'s `sortedArrayUsingSelector:`
 applied to `-allObjects`.
 */
- (NSArray *)dvt_sortedArray;

/**
 The members sorted by `selector`, as `NSArray`'s `sortedArrayUsingSelector:`
 applied to `-allObjects`.

 `selector` is handed straight through unchecked, so one the members do not
 understand raises out of the sort. Members the selector calls equal keep
 whatever order `-allObjects` produced, so the answer is only reproducible when
 the selector separates them.
 */
- (NSArray *)dvt_sortedArrayUsingSelector:(SEL)selector;

/**
 The members ordered by `comparator`, as `NSArray`'s
 `sortedArrayUsingComparator:` applied to `-allObjects`. The comparator decides
 the whole order and is asked about every pair.
 */
- (NSArray *)dvt_sortedArrayUsingComparator:(NSComparisonResult (^)(id first, id second))comparator;

/**
 The receiver's only member, or `nil` when it has none or has more than one.

 An empty set never reaches `-anyObject`, so a multi-member set answers `nil`
 without picking one of its members to return.
 */
- (id)dvt_onlyObject;

/**
 The first member, in the set's own order, that satisfies `test` -- or `nil`.

 This answers the member rather than whether one passed, so despite the name it
 is not the boolean predicate `dvt_anyObjectsPassTest:` is. The walk stops at the
 first match, so the remaining members are never asked.
 */
- (id)dvt_anyObjectPassingTest:(BOOL (^)(id object))test;

/**
 The member satisfying `test` when exactly one member does, and `nil` otherwise.

 `nil` therefore covers two different outcomes: nothing passed, and more than one
 member did. The second is decided as soon as it happens rather than after the
 walk finishes, so the block is asked about as few members as the answer allows.
 Which member wins when exactly one passes does not depend on the set's order.
 */
- (id)dvt_onlyObjectPassingTest:(BOOL (^)(id object))test;

/**
 How many members satisfy `test`. Every member is asked; the walk does not stop
 at the first match or the first failure.

 The block's return value is added up rather than counted, so a block that
 returns something other than `YES` or `NO` contributes that value: returning 3
 for each of three members totals 9. A block declared to answer `BOOL`, as this
 one's parameter is, cannot do that.
 */
- (NSInteger)dvt_numberOfObjectsPassingTest:(BOOL (^)(id object))test;

#pragma mark - Mapping and filtering

/**
  The members, in the set's own order, each run through `block`, minus the `nil`
  answers.

  A block that answers `nil` for a member leaves that member out rather than
  sinking the whole result, which is what the two `Strictly` forms do instead.
 */
- (NSArray *)dvt_arrayByApplyingBlock:(id _Nullable (^)(id object))block;

/**
  As `dvt_arrayByApplyingBlock:`, except a single `nil` answer sinks the result.

  The whole answer becomes `nil`, and it does so at the first `nil` -- `block` is
  asked about one member and no more, so a set of three members whose block
  answers `nil` first time still sees one call. There is no `NSNull` placeholder
  in the array.
 */
- (NSArray *_Nullable)dvt_arrayByApplyingBlockStrictly:(id _Nullable (^)(id object))block;

/**
  The members, each run through `block`, gathered into a set with the `nil` answers
  dropped.

  Answers that repeat collapse, so the result can be smaller than the receiver
  even when no answer is `nil`.
 */
- (NSSet *)dvt_setByApplyingBlock:(id _Nullable (^)(id object))block;

/**
  As `dvt_setByApplyingBlock:`, except a single `nil` answer sinks the result.

  The whole answer becomes `nil` at the first `nil`, exactly as
  `dvt_arrayByApplyingBlockStrictly:` does, so `block` is not asked about the
  remaining members.
 */
- (NSSet *_Nullable)dvt_setByApplyingBlockStrictly:(id _Nullable (^)(id object))block;

/**
  The members satisfying `block`, as a set. Answering `nil` yields an empty set.
 */
- (NSSet *)dvt_setByFilteringUsingBlock:(BOOL (^)(id object))block;

/**
  The members satisfying `test`, as a set.

  When every member passes, the receiver itself comes back rather than a rebuilt
  copy. That identity holds for a mutable receiver as well, because `-copy` of a
  mutable set is a different immutable object; the answer is immutable either
  way. A test that rejects any member answers a fresh set instead.

  On `NSArray` the same method answers an array, so the set/array split is the
  receiver's collection rather than the selector's name.
 */
- (NSSet *)dvt_objectsPassingTest:(BOOL (^)(id object))test;

/** `[NSMutableSet class]`, asked of a set. */
- (Class)dvt_mutableClass;

/**
  The members that `set` also holds, as a set.

  An empty or `nil` `set` answers an empty set rather than the receiver, so this
  empties the receiver where `dvt_setBySubtractingSet:` with the same empty
  argument leaves it alone.

  When every member survives, the answer is the receiver rather than a rebuilt
  copy, as with `dvt_objectsPassingTest:`.
 */
- (NSSet *)dvt_setByIntersectingSet:(NSSet *_Nullable)set;

/**
  The members `set` does not hold, as a set.

  An empty or `nil` `set` answers a copy of the receiver unchanged. Otherwise the
  answer is the receiver when every member survives, and a fresh set when any
  member is removed.
 */
- (NSSet *)dvt_setBySubtractingSet:(NSSet *_Nullable)set;

/**
  The members other than `object`, as a set.

  An absent `object` answers a copy of the receiver unchanged. The comparison is
  `isEqual:`, not pointer identity, so an equal-but-distinct argument removes the
  matching member. A `nil` argument is absent and changes nothing.
 */
- (NSSet *)dvt_setByRemovingObject:(id _Nullable)object;

/**
  The members, each sent `selector`, gathered into a set with the `nil` answers
  dropped and repeated answers collapsed.

  `selector` has to answer an object; one that returns a scalar faults, as the
  answer is treated as an object either way. A member that does not carry the
  selector is skipped, and a `nil` `selector` answers an empty set. Both of those
  abort Apple, as noted on the implementation.
 */
- (NSSet *)dvt_setByApplyingSelector:(SEL _Nullable)selector;

/**
  The member the `comparator` ranks lowest, or `nil` for an empty receiver.

  The comparator is asked `(candidate, incumbent)` — the member being considered
  first, the member held so far second — and only an exact `NSOrderedAscending`
  replaces the incumbent. A `NSOrderedSame` answer is a tie and keeps the
  incumbent, so among equally-ranked members the first one enumerated wins. A
  result outside `NSOrderedAscending`/`Same`/`Descending` does not compare as
  "less", so an out-of-contract `-2` leaves the incumbent in place.

  A `nil` `comparator` faults, as Apple loads the block's invoke pointer without
  checking it.
 */
- (id _Nullable)dvt_minimumObjectUsingComparator:(NSComparisonResult (^_Nullable)(id _Nullable, id _Nullable))comparator;

/**
  The member the `comparator` ranks highest, or `nil` for an empty receiver.

  This is `dvt_minimumObjectUsingComparator:` asked with the comparator's answer
  negated, so the tie-break is shared: an equal-ranked member keeps the incumbent
  and the first one enumerated wins.
 */
- (id _Nullable)dvt_maximumObjectUsingComparator:(NSComparisonResult (^_Nullable)(id _Nullable, id _Nullable))comparator;

/**
  The members folded into one object, or `nil` for an empty receiver.

  The block is asked `(accumulator, next)` — the opposite order from
  `dvt_minimumObjectUsingComparator:` — starting from the first member, which is
  returned untouched without the block being called. The answer is not checked for
  `nil`: a `nil` answer leaves the accumulator empty, and the following member then
  becomes the accumulator directly, so a block that always answers `nil` yields the
  *last* member rather than `nil`.

  A `nil` block faults, as Apple loads the block's invoke pointer without checking
  it.
 */
- (id _Nullable)dvt_objectByFoldingWithBlock:(id _Nullable (^_Nullable)(id _Nullable, id _Nullable))block;

/**
  The members as an array, shuffled.

  A forward to `dvt_shuffledArray` on `-allObjects`, so the answer follows the
  array method's branch on `count`: above one member it is a mutable array, and at
  one member or below it is a copy of an already immutable array — the same object
  for an empty receiver.
 */
- (NSArray *)dvt_shuffledArray;

/**
  A dictionary keyed by each member, valued by the block's answer for it.

  Despite the name, the block's answer is the *value* and the member is the key, so
  a member `"a"` with an uppercasing block answers `a->A`. A `nil` answer is skipped
  rather than stored. The members stay distinct as keys, so a constant answer
  produces one entry per member. The answer is immutable.

  A `nil` block faults, as Apple loads the block's invoke pointer without checking
  it.
 */
- (NSDictionary *)dvt_dictionaryWithEntriesAsKeysAndValuesFromBlock:(id _Nullable (^_Nullable)(id))block;

/**
  A dictionary keyed by the block's answer for each member, valued by the member.

  The mirror image of the method above: the block's answer is the *key* and the
  member is the value, so the same uppercasing block answers `A->a`. Because the
  answers are the keys here, a block answering one constant leaves a single entry
  whose value is the last member enumerated. A `nil` answer is skipped rather than
  stored, and the answer is immutable.

  A `nil` block faults, as Apple loads the block's invoke pointer without checking
  it.
 */
- (NSDictionary *)dvt_dictionaryWithEntriesAsValuesAndKeysFromBlock:(id _Nullable (^_Nullable)(id))block;

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

/**
 `YES` when some object satisfies `test`, stopping at the first that does.

 Empty and `nil`-block behaviour follow `NSSet`, as noted above.
 */
- (BOOL)dvt_anyObjectsPassTest:(BOOL (^)(id object))test;

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

/**
  The receiver's only element, or `nil`.

  Exactly one element, not the first of several: an empty receiver and a two-element
  one both answer `nil`, and a one-element receiver answers that same element rather
  than a copy of it.
 */
- (id _Nullable)dvt_onlyObject;

/**
  The first element `test` accepts, or `nil` when none is accepted.

  Unlike `NSSet`'s `dvt_anyObjectsPassTest:`, which answers a flag, this answers the
  object itself -- the binary returns the element with an autorelease on the way out.
  Scanning stops at the first element that passes, so a block that accepts the second
  member costs two calls.

  The raw 32 bits of the block's answer decide, so a block returning something other
  than a boolean passes on an odd value and fails on an even one.

  A `nil` `test` answers the first element, as `NSArray`'s
  `dvt_firstObjectPassingTest:` does.
 */
- (id _Nullable)dvt_anyObjectPassingTest:(BOOL (^)(id object))test;

/**
  The elements `test` accepts, in receiver order, as a fresh immutable set.

  Always allocated: unlike `NSSet`'s form of this selector, an ordered set does not
  answer the receiver when nothing is filtered out.

  The raw 32 bits of the block's answer decide, and here the whole word counts: any
  nonzero answer passes, so a block returning `2` keeps everything, where the same
  block under `dvt_anyObjectPassingTest:` finds nothing. That is what `NSSet`'s
  `dvt_setByFilteringUsingBlock:` does too.

  A `nil` `test` answers a copy of the receiver.
 */
- (NSOrderedSet *)dvt_objectsPassingTest:(BOOL (^)(id object))test;

/**
  `block` applied to every element, with the `nil` answers dropped, as an immutable array.

  The untyped twin of `dvt_orderedSetByApplyingBlock:`, with the same dropped nils and
  the same repeated answers kept -- two elements mapping to the same object give two
  of it, where the ordered-set form collapses them.
 */
- (NSArray *)dvt_arrayByApplyingBlock:(id _Nullable (^)(id object))block;

/**
  `dvt_arrayByApplyingBlock:` under its other name.

  Apple answers `dvt_arrayByApplyingBlock:` straight from here -- one instruction, a
  tail call -- so the two spellings cannot differ. On `NSArray` the same selector name
  instead answers the mutable array it built; here the array form's answer is the one
  that comes back.
 */
- (NSArray *)dvt_compactMap:(id _Nullable (^)(id object))block;

/**
  The first non-`nil` answer `block` gives, or `nil`.

  Stops at the first element with a usable answer; a block that answers `nil`
  throughout walks the whole receiver and comes back with `nil`, and an empty
  receiver never reaches the block.
 */
- (id _Nullable)dvt_firstMap:(id _Nullable (^)(id object))block;

/**
  The receiver with `object` appended, or the receiver itself.

  `nil`, and anything the receiver already holds, answer the receiver -- the same
  object, not a copy. Only a genuinely new object builds an answer, by appending to
  a mutable copy and handing back its immutable form.
 */
- (NSOrderedSet *)dvt_orderedSetByAddingObject:(id _Nullable)object;

/**
  The receiver with `objects` appended, or the receiver itself.

  An empty or `nil` array answers the receiver: asking `nil` for a count is zero, so
  the `nil` argument lands on the same branch rather than raising.
 */
- (NSOrderedSet *)dvt_orderedSetByAddingObjectsFromArray:(NSArray *_Nullable)objects;

/**
  The receiver without `object`, or the receiver itself.

  `nil`, and anything the receiver does not hold, answer the receiver. A held object
  is removed by equality, so an equal-but-distinct argument removes the element just
  the same.
 */
- (NSOrderedSet *)dvt_orderedSetByRemovingObject:(id _Nullable)object;

/**
  The receiver without the members of `orderedSet`, or the receiver itself.

  An empty or `nil` argument answers the receiver itself rather than a copy of it,
  which `NSSet`'s form of this idea does not do: `dvt_setBySubtractingSet:` takes
  the same shortcut but answers `[self copy]`, and a mutable receiver can tell those
  apart, since a copy of a mutable set is immutable.
 */
- (NSOrderedSet *)dvt_orderedSetBySubtractingOrderedSet:(NSOrderedSet *_Nullable)orderedSet;

/**
  `block` applied to every element, with the `nil` answers dropped, as an immutable set.

  Repeated answers collapse, so the result can be smaller than the receiver even when
  no answer was `nil`: two elements mapping to the same object leave one behind, at
  the position the first of them had. The set is built from the answers directly
  rather than by copying a mutable set, which is why an empty answer is an ordinary
  empty set rather than the receiver.
 */
- (NSOrderedSet *)dvt_orderedSetByApplyingBlock:(id _Nullable (^)(id object))block;

@end

/** The mutable ordered set carries three more, which an immutable one does not answer at all. */
@interface NSMutableOrderedSet (DVTNSOrderedSetAdditions)

/**
  Adds `object` when it is non-`nil`.

  Spelled `IfNotNil` rather than `NSMutableSet`'s `dvt_addObjectIfNonNil:`, which is
  how the binary has it.
 */
- (void)dvt_addObjectIfNotNil:(id _Nullable)object;

/**
  Adds `object` if it is non-`nil`, answering whether that grew the receiver.

  The test is the count, so an object the receiver already holds answers `NO`: adding
  one changes nothing about an ordered set's contents. A `nil` argument is `NO` for the
  same reason.
 */
- (BOOL)dvt_addReturningDidMutate:(id _Nullable)object;

/**
  Removes and answers the last element, or `nil` when empty.

  The element is taken out of the receiver before it is handed back, and an empty
  receiver answers `nil` without asking anything of itself.
 */
- (id _Nullable)dvt_popLastObject;

@end

/* Apple keeps a small set of KVO conveniences in `NSObject(DVTObservingConvenience)`,
   a category of its own. Two of the five answer without touching any observation
   state at all, and are reproduced that way; the notes on each say why, and what
   the binary actually does instead. */

/** Brackets a change with the two KVO notifications, and the two class helpers. */
@interface NSObject (DVTObservingConvenience)

/**
  Runs `block` between a `willChangeValueForKey:` and the matching
  `didChangeValueForKey:` on the receiver.

  The two notifications are sent unconditionally and in that order, and the block
  runs exactly once between them. A `nil` block is not guarded against: the binary
  loads the block's invoke pointer straight out of it and branches to it, so the
  argument has to be non-`nil`. A `nil` `key` is handed to Foundation untouched.
 */
- (void)dvt_changeValueForKey:(NSString *)key usingBlock:(void (^)(void))block;

/**
  Announces every member of `keys`, runs `block` once, then closes the
  notifications in reverse order.

  The two sides are independent enumerations -- the forward one walks `keys`
  directly, the closing one walks `keys.reverseObjectEnumerator` -- so a member
  that appears twice is announced twice on each side, and the closing order is the
  exact reverse of the opening one. `nil` and empty arrays still run the block; they
  simply have nothing to announce, because a message to `nil` answers zero and a
  `nil` enumerator enumerates nothing. A `nil` block faults as in the single-key
  form.
 */
- (void)dvt_changeValueForKeys:(NSArray * _Nullable)keys usingBlock:(void (^)(void))block;

/**
  Does nothing.

  The selector exists in Apple's binary but its whole body is two assertion calls
  and a return: a warning carrying `"Unsupported API. There is no replacement."`
  from `DVTFoundation/DVTFoundation/FoundationClassCategories/DVTNSKeyValueObserving.m`
  line 937, then the soft-assertion handler, then nothing else -- no observation is
  cancelled and no token is touched.

  The warning is not reachable output. It is dispatched to
  `-handleWarningInMethod:object:fileName:lineNumber:messageFormat:arguments:`,
  which logs only through `+[DVTAssertionHandler assertionLoggingAspect]` and
  returns without logging when no aspect is installed, which is the case in every
  process that is not Xcode. Calling the local warning handler instead would print a
  full report where Apple stays silent, so this is a no-op rather than a report that
  Apple does not make.
 */
+ (void)dvt_cancelAllObservingTokensForOwner:(id _Nullable)owner;

/**
  The shared empty array, whatever `object` is.

  The binary loads `___NSArray0__struct` and returns it without reading its
  argument, so this is `@[]` -- the same singleton `[NSArray array]` answers with --
  for a real object, a `nil`, or something that is not an observed object at all.
 */
+ (NSArray *)dvt_creationBacktracesOfObservingTokensForObservedObject:(id _Nullable)object;

/**
  `key` appended to the stand-in receiver `_dvt_standardUserDefaultsProxy.`.

  The answer for `@""` is the bare prefix, so a caller can see where the boundary
  falls. A `nil` key raises `NSInvalidArgumentException`, as appending does, and a
  value that is not a string raises rather than being coerced.
 */
+ (NSString *)dvt_keyPathOnSelfForUserDefaultsKey:(NSString *)key;

@end

/* The older spelling of the two collection tests. Apple keeps them in categories
   of their own, all three named the same thing, and in the binary each one is a
   bare tail call onto the current spelling -- `dvt_areAllObjectsPassingTest:`
   onto `dvt_allObjectsPassTest:` and `dvt_areAnyObjectsPassingTest:` onto
   `dvt_anyObjectsPassTest:`. The forwarding is reproduced here rather than a
   second copy of the logic, so the two spellings cannot drift apart.

   Only `NSArray` carries `dvt_anyObjectsPassTest:` in Apple's inventory, so the
   set-like classes get that spelling alongside the forward, which is also what
   the binary does: their `dvt_anyObjectsPassTest:` is a direct fast-enumeration
   scan of its own rather than a call through `dvt_firstObjectPassingTest:`.

   The category name is what the binary records and is matched. A compiler
   deprecation attribute is not: attributes leave no trace in a Mach-O method
   list, so there is nothing here to check one against, and adding one the
   binary may not carry would warn callers for a deprecation that may not exist. */

/** `YES` when every member satisfies `test`. Forwards to `dvt_allObjectsPassTest:`. */
@interface NSArray (DVTFoundationClassAdditions_DEPRECATED)

- (BOOL)dvt_areAllObjectsPassingTest:(BOOL (^)(id object))test;

/** `YES` when some member satisfies `test`. Forwards to `dvt_anyObjectsPassTest:`. */
- (BOOL)dvt_areAnyObjectsPassingTest:(BOOL (^)(id object))test;

@end

@interface NSSet (DVTFoundationClassAdditions_DEPRECATED)

- (BOOL)dvt_areAllObjectsPassingTest:(BOOL (^)(id object))test;
- (BOOL)dvt_areAnyObjectsPassingTest:(BOOL (^)(id object))test;

@end

@interface NSHashTable (DVTFoundationClassAdditions_DEPRECATED)

- (BOOL)dvt_areAllObjectsPassingTest:(BOOL (^)(id object))test;
- (BOOL)dvt_areAnyObjectsPassingTest:(BOOL (^)(id object))test;

@end

NS_ASSUME_NONNULL_END
