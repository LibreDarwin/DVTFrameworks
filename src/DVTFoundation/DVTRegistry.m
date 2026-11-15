/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 */

#import "DVTRegistry.h"

static BOOL
DVTRegistryConformsToRegistrable(id object)
{
	return ([object conformsToProtocol:@protocol(DVTRegistrable)]);
}

static BOOL
DVTRegistryObjectHasEqualOrHigherVersion(id object, id existingObject)
{
	id objectVersion = nil;
	id existingVersion = nil;

	if ([object respondsToSelector:@selector(version)]) {
		objectVersion = [(id<DVTRegistrable>)object version];
	}
	if ([existingObject respondsToSelector:@selector(version)]) {
		existingVersion = [(id<DVTRegistrable>)existingObject version];
	}
	if (existingVersion == nil) {
		return (YES);
	}
	if (objectVersion == nil) {
		return (NO);
	}
	return ([objectVersion compare:existingVersion] != NSOrderedAscending);
}

@implementation DVTRegistry

- (id)initWithDebugName:(NSString *)debugName
{
	self = [super init];
	if (self != nil) {
		_lock = [[NSRecursiveLock alloc] init];
		_registeredObjectsByIdentifier = [[NSMutableDictionary alloc] init];
		_registeredAliasesByLowercaseIdentifier = [[NSMutableDictionary alloc] init];
		_debugName = [debugName copy];
	}
	return (self);
}

- (id)init
{
	return ([self initWithDebugName:nil]);
}

- (void)dealloc
{
#if !__has_feature(objc_arc)
	[_lock release];
	[_registeredObjectsByIdentifier release];
	[_registeredAliasesByLowercaseIdentifier release];
	[_debugName release];
	[super dealloc];
#endif
}

- (NSString *)debugName
{
	return (_debugName);
}

- (id)lock
{
	return (_lock);
}

- (BOOL)registerObject:(id)object collisionHandler:(BOOL (^)(DVTRegistry *, id, id))collisionHandler
{
	NSString *identifier;
	__block BOOL registered = NO;

	if (object == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-nil object, but it is nil", NSStringFromSelector(_cmd)];
	}
	if (!DVTRegistryConformsToRegistrable(object)) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be an object conforming to DVTRegistrable, but it is %@", NSStringFromSelector(_cmd), object];
	}
	identifier = [object identifier];
	if (identifier == nil || ![identifier isKindOfClass:[NSString class]] || [identifier length] == 0) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it is %@", @"identifier", identifier];
	}

	[(NSRecursiveLock *)_lock lock];
	{
		id existingObject = [_registeredObjectsByIdentifier objectForKey:identifier];
		BOOL shouldReplace = NO;

		if (existingObject == nil) {
			shouldReplace = YES;
		} else if (collisionHandler != nil) {
			shouldReplace = collisionHandler(self, existingObject, object);
		} else {
			shouldReplace = DVTRegistryObjectHasEqualOrHigherVersion(object, existingObject);
		}

		if (shouldReplace) {
			NSArray *aliases = nil;

			[_registeredObjectsByIdentifier setObject:object forKey:identifier];

			if ([object respondsToSelector:@selector(aliases)]) {
				aliases = [object aliases];
			}
			for (NSString *alias in aliases) {
				NSString *key;

				if (![alias isKindOfClass:[NSString class]]) {
					continue;
				}
				key = [alias lowercaseString];
				if ([_registeredAliasesByLowercaseIdentifier objectForKey:key] != nil &&
				    !DVTRegistryObjectHasEqualOrHigherVersion(object, [_registeredAliasesByLowercaseIdentifier objectForKey:key])) {
					continue;
				}
				[_registeredAliasesByLowercaseIdentifier setObject:object forKey:key];
			}

			[self didRegisterObject:object replacingObject:existingObject];
			registered = YES;
		}
	}
	[(NSRecursiveLock *)_lock unlock];

	return (registered);
}

- (id)objectForIdentifier:(NSString *)identifier
{
	id object;

	if (identifier == nil || ![identifier isKindOfClass:[NSString class]] || [identifier length] == 0) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it is %@", @"identifier", identifier];
	}

	[(NSRecursiveLock *)_lock lock];
	object = [_registeredObjectsByIdentifier objectForKey:identifier];
	if (object == nil) {
		object = [_registeredAliasesByLowercaseIdentifier objectForKey:[identifier lowercaseString]];
	}
	[(NSRecursiveLock *)_lock unlock];

	return (object);
}

- (NSArray *)allRegisteredObjects
{
	NSArray *objects;

	[(NSRecursiveLock *)_lock lock];
	objects = [_registeredObjectsByIdentifier allValues];
	[(NSRecursiveLock *)_lock unlock];

	return (objects);
}

- (void)didRegisterObject:(id)object replacingObject:(id)existingObject
{
	(void)object;
	(void)existingObject;
}

@end
