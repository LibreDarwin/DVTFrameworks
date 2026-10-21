//
//  DVTCancellable.h
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

#ifndef DVT_CANCELLABLE_H
#define DVT_CANCELLABLE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A token that can be cancelled.

 The protocol records both spellings of the state question -- the `cancelled`
 property and the explicit `-isCancelled` method, with the property reading
 through the method -- and the binary's protocol metadata lists both.
 `DVTTimerBlockWrapper` is one conformer.
 */
@protocol DVTCancellable <NSObject>

/// `YES` once the receiver has been cancelled.
@property (readonly, getter=isCancelled) BOOL cancelled;

/// Cancels the receiver. Cancelling an already-cancelled token is harmless.
- (void)cancel;

/// The method spelling of the `cancelled` property.
- (BOOL)isCancelled;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_CANCELLABLE_H */
