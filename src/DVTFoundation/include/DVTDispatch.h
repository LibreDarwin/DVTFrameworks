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

/**
 Atomically advances a dispatch-block generation counter and reports the new value.

 The counter is a plain 32-bit word in caller-owned storage rather than a
 dispatch object, so the whole function is two instructions. It returns the value
 *after* the increment, not the one it replaced: starting from zero, the first
 call returns 1.

 @param counter  Address of the word to advance. Held by the caller.
 @return The incremented value.
 */
DVT_EXTERN uint32_t DVTDispatchBlockGenerationIncrement(uint32_t *counter);

/**
 Reports whether a dispatch-block generation is still the current one.

 Probe-verified to answer YES when `*counter` equals `generation` and NO when it
 does not. The condition code in the shipped binary decodes to NE, which would
 give the opposite answer, so the comparison was taken from observed behaviour
 on Apple's own framework rather than from the disassembly. Getting this backwards
 would silently discard every block whose generation is still valid.

 @param counter     Address of the generation counter.
 @param generation  Generation to test.
 @return YES if `generation` is current.
 */
DVT_EXTERN BOOL DVTDispatchBlockGenerationIsCurrent(const uint32_t *counter,
                                                    uint32_t generation);

/**
 A queue that DVT built to run on the main thread, tagged so the block
 performers can recognise it.

 The queue is created at user-initiated priority and then retargeted at the main
 queue, so its work runs on the main thread but keeps its own queue identity,
 label and priority. That identity is the point: it is what lets
 `DVTAsyncPerformBlock` tell a genuine main-thread queue apart from an ordinary
 one and route it through the run loop instead of dispatching onto a queue that
 would only drain if something else called `dispatch_main()`.

 @param label  Label for the new queue.
 @return The new queue, or `NULL` if GCD rejects the request.
 */
DVT_EXTERN dispatch_queue_t _Nullable _DVTDispatchGetMainQueue(const char *label);

/**
 Reports whether `queue` is one of the main-thread queues built by
 `_DVTDispatchGetMainQueue`.

 True for the real main queue and for the queues built by
 `_DVTDispatchGetMainQueue`, and false for every other queue. The real main
 queue is recognised by a tag attached to it on first use, so this is a
 question of provenance rather than a pointer comparison.

 A `NULL` queue returns `NO` here. Apple traps on it, by way of an assertion in
 `DVTConcurrencyUtilities.m`, and the argument is not documented as nullable, so
 nothing should be passing one.
 */
DVT_EXTERN BOOL _DVTDispatchIsMainQueue(dispatch_queue_t _Nullable queue);

/**
 Enqueues `block` on `queue`, routing through the main run loop when `queue` is
 a main-thread queue from `_DVTDispatchGetMainQueue`.

 An ordinary queue is used directly, so the block is submitted through
 `DVTDispatchAsync` and inherits its diagnostic grouping. A main-thread queue
 cannot be dispatched onto directly, because nothing drains it, so the block is
 handed to the main run loop in common modes and the run loop is woken.

 @param queue  Queue to run on.
 @param block  Block to run.
 */
DVT_EXTERN void DVTAsyncPerformBlock(dispatch_queue_t queue, dispatch_block_t block);

/**
 Runs `block` on `queue` and does not return until it has finished.

 An ordinary queue is used directly, through `DVTDispatchSync`. A main-thread
 queue is handed to the main run loop and waited on with a semaphore, since
 dispatching onto one and waiting would never complete.

 Called from the main thread with a main-thread queue, this cannot return: the
 block is waiting for a run loop that the calling thread is itself blocking.
 Call it from another thread in that case.

 @param queue  Queue to run on.
 @param block  Block to run.
 */
DVT_EXTERN void DVTSyncPerformBlock(dispatch_queue_t queue, dispatch_block_t block);

/**
 Enqueues `block` as an operation on `queue`.

 The main operation queue cannot be dispatched onto directly, so blocks bound
 for it are handed to the main run loop instead. Any other queue takes the
 operation as given, which is what makes the block cancellable and dependent in
 the way `NSOperationQueue` callers expect.

 A `NULL` queue is ignored. Apple traps on it, and the argument is not
 documented as nullable.

 @param queue  Operation queue to run on.
 @param block  Block to run.
 */
DVT_EXTERN void DVTAsyncPerformBlockOnOperationQueue(NSOperationQueue *_Nullable queue,
                                                     dispatch_block_t block);

NS_ASSUME_NONNULL_END
