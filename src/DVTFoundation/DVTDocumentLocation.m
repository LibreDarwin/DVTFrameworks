//
//  DVTDocumentLocation.m
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

#import "DVTDocumentLocationInternal.h"
#import "DVTDocumentLocationConversion.h"
#import "DVTTextDocumentLocation.h"

#import <objc/runtime.h>

NSString *const DVTLocationErrorDomain = @"com.apple.DVTFoundation";

NSInteger const DVTLocationGenericErrorCode = -1;

NSString *const DVTPersistentTimestampKey = @"Timestamp";
NSString *const DVTPersistentStartingColumnNumberKey = @"StartingColumnNumber";
NSString *const DVTPersistentEndingColumnNumberKey = @"EndingColumnNumber";
NSString *const DVTPersistentStartingLineNumberKey = @"StartingLineNumber";
NSString *const DVTPersistentEndingLineNumberKey = @"EndingLineNumber";
NSString *const DVTPersistentCharacterRangeLocationKey = @"CharacterRangeLoc";
NSString *const DVTPersistentCharacterRangeLengthKey = @"CharacterRangeLen";
NSString *const DVTPersistentLocationEncodingKey = @"LocationEncoding";

static NSString *const DVTArchiveDocumentURLKey = @"documentURL";
static NSString *const DVTArchiveTimestampKey = @"timestamp";

@implementation DVTDocumentLocation

@synthesize documentURL = _documentURL;
@synthesize timestamp = _timestamp;

- (instancetype)init
{
    return [self initWithDocumentURL:nil timestamp:nil];
}

- (instancetype)initWithDocumentURL:(NSURL *)documentURL timestamp:(NSNumber *)timestamp
{
    self = [super init];
    if (self) {
        _documentURL = documentURL;
        _timestamp = timestamp;
    }
    return self;
}

#pragma mark - URL components

- (NSString *)documentURLString
{
    return _documentURL.absoluteString;
}

- (NSString *)documentScheme
{
    return _documentURL.scheme;
}

- (NSString *)documentPath
{
    return _documentURL.path;
}

/*
 The query is split on '&' and then on the first '=' of each pair, so a key with
 no '=' maps to an empty string and a value containing '=' keeps everything after
 the first one. Query components that cannot be split at all are kept under the
 empty key rather than dropped.
 */
- (NSDictionary<NSString *, NSString *> *)documentParameters
{
    NSString *query = _documentURL.query;
    if (query.length == 0) {
        return @{};
    }
    NSMutableDictionary<NSString *, NSString *> *parameters = [NSMutableDictionary dictionary];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSRange separator = [pair rangeOfString:@"="];
        if (separator.location == NSNotFound) {
            parameters[pair] = @"";
        } else {
            NSString *key = [pair substringToIndex:separator.location];
            NSString *value = [pair substringFromIndex:NSMaxRange(separator)];
            parameters[key] = value;
        }
    }
    return parameters;
}

- (NSString *)pasteboardRepresentation
{
    return _documentURL.path;
}

- (NSDictionary<NSString *, id> *)locationParameters
{
    return @{};
}

#pragma mark - Identity

/*
 Apple compares the URL first with a pointer test, then with -isEqual:, and only
 reaches for -isEqualToCounterpartWithIdenticalClass:compareTimestamps: once both
 objects are known to be of exactly the same class. A subclass therefore never
 compares equal to its superclass, and a nil timestamp only matches another nil.
 */
- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (object == nil || object_getClass(object) != object_getClass(self)) {
        return NO;
    }
    return [self isEqualToCounterpartWithIdenticalClass:object compareTimestamps:YES];
}

- (BOOL)isEqualDisregardingTimestamp:(id)object
{
    if (self == object) {
        return YES;
    }
    if (object == nil || object_getClass(object) != object_getClass(self)) {
        return NO;
    }
    return [self isEqualToCounterpartWithIdenticalClass:object compareTimestamps:NO];
}

static BOOL DVTEqualObjects(id lhs, id rhs)
{
    if (lhs == rhs) {
        return YES;
    }
    if (lhs == nil || rhs == nil) {
        return NO;
    }
    return [lhs isEqual:rhs];
}

- (BOOL)isEqualToCounterpartWithIdenticalClass:(DVTDocumentLocation *)counterpart
                             compareTimestamps:(BOOL)compareTimestamps
{
    BOOL equal = DVTEqualObjects(_documentURL, counterpart.documentURL);
    if (compareTimestamps && equal) {
        equal = DVTEqualObjects(_timestamp, counterpart.timestamp);
    }
    return equal;
}

/*
 Deliberately the URL alone. Two locations that differ only in timestamp are
 unequal but hash alike, which keeps a location usable as a dictionary key across
 a re-resolve even though -isEqual: would separate them.
 */
- (NSUInteger)hash
{
    return _documentURL.hash;
}

- (NSComparisonResult)compare:(id)object
{
    if (self == object) {
        return NSOrderedSame;
    }
    if (![object isKindOfClass:[DVTDocumentLocation class]]) {
        return NSOrderedDescending;
    }
    return [self.documentURLString compare:((DVTDocumentLocation *)object).documentURLString];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ timestamp:%@, documentURL:%@", [super description],
                                      _timestamp, _documentURL];
}

#pragma mark - Copying

/*
 A location never changes after initialization, so a copy can be the receiver
 itself. -copyWithURL: is the operation that has to build a new object, because
 that one really does differ.
 */
- (instancetype)copyWithZone:(NSZone *)zone
{
    return self;
}

- (instancetype)copyWithURL:(NSURL *)url
{
    return [[[self class] alloc] initWithDocumentURL:url timestamp:_timestamp];
}

#pragma mark - Persistent parameters

/*
 Parameters are sorted before being written into the fragment, so a persisted
 location has one spelling regardless of the order the subclass hooks happened to
 run in.
 */
static NSArray<NSURLQueryItem *> *DVTPersistentQueryItems(NSDictionary<NSString *, NSString *> *parameters)
{
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    for (NSString *key in [parameters.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [items addObject:[NSURLQueryItem queryItemWithName:key value:parameters[key]]];
    }
    return items;
}

/*
 The fragment is percent-*not*-encoded here: Apple writes the '&' and '='
 separators literally, so the fragment is assigned as an already-encoded string
 and read back from -percentEncodedFragment rather than -fragment.
 */
static NSString *DVTPersistentFragment(NSDictionary<NSString *, NSString *> *parameters)
{
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    for (NSString *key in [parameters.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, parameters[key]]];
    }
    return [pairs componentsJoinedByString:@"&"];
}

NSDictionary<NSString *, NSString *> *DVTPersistentParametersFromFragment(NSString *fragment)
{
    NSMutableDictionary<NSString *, NSString *> *parameters = [NSMutableDictionary dictionary];
    if (fragment.length == 0) {
        return parameters;
    }
    for (NSString *pair in [fragment componentsSeparatedByString:@"&"]) {
        NSRange separator = [pair rangeOfString:@"="];
        if (separator.location != NSNotFound) {
            parameters[[pair substringToIndex:separator.location]] =
                [pair substringFromIndex:NSMaxRange(separator)];
        }
    }
    return parameters;
}

/*
  Apple leaves both of these alone: a caller that reaches them gets an empty
  dictionary back, even for a fully specified text location, while the persistable
  representation still carries every field. So the fragment is assembled by
  -DVTPopulatePersistentParameters below rather than through these hooks.
 */
- (void)populateLocationParameters:(NSMutableDictionary<NSString *, id> *)locationParameters
{
    [self _populateLocationParameters:locationParameters decodableClassName:NULL error:NULL];
}

- (BOOL)_populateLocationParameters:(NSMutableDictionary<NSString *, id> *)locationParameters
              decodableClassName:(NSString **)decodableClassName
                             error:(NSError **)error
{
    if (decodableClassName != NULL) {
        *decodableClassName = NSStringFromClass([self class]);
    }
    return YES;
}

/*
  Neither class overrides the persistable builder, so this cannot be a method a
  subclass contributes to without putting a selector in the surface Apple does not
  have. The document-location family is closed -- the only subclass is
  DVTTextDocumentLocation -- so the fields are selected by class instead. That is
  why this header knows about the subclass.
 */
/*
  Records `value` under `key` unless it is `absent`.

  Each key is dropped on its own, not as a group: a location naming only its
  character range still records that range, and one naming only its lines still
  records those. That independence is what lets a range with no location
  (`{NSNotFound, 5}`) survive as a length on its own.
 */
static void DVTPutParameter(NSMutableDictionary<NSString *, NSString *> *parameters, NSString *key, NSString *value,
                            BOOL absent)
{
    if (!absent) {
        parameters[key] = value;
    }
}

/*
  The superclass owns the timestamp and the encoding; a text location adds its
  four line and column numbers and its character range.

  A key naming no position is left out entirely rather than recorded as
  `NSNotFound`, which keeps the representation of a location that names nothing
  down to just the document it belongs to.
 */
static void DVTPopulatePersistentParameters(DVTDocumentLocation *location,
                                            NSMutableDictionary<NSString *, NSString *> *parameters)
{
    NSNumber *timestamp = location.timestamp;
    if (timestamp != nil) {
        parameters[DVTPersistentTimestampKey] = timestamp.stringValue;
    }
    if (![location isKindOfClass:[DVTTextDocumentLocation class]]) {
        return;
    }
    DVTTextDocumentLocation *text = (DVTTextDocumentLocation *)location;

    /* Native is the encoding a location carries unless it says otherwise, so
       recording it would only make every such location spell out the default. */
    DVTPutParameter(parameters, DVTPersistentLocationEncodingKey,
                    [NSString stringWithFormat:@"%ld", (long)text.locationEncoding],
                    text.locationEncoding == DVTLocationEncodingNative);

    DVTPutParameter(parameters, DVTPersistentStartingColumnNumberKey,
                    [NSString stringWithFormat:@"%ld", (long)text.startingColumnNumber],
                    text.startingColumnNumber == NSNotFound);
    DVTPutParameter(parameters, DVTPersistentEndingColumnNumberKey,
                    [NSString stringWithFormat:@"%ld", (long)text.endingColumnNumber],
                    text.endingColumnNumber == NSNotFound);
    DVTPutParameter(parameters, DVTPersistentStartingLineNumberKey,
                    [NSString stringWithFormat:@"%ld", (long)text.startingLineNumber],
                    text.startingLineNumber == NSNotFound);
    DVTPutParameter(parameters, DVTPersistentEndingLineNumberKey,
                    [NSString stringWithFormat:@"%ld", (long)text.endingLineNumber],
                    text.endingLineNumber == NSNotFound);

    NSRange characterRange = text.characterRange;
    DVTPutParameter(parameters, DVTPersistentCharacterRangeLocationKey,
                    [NSString stringWithFormat:@"%lu", (unsigned long)characterRange.location],
                    characterRange.location == NSNotFound);
    DVTPutParameter(parameters, DVTPersistentCharacterRangeLengthKey,
                    [NSString stringWithFormat:@"%lu", (unsigned long)characterRange.length], characterRange.length == 0);
}

- (NSURL *)persistableURLRepresentationAndDecodableClassName:(NSString **)decodableClassName
                                                     error:(NSError **)error
{
    if (decodableClassName != NULL) {
        *decodableClassName = NSStringFromClass([self class]);
    }
    if (_documentURL == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:DVTLocationErrorDomain
                                         code:DVTLocationGenericErrorCode
                                     userInfo:@{NSLocalizedDescriptionKey: @"The location has no document URL."}];
        }
        return nil;
    }
    NSMutableDictionary<NSString *, NSString *> *parameters = [NSMutableDictionary dictionary];
    DVTPopulatePersistentParameters(self, parameters);
    NSURLComponents *components = [NSURLComponents componentsWithURL:_documentURL resolvingAgainstBaseURL:NO];
    components.percentEncodedFragment = DVTPersistentFragment(parameters);
    return components.URL;
}

- (NSString *)persistableStringRepresentationAndDecodableClassName:(NSString **)decodableClassName
                                                           error:(NSError **)error
{
    NSURL *url = [self persistableURLRepresentationAndDecodableClassName:decodableClassName error:error];
    return url.absoluteString;
}

- (instancetype)initWithURL:(NSURL *)url
         locationParameters:(NSDictionary<NSString *, id> *)locationParameters
                      error:(NSError **)error
{
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *fragment = urlComponents.percentEncodedFragment;
    NSMutableDictionary<NSString *, NSString *> *parameters = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in urlComponents.queryItems) {
        if (item.value != nil) {
            parameters[item.name] = item.value;
        }
    }
    [parameters addEntriesFromDictionary:DVTPersistentParametersFromFragment(fragment)];
    for (id key in locationParameters) {
        id value = locationParameters[key];
        if ([value isKindOfClass:NSString.class]) {
            parameters[key] = value;
        }
    }
    /*
     A consumed parameter is not part of the document's address, so the timestamp
     -- the one key the superclass owns -- is dropped from the stored URL. Keys a
     subclass understands are left in place for that subclass to deal with. The
     fragment is rebuilt from the surviving parameters rather than edited in
     place, which is what puts it back in sorted order.
     */
    NSMutableDictionary<NSString *, NSString *> *retained = [DVTPersistentParametersFromFragment(fragment) mutableCopy];
    [retained removeObjectForKey:DVTPersistentTimestampKey];
    urlComponents.percentEncodedFragment = retained.count > 0 ? DVTPersistentFragment(retained) : nil;

    self = [self initWithDocumentURL:urlComponents.URL timestamp:nil];
    if (self == nil) {
        return nil;
    }
    /*
     A subclass reads its own keys back out of the fragment in its own
     -initWithURL:locationParameters:error:. The timestamp is consumed here,
     because this is the only class that owns it.
     */
    NSString *timestamp = parameters[DVTPersistentTimestampKey];
    if (timestamp != nil) {
        _timestamp = @(timestamp.integerValue);
    }
    return self;
}

#pragma mark - Coding

/*
  -initWithCoder: decodes this class's own fields rather than dispatching to
  -dvt_initFromDeserializer:, because a subclass overrides both and would
  otherwise decode its fields twice.
 */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *urlString = [coder decodeObjectOfClass:NSString.class forKey:DVTArchiveDocumentURLKey];
    NSNumber *timestamp = [coder decodeObjectOfClass:NSNumber.class forKey:DVTArchiveTimestampKey];
    return [self initWithDocumentURL:(urlString != nil ? [NSURL URLWithString:urlString] : nil)
                            timestamp:timestamp];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_documentURL.absoluteString forKey:DVTArchiveDocumentURLKey];
    [coder encodeObject:_timestamp forKey:DVTArchiveTimestampKey];
}

- (instancetype)dvt_initFromDeserializer:(NSCoder *)deserializer
{
    NSString *urlString = [deserializer decodeObjectOfClass:NSString.class forKey:DVTArchiveDocumentURLKey];
    NSNumber *timestamp = [deserializer decodeObjectOfClass:NSNumber.class forKey:DVTArchiveTimestampKey];
    return [self initWithDocumentURL:(urlString != nil ? [NSURL URLWithString:urlString] : nil)
                            timestamp:timestamp];
}

- (void)dvt_writeToSerializer:(NSCoder *)serializer
{
    [serializer encodeObject:_documentURL.absoluteString forKey:DVTArchiveDocumentURLKey];
    [serializer encodeObject:_timestamp forKey:DVTArchiveTimestampKey];
}

#pragma mark - Swift macros

- (DVTDocumentLocation *)rootMacroLocationIfApplicable
{
    return nil;
}

#pragma mark - Construction

+ (BOOL)supportsSecureCoding
{
    return YES;
}

+ (BOOL)supportsEncodingToPersistableURL
{
    return YES;
}

+ (BOOL)isDocumentLocation:(DVTDocumentLocation *)location
    equalToDocumentLocation:(DVTDocumentLocation *)otherLocation
         compareTimestamps:(BOOL)compareTimestamps
{
    if (location == otherLocation) {
        return YES;
    }
    if (location == nil || otherLocation == nil) {
        return NO;
    }
    if (object_getClass(location) != object_getClass(otherLocation)) {
        return NO;
    }
    return [location isEqualToCounterpartWithIdenticalClass:otherLocation
                                         compareTimestamps:compareTimestamps];
}

+ (Class)documentLocationClassNamedLoadingIfNeeded:(NSString *)name
{
    Class locationClass = NSClassFromString(name);
    if (locationClass == Nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"There is no document location class named %@.", name];
    }
    return locationClass;
}

+ (id)documentLocationWithURLScheme:(NSString *)scheme
                               path:(NSString *)path
                 documentParameters:(id)documentParameters
                  locationParameters:(NSDictionary<NSString *, id> *)locationParameters
{
    /*
     Assembling the string first, rather than setting -scheme and -path, is what
     keeps the empty authority in `file:///tmp/z.txt`; -path alone collapses the
     result to `file:/tmp/z.txt`.
     */
    NSURLComponents *components = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"%@://%@", scheme, path]];
    if (components == nil) {
        components = [[NSURLComponents alloc] init];
        components.scheme = scheme;
        components.path = path;
    }
    if ([documentParameters isKindOfClass:NSDictionary.class]) {
        components.queryItems = DVTPersistentQueryItems(documentParameters);
    } else if ([documentParameters isKindOfClass:NSString.class]) {
        components.percentEncodedQuery = documentParameters;
    }
    NSError *error = nil;
    return [[self alloc] initWithURL:components.URL
                   locationParameters:locationParameters ?: @{}
                                error:&error];
}

+ (id)deserializedDocumentLocationForClassName:(NSString *)className
                          stringRepresentation:(NSString *)stringRepresentation
                                        error:(NSError **)error
{
    return [self deserializedDocumentLocationForClassName:className
                                    stringRepresentation:stringRepresentation
                                     allowLossyDecoding:NO
                                                  error:error];
}

+ (id)deserializedDocumentLocationForClassName:(NSString *)className
                          stringRepresentation:(NSString *)stringRepresentation
                           allowLossyDecoding:(BOOL)allowLossyDecoding
                                        error:(NSError **)error
{
    Class locationClass = NSClassFromString(className);
    if (locationClass == Nil || ![locationClass isSubclassOfClass:[DVTDocumentLocation class]]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:DVTLocationErrorDomain
                                         code:DVTLocationGenericErrorCode
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"There is no document location class named %@.", className]}];
        }
        return nil;
    }
    NSURL *url = [NSURL URLWithString:stringRepresentation];
    if (url == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:DVTLocationErrorDomain
                                         code:DVTLocationGenericErrorCode
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"The representation is not a valid URL."}];
        }
        return nil;
    }
    return [[locationClass alloc] initWithURL:url locationParameters:@{} error:error];
}

@end
