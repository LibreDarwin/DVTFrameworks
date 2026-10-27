//
//  NSURL+DVTSecurityAdditions.h
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

#ifndef NS_URL_DVT_SECURITY_ADDITIONS_H
#define NS_URL_DVT_SECURITY_ADDITIONS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The `SecProtocolType` a URL's scheme names.

 The binary compares scheme prefixes in a fixed order, so `https` is not read
 as `http` and `svn+ssh` is not read as `svn`. An unrecognised or absent scheme
 answers `0`.
 */
@interface NSURL (DVTSecurityAdditions)

/// The Security framework protocol type for the receiver's scheme, or `0`.
- (unsigned int)dvt_secProtocol;

@end

NS_ASSUME_NONNULL_END

#endif /* NS_URL_DVT_SECURITY_ADDITIONS_H */
