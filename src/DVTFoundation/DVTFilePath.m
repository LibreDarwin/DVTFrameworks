/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 */

#import "DVTFilePath.h"

@implementation DVTFilePath

+ (DVTFilePath *)filePathForPathString:(NSString *)pathString
{
	if (pathString == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should not be nil", @"pathString"];
	}
	return ([[self alloc] initWithPathString:pathString]);
}

+ (DVTFilePath *)filePathForFileURL:(NSURL *)fileURL
{
	return ([[self alloc] initWithPathString:[fileURL path]]);
}

- (id)initWithPathString:(NSString *)pathString
{
	if (pathString == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ should not be nil", @"pathString"];
	}

	self = [super init];
	if (self != nil) {
		_pathString = [pathString copy];
	}
	return (self);
}

- (NSString *)pathString
{
	return (_pathString);
}

- (NSURL *)fileURL
{
	return ([NSURL fileURLWithPath:_pathString]);
}

- (NSString *)lastPathComponent
{
	return ([_pathString lastPathComponent]);
}

- (NSString *)pathExtension
{
	return ([_pathString pathExtension]);
}

- (NSArray *)directoryContents
{
	return ([[NSFileManager defaultManager] contentsOfDirectoryAtPath:_pathString error:NULL]);
}

- (NSArray *)sortedDirectoryContents
{
	NSArray *contents = [self directoryContents];

	return ([contents sortedArrayUsingSelector:@selector(localizedStandardCompare:)]);
}

- (NSString *)fileTypeAttribute
{
	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:_pathString error:NULL];
	NSString *fileType = [attributes fileType];

	return ((fileType != nil) ? fileType : NSFileTypeUnknown);
}

- (BOOL)isEqual:(id)other
{
	if (other == self) {
		return (YES);
	}
	if (other == nil || ![other isKindOfClass:[DVTFilePath class]]) {
		return (NO);
	}
	return ([_pathString isEqualToString:[(DVTFilePath *)other pathString]]);
}

- (NSUInteger)hash
{
	return ([_pathString hash]);
}

- (NSString *)description
{
	return ([NSString stringWithFormat:@"<DVTFilePath:%p:'%@'>", self, _pathString]);
}

@end
