/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 */

#import "DVTMacroNameRegistry.h"
#import "DVTMacroNameRegistryRegistration.h"

static void
DVTMacroNameRegistryCheckMacroName(id macroName)
{
	if (macroName == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it is nil", @"macroName"];
	}
	if (CFGetTypeID((__bridge CFTypeRef)macroName) != CFStringGetTypeID()) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it is %@", @"macroName", macroName];
	}
	if ([macroName length] == 0) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it is %@", @"macroName", macroName];
	}
}

@implementation DVTMacroNameRegistry

- (id)initWithDebugName:(NSString *)name defaultIsListType:(BOOL)isListType
{
	self = [super initWithDebugName:name];
	if (self != nil) {
		_defaultIsListType = isListType;
	}
	return (self);
}

- (id)initWithDebugName:(NSString *)name
{
	return ([self initWithDebugName:name defaultIsListType:YES]);
}

- (id)init
{
	return ([self initWithDebugName:nil]);
}

- (BOOL)defaultIsListType
{
	return (_defaultIsListType);
}

- (void)registerMacroName:(NSString *)name isListType:(BOOL)isListType
{
	DVTMacroNameRegistryRegistration *registration;

	DVTMacroNameRegistryCheckMacroName(name);
	registration = [[DVTMacroNameRegistryRegistration alloc] initWithMacroName:name isListType:isListType];
	/* The first registration of a name wins. */
	[self registerObject:registration collisionHandler:^BOOL(DVTRegistry *registry, id existingObject, id newObject) {
		(void)registry;
		(void)existingObject;
		(void)newObject;
		return (NO);
	}];
}

- (BOOL)macroIsListType:(NSString *)name
{
	DVTMacroNameRegistryRegistration *registration;

	DVTMacroNameRegistryCheckMacroName(name);
	registration = [self objectForIdentifier:name];
	if (registration == nil) {
		return (_defaultIsListType);
	}
	return ([registration isListType]);
}

@end

@implementation DVTMacroNameRegistryRegistration

- (id)initWithMacroName:(NSString *)name isListType:(BOOL)isListType
{
	self = [super init];
	if (self != nil) {
		_macroName = [name copy];
		_listType = isListType;
	}
	return (self);
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_macroName release];
	[super dealloc];
}
#endif

- (NSString *)macroName
{
	return (_macroName);
}

- (BOOL)isListType
{
	return (_listType);
}

- (NSString *)identifier
{
	return (_macroName);
}

- (NSString *)description
{
	return ([NSString stringWithFormat:@"<%@:%p: %@, listType=%@>",
		   NSStringFromClass([self class]), (__bridge void *)self,
		   _macroName, _listType ? @"YES" : @"NO"]);
}

@end
