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

/**
 The receiver's query decoded as key-value assignments.

 A query is a `&`-separated list of `key=value` pairs, with both halves
 percent-decoded; a pair without `=` is a key with an empty value, empty pairs
 are skipped, and a pair whose key decodes to the empty string is dropped.
 `nil` when the receiver has no query.

 @return The decoded assignments, or `nil`.
 */
- (nullable NSDictionary<NSString *, NSString *> *)dvt_documentParameters;

/**
 The receiver's fragment decoded as key-value assignments, with the same
 grammar as `-dvt_documentParameters`. `nil` when the receiver has no fragment.

 @return The decoded assignments, or `nil`.
 */
- (nullable NSDictionary<NSString *, NSString *> *)dvt_locationParameters;

/**
 Builds a URL from its parts: `scheme://path?document#location`.

 A missing scheme omits both the scheme and the `://`, a missing path omits the
 path, and a nil or empty parameter dictionary omits its separator. The path is
 percent-encoded as a path and the parameters as assignments; assignment pairs
 are ordered by key. When every part is absent the answer is the empty URL.

 @param scheme The URL scheme, or `nil`.
 @param path The unescaped path, or `nil`.
 @param documentParameters The query assignments, or `nil`.
 @param locationParameters The fragment assignments, or `nil`.
 @return The URL, or `nil` when its text cannot be parsed.
 */
+ (nullable id)dvt_URLWithScheme:(nullable NSString *)scheme
                            path:(nullable NSString *)path
              documentParameters:(nullable NSDictionary<NSString *, NSString *> *)documentParameters
              locationParameters:(nullable NSDictionary<NSString *, NSString *> *)locationParameters;

/**
 Builds a URL for a non-file scheme and an absolute path, reporting failures.

 The scheme must be a non-empty string other than `file` and the path must not
 be nil; those are assertions. A non-empty relative path, or text that cannot
 be parsed into a URL, makes the method answer `nil` and, when `error` is not
 `NULL`, describes the problem through that pointer. The path is absolute, so
 the answer has an empty host: `x-test:///a/b`. The query is omitted when the
 dictionary is nil or empty.

 @param scheme The non-file scheme.
 @param absolutePath The absolute path to represent, or an empty string.
 @param documentParameters The query assignments, or `nil`.
 @param error On failure, a description of the problem.
 @return The URL, or `nil` on failure.
 */
+ (nullable id)dvt_URLWithNonFileScheme:(NSString *)scheme
                           absolutePath:(NSString *)absolutePath
                     documentParameters:(nullable NSDictionary<NSString *, NSString *> *)documentParameters
                                  error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif /* NS_URL_DVT_URL_ADDITIONS_H */
