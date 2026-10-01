//
//  DVTEnvironmentSnapshot.h
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
#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Controls whether `DVTPerformWithEnvironmentSnapshot()` creates the process
 environment snapshot, requires an existing one, or merely updates it.

 The numeric values are load bearing: they are baked into the framework's own
 call sites (`1` for the read-only accessors, `2` for the mutators) and callers
 compiled against the original framework pass them directly.
 */
typedef NS_ENUM(NSInteger, DVTCachedEnvioronmentBlockMode) {
    /// Invoke the block only when a snapshot already exists.
    DVTCachedEnvioronmentBlockModeSkip = 0,
    /// Create the snapshot from `NSProcessInfo` when one does not exist yet,
    /// then invoke the block. This is the mode the read-only accessors use.
    DVTCachedEnvioronmentBlockModeCreateIfNeeded = 1,
    /// Invoke the block so it can mutate an already-cached snapshot. No
    /// snapshot is created: the mutators call `setenv`/`unsetenv` themselves,
    /// so an absent snapshot will simply be rebuilt from the live environment
    /// on the next read and needs no repair. This is the mode the mutators use.
    DVTCachedEnvioronmentBlockModeUpdate = 2,
};

/**
 Returns a copy of the cached environment snapshot, creating the snapshot on
 first use. Never returns `nil`; an unset snapshot reads as the empty
 dictionary.
 */
DVT_EXTERN NSDictionary<NSString *, NSString *> *DVTEnvironmentSnapshot(void);

/**
 Returns the cached value for `name`, or `nil` when it is not present.
 */
DVT_EXTERN NSString *_Nullable DVTEnvironmentSnapshotString(NSString *name);

/**
 Returns `-[DVTEnvironmentSnapshotString(name) boolValue]`, so a missing
 variable reads as `NO`.
 */
DVT_EXTERN BOOL DVTEnvironmentSnapshotBool(NSString *name);

/**
 Drops the cached snapshot so the next read re-creates it from the live
 process environment.
 */
DVT_EXTERN void DVTResetEnvironmentSnapshot(void);

/**
 Sets `name` in the live process environment and, when the cached snapshot
 exists, updates the snapshot to match. Does nothing when either string is
 `nil` or when the C conversion fails.
 */
DVT_EXTERN void DVTSetEnvironmentVariable(NSString *name, NSString *_Nullable value);

/**
 Unsets `name` from the live process environment and, when the cached snapshot
 exists, removes it from the snapshot. Does nothing when `name` is `nil` or the
 C conversion fails.
 */
DVT_EXTERN void DVTRemoveEnvironmentVariable(NSString *name);

/**
 Runs `block` while holding the snapshot lock, passing the mutable snapshot
 dictionary (or `nil` when `mode` is not `CreateIfNeeded`/`Update` and no
 snapshot exists yet).

 @note The snapshot lock is an unfair lock held across the block invocation, so
       `block` must not re-enter the environment snapshot API. This matches the
       original implementation, which is not reentrant-safe by design.
 */
DVT_EXTERN void DVTPerformWithEnvironmentSnapshot(DVTCachedEnvioronmentBlockMode mode,
                                                  void (^)(NSMutableDictionary *_Nullable snapshot));

/**
 Interprets `value` the way `-[NSString boolValue]` does: a leading sign or
 digit parses numerically, otherwise `Y`/`y`/`T`/`t` are true and everything
 else -- including the empty string -- is false.

 PureDarwin's `NSString` does not declare `-boolValue`, so the snapshot bool
 accessor and the assertion environment checks share this implementation.
 */
DVT_EXTERN BOOL DVTStringIsTrue(NSString *_Nullable value);

@class NSProcessInfo;

NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN

/**
 Compatibility shims exposed by the original framework. The category name
 contains a long-standing upstream typo ("Envioronment"); it is preserved
 verbatim so that selectors match byte for byte.
 */
@interface NSProcessInfo (DVTCachedEnvioronmentCompatibility)

@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *dvt_cachedEnvironment;

- (nullable NSString *)dvt_cachedEnvironmentValueForVariable:(NSString *)variable;
- (BOOL)dvt_cachedEnvironmentBoolForVariable:(NSString *)variable;
- (void)dvt_setValue:(nullable NSString *)value forEnvironmentVariable:(NSString *)variable;
- (void)dvt_removeValueForEnvironmentVariable:(NSString *)variable;

@end

NS_ASSUME_NONNULL_END
