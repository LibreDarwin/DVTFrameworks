//
//  DVTSystemActivityToken.h
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

/**
 A Foundation system activity owned by the framework.

 Creating a token starts an activity through
 `-[NSProcessInfo beginActivityWithOptions:reason:]` and registers the token in
 the process-wide set of active activities. Invalidating the token ends the
 activity and removes it from that set.

 This port implements the activity lifecycle only. The original class also
 carries display and system sleep assertions (established lazily for the
 sleep-related activity options) and an invalidation backtrace from
 `DVTInvalidation`; both belong to those classes' own ports and are omitted
 here.
 */
@interface DVTSystemActivityToken : NSObject

/// The token returned by `-[NSProcessInfo beginActivityWithOptions:reason:]`.
@property (nonatomic, strong, nullable) id processInfoToken;

/// The reason passed when the token was created.
@property (nonatomic, copy) NSString *reason;

/// The activity options passed when the token was created.
@property (nonatomic) unsigned long long activityOptions;

/// `NO` once the token has been invalidated.
@property (nonatomic, readonly, getter=isValid) BOOL valid;

/**
 Runs `block` while holding the registry lock, passing the mutable set of
 active tokens.

 @note The lock is not recursive, so `block` must not ask for it again; that
       matches the original implementation.
 */
+ (void)_accessSystemActivityTokensWithBlock:(void (^)(NSMutableSet<DVTSystemActivityToken *> *tokens))block;

/**
 Starts a system activity and returns a token for it.

 The activity is started with `-[NSProcessInfo beginActivityWithOptions:reason:]`;
 a failure to create it is an assertion failure.
 */
- (instancetype)initWithOptions:(unsigned long long)options reason:(NSString *)reason;

/// Ends the activity and unregisters the token.
- (void)invalidate;

/// Ends the activity and unregisters the token, without the validity check.
- (void)primitiveInvalidate;

/// Marks the token invalid without ending its activity.
- (void)markAsInvalid;

@end

NS_ASSUME_NONNULL_END
