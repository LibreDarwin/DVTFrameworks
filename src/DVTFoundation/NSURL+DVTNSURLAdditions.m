//
//  NSURL+DVTNSURLAdditions.m
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

#import "NSURL+DVTNSURLAdditions.h"

#import <Security/SecBase.h>

#import "DVTAssertions.h"
#import "NSURL+DVTSecurityAdditions.h"

@implementation NSURL (DVTNSURLAdditions)

+ (id)dvt_emptyURL
{
    /* The binary creates the URL inside a dispatch_once block and soft-asserts
       that it is non-nil. -[NSURL URLWithString:@""] does not fail in
       practice, and the soft-assertion family belongs to another unit, so the
       check is omitted here. */
    static NSURL *emptyURL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        emptyURL = [NSURL URLWithString:@""];
    });
    return emptyURL;
}

- (BOOL)dvt_isEmptyURL
{
    /* Identity, not -isEqual:, as in the binary: only the cached instance
       counts, and an independently created empty URL does not. */
    return self == [NSURL dvt_emptyURL];
}

- (BOOL)dvt_isFilePathURL
{
    return [self isFileURL] && ![self isFileReferenceURL];
}

+ (id)dvt_fileURLWithAbsoluteOrRelativePath:(NSString *)path
{
    DVTAssert(path != nil, @"(path) != nil", nil,
              @"%@ should be a non-empty string, but it is nil", @"path");
    DVTAssert(CFGetTypeID((__bridge CFStringRef)path) == CFStringGetTypeID(),
              @"CFGetTypeID((CFStringRef)path) == CFStringGetTypeID()", nil,
              @"%@ should be a non-empty string, but it is %@", @"path", [path description]);
    DVTAssert(![path isEqualToString:@""], @"![(path) isEqualToString:@\"\"]", nil,
              @"%@ should be a non-empty string, but it's an empty string", @"path");

    return (__bridge_transfer NSURL *)CFURLCreateWithFileSystemPathRelativeToBase(kCFAllocatorDefault,
                                                                                  (__bridge CFStringRef)path,
                                                                                  kCFURLPOSIXPathStyle,
                                                                                  false,
                                                                                  NULL);
}

- (BOOL)dvt_isGeneneratedInterface
{
    NSString *scheme = [self scheme];
    return [scheme isEqualToString:@"x-xcode-module"]
        || [scheme isEqualToString:@"x-xcode-swift-source-interface"]
        || [scheme isEqualToString:@"x-xcode-swift-header-interface"];
}

- (NSString *)dvt_sanitizedFilePath
{
    NSMutableString *path = [[self path] mutableCopy];
    NSRange homeRange = [path rangeOfString:NSHomeDirectory()];
    if (homeRange.length != 0) {
        [path replaceCharactersInRange:homeRange withString:@"$HOME$"];
    }

    NSRegularExpression *volumeExpression =
        [NSRegularExpression regularExpressionWithPattern:@"\\/Volumes\\/[^\\/]*"
                                                  options:0
                                                    error:NULL];
    NSRange volumeRange = [volumeExpression rangeOfFirstMatchInString:path
                                                              options:0
                                                                range:NSMakeRange(0, [path length])];
    if (volumeRange.length != 0) {
        [path replaceCharactersInRange:volumeRange withString:@"$VOLUME$"];
    }
    return path;
}

@end

@implementation NSURL (DVTSecurityAdditions)

- (unsigned int)dvt_secProtocol
{
    NSString *scheme = [self scheme];
    if ([scheme hasPrefix:@"https"]) {
        return kSecProtocolTypeHTTPS;
    }
    if ([scheme hasPrefix:@"http"]) {
        return kSecProtocolTypeHTTP;
    }
    if ([scheme hasPrefix:@"svn+ssh"]) {
        return kSecProtocolTypeSSH;
    }
    if ([scheme hasPrefix:@"svn"]) {
        return kSecProtocolTypeSVN;
    }
    if ([scheme hasPrefix:@"ssh"]) {
        return kSecProtocolTypeSSH;
    }
    if ([scheme hasPrefix:@"ftp"]) {
        return kSecProtocolTypeFTP;
    }
    return 0;
}

@end
