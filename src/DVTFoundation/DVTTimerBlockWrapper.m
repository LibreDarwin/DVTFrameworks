//
//  DVTTimerBlockWrapper.m
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

#import "DVTTimerBlockWrapper.h"

#import "NSTimer+DVTNSTimerAdditions.h"

@implementation DVTTimerBlockWrapper {
    NSTimer *_timer;
    void (^_handler)(void);
}

- (instancetype)initWithTimeInterval:(NSTimeInterval)interval
                             repeats:(BOOL)repeats
                             handler:(void (^)(void))handler
{
    self = [super init];
    if (self) {
        /* The timer is scheduled before the handler is stored, as in the
           binary. It cannot fire until the run loop next runs, by which point
           the handler is in place. */
        _timer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                  target:self
                                                selector:@selector(fire:)
                                                userInfo:nil
                                                 repeats:repeats];
        _handler = [handler copy];
    }
    return self;
}

- (BOOL)isCancelled
{
    /* Cancelling drops the handler, so its absence is the whole answer. */
    return _handler == nil;
}

- (void)cancel
{
    [_timer invalidate];
    _timer = nil;
    _handler = nil;
}

- (void)fire:(NSTimer *)timer
{
    /* No nil check, as in the binary: a cancelled wrapper's timer is already
       invalidated, so this is only reachable by sending -fire: directly. */
    _handler();
}

@end

@implementation NSTimer (DVTNSTimerAdditions)

+ (id)dvt_scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                 repeats:(BOOL)repeats
                                 handler:(void (^)(void))handler
{
    return [[DVTTimerBlockWrapper alloc] initWithTimeInterval:interval
                                                      repeats:repeats
                                                      handler:handler];
}

@end
