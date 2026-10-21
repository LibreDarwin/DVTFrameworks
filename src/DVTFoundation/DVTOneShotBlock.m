//
//  DVTOneShotBlock.m
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

#import "DVTOneShotBlock.h"

@implementation DVTOneShotBlock {
    void (^_callbackBlock)(void);
    BOOL _isInvalid;
}

+ (instancetype)oneShotBlockWithCallback:(void (^)(void))callback
{
    return [[self alloc] initWithCallbackBlock:callback];
}

- (instancetype)initWithCallbackBlock:(void (^)(void))block
{
    self = [super init];
    if (self) {
        _callbackBlock = [block copy];
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
    /* The original reads, retains, and invokes the block before clearing the
       ivar, so the callback still sees itself as installed while it runs. */
    void (^callback)(void) = _callbackBlock;
    if (callback) {
        callback();
    }
    _callbackBlock = nil;
}

- (void)invalidate
{
    if (!self.isValid) {
        return;
    }
    _isInvalid = YES;
    [self primitiveInvalidate];
}

@end
