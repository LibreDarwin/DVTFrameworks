//
//  DVTOneShotBlock.h
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
 A token that runs a callback exactly once when invalidated.

 The class is used to undo a balanced pair of operations at the end of a
 scope: `-[NSProcessInfo dvt_disableAutomaticTerminationWithReason:]` returns
 one whose callback re-enables automatic termination, for instance.

 This port implements the callback lifecycle only. The original class is a
 `DVTInvalidation` and also records an invalidation backtrace, which belongs to
 that class's own port and is omitted here.
 */
@interface DVTOneShotBlock : NSObject

/// `NO` once the token has been invalidated.
@property (nonatomic, readonly, getter=isValid) BOOL valid;

/// Creates a token for `callback`, without running it.
+ (instancetype)oneShotBlockWithCallback:(void (^)(void))callback;

/// Stores a copy of `block`; the callback runs once when the token is invalidated.
- (instancetype)initWithCallbackBlock:(void (^)(void))block;

/// Runs the callback (if it has not run yet) and clears it.
- (void)invalidate;

/// Runs the callback and clears it, without the validity check.
- (void)primitiveInvalidate;

/// Marks the token invalid without running its callback.
- (void)markAsInvalid;

@end

NS_ASSUME_NONNULL_END
