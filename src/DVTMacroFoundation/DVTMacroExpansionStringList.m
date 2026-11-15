/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Deviations from Apple's implementation:
 *
 *  - Apple's abstract-class and subclass-responsibility checks go through
 *    DVTAssertionFailureHandler; a clean-room build raises
 *    NSInvalidArgumentException with the same message instead.
 */

#import "DVTMacroExpansionStringList.h"

static void
DVTMacroExpansionStringListRaiseSubclassResponsibility(id object, NSString *methodName)
{
	[NSException raise:NSInvalidArgumentException
		    format:@"method %@ is a subclass responsibility of %@",
			   methodName, NSStringFromClass([object class])];
}

@implementation DVTMacroExpansionStringList

+ (id)allocWithZone:(NSZone *)zone
{
	if (self == [DVTMacroExpansionStringList class]) {
		[NSException raise:NSInvalidArgumentException format:@"%@ is an abstract class and cannot be instantiated", NSStringFromClass([self class])];
	}
	return ([super allocWithZone:zone]);
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
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList dvt_isLiteral]");
	return (NO);
}

- (id)dvt_stringForm
{
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList dvt_stringForm]");
	return (nil);
}

- (NSUInteger)hash
{
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList hash]");
	return (0);
}

- (BOOL)isEqual:(id)equal
{
	(void)equal;
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList isEqual:]");
	return (NO);
}

- (NSUInteger)count
{
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList count]");
	return (0);
}

- (id)objectAtIndex:(NSUInteger)index
{
	(void)index;
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList objectAtIndex:]");
	return (nil);
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)buffer count:(NSUInteger)len
{
	(void)state;
	(void)buffer;
	(void)len;
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList countByEnumeratingWithState:objects:count:]");
	return (0);
}

- (id)description
{
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList description]");
	return (nil);
}

- (id)dvt_evaluateAsStringInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList dvt_evaluateAsStringInScope:withState:]");
	return (nil);
}

- (id)dvt_evaluateAsStringListInScope:(id)scope withState:(const struct DVTNestedMacroExpansionState *)state
{
	(void)scope;
	(void)state;
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList dvt_evaluateAsStringListInScope:withState:]");
	return (nil);
}

- (void)dvt_assertInternalConsistency
{
}

- (id)dvt_debugDescription
{
	DVTMacroExpansionStringListRaiseSubclassResponsibility(self, @"-[DVTMacroExpansionStringList dvt_debugDescription]");
	return (nil);
}

@end
