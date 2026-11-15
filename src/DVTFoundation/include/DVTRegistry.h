/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTFoundation's DVTRegistry.
 *
 * Deviation from Apple's implementation: DVTFoundation's DVTDispatchLock is
 * not available in this tree, so the registry serialises access with an
 * NSRecursiveLock instead.  The observable behaviour of
 * -registerObject:collisionHandler: is unchanged.
 */

#ifndef DVTFOUNDATION_DVTREGISTRY_H
#define DVTFOUNDATION_DVTREGISTRY_H

#import <Foundation/Foundation.h>

#import "DVTRegistrable.h"

@interface DVTRegistry : NSObject {
    id _lock;
    NSMutableDictionary *_registeredObjectsByIdentifier;
    NSMutableDictionary *_registeredAliasesByLowercaseIdentifier;
    NSString *_debugName;
}

- (id)initWithDebugName:(NSString *)debugName;
- (id)init;

- (NSString *)debugName;
- (id)lock;

/* Returns YES when the object was registered (or replaced an existing
 * object), NO when the collision handler declined the registration.  The
 * handler receives the registry, the already registered object and the new
 * object. */
- (BOOL)registerObject:(id)object collisionHandler:(BOOL (^)(DVTRegistry *registry, id existingObject, id newObject))collisionHandler;

- (id)objectForIdentifier:(NSString *)identifier;
- (NSArray *)allRegisteredObjects;

- (void)didRegisterObject:(id)object replacingObject:(id)existingObject;

@end

#endif	/* DVTFOUNDATION_DVTREGISTRY_H */
