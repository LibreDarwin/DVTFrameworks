/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 */

#import "DVTPlugInManager.h"

static DVTPlugInManager *sDefaultPlugInManager = nil;

@implementation DVTPlugInManager

+ (DVTPlugInManager *)defaultPlugInManager
{
	@synchronized ([DVTPlugInManager class]) {
		if (sDefaultPlugInManager == nil) {
			sDefaultPlugInManager = [[DVTPlugInManager alloc] init];
		}
	}
	return (sDefaultPlugInManager);
}

- (id)init
{
	self = [super init];
	if (self != nil) {
		_pathExtensions = [self _defaultPathExtensions];
	}
	return (self);
}

- (NSSet *)pathExtensions
{
	return (_pathExtensions);
}

- (void)setPathExtensions:(NSSet *)pathExtensions
{
	_pathExtensions = [pathExtensions copy];
}

- (NSSet *)_defaultPathExtensions
{
	return ([NSSet setWithObject:@"dvtplugin"]);
}

@end
