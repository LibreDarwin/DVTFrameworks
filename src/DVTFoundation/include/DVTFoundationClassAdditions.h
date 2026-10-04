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

@end

@interface NSMutableArray (DVTFoundationClassAdditions)

/** Appends `object` only when it is non-`nil`. */
- (void)dvt_addObjectIfNonNil:(id _Nullable)object;

/** Appends every element of `objects` that is not already present. */
- (void)dvt_addObjectsFromArrayIfAbsent:(NSArray *)objects;

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
