//
//  DVTDispatch.m
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

#import "DVTDispatch.h"

dispatch_queue_t DVTDispatchCreateQueue(BOOL serial,
                                       qos_class_t qos,
                                       uintptr_t attributes,
                                       const char *label)
{
    (void)attributes;
    // A non-zero `serial` selects a null attribute, which is how GCD spells
    // "serial"; zero selects the concurrent attribute explicitly. The
    // autorelease frequency is then forced to work-item either way, which is
    // what keeps the two branches differing only in concurrency.
    dispatch_queue_attr_t attr = serial ? DISPATCH_QUEUE_SERIAL
                                        : DISPATCH_QUEUE_CONCURRENT;
    attr = dispatch_queue_attr_make_with_autorelease_frequency(attr, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM);
    attr = dispatch_queue_attr_make_with_qos_class(attr, qos, 0);
    return dispatch_queue_create(label, attr);
}

void DVTDispatchAsync(dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_async(queue, block);
}

void DVTDispatchSync(dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_sync(queue, block);
}

void DVTDispatchAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_after(when, queue, block);
}

void DVTDispatchBarrierAsync(dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_barrier_async(queue, block);
}

void DVTDispatchGroupNotify(dispatch_group_t group, dispatch_queue_t queue, dispatch_block_t block)
{
    dispatch_group_notify(group, queue, block);
}

void DVTDispatchSourceSetEventHandler(dispatch_source_t source, dispatch_block_t handler)
{
    dispatch_source_set_event_handler(source, handler);
}

void DVTDispatchSourceSetCancelHandler(dispatch_source_t source,
                                       dispatch_block_t handler,
                                       dispatch_group_t group)
{
    (void)group;
    dispatch_source_set_cancel_handler(source, handler);
}

uint32_t DVTDispatchBlockGenerationIncrement(uint32_t *counter)
{
    /* Post-increment: the caller gets the value the counter now holds, so that a
       generation can be stamped on the block it is about to dispatch and still be
       compared against later. LDADD with acquire-release ordering, matching the
       release side and keeping the paired load from being hoisted above it. */
    return __atomic_fetch_add(counter, 1, __ATOMIC_ACQ_REL) + 1;
}

BOOL DVTDispatchBlockGenerationIsCurrent(const uint32_t *counter, uint32_t generation)
{
    /* Acquire, so that whatever the dispatching thread wrote before advancing the
       generation is visible to whichever thread later reads it back. */
    return __atomic_load_n(counter, __ATOMIC_ACQUIRE) == generation;
}

/* Tag applied to the queues _DVTDispatchGetMainQueue builds. A queue-specific
   value rather than a queue comparison, because the point is to recognise the
   queue by provenance: it is a stand-in for the main thread, not the main
   dispatch queue itself. */
static const void *DVTDispatchMainQueueKey = &DVTDispatchMainQueueKey;

dispatch_queue_t _DVTDispatchGetMainQueue(const char *label)
{
    /* User-initiated: the queue exists only to be retargeted at the main queue,
       so it wants the highest of the standard priorities, not main-queue default. */
    dispatch_queue_attr_t attributes =
        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                QOS_CLASS_USER_INITIATED, 0);
    dispatch_queue_t queue = dispatch_queue_create(label, attributes);
    if (queue == NULL) {
        return NULL;
    }
    dispatch_set_target_queue(queue, dispatch_get_main_queue());
    dispatch_queue_set_specific(queue, DVTDispatchMainQueueKey, (void *)1, NULL);
    return queue;
}

BOOL _DVTDispatchIsMainQueue(dispatch_queue_t queue)
{
    if (queue == NULL) {
        return NO;
    }
    /* The real main queue is tagged once, on first use, rather than at load time:
       touching it from a load-time initialiser would be reaching into libdispatch
       before it is necessarily ready. Lazy tagging also means the tag is only
       ever attached from a thread that has already called in here. */
    static dispatch_once_t tagMainQueueOnce;
    dispatch_once(&tagMainQueueOnce, ^{
        dispatch_queue_set_specific(dispatch_get_main_queue(), DVTDispatchMainQueueKey,
                                    (void *)1, NULL);
    });
    return dispatch_queue_get_specific(queue, DVTDispatchMainQueueKey) != NULL;
}

/* Not exported by Apple; local to this file for the same reason it is local
   there. The label is only ever used for diagnostics, which this reconstruction
   does not perform, so it is accepted and dropped. */
static void DVTAsyncPerformBlockOnMainRunLoop(const char *label, dispatch_block_t block)
{
    (void)label;
    CFRunLoopRef runLoop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(runLoop, kCFRunLoopCommonModes, ^{
        block();
    });
    CFRunLoopWakeUp(runLoop);
}

void DVTAsyncPerformBlock(dispatch_queue_t queue, dispatch_block_t block)
{
    if (_DVTDispatchIsMainQueue(queue)) {
        DVTAsyncPerformBlockOnMainRunLoop(dispatch_queue_get_label(queue), block);
    } else {
        DVTDispatchAsync(queue, block);
    }
}

void DVTSyncPerformBlock(dispatch_queue_t queue, dispatch_block_t block)
{
    if (!_DVTDispatchIsMainQueue(queue)) {
        DVTDispatchSync(queue, block);
        return;
    }
    /* The block has to reach a run loop that is being serviced by some other
       thread, because this one is about to stop and wait. */
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    CFRunLoopRef runLoop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(runLoop, kCFRunLoopCommonModes, ^{
        /* Signalled from a finally, not after the call: an exception thrown by
           the caller's block would otherwise unwind out of the run loop and
           leave whoever is waiting here asleep forever. */
        @try {
            block();
        } @finally {
            dispatch_semaphore_signal(finished);
        }
    });
    CFRunLoopWakeUp(runLoop);
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
}

void DVTAsyncPerformBlockOnOperationQueue(NSOperationQueue *queue, dispatch_block_t block)
{
    if (queue == nil) {
        return;
    }
    if ([queue isEqual:[NSOperationQueue mainQueue]]) {
        DVTAsyncPerformBlockOnMainRunLoop(NULL, block);
        return;
    }
    /* Apple builds the operation with a private DVTOperation subclass, which
       adds cancellation-block bookkeeping, decides whether cancellation should
       hop to the main thread, and drops dependencies once finished. None of that
       is scheduling, so the public block-operation factory stands in and the
       diagnostic behaviour is left out along with the rest. */
    [queue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        block();
    }]];
}
