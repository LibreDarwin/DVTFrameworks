/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 */

#import "DVTMacroNameString.h"

static NSMutableDictionary *DVTMacroNameStringRegistry;
static NSLock *DVTMacroNameStringRegistryLock;
static unsigned long long DVTMacroNameStringNextRegistrationNumber;

@implementation DVTMacroNameString

+ (void)initialize
{
	if (self != [DVTMacroNameString class]) {
		return;
	}
	DVTMacroNameStringRegistry = [[NSMutableDictionary alloc] init];
	DVTMacroNameStringRegistryLock = [[NSLock alloc] init];
	DVTMacroNameStringNextRegistrationNumber = 1;
}

+ (id)macroNameStringForString:(id)string createIfNeeded:(BOOL)needed
{
	DVTMacroNameString *nameString;

	(void)needed;
	if (string == nil) {
		return (nil);
	}
	if ([string isKindOfClass:[DVTMacroNameString class]]) {
		return (string);
	}
	if (CFGetTypeID((__bridge CFTypeRef)string) != CFStringGetTypeID()) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should be a non-empty string, but it is %@", @"string", string];
	}

	[DVTMacroNameStringRegistryLock lock];
	nameString = [DVTMacroNameStringRegistry objectForKey:string];
	if (nameString == nil) {
		nameString = [[DVTMacroNameString alloc] initWithContents:string
					 registrationNumber:DVTMacroNameStringNextRegistrationNumber++];
		[DVTMacroNameStringRegistry setObject:nameString forKey:string];
	}
	[DVTMacroNameStringRegistryLock unlock];

	return (nameString);
}

- (id)initWithContents:(id)contents registrationNumber:(unsigned long long)number
{
	self = [super init];
	if (self != nil) {
		_contents = [contents copy];
		_hashValue = (unsigned long long)[_contents hash];
		_regNumber = number;
	}
	return (self);
}

- (id)init
{
	/* Apple asserts here; the release framework traps instead of raising. */
	[NSException raise:NSInvalidArgumentException format:@"%@", @""];
	return (nil);
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_contents release];
	[super dealloc];
}
#endif

- (id)copy
{
	return (self);
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return (self);
}

- (id)replacementObjectForCoder:(NSCoder *)coder
{
	(void)coder;
	/* Archived macro names decode as plain strings. */
	return (_contents);
}

- (NSUInteger)length
{
	return ([_contents length]);
}

- (unsigned short)characterAtIndex:(NSUInteger)index
{
	return ([_contents characterAtIndex:index]);
}

- (void)getCharacters:(unsigned short *)buffer range:(NSRange)range
{
	[_contents getCharacters:buffer range:range];
}

- (NSUInteger)hash
{
	return (_hashValue);
}

- (BOOL)isEqual:(id)object
{
	if (object == self) {
		return (YES);
	}
	if (object == nil) {
		return (NO);
	}
	return ([_contents isEqual:object]);
}

- (unsigned long long)macroRegistrationNumber
{
	return (_regNumber);
}

- (NSString *)description
{
	return (_contents);
}

@end
