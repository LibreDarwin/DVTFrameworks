/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's DVTMacroNameString:
 * an interned NSString subclass used as a macro name.  Every instance is
 * handed out by +macroNameStringForString:createIfNeeded: and carries a
 * process-unique registration number.
 */

#ifndef DVTMACROFOUNDATION_DVTMACRONAMESTRING_H
#define DVTMACROFOUNDATION_DVTMACRONAMESTRING_H

#import <Foundation/Foundation.h>

@interface DVTMacroNameString : NSString {
	NSString *_contents;
	unsigned long long _hashValue;
	unsigned long long _regNumber;
}

+ (id)macroNameStringForString:(id)string createIfNeeded:(BOOL)needed;

- (id)initWithContents:(id)contents registrationNumber:(unsigned long long)number;

- (unsigned long long)macroRegistrationNumber;

@end

#endif	/* DVTMACROFOUNDATION_DVTMACRONAMESTRING_H */
