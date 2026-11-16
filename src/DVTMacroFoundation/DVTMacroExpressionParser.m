/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's macro expression parser.
 *
 * The grammar accepted here was derived from the observable behavior of
 * DVTMacroExpressionByParsingString, DVTMacroExpressionByParsingStringAsList
 * and DVTMacroExpressionByParsingStringArrayAsList:
 *
 *   expression  := (literal | substitution)*
 *   substitution:= '$' name | '$' '(' name (':' operator)* ')'
 *                | '$' '{' ... '}' | '$' '[' ... ']'
 *   operator    := opname | opname '=' expression
 *
 * A '$' followed by '$' or the end of the string is a literal dollar sign.
 * Other characters are literal text; there are no backslash escapes inside
 * single expressions (only the list parser dequotes words).
 *
 * Deviations from Apple's implementation:
 *
 *  - The parser uses NSMutableArray/NSMutableData instead of the private
 *    DVT::ArrayBuilder and DVT::FileSystemRepresentation helpers.
 *  - Malformed UTF-8 is decoded as ISO Latin-1 rather than being passed
 *    through the potentially-malformed-string helper.
 */

#import "DVTMacroExpressionParser.h"

#import <CoreFoundation/CoreFoundation.h>
#import <ctype.h>
#import <stdlib.h>
#import <string.h>

#import "DVTMacroExpansionOperator.h"
#import "DVTMacroExpansionReplacementOperatorWithParseError.h"
#import "DVTMacroExpansionRetrievalOperatorWithParseError.h"
#import "DVTMacroExpansionString_Concatenation.h"
#import "DVTMacroExpansionString_StringSubstitution.h"
#import "DVTMacroExpansionString_Substitution.h"
#import "DVTMacroExpansionStringList_Literal.h"
#import "DVTMacroExpansionStringList_NonLiteral.h"
#import "NSString+DVTMacroExpansion.h"

static id ParseMacroExpansionString(const char *str, const char **end, char stop1, char stop2, BOOL flag, NSString *sourceString);

static NSString *DVTStringFromBytes(const char *bytes, NSUInteger length)
{
	if (length == 0) {
		return (@"");
	}
	NSString *string = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
	if (string == nil) {
		string = [[NSString alloc] initWithBytes:bytes length:length encoding:NSISOLatin1StringEncoding];
	}
	return (string != nil ? string : @"");
}

static char *DVTFileSystemRepresentation(NSString *string, NSUInteger *length)
{
	CFIndex maximum = CFStringGetMaximumSizeOfFileSystemRepresentation((__bridge CFStringRef)string);
	if (maximum < 0) {
		maximum = 0;
	}
	char *bytes = malloc((size_t)maximum + 1);
	if (bytes == NULL) {
		*length = 0;
		return (NULL);
	}
	if (!CFStringGetFileSystemRepresentation((__bridge CFStringRef)string, bytes, maximum + 1)) {
		bytes[0] = '\0';
	}
	*length = strlen(bytes);
	return (bytes);
}

static NSString *DVTSourceStringByExpandingLeadingInheritedMarker(NSString *string)
{
	if ([string length] > 0 && [string characterAtIndex:0] == 1) {
		NSString *rest = [string substringFromIndex:1];
		if ([rest length] == 0) {
			return (@"$(inherited)");
		}
		return ([@"$(inherited) " stringByAppendingString:rest]);
	}
	return (string);
}

static NSString *ParseLiteralStringFragment(const char *str, const char **end, char stop1, char stop2)
{
	const char *p = str;
	while (*p != '\0' && *p != '$' && *p != stop1 && *p != stop2) {
		p++;
	}
	*end = p;
	if (p == str) {
		return (nil);
	}
	return (DVTStringFromBytes(str, (NSUInteger)(p - str)));
}

static NSError *MakeParseError(NSString *operatorName, NSString *sourceString)
{
	NSDictionary *userInfo = @{
		NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Unknown operator '%@'", operatorName],
		@"SourceString" : (sourceString != nil ? sourceString : @""),
	};
	return ([NSError errorWithDomain:@"DVTMacroExpansionErrorDomain" code:999 userInfo:userInfo]);
}

static id MakeConcatenation(const char *start, const char *end, NSArray *parts)
{
	if ([parts count] == 1) {
		return ([parts objectAtIndex:0]);
	}
	return ([DVTMacroExpansionString_Concatenation newWithOriginalString:DVTStringFromBytes(start, (NSUInteger)(end - start))
								  substrings:parts]);
}

static BOOL DVTIsMacroNameStart(unsigned char c)
{
	return (isalpha(c) || c == '_');
}

static BOOL DVTIsMacroNameContinuation(unsigned char c)
{
	return (isalnum(c) || c == '_' || c == '.');
}

static id ParseSubstitutionExpressionStringFragment(const char *str, const char **end, BOOL flag)
{
	const char *start = str;
	const char *p = str + 1;
	char close = '\0';
	BOOL delimited = NO;

	if (*p == '(') {
		close = ')';
		delimited = YES;
	} else if (*p == '{') {
		close = '}';
		delimited = YES;
	} else if (*p == '[') {
		close = ']';
		delimited = YES;
	}

	id macroNameExpression = nil;
	if (delimited) {
		p++;
		const char *nameStart = p;
		NSMutableArray *nameParts = [NSMutableArray array];
		while (*p != '\0') {
			NSString *literal = ParseLiteralStringFragment(p, &p, ':', close);
			if (literal != nil) {
				[nameParts addObject:literal];
			}
			if (*p == '$') {
				[nameParts addObject:ParseSubstitutionExpressionStringFragment(p, &p, YES)];
				continue;
			}
			break;
		}
		const char *nameEnd = p;
		macroNameExpression = MakeConcatenation(nameStart, nameEnd, nameParts);
	} else {
		if (!DVTIsMacroNameStart((unsigned char)*p)) {
			/* A lone '$' (or "$$") is literal text. */
			*end = (p + (*p == '$' ? 1 : 0));
			return (@"$");
		}
		const char *nameStart = p;
		p++;
		while (DVTIsMacroNameContinuation((unsigned char)*p)) {
			p++;
		}
		NSString *name = DVTStringFromBytes(nameStart, (NSUInteger)(p - nameStart));
		NSMutableArray *nameParts = [NSMutableArray arrayWithObject:name];
		if (*p == '$' && p[1] == '(') {
			[nameParts addObject:ParseSubstitutionExpressionStringFragment(p, &p, flag)];
		}
		NSString *nameSource = DVTStringFromBytes(nameStart, (NSUInteger)(p - nameStart));
		macroNameExpression = [DVTMacroExpansionString_Concatenation newWithOriginalString:nameSource substrings:nameParts];
	}

	NSMutableArray *operators = [NSMutableArray array];
	if (delimited) {
		while (*p == ':') {
			p++;
			const char *operatorStart = p;
			while (*p != '\0' && *p != ':' && *p != '=' && *p != close) {
				p++;
			}
			NSString *operatorName = DVTStringFromBytes(operatorStart, (NSUInteger)(p - operatorStart));
			id op = nil;
			if (*p == '=') {
				p++;
				const char *argumentStart = p;
				id replacement = ParseMacroExpansionString(argumentStart, &p, ':', close, flag, nil);
				Class operatorClass = [DVTMacroExpansionOperator replacementOperatorClassForOperatorNamed:operatorName];
				if (operatorClass != Nil) {
					op = [[operatorClass alloc] initWithReplacementExpression:replacement];
				} else {
					NSString *source = DVTStringFromBytes(operatorStart, (NSUInteger)(p - operatorStart));
					op = [[DVTMacroExpansionReplacementOperatorWithParseError alloc] initWithReplacementExpression:replacement
															       parseError:MakeParseError(operatorName, source)];
				}
			} else {
				Class operatorClass = [DVTMacroExpansionOperator retrievalOperatorClassForOperatorNamed:operatorName];
				if (operatorClass != Nil) {
					op = [[operatorClass alloc] init];
				} else {
					NSString *source = DVTStringFromBytes(operatorStart, (NSUInteger)(p - operatorStart));
					op = [[DVTMacroExpansionRetrievalOperatorWithParseError alloc] initWithParseError:MakeParseError(operatorName, source)];
				}
			}
			[operators addObject:op];
		}
		if (close != '\0' && *p == close) {
			p++;
		}
	}

	NSString *originalString = DVTStringFromBytes(start, (NSUInteger)(p - start));
	Class substitutionClass = flag ? [DVTMacroExpansionString_StringSubstitution class] : [DVTMacroExpansionString_Substitution class];
	id substitution = [[substitutionClass alloc] initWithOriginalString:originalString
						    macroNameExpression:macroNameExpression
						    preserveOriginalStringIfUnresolved:(delimited ? NO : YES)
						    operators:operators];
	*end = p;
	return (substitution);
}

static id ParseMacroExpansionString(const char *str, const char **end, char stop1, char stop2, BOOL flag, NSString *sourceString)
{
	const char *p = str;
	NSMutableArray *parts = [NSMutableArray array];

	while (*p != '\0') {
		NSString *literal = ParseLiteralStringFragment(p, &p, stop1, stop2);
		if (literal != nil) {
			[parts addObject:literal];
		}
		if (*p == '$') {
			[parts addObject:ParseSubstitutionExpressionStringFragment(p, &p, flag)];
			continue;
		}
		break;
	}

	NSString *originalString = sourceString;
	if (originalString == nil) {
		originalString = (p != str ? DVTStringFromBytes(str, (NSUInteger)(p - str)) : @"");
	}
	id result = MakeConcatenation(str, p, parts);
	if ([parts count] == 0) {
		result = [DVTMacroExpansionString_Concatenation newWithOriginalString:originalString substrings:parts];
	} else if ([parts count] > 1) {
		result = [DVTMacroExpansionString_Concatenation newWithOriginalString:originalString substrings:parts];
	}
	*end = p;
	return (result);
}

static id DVTEmptyStringListExpression(void)
{
	static id emptyList = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		emptyList = [DVTMacroExpansionStringList_Literal newWithStringForm:@"" literalStrings:@[]];
	});
	return (emptyList);
}

id DVTMacroExpressionByParsingString(NSString *string)
{
	if (string == nil) {
		return (nil);
	}

	id literalValue = [string dvt_literalValueOfCommonString];
	if (literalValue != nil) {
		return ([literalValue copy]);
	}

	NSString *input = DVTSourceStringByExpandingLeadingInheritedMarker(string);
	NSUInteger length = 0;
	char *bytes = DVTFileSystemRepresentation(input, &length);
	if (bytes == NULL) {
		return ([input copy]);
	}
	if (memchr(bytes, '$', length) == NULL) {
		free(bytes);
		return ([input copy]);
	}

	const char *end = NULL;
	id result = ParseMacroExpansionString(bytes, &end, '\0', '\0', YES, input);
	free(bytes);
	return (result);
}

id DVTMacroExpressionByParsingStringAsList(NSString *string)
{
	if (string == nil) {
		return (nil);
	}
	if ([string length] == 0) {
		return (DVTEmptyStringListExpression());
	}

	NSString *input = DVTSourceStringByExpandingLeadingInheritedMarker(string);
	NSUInteger length = 0;
	char *bytes = DVTFileSystemRepresentation(input, &length);
	if (bytes == NULL) {
		return (DVTEmptyStringListExpression());
	}

	NSMutableArray *elements = [NSMutableArray array];
	const char *p = bytes;
	while (*p != '\0') {
		while (isspace((unsigned char)*p)) {
			p++;
		}
		if (*p == '\0') {
			break;
		}

		const char *wordStart = p;
		NSMutableArray *parts = [NSMutableArray array];
		NSMutableData *literalBytes = [NSMutableData data];
		char quote = '\0';

		while (*p != '\0') {
			unsigned char c = (unsigned char)*p;
			if (quote == '\0' && isspace(c)) {
				break;
			}
			if (c == '$') {
				if (p[1] == '$' || p[1] == '\0') {
					[literalBytes appendBytes:"$" length:1];
					p++;
				} else {
					if ([literalBytes length] > 0) {
						[parts addObject:DVTStringFromBytes([literalBytes bytes], [literalBytes length])];
						[literalBytes setLength:0];
					}
					[parts addObject:ParseSubstitutionExpressionStringFragment(p, &p, (quote != '\0'))];
				}
			} else if (c == '\\') {
				if (p[1] != '\0') {
					[literalBytes appendBytes:(p + 1) length:1];
					p += 2;
				} else {
					[literalBytes appendBytes:p length:1];
					p++;
				}
			} else if (c == '"' || c == '\'') {
				if (quote == '\0') {
					quote = (char)c;
					p++;
				} else if (quote == (char)c) {
					quote = '\0';
					p++;
				} else {
					[literalBytes appendBytes:p length:1];
					p++;
				}
			} else {
				[literalBytes appendBytes:p length:1];
				p++;
			}
		}
		if ([literalBytes length] > 0) {
			[parts addObject:DVTStringFromBytes([literalBytes bytes], [literalBytes length])];
			[literalBytes setLength:0];
		}

		if ([parts count] == 0) {
			[elements addObject:@""];
		} else if ([parts count] == 1) {
			[elements addObject:[parts objectAtIndex:0]];
		} else {
			[elements addObject:[DVTMacroExpansionString_Concatenation newWithOriginalString:DVTStringFromBytes(wordStart, (NSUInteger)(p - wordStart))
											    substrings:parts]];
		}
	}

	id stringForm = DVTMacroExpressionByParsingString(input);
	free(bytes);
	return ([DVTMacroExpansionStringList_NonLiteral newWithStringForm:stringForm elements:elements]);
}

id DVTMacroExpressionByParsingStringArrayAsList(NSArray *strings)
{
	if (strings == nil) {
		return (nil);
	}
	if ([strings count] == 0) {
		return (@[]);
	}

	NSMutableArray *elements = [NSMutableArray arrayWithCapacity:[strings count]];
	for (id string in strings) {
		if (![string isKindOfClass:[NSString class]]) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should contain strings, but it contains %@", @"strings", string];
		}
		NSUInteger length = 0;
		char *bytes = DVTFileSystemRepresentation(string, &length);
		const char *end = NULL;
		id element = ParseMacroExpansionString(bytes, &end, '\0', '\0', NO, string);
		free(bytes);
		[elements addObject:element];
	}

	id stringForm = DVTMacroExpressionByParsingString([strings componentsJoinedByString:@" "]);
	return ([DVTMacroExpansionStringList_NonLiteral newWithStringForm:stringForm elements:elements]);
}
