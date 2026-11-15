/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroNameRegistryRegistration: the DVTRegistrable object a
 * DVTMacroNameRegistry stores for each registered macro name.
 */

#ifndef DVTMACROFOUNDATION_DVTMACRONAMEREGISTRYREGISTRATION_H
#define DVTMACROFOUNDATION_DVTMACRONAMEREGISTRYREGISTRATION_H

#import <Foundation/Foundation.h>

#import "DVTRegistrable.h"

@interface DVTMacroNameRegistryRegistration : NSObject <DVTRegistrable> {
	BOOL _listType;
	NSString *_macroName;
}

- (id)initWithMacroName:(NSString *)name isListType:(BOOL)isListType;

@property (readonly, copy) NSString *macroName;
@property (readonly, getter=isListType) BOOL listType;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACRONAMEREGISTRYREGISTRATION_H */
