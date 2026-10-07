//
//  DVTCodingAdditions.h
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

#ifndef DVT_CODING_ADDITIONS_H
#define DVT_CODING_ADDITIONS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Conveniences for secure unarchiving the handful of value and container types
 DVTFoundation regularly decodes from keyed archives.

 Each method is a thin wrapper around `decodeObjectOfClass:forKey:` restricted
 to a single class, so `NSKeyedUnarchiver` fails safe under `NSSecureCoding`
 without callers having to spell out the class at every call site.
 */
@interface NSCoder (DVTCodingAdditions)

- (NSData *_Nullable)dvt_decodeDataForKey:(NSString *)key;
- (NSNumber *_Nullable)dvt_decodeNumberForKey:(NSString *)key;
- (NSString *_Nullable)dvt_decodeStringForKey:(NSString *)key;
- (NSURL *_Nullable)dvt_decodeURLForKey:(NSString *)key;
- (NSValue *_Nullable)dvt_decodeValueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END

#endif /* DVT_CODING_ADDITIONS_H */