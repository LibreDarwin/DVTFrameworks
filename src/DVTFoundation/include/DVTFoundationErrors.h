//
//  DVTFoundationErrors.h
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

#ifndef DVT_FOUNDATION_ERRORS_H
#define DVT_FOUNDATION_ERRORS_H

#import <Foundation/NSString.h>

#include "DVTDefines.h"

/**
 The `NSError` domain for errors originating in DVTFoundation itself.

 IDETools resolves this symbol with `dlsym` before it relies on it, so it has to
 stay an exported data symbol rather than becoming an inline or hidden one.
 */
DVT_EXTERN NSString *const DVTFoundationErrorDomain;

/**
 The `NSError` domain for device-preparation failures.

 The binary exports the symbol and spells the domain `com.apple.dt.deviceprep`.
 `-dvt_fillDeviceOperationAnalyticsDictionary:` treats errors in it as device
 failures worth recording, so it is exported here too.
 */
DVT_EXTERN NSString *const DVTDevicePreparationErrorDomain;

#endif /* DVT_FOUNDATION_ERRORS_H */
