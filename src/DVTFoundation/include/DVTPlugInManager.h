/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of the subset of DVTFoundation's DVTPlugInManager
 * that this tree needs.
 *
 * Apple's plug-in manager discovers and loads .dvtplugin bundles.  This tree
 * does not implement the plug-in system, so only the shared instance and the
 * path extension set (used to decide which directories to skip while scanning
 * for specifications) are reproduced.  The default path extension is
 * "dvtplugin", as returned by Apple's -_defaultPathExtensions.
 */

#ifndef DVTFOUNDATION_DVTPLUGINMANAGER_H
#define DVTFOUNDATION_DVTPLUGINMANAGER_H

#import <Foundation/Foundation.h>

@interface DVTPlugInManager : NSObject {
    NSSet *_pathExtensions;
}

+ (DVTPlugInManager *)defaultPlugInManager;

- (NSSet *)pathExtensions;
- (void)setPathExtensions:(NSSet *)pathExtensions;
- (NSSet *)_defaultPathExtensions;

@end

#endif	/* DVTFOUNDATION_DVTPLUGINMANAGER_H */
