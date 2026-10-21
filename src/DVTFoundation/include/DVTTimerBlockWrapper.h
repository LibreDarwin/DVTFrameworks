//
//  DVTTimerBlockWrapper.h
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

#ifndef DVT_TIMER_BLOCK_WRAPPER_H
#define DVT_TIMER_BLOCK_WRAPPER_H

#import <Foundation/Foundation.h>

#import "DVTCancellable.h"

NS_ASSUME_NONNULL_BEGIN

/**
 A scheduled timer whose callback is a block, exposed as a cancellable token.

 `+[NSTimer dvt_scheduledTimerWithTimeInterval:repeats:handler:]` vends these;
 the `NSTimer` receiver of that category method is only a namespace, and the
 answer is a wrapper rather than a timer.

 The wrapper owns the scheduled `NSTimer` and a copy of the handler. The timer
 targets the wrapper with `-fire:`, which invokes the handler with no arguments.
 Cancelling invalidates the timer and drops the handler; a cancelled wrapper
 never invokes it again.
 */
@interface DVTTimerBlockWrapper : NSObject <DVTCancellable>

/**
  Creates a scheduled timer and stores a copy of `handler`.

  The timer is scheduled on the current run loop in the default mode, with the
  wrapper as its target and `-fire:` as its selector, so the wrapper must stay
  alive for the timer to deliver. A non-repeating timer that has fired is not
  the same as a cancelled wrapper: the handler stays until `-cancel` is sent.

  @param interval The timer's interval, in seconds.
  @param repeats Whether the timer reschedules itself after firing.
  @param handler The callback, invoked with no arguments each time the timer
  fires.
  */
- (instancetype)initWithTimeInterval:(NSTimeInterval)interval
                             repeats:(BOOL)repeats
                             handler:(void (^)(void))handler;

/// `YES` once `-cancel` has been sent; the handler's absence is the state.
@property (readonly, getter=isCancelled) BOOL cancelled;

/**
  Invalidates the timer and releases both the timer and the handler, so the
  block is not invoked again. Cancelling twice is harmless.
  */
- (void)cancel;

/**
  The timer's callback: invokes the stored handler.

  The binary reads the handler and calls it without a nil check, and this port
  keeps that: after `-cancel` the timer is invalidated, so the only way to
  arrive here with no handler is to send `-fire:` directly after cancelling.

  @param timer The timer that fired; unused.
  */
- (void)fire:(nullable NSTimer *)timer;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_TIMER_BLOCK_WRAPPER_H */
