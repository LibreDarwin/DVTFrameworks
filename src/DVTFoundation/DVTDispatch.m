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
