//
//  DVTDispatch.h
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
#import <dispatch/dispatch.h>
#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Creates a queue whose concurrency and quality of service are both explicit.

 The argument order is not the one the GCD function itself uses, and `serial`
 is the inverse of what it reads like: a non-zero `serial` yields a serial
 queue, zero yields a concurrent one. `attributes` is accepted for
 source-compatibility and ignored; Apple never reads it either.

 @param serial      Non-zero for a serial queue, zero for a concurrent queue.
 @param qos         Quality of service applied to the queue's attributes.
 @param attributes  Unused.
 @param label       Queue label, retained by GCD and readable back with
                    `dispatch_queue_get_label`.
 @return A new queue, or `NULL` only if GCD rejects the request.
 */
DVT_EXTERN dispatch_queue_t _Nullable DVTDispatchCreateQueue(BOOL serial,
                                                             qos_class_t qos,
                                                             uintptr_t attributes,
                                                             const char *label);

/** Enqueues `block` on `queue`. */
DVT_EXTERN void DVTDispatchAsync(dispatch_queue_t queue, dispatch_block_t block);

/** Enqueues `block` on `queue` and waits for it to finish. */
DVT_EXTERN void DVTDispatchSync(dispatch_queue_t queue, dispatch_block_t block);

/**
 Enqueues `block` on `queue` once `when` has passed.

 @param when   A `dispatch_time_t` deadline.
 @param queue  Queue to run on.
 @param block  Block to run.
 */
DVT_EXTERN void DVTDispatchAfter(dispatch_time_t when,
                                 dispatch_queue_t queue,
                                 dispatch_block_t block);

/** Enqueues `block` as a barrier on `queue`. */
DVT_EXTERN void DVTDispatchBarrierAsync(dispatch_queue_t queue, dispatch_block_t block);

/** Runs `block` on `queue` once every task in `group` has completed. */
DVT_EXTERN void DVTDispatchGroupNotify(dispatch_group_t group,
                                       dispatch_queue_t queue,
                                       dispatch_block_t block);

/** Installs `handler` as the event handler of `source`. */
DVT_EXTERN void DVTDispatchSourceSetEventHandler(dispatch_source_t source,
                                                 dispatch_block_t handler);

/**
 Installs `handler` as the cancellation handler of `source`.

 `group` is submitted to rather than the source's own queue, which is what lets
 several sources share one cancellation barrier.
 */
DVT_EXTERN void DVTDispatchSourceSetCancelHandler(dispatch_source_t source,
                                                  dispatch_block_t handler,
                                                  dispatch_group_t group);

NS_ASSUME_NONNULL_END
