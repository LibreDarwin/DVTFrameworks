//
//  DVTDiffHashing.m
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

#import "DVTDiffHashing.h"

#import <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

NSUInteger DVTStringGetCRC32Checksum(NSString *string, NSUInteger startIndex, NSUInteger length)
{
    UniChar buffer[32];
    uLong crc = crc32(0L, Z_NULL, 0);
    NSUInteger endIndex = startIndex + length;
    for (NSUInteger index = startIndex; index < endIndex; index += 32) {
        NSUInteger chunkSize = endIndex - index;
        if (chunkSize > 32) {
            chunkSize = 32;
        }
        CFStringGetCharacters((__bridge CFStringRef)string, CFRangeMake(index, chunkSize), buffer);
        crc = crc32(crc, (const Bytef *)buffer, (uInt)(chunkSize * 2));
    }
    return (NSUInteger)crc;
}

@implementation DVTDiffFNVHashCache {
    uint64_t *_modifiedFNVHash;
    NSUInteger _modifiedFNVHashLength;
    uint64_t *_originalFNVHash;
    NSUInteger _originalFNVHashLength;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setModifiedFNVHash:NULL];
        [self setModifiedFNVHashLength:0];
        [self setOriginalFNVHash:NULL];
        [self setOriginalFNVHashLength:0];
    }
    return self;
}

- (void)dealloc
{
    if (_modifiedFNVHash) {
        free(_modifiedFNVHash);
        _modifiedFNVHash = NULL;
        _modifiedFNVHashLength = 0;
    }
    if (_originalFNVHash) {
        free(_originalFNVHash);
        _originalFNVHash = NULL;
        _originalFNVHashLength = 0;
    }
}

- (uint64_t *)modifiedFNVHash
{
    return _modifiedFNVHash;
}

- (void)setModifiedFNVHash:(uint64_t *)modifiedFNVHash
{
    if (_modifiedFNVHash) {
        free(_modifiedFNVHash);
    }
    _modifiedFNVHash = modifiedFNVHash;
}

- (NSUInteger)modifiedFNVHashLength
{
    return _modifiedFNVHashLength;
}

- (void)setModifiedFNVHashLength:(NSUInteger)modifiedFNVHashLength
{
    _modifiedFNVHashLength = modifiedFNVHashLength;
}

- (uint64_t *)originalFNVHash
{
    return _originalFNVHash;
}

- (void)setOriginalFNVHash:(uint64_t *)originalFNVHash
{
    if (_originalFNVHash) {
        free(_originalFNVHash);
    }
    _originalFNVHash = originalFNVHash;
}

- (NSUInteger)originalFNVHashLength
{
    return _originalFNVHashLength;
}

- (void)setOriginalFNVHashLength:(NSUInteger)originalFNVHashLength
{
    _originalFNVHashLength = originalFNVHashLength;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    DVTDiffFNVHashCache *copy = [[[self class] allocWithZone:zone] init];
    if (copy == nil) {
        return nil;
    }
    if (_modifiedFNVHash != NULL) {
        NSUInteger byteCount = _modifiedFNVHashLength * sizeof(uint64_t);
        uint64_t *hash = malloc(byteCount);
        memcpy(hash, _modifiedFNVHash, byteCount);
        copy->_modifiedFNVHash = hash;
        copy->_modifiedFNVHashLength = _modifiedFNVHashLength;
    }
    if (_originalFNVHash != NULL) {
        NSUInteger byteCount = _originalFNVHashLength * sizeof(uint64_t);
        uint64_t *hash = malloc(byteCount);
        memcpy(hash, _originalFNVHash, byteCount);
        copy->_originalFNVHash = hash;
        copy->_originalFNVHashLength = _originalFNVHashLength;
    }
    return copy;
}

@end

/*
 The dictionary hasher performs its accumulation through a captured value rather
 than through this object; the class exists in Apple's binary (it is referenced
 only by its own initializer) and is implemented here for symbol parity.
 */
@interface _DVTDiffHashingDictionaryDiffHashContext : NSObject
@property(atomic, strong) id dataSource;
@property(nonatomic) NSUInteger diffHash;
- (instancetype)initWithDataSource:(id)dataSource diffHash:(NSUInteger)diffHash;
@end

@implementation _DVTDiffHashingDictionaryDiffHashContext

- (instancetype)initWithDataSource:(id)dataSource diffHash:(NSUInteger)diffHash
{
    self = [super init];
    if (self) {
        _dataSource = dataSource;
        _diffHash = diffHash;
    }
    return self;
}

@end

@implementation NSArray (DVTDiffHashing)

- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource
{
    NSUInteger result = 0;
    for (id object in self) {
        result += [object dvt_diffHashForDataSource:dataSource];
    }
    return result;
}

@end

@implementation NSData (DVTDiffHashing)

- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource
{
    (void)dataSource;
    return (NSUInteger)crc32(crc32(0L, Z_NULL, 0), (const Bytef *)self.bytes, (uInt)self.length);
}

@end

@implementation NSDictionary (DVTDiffHashing)

- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource
{
    __block NSUInteger diffHash = 0;
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        (void)stop;
        diffHash += [object dvt_diffHashForDataSource:dataSource];
        diffHash += [key dvt_diffHashForDataSource:dataSource];
    }];
    return diffHash;
}

@end

@implementation NSNumber (DVTDiffHashing)

- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource
{
    (void)dataSource;
    return self.unsignedIntegerValue;
}

@end

@implementation NSString (DVTDiffHashing)

- (NSUInteger)dvt_diffHashForDataSource:(nullable id)dataSource
{
    (void)dataSource;
    return DVTStringGetCRC32Checksum(self, 0, self.length);
}

@end