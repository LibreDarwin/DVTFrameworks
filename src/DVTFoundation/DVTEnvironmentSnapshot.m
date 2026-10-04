//
//  DVTEnvironmentSnapshot.m
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

#import "DVTEnvironmentSnapshot.h"

#import <Foundation/NSProcessInfo.h>
#import <os/lock.h>
#import <stdlib.h>

/**
 The snapshot is a mutable copy of the process environment, cached for the life
 of the process until `DVTResetEnvironmentSnapshot()` throws it away. Reading
 it through `DVTEnvironmentSnapshotString()` therefore does *not* observe
 `setenv()` calls made behind the framework's back; only the mutators below
 keep it in sync.
 */
static os_unfair_lock DVTSnapshotLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSString *> *DVTCachedEnvironmentSnapshot;

static NSMutableDictionary<NSString *, NSString *> *DVTExistingSnapshot(void)
{
    return DVTCachedEnvironmentSnapshot;
}

static NSMutableDictionary<NSString *, NSString *> *DVTCreateSnapshotLocked(void)
{
    if (DVTCachedEnvironmentSnapshot == nil) {
        NSDictionary<NSString *, NSString *> *live = [NSProcessInfo processInfo].environment;
        DVTCachedEnvironmentSnapshot = (NSMutableDictionary<NSString *, NSString *> *)[live mutableCopy];
    }
    return DVTCachedEnvironmentSnapshot;
}

/**
 `-boolValue` is not part of PureDarwin's NSString, so reproduce the semantics
 the real Foundation implements. Verified against Foundation on Darwin:

 - leading spaces and tabs are skipped, but a newline is not;
 - an optional `+`/`-` may follow, and a sign with no digits is false;
 - a run of digits decides numerically and the sign does *not* negate it, so
   `"-1"` and `"10x"` are true while `"-0"`, `"00"` and `"0abc"` are false;
 - with no digits, only an unprefixed `Y`, `y`, `T` or `t` is true.
 */
BOOL DVTStringIsTrue(NSString *value)
{
    NSUInteger length = value.length;
    NSUInteger index = 0;

    while (index < length) {
        unichar character = [value characterAtIndex:index];
        if (character != ' ' && character != '\t') {
            break;
        }
        index++;
    }
    if (index >= length) {
        return NO;
    }

    unichar first = [value characterAtIndex:index];
    BOOL signed_ = (first == '-' || first == '+');
    if (signed_) {
        index++;
    }

    BOOL sawDigit = NO;
    BOOL nonzero = NO;
    for (; index < length; index++) {
        unichar character = [value characterAtIndex:index];
        if (character < '0' || character > '9') {
            break;
        }
        sawDigit = YES;
        if (character != '0') {
            nonzero = YES;
        }
    }

    if (sawDigit) {
        return nonzero;
    }
    if (signed_) {
        return NO;
    }
    return first == 'Y' || first == 'y' || first == 'T' || first == 't';
}

void DVTPerformWithEnvironmentSnapshot(DVTCachedEnvioronmentBlockMode mode,
                                      void (^block)(NSMutableDictionary<NSString *, NSString *> *_Nullable snapshot))
{
    if (block == nil) {
        return;
    }

    os_unfair_lock_lock(&DVTSnapshotLock);
    if (mode == DVTCachedEnvioronmentBlockModeCreateIfNeeded) {
        (void)DVTCreateSnapshotLocked();
    } else if (mode == DVTCachedEnvioronmentBlockModeSkip) {
        /* Documented as "invoke only when a snapshot already exists". */
        NSMutableDictionary<NSString *, NSString *> *existing = DVTExistingSnapshot();
        if (existing != nil) {
            block(existing);
        }
        os_unfair_lock_unlock(&DVTSnapshotLock);
        return;
    }
    block(DVTExistingSnapshot());
    os_unfair_lock_unlock(&DVTSnapshotLock);
}

NSDictionary<NSString *, NSString *> *DVTEnvironmentSnapshot(void)
{
    __block NSDictionary<NSString *, NSString *> *result = nil;
    DVTPerformWithEnvironmentSnapshot(DVTCachedEnvioronmentBlockModeCreateIfNeeded,
                                      ^(NSMutableDictionary<NSString *, NSString *> *snapshot) {
                                          result = (NSDictionary<NSString *, NSString *> *)[snapshot copy];
                                      });
    return result != nil ? result : (NSDictionary<NSString *, NSString *> *)@{};
}

NSString *DVTEnvironmentSnapshotString(NSString *name)
{
    if (name == nil) {
        return nil;
    }

    __block NSString *result = nil;
    /* A read-only accessor uses the create-if-needed mode, so the value is
       available even when this is the first snapshot touched. */
    DVTPerformWithEnvironmentSnapshot(DVTCachedEnvioronmentBlockModeCreateIfNeeded,
                                      ^(NSMutableDictionary<NSString *, NSString *> *snapshot) {
                                          result = [snapshot objectForKey:name];
                                      });
    return result;
}

BOOL DVTEnvironmentSnapshotBool(NSString *name)
{
    NSString *value = DVTEnvironmentSnapshotString(name);
    return value != nil ? DVTStringIsTrue(value) : NO;
}

void DVTResetEnvironmentSnapshot(void)
{
    os_unfair_lock_lock(&DVTSnapshotLock);
    DVTCachedEnvironmentSnapshot = nil;
    os_unfair_lock_unlock(&DVTSnapshotLock);
}

void DVTSetEnvironmentVariable(NSString *name, NSString *value)
{
    if (name == nil || value == nil) {
        return;
    }

    const char *nameBytes = [name UTF8String];
    const char *valueBytes = [value UTF8String];
    if (nameBytes == NULL || valueBytes == NULL) {
        return;
    }

    if (setenv(nameBytes, valueBytes, 1) != 0) {
        return;
    }

    DVTPerformWithEnvironmentSnapshot(DVTCachedEnvioronmentBlockModeUpdate,
                                      ^(NSMutableDictionary<NSString *, NSString *> *snapshot) {
                                          if (snapshot != nil) {
                                              [snapshot setObject:value forKey:name];
                                          }
                                      });
}

void DVTRemoveEnvironmentVariable(NSString *name)
{
    if (name == nil) {
        return;
    }

    const char *nameBytes = [name UTF8String];
    if (nameBytes == NULL) {
        return;
    }

    if (unsetenv(nameBytes) != 0) {
        return;
    }

    DVTPerformWithEnvironmentSnapshot(DVTCachedEnvioronmentBlockModeUpdate,
                                      ^(NSMutableDictionary<NSString *, NSString *> *snapshot) {
                                          if (snapshot != nil) {
                                              [snapshot removeObjectForKey:name];
                                          }
                                      });
}

@implementation NSProcessInfo (DVTCachedEnvioronmentCompatibility)

- (NSDictionary<NSString *, NSString *> *)dvt_cachedEnvironment
{
    return DVTEnvironmentSnapshot();
}

- (NSString *)dvt_cachedEnvironmentValueForVariable:(NSString *)variable
{
    return DVTEnvironmentSnapshotString(variable);
}

- (BOOL)dvt_cachedEnvironmentBoolForVariable:(NSString *)variable
{
    return DVTEnvironmentSnapshotBool(variable);
}

- (void)dvt_setValue:(NSString *)value forEnvironmentVariable:(NSString *)variable
{
    DVTSetEnvironmentVariable(variable, value);
}

- (void)dvt_removeEnvironmentVariable:(NSString *)variable
{
    DVTRemoveEnvironmentVariable(variable);
}

@end
