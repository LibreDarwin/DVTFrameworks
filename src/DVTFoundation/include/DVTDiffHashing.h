//
//  DVTDiffHashing.h
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

#ifndef DVT_DIFF_HASHING_H
#define DVT_DIFF_HASHING_H

#import <Foundation/Foundation.h>
#include <stdint.h>

#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Computes the CRC-32 checksum of the UTF-16 code units in a range of a string.

 The diff machinery uses this as the per-line hash when comparing two versions
 of a document; a pair of lines whose checksums match are then confirmed by a
 direct character comparison. The result is reproducible from the string's
 UTF-16 code units (little-endian on the platforms this library targets), so
 `DVTStringGetCRC32Checksum(string, 0, string.length)` equals the CRC-32 of
 `[string dataUsingEncoding:NSUTF16LittleEndian]`.
 */
DVT_EXTERN NSUInteger DVTStringGetCRC32Checksum(NSString *string, NSUInteger startIndex, NSUInteger length);

/**
 The cached FNV hash pair for one diff.

 The diff token store keeps the modified and original line hashes it has already
 computed so repeated comparisons do not recompute them. The hash buffers are
 owned by the instance: a setter frees the previous buffer before installing the
 replacement, clearing installs NULL, and -copyWithZone: duplicates the buffers
 rather than sharing them. Pass only buffers obtained from malloc (or NULL) to a
 setter.
 */
@interface DVTDiffFNVHashCache : NSObject <NSCopying>

@property(nonatomic, nullable) uint64_t *modifiedFNVHash;
@property(nonatomic) NSUInteger modifiedFNVHashLength;
@property(nonatomic, nullable) uint64_t *originalFNVHash;
@property(nonatomic) NSUInteger originalFNVHashLength;

@end

/**
 A structural hash of the receiver, stable across the platforms this library
 targets.

 The composite collection types fold their members in, and every method passes
 `dataSource` through to the members it hashes, but the primitive hashers
 (NSString, NSData, NSNumber) ignore it. An NSString hashes to the CRC-32 of
 its UTF-16 code units, an NSData to the CRC-32 of its raw bytes, an NSNumber to
 its unsignedIntegerValue, and the collection classes to the sum of the hashes
 of their members (keys and values for NSDictionary), so the result does not
 depend on enumeration order.
 */
@interface NSArray (DVTDiffHashing)
- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource;
@end

@interface NSData (DVTDiffHashing)
- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource;
@end

@interface NSDictionary (DVTDiffHashing)
- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource;
@end

@interface NSNumber (DVTDiffHashing)
- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource;
@end

@interface NSString (DVTDiffHashing)
- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource;
@end

NS_ASSUME_NONNULL_END

#endif /* DVT_DIFF_HASHING_H */