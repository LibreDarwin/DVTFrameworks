//
//  DVTSystemActivityToken.m
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

#import "DVTSystemActivityToken.h"

#import "DVTAssertions.h"
#import "NSLock+DVTFoundationExtensions.h"

/*
 The set of live tokens is process-wide and shared by every token instance.
 The lock is an ordinary (non-recursive) NSLock, matching the original: the
 accessor's block runs while the lock is held and must not re-enter it.
 */
static NSMutableSet<DVTSystemActivityToken *> *DVTSystemActivityTokens = nil;
static NSLock *DVTSystemActivityTokensLock = nil;

@implementation DVTSystemActivityToken {
    BOOL _isInvalid;
}

+ (void)initialize
{
    if (self != [DVTSystemActivityToken class]) {
        return;
    }
    DVTSystemActivityTokens = [[NSMutableSet alloc] init];
    DVTSystemActivityTokensLock = [[NSLock alloc] init];
}

+ (void)_accessSystemActivityTokensWithBlock:(void (^)(NSMutableSet<DVTSystemActivityToken *> *))block
{
    /* Messaging the class has already run +initialize. The assertion mirrors
       the original, which reports a locked sentinel left behind when the lazy
       initialization never ran. */
    DVTAssert(DVTSystemActivityTokensLock != nil,
              @"DVTSystemActivityTokensLock != nil", nil,
              @"+[DVTSystemActivityToken initialize] did not run");
    NSMutableSet *tokens = DVTSystemActivityTokens;
    [DVTSystemActivityTokensLock dvt_performLockedBlock:^{
        block(tokens);
    }];
}

- (instancetype)initWithOptions:(unsigned long long)options reason:(NSString *)reason
{
    self = [super init];
    if (self) {
        _activityOptions = options;
        _reason = [reason copy];
        _processInfoToken = [[NSProcessInfo processInfo] beginActivityWithOptions:options reason:reason];
        DVTAssert(_processInfoToken != nil,
                  @"processInfoToken != nil", nil,
                  @"-[NSProcessInfo beginActivityWithOptions:reason:] failed for %@", reason);
    }
    return self;
}

- (BOOL)isValid
{
    return !_isInvalid;
}

- (void)markAsInvalid
{
    _isInvalid = YES;
}

- (void)primitiveInvalidate
{
    id processInfoToken = self.processInfoToken;
    DVTAssert(processInfoToken != nil,
              @"(processInfoToken) != nil", nil,
              @"%@ has no Foundation activity token to end", self);
    [[NSProcessInfo processInfo] endActivity:processInfoToken];
    self.processInfoToken = nil;
    [DVTSystemActivityToken _accessSystemActivityTokensWithBlock:^(NSMutableSet<DVTSystemActivityToken *> *tokens) {
        [tokens removeObject:self];
    }];
}

- (void)invalidate
{
    if (!self.isValid) {
        return;
    }
    [self primitiveInvalidate];
    [self markAsInvalid];
}

@end
