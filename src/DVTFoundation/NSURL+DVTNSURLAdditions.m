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
#import "DVTFoundationClassAdditions.h"
#import "NSURL+DVTSecurityAdditions.h"

/**
 The characters an assignment key or value keeps verbatim.

 The set deliberately excludes `%`, `&`, `#`, and `=` but keeps `?`, `;`, and
 `:`; a `+` is not treated as a space, so these are strict percent escapes.
 */
static NSCharacterSet *DVTURLAssignmentCharacterSet(void)
{
    static NSCharacterSet *characterSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        characterSet = [NSCharacterSet characterSetWithCharactersInString:
            @"!$'()*+,-./0123456789:;?@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"];
    });
    return characterSet;
}

/**
 The characters a path keeps verbatim.

 A different set from the assignment one: `&` and `=` survive a path, while `?`
 and `#` do not, because either would end the path component.
 */
static NSCharacterSet *DVTURLPathCharacterSet(void)
{
    static NSCharacterSet *characterSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        characterSet = [NSCharacterSet characterSetWithCharactersInString:
            @"!$&'()*+,-./0123456789:=@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"];
    });
    return characterSet;
}

/**
 Renders a dictionary as `key=value&key2=value2`.

 Keys are visited in sorted order so the text is stable, and both halves are
 percent-encoded with the assignment set. An empty dictionary answers the empty
 string.
 */
static NSString *DVTStringByEncodingDictionaryAsURLEscapedAssignments(NSDictionary<NSString *, NSString *> *dict)
{
    DVTAssert(dict != nil, @"(dict) != nil", nil,
              @"%@ should be a dictionary, but it is nil", @"dict");
    DVTAssert(CFGetTypeID((__bridge CFDictionaryRef)dict) == CFDictionaryGetTypeID(),
              @"CFGetTypeID((CFDictionaryRef)dict) == CFDictionaryGetTypeID()", nil,
              @"%@ should be a dictionary, but it is %@", @"dict", [dict description]);

    NSCharacterSet *allowedCharacters = DVTURLAssignmentCharacterSet();
    NSMutableString *result = [NSMutableString string];
    NSArray<NSString *> *keys = [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)];
    BOOL first = YES;
    for (NSString *key in keys) {
        if (!first) {
            [result appendString:@"&"];
        }
        [result appendString:[key stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacters]];
        [result appendString:@"="];
        NSString *value = [dict objectForKeyedSubscript:key];
        [result appendString:[value stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacters]];
        first = NO;
    }
    return result;
}

/**
 Parses `key=value&key2=value2` back into a dictionary.

 Empty pairs are skipped. A pair without `=` is a key with an empty value; a
 half that fails to percent-decode becomes the empty string, and a pair whose
 key is finally empty is dropped, because an empty key cannot be stored.
 */
static NSDictionary<NSString *, NSString *> *DVTDictionaryByDecodingStringFromURLEscapedAssignments(NSString *string)
{
    DVTAssert(CFGetTypeID((__bridge CFStringRef)string) == CFStringGetTypeID(),
              @"CFGetTypeID((CFStringRef)string) == CFStringGetTypeID()", nil,
              @"%@ should be a string, but it is %@", @"string", [string description]);

    NSMutableDictionary<NSString *, NSString *> *dictionary = [NSMutableDictionary dictionary];
    NSArray<NSString *> *components = [string componentsSeparatedByString:@"&"];
    for (NSString *component in components) {
        if (component.length == 0) {
            continue;
        }

        NSString *key;
        NSString *value;
        NSRange equalsRange = [component rangeOfString:@"="];
        if (equalsRange.location == NSNotFound) {
            NSString *decodedKey = [component stringByRemovingPercentEncoding];
            key = decodedKey != nil ? decodedKey : @"";
            value = @"";
        } else {
            NSString *keyPart = [component substringToIndex:equalsRange.location];
            NSString *decodedKey = [keyPart stringByRemovingPercentEncoding];
            key = decodedKey != nil ? decodedKey : @"";

            NSUInteger valueStart = equalsRange.location + equalsRange.length;
            NSString *valuePart = [component substringFromIndex:valueStart];
            NSString *decodedValue = [valuePart stringByRemovingPercentEncoding];
            value = decodedValue != nil ? decodedValue : @"";
        }

        DVTAssert(CFGetTypeID((__bridge CFStringRef)key) == CFStringGetTypeID(),
                  @"CFGetTypeID((CFStringRef)key) == CFStringGetTypeID()", nil,
                  @"%@ should be a string, but it is %@", @"key", [key description]);
        DVTAssert(CFGetTypeID((__bridge CFStringRef)value) == CFStringGetTypeID(),
                  @"CFGetTypeID((CFStringRef)val) == CFStringGetTypeID()", nil,
                  @"%@ should be a string, but it is %@", @"val", [value description]);

        if (![key isEqualToString:@""]) {
            [dictionary setObject:value forKey:key];
        }
    }
    return dictionary;
}

@interface NSURL (DVTNSURLAdditionsPrivate)

+ (nullable id)_dvt_persistableAndCompatibleURLWithScheme:(nullable NSString *)scheme
                                                     path:(nullable NSString *)path
                                       documentParameters:(nullable NSDictionary<NSString *, NSString *> *)documentParameters
                                       locationParameters:(nullable NSDictionary<NSString *, NSString *> *)locationParameters;

@end

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

- (NSDictionary<NSString *, NSString *> *)dvt_documentParameters
{
    NSString *query = [self query];
    return query != nil ? DVTDictionaryByDecodingStringFromURLEscapedAssignments(query) : nil;
}

- (NSDictionary<NSString *, NSString *> *)dvt_locationParameters
{
    NSString *fragment = [self fragment];
    return fragment != nil ? DVTDictionaryByDecodingStringFromURLEscapedAssignments(fragment) : nil;
}

+ (id)dvt_URLWithScheme:(NSString *)scheme
                   path:(NSString *)path
     documentParameters:(NSDictionary<NSString *, NSString *> *)documentParameters
     locationParameters:(NSDictionary<NSString *, NSString *> *)locationParameters
{
    return [self _dvt_persistableAndCompatibleURLWithScheme:scheme
                                                       path:path
                                         documentParameters:documentParameters
                                         locationParameters:locationParameters];
}

+ (id)_dvt_persistableAndCompatibleURLWithScheme:(NSString *)scheme
                                            path:(NSString *)path
                              documentParameters:(NSDictionary<NSString *, NSString *> *)documentParameters
                              locationParameters:(NSDictionary<NSString *, NSString *> *)locationParameters
{
    NSMutableString *builder = [NSMutableString string];
    if (scheme != nil) {
        [builder appendString:scheme];
        [builder appendString:@"://"];
    }
    if (path != nil) {
        [builder appendString:[path stringByAddingPercentEncodingWithAllowedCharacters:DVTURLPathCharacterSet()]];
    }
    if ([documentParameters count] != 0) {
        [builder appendString:@"?"];
        [builder appendString:DVTStringByEncodingDictionaryAsURLEscapedAssignments(documentParameters)];
    }
    if ([locationParameters count] != 0) {
        [builder appendString:@"#"];
        [builder appendString:DVTStringByEncodingDictionaryAsURLEscapedAssignments(locationParameters)];
    }

    NSString *urlString;
    if (builder.length != 0) {
        /* -dvt_sharedCopy of an immutable string is the string itself, and the
           builder's text is already a complete immutable string here. */
        urlString = [builder copy];
        DVTAssert(urlString != nil, @"((urlString)) != nil", nil,
                  @"%@ should not be nil.", @"(urlString)");
    } else {
        urlString = @"";
    }

    NSURL *nsurl = [NSURL URLWithString:urlString];
    DVTAssert(nsurl != nil, @"nsurl != nullptr", nil,
              @"couldn't create an URL from the string '%@'", urlString);
    return nsurl;
}

+ (id)dvt_URLWithNonFileScheme:(NSString *)scheme
                  absolutePath:(NSString *)absolutePath
            documentParameters:(NSDictionary<NSString *, NSString *> *)documentParameters
                         error:(NSError **)error
{
    DVTAssert(scheme != nil, @"(scheme) != nil", nil,
              @"%@ should be a non-empty string, but it is nil", @"scheme");
    DVTAssert(CFGetTypeID((__bridge CFStringRef)scheme) == CFStringGetTypeID(),
              @"CFGetTypeID((CFStringRef)scheme) == CFStringGetTypeID()", nil,
              @"%@ should be a non-empty string, but it is %@", @"scheme", [scheme description]);
    DVTAssert(![scheme isEqualToString:@""], @"![(scheme) isEqualToString:@\"\"]", nil,
              @"%@ should be a non-empty string, but it's an empty string", @"scheme");
    DVTAssert(![scheme isEqualToString:NSURLFileScheme],
              @"![scheme isEqualToString:NSURLFileScheme]", nil, @"");
    DVTAssert(absolutePath != nil, @"((absolutePath)) != nil", nil,
              @"%@ should not be nil.", @"(absolutePath)");

    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = scheme;
    components.host = @"";
    if ([absolutePath dvt_isNonEmpty] && ![absolutePath isAbsolutePath]) {
        NSString *message = [NSString stringWithFormat:@"Cannot use scheme (%@) with a non-absolute path (%@)",
                                                       scheme, absolutePath];
        if (error != NULL) {
            *error = [NSError dvt_errorWithMessage:message];
        }
        return nil;
    }
    components.path = absolutePath;

    if ([documentParameters count] != 0) {
        components.percentEncodedQuery = DVTStringByEncodingDictionaryAsURLEscapedAssignments(documentParameters);
    }

    NSURL *url = [components URL];
    if (url != nil) {
        return url;
    }

    NSString *message = [NSString stringWithFormat:@"Failed to create URL with scheme (%@) absolutePath (%@) documentParameters (%@)",
                                                   scheme, absolutePath, documentParameters];
    if (error != NULL) {
        *error = [NSError dvt_errorWithMessage:message];
    }
    return nil;
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
