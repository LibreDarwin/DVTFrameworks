//
//  NSURL+DVTNSURLAdditions.h
//  DVTFoundation
//
//  Copyright (C) 2026, LibreDarwin
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its
//     contributors may be used to endorse or promote products derived from
//     this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED.
//

#ifndef NS_URL_DVT_URL_ADDITIONS_H
#define NS_URL_DVT_URL_ADDITIONS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Predicates and path handling for URLs, plus the shared empty URL.

 The empty URL is a cached instance, and `-dvt_isEmptyURL` tests for that
 instance specifically rather than for an empty string: the identity test is
 what the binary does, and `+dvt_emptyURL` is the way to obtain the object it
 recognises.

 `-dvt_isGeneneratedInterface` keeps the original's spelling of "generated".
 */
@interface NSURL (DVTNSURLAdditions)

/// The shared empty URL (`[NSURL URLWithString:@""]`), created once.
+ (id)dvt_emptyURL;

/// `YES` only when the receiver is the instance from `+dvt_emptyURL`.
- (BOOL)dvt_isEmptyURL;

/// `YES` for file URLs that name a path rather than a file reference.
- (BOOL)dvt_isFilePathURL;

/**
 Creates a file URL for `path` without touching the file system.

 The path may be absolute or relative; it is parsed with the POSIX path style
 and is not marked as a directory. A relative path resolves against the current
 working directory, as `CFURLCreateWithFileSystemPathRelativeToBase` does.
 `path` must be a non-empty string; anything else is a programmer error and
 fails an assertion.

 @param path The file system path to represent.
 @return A file URL for `path`.
 */
+ (id)dvt_fileURLWithAbsoluteOrRelativePath:(NSString *)path;

/// `YES` when the scheme is one of the generated-interface schemes.
- (BOOL)dvt_isGeneneratedInterface;

/**
 The receiver's path with the home directory and volume names hidden.

 The first occurrence of `NSHomeDirectory()` becomes `$HOME$` and the first
 `/Volumes/<name>` component becomes `$VOLUME$`, so the answer is safe to show
 in logs and diagnostics.
 */
- (nullable NSString *)dvt_sanitizedFilePath;

@end

NS_ASSUME_NONNULL_END

#endif /* NS_URL_DVT_URL_ADDITIONS_H */
