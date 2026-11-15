/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Clean-room reimplementation of the subset of DVTFoundation's DVTFilePath
 * that this tree needs.
 *
 * Apple's DVTFilePath is a large, cache-backed filesystem abstraction with
 * vnodes, file data types and a global lock.  The subset below reproduces the
 * observable results of the corresponding Apple methods using NSFileManager;
 * no caching is performed.  Path strings are stored verbatim.
 */

#ifndef DVTFOUNDATION_DVTFILEPATH_H
#define DVTFOUNDATION_DVTFILEPATH_H

#import <Foundation/Foundation.h>

@class NSURL;

@interface DVTFilePath : NSObject {
    NSString *_pathString;
}

+ (DVTFilePath *)filePathForPathString:(NSString *)pathString;
+ (DVTFilePath *)filePathForFileURL:(NSURL *)fileURL;

- (id)initWithPathString:(NSString *)pathString;

- (NSString *)pathString;
- (NSURL *)fileURL;
- (NSString *)lastPathComponent;
- (NSString *)pathExtension;

/* The names of the directory's immediate children, unsorted.  nil when the
 * receiver is not a readable directory. */
- (NSArray *)directoryContents;

/* The names of the directory's immediate children, sorted with
 * -[NSString localizedStandardCompare:]. */
- (NSArray *)sortedDirectoryContents;

/* The NSFileType* attribute (NSFileTypeDirectory, NSFileTypeRegular, ...).
 * NSFileTypeUnknown is returned when the file cannot be inspected. */
- (NSString *)fileTypeAttribute;

@end

#endif	/* DVTFOUNDATION_DVTFILEPATH_H */
