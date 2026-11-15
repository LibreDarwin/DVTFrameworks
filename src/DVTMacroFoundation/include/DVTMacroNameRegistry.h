/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's DVTMacroNameRegistry:
 * the registry that records, for every known macro name, whether values of
 * that macro are lists.  Unknown names fall back to the registry default.
 */

#ifndef DVTMACROFOUNDATION_DVTMACRONAMEREGISTRY_H
#define DVTMACROFOUNDATION_DVTMACRONAMEREGISTRY_H

#import <Foundation/Foundation.h>

#import "DVTRegistry.h"

@interface DVTMacroNameRegistry : DVTRegistry {
	BOOL _defaultIsListType;
}

- (id)initWithDebugName:(NSString *)name defaultIsListType:(BOOL)isListType;

- (void)registerMacroName:(NSString *)name isListType:(BOOL)isListType;
- (BOOL)macroIsListType:(NSString *)name;

@property (readonly) BOOL defaultIsListType;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACRONAMEREGISTRY_H */
