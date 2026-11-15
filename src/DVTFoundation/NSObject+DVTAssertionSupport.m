/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 */

#import "NSObject+DVTAssertionSupport.h"

@implementation NSObject (DVTAssertionSupport)

+ (id)descriptionForAssertionMessage
{
	return ([NSString stringWithFormat:@"<%@>", NSStringFromClass(self)]);
}

- (id)descriptionForAssertionMessage
{
	return ([NSString stringWithFormat:@"<%@: %p>", NSStringFromClass([self class]), self]);
}

@end
