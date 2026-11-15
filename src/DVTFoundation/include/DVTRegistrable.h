/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTFoundation's DVTRegistrable protocol.
 */

#ifndef DVTFOUNDATION_DVTREGISTRABLE_H
#define DVTFOUNDATION_DVTREGISTRABLE_H

#import <Foundation/Foundation.h>

@class DVTVersion;

@protocol DVTRegistrable <NSObject>

- (NSString *)identifier;

@optional
- (NSArray *)aliases;
- (DVTVersion *)version;

@end

#endif	/* DVTFOUNDATION_DVTREGISTRABLE_H */
