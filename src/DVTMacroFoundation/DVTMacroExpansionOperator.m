/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of DVTMacroFoundation's
 * DVTMacroExpansionOperator, its built-in operator classes, and the helper
 * used by their -dvt_debugDescription methods.
 *
 * Deviations from Apple's implementation:
 *
 *  - The operator registries are NSMutableDictionary/NSMutableArray pairs
 *    instead of DVTRegistry instances; Class objects cannot implement the
 *    DVTRegistrable protocol, and only the lookup and ordered enumeration
 *    results are observable.
 *  - The abstract-method and subclass-responsibility assertions are raised as
 *    NSInvalidArgumentException instead of going through
 *    DVTAssertionFailureHandler.
 *  - The concrete operators below are declared in the single internal header
 *    DVTMacroExpansionBuiltInOperators.h rather than in one public header per
 *    class.  Their class names, selectors, registrations and behaviour match
 *    Apple's binary.
 *  - -dvt_stringByRemovingPrefix:, -dvt_isNonEmpty and
 *    -dvt_stringByMakingPathRelativeToBasePath: are implemented as local
 *    helpers because the DVTFoundation additions that provide them are not
 *    part of this stage of the port.
 */

#import "DVTMacroExpansionOperator.h"

#import <CoreFoundation/CoreFoundation.h>

#import "DVTFoundationClassAdditions.h"
#import "DVTMacroExpansionBuiltInOperators.h"
#import "DVTMacroExpansionReplacementOperator.h"
#import "DVTMacroExpansionReplacementOperatorWithParseError.h"
#import "DVTMacroExpansionRetrievalOperator.h"
#import "DVTMacroExpansionRetrievalOperatorWithParseError.h"
#import "DVTMacroExpansionString.h"
#import "DVTMacroExpansion-Protocol.h"

static NSMutableDictionary *DVTMacroExpansionRetrievalOperatorRegistry = nil;
static NSMutableArray *DVTMacroExpansionRetrievalOperatorClasses = nil;
static NSMutableDictionary *DVTMacroExpansionReplacementOperatorRegistry = nil;
static NSMutableArray *DVTMacroExpansionReplacementOperatorClasses = nil;

static void
DVTAppendUTF32Character(NSMutableString *result, uint32_t character)
{
	if (character <= 0xFFFF) {
		unichar unit = (unichar)character;
		[result appendString:[NSString stringWithCharacters:&unit length:1]];
	} else {
		character -= 0x10000;
		unichar units[2] = { (unichar)(0xD800 + (character >> 10)), (unichar)(0xDC00 + (character & 0x3FF)) };
		[result appendString:[NSString stringWithCharacters:units length:2]];
	}
}

NSString *
DVTMacroExpansionItalicizedString(NSString *string)
{
	NSMutableString *result = [NSMutableString stringWithCapacity:[string length]];
	NSUInteger index;
	for (index = 0; index < [string length]; index++) {
		unichar character = [string characterAtIndex:index];
		if (character >= 'a' && character <= 'z') {
			DVTAppendUTF32Character(result, (uint32_t)(0x1D5EE + (character - 'a')));
		} else if (character >= 'A' && character <= 'Z') {
			DVTAppendUTF32Character(result, (uint32_t)(0x1D5D4 + (character - 'A')));
		} else {
			DVTAppendUTF32Character(result, character);
		}
	}
	return (result);
}

static void
DVTMacroExpansionOperatorRaiseAbstract(id object, NSString *methodName)
{
	[NSException raise:NSInvalidArgumentException
		    format:@"%@ is an abstract method of %@ and must be overridden",
			   methodName, NSStringFromClass([object class])];
}

@interface DVTMacroExpansionOperator ()
+ (void)initializeBuiltInOperatorRegistries;
@end

@implementation DVTMacroExpansionOperator

+ (void)initialize
{
	if (self == [DVTMacroExpansionOperator class]) {
		[self registerBuiltInOperators];
	}
}

+ (void)initializeBuiltInOperatorRegistries
{
	if (DVTMacroExpansionRetrievalOperatorRegistry == nil) {
		DVTMacroExpansionRetrievalOperatorRegistry = [[NSMutableDictionary alloc] init];
		DVTMacroExpansionRetrievalOperatorClasses = [[NSMutableArray alloc] init];
	}
	if (DVTMacroExpansionReplacementOperatorRegistry == nil) {
		DVTMacroExpansionReplacementOperatorRegistry = [[NSMutableDictionary alloc] init];
		DVTMacroExpansionReplacementOperatorClasses = [[NSMutableArray alloc] init];
	}
}

+ (void)registerBuiltInOperators
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[self initializeBuiltInOperatorRegistries];

		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_quote class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_upper class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_lower class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_identifier class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_rfc1034identifier class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_c99extidentifier class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_dir class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_file class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_base class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_suffix class]];
		[self registerRetrievalOperatorClass:[DVTMacroExpansionRetrievalOperator_standardizepath class]];

		[self registerReplacementOperatorClass:[DVTMacroExpansionReplacementOperator_dir class]];
		[self registerReplacementOperatorClass:[DVTMacroExpansionReplacementOperator_file class]];
		[self registerReplacementOperatorClass:[DVTMacroExpansionReplacementOperator_base class]];
		[self registerReplacementOperatorClass:[DVTMacroExpansionReplacementOperator_suffix class]];
		[self registerReplacementOperatorClass:[DVTMacroExpansionReplacementOperator_relativeto class]];
		[self registerReplacementOperatorClass:[DVTMacroExpansionReplacementOperator_default class]];
	});
}

+ (id)retrievalOperatorRegistry
{
	[self initializeBuiltInOperatorRegistries];
	return (DVTMacroExpansionRetrievalOperatorRegistry);
}

+ (void)registerRetrievalOperatorClass:(Class)operatorClass
{
	[self initializeBuiltInOperatorRegistries];
	NSString *name = [operatorClass operatorName];
	if (name == nil) {
		return;
	}
	if ([DVTMacroExpansionRetrievalOperatorRegistry objectForKey:name] == nil) {
		[DVTMacroExpansionRetrievalOperatorClasses addObject:operatorClass];
	}
	[DVTMacroExpansionRetrievalOperatorRegistry setObject:operatorClass forKey:name];
}

+ (id)registeredRetrievalOperatorClasses
{
	[self initializeBuiltInOperatorRegistries];
	return ([NSArray arrayWithArray:DVTMacroExpansionRetrievalOperatorClasses]);
}

+ (Class)retrievalOperatorClassForOperatorNamed:(NSString *)name
{
	[self initializeBuiltInOperatorRegistries];
	return ([DVTMacroExpansionRetrievalOperatorRegistry objectForKey:name]);
}

+ (id)replacementOperatorRegistry
{
	[self initializeBuiltInOperatorRegistries];
	return (DVTMacroExpansionReplacementOperatorRegistry);
}

+ (void)registerReplacementOperatorClass:(Class)operatorClass
{
	[self initializeBuiltInOperatorRegistries];
	NSString *name = [operatorClass operatorName];
	if (name == nil) {
		return;
	}
	if ([DVTMacroExpansionReplacementOperatorRegistry objectForKey:name] == nil) {
		[DVTMacroExpansionReplacementOperatorClasses addObject:operatorClass];
	}
	[DVTMacroExpansionReplacementOperatorRegistry setObject:operatorClass forKey:name];
}

+ (id)registeredReplacementOperatorClasses
{
	[self initializeBuiltInOperatorRegistries];
	return ([NSArray arrayWithArray:DVTMacroExpansionReplacementOperatorClasses]);
}

+ (Class)replacementOperatorClassForOperatorNamed:(NSString *)name
{
	[self initializeBuiltInOperatorRegistries];
	return ([DVTMacroExpansionReplacementOperatorRegistry objectForKey:name]);
}

+ (id)operatorName
{
	NSString *className = NSStringFromClass(self);
	NSRange underscoreRange = [className rangeOfString:@"_" options:NSBackwardsSearch];
	if (underscoreRange.location == NSNotFound) {
		return (className);
	}
	return ([className substringFromIndex:NSMaxRange(underscoreRange)]);
}

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)string;
	(void)scope;
	DVTMacroExpansionOperatorRaiseAbstract(self, @"-[DVTMacroExpansionOperator stringByApplyingOperatorToString:inMacroExpansionScope:]");
	return (nil);
}

- (id)stringListByApplyingOperatorToStringList:(id)list inMacroExpansionScope:(id)scope
{
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[list count]];
	for (id string in list) {
		id applied = [self stringByApplyingOperatorToString:string inMacroExpansionScope:scope];
		if (applied != nil) {
			[result addObject:applied];
		}
	}
	return (result);
}

- (BOOL)hasParseError
{
	return ([self parseError] != nil);
}

- (id)parseError
{
	return (nil);
}

- (id)dvt_debugDescription
{
	return ([NSString stringWithFormat:@"【%@】", DVTMacroExpansionItalicizedString([[self class] operatorName])]);
}

- (BOOL)applyToEmptyResult
{
	return (NO);
}

@end

@implementation DVTMacroExpansionRetrievalOperator

- (id)init
{
	return ([super init]);
}

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)string;
	(void)scope;
	DVTMacroExpansionOperatorRaiseAbstract(self, @"-[DVTMacroExpansionRetrievalOperator stringByApplyingOperatorToString:inMacroExpansionScope:]");
	return (nil);
}

- (id)stringListByApplyingOperatorToStringList:(id)list inMacroExpansionScope:(id)scope
{
	return ([super stringListByApplyingOperatorToStringList:list inMacroExpansionScope:scope]);
}

- (id)dvt_debugDescription
{
	return ([NSString stringWithFormat:@"【%@】", DVTMacroExpansionItalicizedString([[self class] operatorName])]);
}

@end

@implementation DVTMacroExpansionRetrievalOperatorWithParseError

+ (id)operatorName
{
	return (@"<ERROR>");
}

- (id)initWithParseError:(id)error
{
	self = [super init];
	if (self != nil) {
		_parseError = [error copy];
	}
	return (self);
}

- (id)parseError
{
	return (_parseError);
}

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return (string);
}

@end

@implementation DVTMacroExpansionReplacementOperator

- (id)initWithReplacementExpression:(id)expression
{
	self = [super init];
	if (self != nil) {
		if (expression == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a macro expansion expression, but it is nil", @"expression"];
		}
		if (![expression isKindOfClass:[NSString class]]) {
			[NSException raise:NSInvalidArgumentException
				    format:@"%@ should be a macro expansion expression, but it is %@",
					   @"expression", [expression description]];
		}
		_replExpr = expression;
	}
	return (self);
}

- (id)replacementExpression
{
	return (_replExpr);
}

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)string;
	(void)scope;
	DVTMacroExpansionOperatorRaiseAbstract(self, @"-[DVTMacroExpansionReplacementOperator stringByApplyingOperatorToString:inMacroExpansionScope:]");
	return (nil);
}

- (id)stringListByApplyingOperatorToStringList:(id)list inMacroExpansionScope:(id)scope
{
	return ([super stringListByApplyingOperatorToStringList:list inMacroExpansionScope:scope]);
}

- (id)dvt_debugDescription
{
	return ([NSString stringWithFormat:@"【%@=%@】",
			DVTMacroExpansionItalicizedString([[self class] operatorName]), [_replExpr description]]);
}

@end

@implementation DVTMacroExpansionReplacementOperatorWithParseError

+ (id)operatorName
{
	return (@"<ERROR>");
}

- (id)initWithReplacementExpression:(id)expression parseError:(id)error
{
	self = [super initWithReplacementExpression:expression];
	if (self != nil) {
		_parseError = [error copy];
	}
	return (self);
}

- (id)parseError
{
	return (_parseError);
}

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return (string);
}

@end

static BOOL
DVTStringIsNonEmpty(NSString *string)
{
	return (string != nil && [string length] != 0);
}

static NSString *
DVTStringByRemovingPrefix(NSString *string, NSString *prefix)
{
	if ([string hasPrefix:prefix]) {
		return ([string substringFromIndex:[prefix length]]);
	}
	return (string);
}

static NSString *
DVTStringByMakingPathRelativeToBasePath(NSString *string, NSString *basePath)
{
	NSArray *stringComponents = [string pathComponents];
	NSArray *baseComponents = [basePath pathComponents];
	NSUInteger commonCount = 0;
	NSUInteger commonLimit = MIN([stringComponents count], [baseComponents count]);
	NSUInteger index;

	for (index = 0; index < commonLimit; index++) {
		if (![[stringComponents objectAtIndex:index] isEqualToString:[baseComponents objectAtIndex:index]]) {
			break;
		}
		commonCount = index + 1;
	}

	NSMutableArray *resultComponents = [NSMutableArray array];
	for (index = commonCount; index < [baseComponents count]; index++) {
		[resultComponents addObject:@".."];
	}
	for (index = commonCount; index < [stringComponents count]; index++) {
		[resultComponents addObject:[stringComponents objectAtIndex:index]];
	}
	return ([resultComponents componentsJoinedByString:@"/"]);
}

static NSString *
DVTStringByManglingToIdentifier(NSString *string, BOOL decompose, BOOL allowUnderscore, unichar replacementCharacter)
{
	NSString *source = decompose ? [string decomposedStringWithCanonicalMapping] : string;
	NSMutableString *result = [NSMutableString stringWithCapacity:[source length]];
	BOOL first = YES;

	for (NSUInteger index = 0; index < [source length]; index++) {
		unichar character = [source characterAtIndex:index];
		BOOL allowed;
		if ((character >= 'a' && character <= 'z') ||
		    (character >= 'A' && character <= 'Z') ||
		    (character >= '0' && character <= '9') ||
		    (allowUnderscore && character == '_') ||
		    character == replacementCharacter) {
			allowed = YES;
		} else {
			allowed = NO;
		}
		if (first && character >= '0' && character <= '9') {
			[result appendFormat:@"%C", replacementCharacter];
			first = NO;
			continue;
		}
		first = NO;
		[result appendFormat:@"%C", (unichar)(allowed ? character : replacementCharacter)];
	}
	return (result);
}

@implementation DVTMacroExpansionRetrievalOperator_quote

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	if (!DVTStringIsNonEmpty(string)) {
		return (@"");
	}
	NSMutableString *result = [NSMutableString stringWithCapacity:[string length]];
	for (NSUInteger index = 0; index < [string length]; index++) {
		unichar character = [string characterAtIndex:index];
		if (character == ' ' || character == '"' || character == '\'' || character == '\\') {
			[result appendString:@"\\"];
		}
		[result appendFormat:@"%C", character];
	}
	return (result);
}

@end

@implementation DVTMacroExpansionRetrievalOperator_upper

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return ([string uppercaseString]);
}

@end

@implementation DVTMacroExpansionRetrievalOperator_lower

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return ([string lowercaseString]);
}

@end

@implementation DVTMacroExpansionRetrievalOperator_identifier

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return (DVTStringByManglingToIdentifier(string, YES, YES, '_'));
}

@end

@implementation DVTMacroExpansionRetrievalOperator_rfc1034identifier

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return (DVTStringByManglingToIdentifier(string, YES, NO, '-'));
}

@end

@implementation DVTMacroExpansionRetrievalOperator_c99extidentifier

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	NSMutableString *result = [NSMutableString stringWithCapacity:[string length]];
	BOOL first = YES;

	for (NSUInteger index = 0; index < [string length]; index++) {
		unichar character = [string characterAtIndex:index];
		BOOL allowed;
		if ((character >= 'a' && character <= 'z') ||
		    (character >= 'A' && character <= 'Z') ||
		    (character >= '0' && character <= '9') ||
		    character == '_') {
			allowed = YES;
		} else if (character >= 0x80 && [[NSCharacterSet letterCharacterSet] longCharacterIsMember:character]) {
			allowed = YES;
		} else {
			allowed = NO;
		}
		if (first && character >= '0' && character <= '9') {
			[result appendString:@"_"];
		}
		first = NO;
		[result appendFormat:@"%C", (unichar)(allowed ? character : (unichar)'_')];
	}
	return (result);
}

@end

@implementation DVTMacroExpansionRetrievalOperator_dir

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	NSString *directory = [string stringByDeletingLastPathComponent];
	if ([directory length] == 0) {
		return (@"./");
	}
	if ([directory isEqualToString:@"/"]) {
		return (@"/");
	}
	return ([directory stringByAppendingString:@"/"]);
}

@end

@implementation DVTMacroExpansionRetrievalOperator_file

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return ([string lastPathComponent]);
}

@end

@implementation DVTMacroExpansionRetrievalOperator_base

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return ([[string lastPathComponent] stringByDeletingPathExtension]);
}

@end

@implementation DVTMacroExpansionRetrievalOperator_suffix

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	NSString *extension = [string pathExtension];
	if ([extension length] == 0) {
		return (@"");
	}
	return ([@"." stringByAppendingString:extension]);
}

@end

@implementation DVTMacroExpansionRetrievalOperator_standardizepath

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return ([string stringByStandardizingPath]);
}

@end

@implementation DVTMacroExpansionRetrievalOperator_xml

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)string;
	(void)scope;
	return (nil);
}

@end

@implementation DVTMacroExpansionReplacementOperator_dir

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return ([_replExpr stringByAppendingPathComponent:[string lastPathComponent]]);
}

@end

@implementation DVTMacroExpansionReplacementOperator_file

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return ([[string stringByDeletingLastPathComponent] stringByAppendingPathComponent:_replExpr]);
}

@end

@implementation DVTMacroExpansionReplacementOperator_base

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	NSString *replacement = [_replExpr stringByAppendingPathExtension:[string pathExtension]];
	return ([[string stringByDeletingLastPathComponent] stringByAppendingPathComponent:replacement]);
}

@end

@implementation DVTMacroExpansionReplacementOperator_suffix

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	NSString *extension = DVTStringByRemovingPrefix(_replExpr, @".");
	return ([[string stringByDeletingPathExtension] stringByAppendingPathExtension:extension]);
}

@end

@implementation DVTMacroExpansionReplacementOperator_relativeto

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	if ([string isAbsolutePath] && [_replExpr isAbsolutePath]) {
		NSString *relative = DVTStringByMakingPathRelativeToBasePath(_replExpr, string);
		return (DVTStringIsNonEmpty(relative) ? relative : @".");
	}
	return (string);
}

@end

@implementation DVTMacroExpansionReplacementOperator_default

- (id)stringByApplyingOperatorToString:(NSString *)string inMacroExpansionScope:(id)scope
{
	(void)scope;
	return (DVTStringIsNonEmpty(string) ? string : _replExpr);
}

- (BOOL)applyToEmptyResult
{
	return (YES);
}

@end
