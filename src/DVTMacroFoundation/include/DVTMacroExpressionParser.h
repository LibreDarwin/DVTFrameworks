/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Internal interface of the DVT macro expression parser.  Apple exports these
 * four entry points from DVTMacroFoundation but does not ship a public header
 * for them; this header is intentionally framework-private.
 *
 * The parser turns a macro value string such as "$(SRCROOT:dir)/Foo.plist"
 * into a tree of DVTMacroExpansionString objects.  The AsList variants split
 * the value into whitespace-separated words first (honouring double quotes,
 * single quotes and backslash escapes) and return a
 * DVTMacroExpansionStringList.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPRESSIONPARSER_H
#define DVTMACROFOUNDATION_DVTMACROEXPRESSIONPARSER_H

#import <Foundation/Foundation.h>

@class NSArray, NSString;

id DVTMacroExpressionByParsingString(NSString *string);
id DVTMacroExpressionByParsingStringAsList(NSString *string);
id DVTMacroExpressionByParsingStringArrayAsList(NSArray *strings);

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPRESSIONPARSER_H */
