/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - Apple's abstract-class and subclass-responsibility checks go through
 *    DVTAssertionFailureHandler; a clean-room build raises
 *    NSInvalidArgumentException with the same message instead.
 */

#import "DVTMacroExpansionString.h"

#import <CoreFoundation/CoreFoundation.h>

#import "NSObject+DVTAssertionSupport.h"

static void
DVTMacroExpansionStringRaiseSubclassResponsibility(id object, NSString *methodName)
{
	[NSException raise:NSInvalidArgumentException
		    format:@"method %@ is a subclass responsibility of %@",
			   methodName, NSStringFromClass([object class])];
}

@implementation DVTMacroExpansionString

+ (id)allocWithZone:(NSZone *)zone
{
	if (self == [DVTMacroExpansionString class]) {
		[NSException raise:NSInvalidArgumentException format:@"%@ is an abstract class and cannot be instantiated", NSStringFromClass([self class])];
	}
	return ([super allocWithZone:zone]);
}

- (id)initWithOriginalString:(NSString *)string
{
	self = [super init];
	if (self != nil) {
		if (string == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a string, but it is nil", @"origString"];
		}
		if (CFGetTypeID((__bridge CFTypeRef)string) != CFStringGetTypeID()) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a string, but it is %@", @"origString", [string descriptionForAssertionMessage]];
		}
		_origString = [string copy];
	}
	return (self);
}

- (void)dealloc
{
#if !__has_feature(objc_arc)
	[_origString release];
	[super dealloc];
#endif
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return (self);
}

- (id)copy
{
	return (self);
}

- (BOOL)dvt_isLiteral
{
	DVTMacroExpansionStringRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionString dvt_isLiteral]");
	return (NO);
}

- (id)dvt_stringForm
{
	return (self);
}

- (BOOL)isEqual:(id)object
{
	return ([_origString isEqual:object]);
}

- (NSUInteger)hash
{
	return ([_origString hash]);
}

- (NSUInteger)length
{
	return ([_origString length]);
}

- (unichar)characterAtIndex:(NSUInteger)index
{
	return ([_origString characterAtIndex:index]);
}

- (void)getCharacters:(unichar *)characters range:(NSRange)range
{
	[_origString getCharacters:characters range:range];
}

- (id)description
{
	return ([_origString description]);
}

- (id)replacementObjectForCoder:(NSCoder *)coder
{
	return ([_origString replacementObjectForCoder:coder]);
}

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	DVTMacroExpansionStringRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionString dvt_evaluateAsStringInScope:withState:]");
	return (nil);
}

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	DVTMacroExpansionStringRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionString dvt_evaluateAsStringListInScope:withState:]");
	return (nil);
}

- (void)dvt_assertInternalConsistency
{
}

- (id)dvt_debugDescription
{
	DVTMacroExpansionStringRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionString dvt_debugDescription]");
	return (nil);
}

@end
