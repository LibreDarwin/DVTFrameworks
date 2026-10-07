//
//  DVTCodingAdditions.m
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

#import "DVTCodingAdditions.h"

@implementation NSCoder (DVTCodingAdditions)
- (NSData *_Nullable)dvt_decodeDataForKey:(NSString *)key {
    return [self decodeObjectOfClass:[NSData class] forKey:key];
}

- (NSNumber *_Nullable)dvt_decodeNumberForKey:(NSString *)key {
    return [self decodeObjectOfClass:[NSNumber class] forKey:key];
}

- (NSString *_Nullable)dvt_decodeStringForKey:(NSString *)key {
    return [self decodeObjectOfClass:[NSString class] forKey:key];
}

- (NSURL *_Nullable)dvt_decodeURLForKey:(NSString *)key {
    return [self decodeObjectOfClass:[NSURL class] forKey:key];
}

- (NSValue *_Nullable)dvt_decodeValueForKey:(NSString *)key {
    return [self decodeObjectOfClass:[NSValue class] forKey:key];
}
@end