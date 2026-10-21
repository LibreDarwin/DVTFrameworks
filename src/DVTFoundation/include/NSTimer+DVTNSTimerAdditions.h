//
//  NSTimer+DVTNSTimerAdditions.h
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

#ifndef NS_TIMER_DVT_TIMER_ADDITIONS_H
#define NS_TIMER_DVT_TIMER_ADDITIONS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A scheduled timer with a block callback.

 The receiver is only a namespace: the answer is a `DVTTimerBlockWrapper`, a
 cancellable token that owns the timer and a copy of `handler` (declared in
 `DVTTimerBlockWrapper.h`). The return type stays `id` because that is how the
 category is recorded in the binary.

 The timer is scheduled on the current run loop in the default mode.
 */
@interface NSTimer (DVTNSTimerAdditions)

/**
  Schedules a timer that invokes `handler` with no arguments.

  @param interval The timer's interval, in seconds.
  @param repeats Whether the timer reschedules itself after firing.
  @param handler The callback to copy and invoke.
  @return A new `DVTTimerBlockWrapper`; send it `-cancel` to stop the timer and
  release the handler.
  */
+ (id)dvt_scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                 repeats:(BOOL)repeats
                                 handler:(void (^)(void))handler;

@end

NS_ASSUME_NONNULL_END

#endif /* NS_TIMER_DVT_TIMER_ADDITIONS_H */
