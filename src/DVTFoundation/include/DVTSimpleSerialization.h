//
//  DVTSimpleSerialization.h
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

#ifndef DVT_SIMPLE_SERIALIZATION_H
#define DVT_SIMPLE_SERIALIZATION_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A minimal coder-shaped serialization protocol used by DVTFoundation in place of
 `NSSecureCoding`.

 It mirrors `NSCoding`'s two halves exactly, and a `DVTSimpleSerialization` is
 interchangeable with an `NSCoding` conformer as far as `NSKeyedArchiver` and
 `NSKeyedUnarchiver` are concerned: only the selector names differ.
 */
@protocol DVTSimpleSerialization <NSObject>

/**
 Reads the receiver's state out of `deserializer`.

 `initWithCoder:` and this method are two spellings of the same operation; a
 class that implements one is expected to implement the other in terms of it.
 Returning `nil` indicates that `deserializer` did not describe a usable
 instance.
 */
- (nullable instancetype)dvt_initFromDeserializer:(NSCoder *)deserializer;

/**
 Writes the receiver's state into `serializer`.

 The counterpart of `-dvt_initFromDeserializer:`.
 */
- (void)dvt_writeToSerializer:(NSCoder *)serializer;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_SIMPLE_SERIALIZATION_H */
