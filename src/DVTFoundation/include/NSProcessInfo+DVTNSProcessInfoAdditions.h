//
//  NSProcessInfo+DVTNSProcessInfoAdditions.h
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

NS_ASSUME_NONNULL_BEGIN

@class DVTOneShotBlock;
@class DVTSystemActivityToken;

/**
 Process information, termination bookkeeping, and system activity tokens used
 by Xcode.

 Sudden termination is tracked in a dictionary of reason to count, automatic
 termination in a counted set of reasons, and system activities in a set of
 tokens. All three are process-wide and guarded by their own lock.

 The termination state is normally reached through the
 `-dvt_disable...TerminationForReason:` / `-dvt_enable...TerminationForReason:`
 pair rather than the count accessors, and every disable should be balanced by
 an enable (or by invalidating the token returned from
 `-dvt_disableAutomaticTerminationWithReason:`).
 */
@interface NSProcessInfo (DVTNSProcessInfoAdditions)

/**
 The number of CPUs the kernel reports as available, from
 `sysctl(HW_AVAILCPU)`. A failed query reads as 0.
 */
- (unsigned long long)dvt_numberOfAvailableCPUs;

/**
 The absolute path of the running executable.

 The path comes from `_NSGetExecutablePath`, sizing the buffer from the length
 the call reports, and is converted with
 `-[NSFileManager stringWithFileSystemRepresentation:length:]`. The conversion
 uses the C string length rather than the reported buffer size, so the result
 carries no trailing NUL (the original's does).
 */
- (NSString *)dvt_executablePath;

/// `YES` when the process name is exactly `Xcode`.
- (BOOL)isXcode;

/// `YES` when the process name is exactly `Playgrounds`.
- (BOOL)isSwiftPlaygrounds;

/**
 The distinct reasons currently keeping sudden termination disabled, in
 unordered dictionary-key order.
 */
- (NSArray<NSString *> *)dvt_suddenTerminationDisablingReasons;

/**
 How many times sudden termination was disabled for `reason`, or 0 when the
 reason is not present. The count is signed; the private setter stores
 non-zero values unchanged.
 */
- (long long)dvt_suddenTerminationDisablingCountForReason:(NSString *)reason;

/**
 Overrides the count for `reason` without touching Foundation. A count of 0
 removes the reason; every other value, including a negative one, is stored.
 */
- (void)_dvt_setSuddenTerminationDisablingCount:(long long)count forReason:(NSString *)reason;

/// The distinct reasons currently keeping automatic termination disabled.
- (NSArray<NSString *> *)dvt_automaticTerminationDisablingReasons;

/**
 How many nested `-dvt_disableAutomaticTerminationForReason:` calls are
 outstanding for `reason`. The reasons live in a counted set, so repeated
 disables of the same reason accumulate.
 */
- (long long)dvt_automaticTerminationDisablingCountForReason:(NSString *)reason;

/**
 Disables automatic termination for `reason` and returns a one-shot block that
 re-enables it when invalidated. The disable is performed before the block is
 returned, so the caller only has to retain the block for as long as the
 activity needs to keep the process alive.
 */
- (DVTOneShotBlock *)dvt_disableAutomaticTerminationWithReason:(NSString *)reason;

/**
 Adds `reason` to the counted set of automatic termination reasons, then calls
 `-disableAutomaticTermination:` when the receiver responds to it.

 `reason` must be a non-empty string.
 */
- (void)dvt_disableAutomaticTerminationForReason:(NSString *)reason;

/**
 Removes one occurrence of `reason` and calls `-enableAutomaticTermination:`
 when it was present. Removing an absent reason is a no-op.

 `reason` must be a non-empty string.
 */
- (void)dvt_enableAutomaticTerminationForReason:(NSString *)reason;

/**
 Decrements the sudden termination count for `reason` and calls
 `-enableSuddenTermination`. An absent reason is left at zero rather than going
 negative.

 `reason` must be a non-empty string.
 */
- (void)dvt_enableSuddenTerminationForReason:(NSString *)reason;

/**
 Increments the sudden termination count for `reason` and calls
 `-disableSuddenTermination`.

 `reason` must be a non-empty string.
 */
- (void)dvt_disableSuddenTerminationForReason:(NSString *)reason;

/**
 Whether the process is known to run without a graphical interface.

 The flag is an associated object, so it is per-instance and is not derived
 from the process environment.
 */
- (BOOL)dvt_isNonGraphicalProcess;

/// Stores the value returned by `-dvt_isNonGraphicalProcess`.
- (void)dvt_setIsNonGraphicalProcess:(BOOL)isNonGraphicalProcess;

/**
 Whether Xcode should refuse to save.

 `XCODEBUILD_FORCE_ALLOW_SAVING` in the environment forces `NO`. Otherwise the
 associated override set with `-dvt_setDisallowSavingOverride:` wins, and when
 no override has been set the non-graphical process flag is used (a
 non-graphical process must not save).
 */
- (BOOL)dvt_shouldDisallowSaving;

/// Stores an associated-object override for `-dvt_shouldDisallowSaving`.
- (void)dvt_setDisallowSavingOverride:(BOOL)disallowSavingOverride;

/**
 Starts a Foundation activity and returns a token that ends it.

 The returned token is registered in the process-wide set of active tokens and
 removes itself when invalidated.
 */
- (DVTSystemActivityToken *)dvt_beginActivityWithOptions:(unsigned long long)options
                                                  reason:(NSString *)reason;

/**
 The active tokens whose activity options share at least one bit with
 `options`. The array is unordered.
 */
- (NSArray<DVTSystemActivityToken *> *)dvt_activeSystemActivityTokensMatchingOptions:(unsigned long long)options;

@end

NS_ASSUME_NONNULL_END
