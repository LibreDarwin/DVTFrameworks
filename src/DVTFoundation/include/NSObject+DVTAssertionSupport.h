/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of the part of DVTFoundation's
 * NSObject (DVTAssertionSupport) category that the macro foundation needs in
 * order to format its assertion messages.
 *
 * Deviations from Apple's implementation: only +descriptionForAssertionMessage
 * and -descriptionForAssertionMessage are provided so far; the rest of the
 * category (serialization, invalidation, KVO helpers, ...) belongs to a later
 * stage and is deliberately absent.
 *
 * -dvt_broadcast: and -dvt_broadcast:userInfo: are not declared or implemented
 * yet: they forward to DVTBroadcastCenter, which is a separate subsystem.  The
 * macro definition table declares the one it calls in its own implementation
 * file until then.
 */

#ifndef DVTFOUNDATION_NSOBJECT_DVTASSERTIONSUPPORT_H
#define DVTFOUNDATION_NSOBJECT_DVTASSERTIONSUPPORT_H

#import <Foundation/Foundation.h>

@interface NSObject (DVTAssertionSupport)

+ (id)descriptionForAssertionMessage;
- (id)descriptionForAssertionMessage;

@end

#endif	/* DVTFOUNDATION_NSOBJECT_DVTASSERTIONSUPPORT_H */
