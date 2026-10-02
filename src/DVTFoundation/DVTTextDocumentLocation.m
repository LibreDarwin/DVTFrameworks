//
//  DVTTextDocumentLocation.m
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

#import "DVTTextDocumentLocation.h"
#import "DVTDocumentLocationInternal.h"

#import <objc/runtime.h>

static NSString *const DVTStartingColumnNumberKey = @"startingColumnNumber";
static NSString *const DVTEndingColumnNumberKey = @"endingColumnNumber";
static NSString *const DVTStartingLineNumberKey = @"startingLineNumber";
static NSString *const DVTEndingLineNumberKey = @"endingLineNumber";
static NSString *const DVTCharacterRangeLocationKey = @"characterRangeLoc";
static NSString *const DVTCharacterRangeLengthKey = @"characterRangeLen";
static NSString *const DVTLocationEncodingKey = @"locationEncoding";

/*
 The ivars are declared explicitly and in Apple's order, so the offsets are fixed
 by this list rather than by the order the properties happen to be synthesized in:
 columns at +24 and +32, lines at +40 and +48, the character range at +56, the
 encoding at +72 and the unretained represented object at +80.

 -lineRange has a getter but no ivar and no @dynamic, which is what Apple reports
 for it: a plain computed property, not a dynamically dispatched one.
 */
@implementation DVTTextDocumentLocation {
    NSInteger _startingColumnNumber;
    NSInteger _endingColumnNumber;
    NSInteger _startingLineNumber;
    NSInteger _endingLineNumber;
    NSRange _characterRange;
    NSInteger _locationEncoding;
    __unsafe_unretained id _representedObject;
}

@synthesize startingColumnNumber = _startingColumnNumber;
@synthesize endingColumnNumber = _endingColumnNumber;
@synthesize startingLineNumber = _startingLineNumber;
@synthesize endingLineNumber = _endingLineNumber;
@synthesize characterRange = _characterRange;
@synthesize locationEncoding = _locationEncoding;
@synthesize representedObject = _representedObject;

#pragma mark - Initializers

- (instancetype)initWithDocumentURL:(NSURL *)documentURL timestamp:(NSNumber *)timestamp
{
    self = [super initWithDocumentURL:documentURL timestamp:timestamp];
    if (self) {
        _startingColumnNumber = NSNotFound;
        _endingColumnNumber = NSNotFound;
        _startingLineNumber = NSNotFound;
        _endingLineNumber = NSNotFound;
        _characterRange = NSMakeRange(NSNotFound, 0);
        _locationEncoding = 0;
    }
    return self;
}

- (instancetype)_initWithDocumentURL:(NSURL *)documentURL
                           timestamp:(NSNumber *)timestamp
                startingColumnNumber:(NSInteger)startingColumnNumber
                  endingColumnNumber:(NSInteger)endingColumnNumber
                   startingLineNumber:(NSInteger)startingLineNumber
                     endingLineNumber:(NSInteger)endingLineNumber
                      characterRange:(NSRange)characterRange
                    locationEncoding:(NSInteger)locationEncoding
{
    /*
     Apple validates before it calls -initWithDocumentURL:timestamp:, so an
     inconsistent location raises before any ivar is written.
     */
    [[self class] assertValidityOfStartingColumnNumber:startingColumnNumber
                                    endingColumnNumber:endingColumnNumber
                                     startingLineNumber:startingLineNumber
                                       endingLineNumber:endingLineNumber
                                        characterRange:characterRange
                                      locationEncoding:locationEncoding];
    self = [self initWithDocumentURL:documentURL timestamp:timestamp];
    if (self) {
        _startingColumnNumber = startingColumnNumber;
        _endingColumnNumber = endingColumnNumber;
        _startingLineNumber = startingLineNumber;
        _endingLineNumber = endingLineNumber;
        _characterRange = characterRange;
        _locationEncoding = locationEncoding;
    }
    return self;
}

- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(NSNumber *)timestamp
               startingColumnNumber:(NSInteger)startingColumnNumber
                 endingColumnNumber:(NSInteger)endingColumnNumber
                  startingLineNumber:(NSInteger)startingLineNumber
                    endingLineNumber:(NSInteger)endingLineNumber
                     characterRange:(NSRange)characterRange
                   locationEncoding:(NSInteger)locationEncoding
{
    return [self _initWithDocumentURL:documentURL
                             timestamp:timestamp
                  startingColumnNumber:startingColumnNumber
                    endingColumnNumber:endingColumnNumber
                     startingLineNumber:startingLineNumber
                       endingLineNumber:endingLineNumber
                        characterRange:characterRange
                      locationEncoding:locationEncoding];
}

- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(NSNumber *)timestamp
               startingColumnNumber:(NSInteger)startingColumnNumber
                 endingColumnNumber:(NSInteger)endingColumnNumber
                  startingLineNumber:(NSInteger)startingLineNumber
                    endingLineNumber:(NSInteger)endingLineNumber
                   locationEncoding:(NSInteger)locationEncoding
{
    return [self _initWithDocumentURL:documentURL
                             timestamp:timestamp
                  startingColumnNumber:startingColumnNumber
                    endingColumnNumber:endingColumnNumber
                     startingLineNumber:startingLineNumber
                       endingLineNumber:endingLineNumber
                        characterRange:NSMakeRange(NSNotFound, 0)
                      locationEncoding:locationEncoding];
}

- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(NSNumber *)timestamp
               startingColumnNumber:(NSInteger)startingColumnNumber
                 endingColumnNumber:(NSInteger)endingColumnNumber
                  startingLineNumber:(NSInteger)startingLineNumber
                    endingLineNumber:(NSInteger)endingLineNumber
{
    return [self _initWithDocumentURL:documentURL
                             timestamp:timestamp
                  startingColumnNumber:startingColumnNumber
                    endingColumnNumber:endingColumnNumber
                     startingLineNumber:startingLineNumber
                       endingLineNumber:endingLineNumber
                        characterRange:NSMakeRange(NSNotFound, 0)
                      locationEncoding:0];
}

- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(NSNumber *)timestamp
               startingColumnNumber:(NSInteger)startingColumnNumber
                 endingColumnNumber:(NSInteger)endingColumnNumber
                  startingLineNumber:(NSInteger)startingLineNumber
                    endingLineNumber:(NSInteger)endingLineNumber
                     characterRange:(NSRange)characterRange
{
    return [self _initWithDocumentURL:documentURL
                             timestamp:timestamp
                  startingColumnNumber:startingColumnNumber
                    endingColumnNumber:endingColumnNumber
                     startingLineNumber:startingLineNumber
                       endingLineNumber:endingLineNumber
                        characterRange:characterRange
                      locationEncoding:0];
}

/*
 The stored line numbers are exclusive at the end, so a length-n range becomes
 {location, location + n - 1}. That is what makes -lineRange read back unchanged.
 */
- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(NSNumber *)timestamp
                           lineRange:(NSRange)lineRange
{
    return [self _initWithDocumentURL:documentURL
                             timestamp:timestamp
                  startingColumnNumber:NSNotFound
                    endingColumnNumber:NSNotFound
                     startingLineNumber:(NSInteger)lineRange.location
                       endingLineNumber:(NSInteger)(lineRange.location + lineRange.length - 1)
                        characterRange:NSMakeRange(NSNotFound, 0)
                      locationEncoding:0];
}

- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(NSNumber *)timestamp
                      characterRange:(NSRange)characterRange
{
    return [self _initWithDocumentURL:documentURL
                             timestamp:timestamp
                  startingColumnNumber:NSNotFound
                    endingColumnNumber:NSNotFound
                     startingLineNumber:NSNotFound
                       endingLineNumber:NSNotFound
                        characterRange:characterRange
                      locationEncoding:0];
}

- (instancetype)initWithDocumentURL:(NSURL *)documentURL
                          timestamp:(NSNumber *)timestamp
                      characterRange:(NSRange)characterRange
                    locationEncoding:(NSInteger)locationEncoding
{
    return [self _initWithDocumentURL:documentURL
                             timestamp:timestamp
                  startingColumnNumber:NSNotFound
                    endingColumnNumber:NSNotFound
                     startingLineNumber:NSNotFound
                       endingLineNumber:NSNotFound
                        characterRange:characterRange
                      locationEncoding:locationEncoding];
}

#pragma mark - Derived ranges

/*
 An unspecified line collapses the whole range to {NSNotFound, 0} rather than
 producing the arithmetic result of two sentinels, and a fully specified location
 gains one over its line count because the ending line is exclusive.
 */
/*
 The superclass keeps a persistable URL exactly as given, fragment included, and
 parses the fragment into its own fields. A text location has to do the opposite
 for the URL: leaving the fragment in place would make -documentURLString report
 the encoding parameters as part of the document's address, and would make two
 otherwise identical locations compare unequal.
 */
- (instancetype)initWithURL:(NSURL *)url
         locationParameters:(NSDictionary<NSString *, id> *)locationParameters
                      error:(NSError **)error
{
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *fragment = components.percentEncodedFragment;
    NSDictionary<NSString *, NSString *> *parameters = DVTPersistentParametersFromFragment(fragment);
    components.percentEncodedFragment = nil;

    /*
     The superclass reads the timestamp out of the fragment, which this class has
     just taken for itself, so it is handed over in the one channel the superclass
     does consult before it strips anything. The caller's own parameters are
     forwarded unchanged otherwise.
     */
    NSString *timestamp = parameters[DVTPersistentTimestampKey];
    if (timestamp == nil) {
        self = [super initWithURL:components.URL locationParameters:locationParameters error:error];
    } else {
        NSMutableDictionary<NSString *, id> *forwarded = [locationParameters mutableCopy];
        if (forwarded == nil) {
            forwarded = [NSMutableDictionary dictionary];
        }
        forwarded[DVTPersistentTimestampKey] = timestamp;
        self = [super initWithURL:components.URL locationParameters:forwarded error:error];
    }
    if (self == nil) {
        return nil;
    }
    NSString *value = nil;
    if ((value = parameters[DVTPersistentStartingColumnNumberKey]) != nil) {
        _startingColumnNumber = value.longLongValue;
    }
    if ((value = parameters[DVTPersistentEndingColumnNumberKey]) != nil) {
        _endingColumnNumber = value.longLongValue;
    }
    if ((value = parameters[DVTPersistentStartingLineNumberKey]) != nil) {
        _startingLineNumber = value.longLongValue;
    }
    if ((value = parameters[DVTPersistentEndingLineNumberKey]) != nil) {
        _endingLineNumber = value.longLongValue;
    }
    NSString *characterRangeLocation = parameters[DVTPersistentCharacterRangeLocationKey];
    NSString *characterRangeLength = parameters[DVTPersistentCharacterRangeLengthKey];
    if (characterRangeLocation != nil && characterRangeLength != nil) {
        _characterRange = NSMakeRange(characterRangeLocation.longLongValue, characterRangeLength.longLongValue);
    }
    if ((value = parameters[DVTPersistentLocationEncodingKey]) != nil) {
        _locationEncoding = value.longLongValue;
    }
    return self;
}

- (NSRange)lineRange
{
    if (_startingLineNumber == NSNotFound || _endingLineNumber == NSNotFound) {
        return NSMakeRange(NSNotFound, 0);
    }
    return NSMakeRange((NSUInteger)_startingLineNumber,
                       (NSUInteger)(_endingLineNumber - _startingLineNumber + 1));
}

#pragma mark - Validation

+ (NSString *)validateFailureMessageForStartingColumnNumber:(NSInteger)startingColumnNumber
                                         endingColumnNumber:(NSInteger)endingColumnNumber
                                          startingLineNumber:(NSInteger)startingLineNumber
                                            endingLineNumber:(NSInteger)endingLineNumber
                                             characterRange:(NSRange)characterRange
                                           locationEncoding:(NSInteger)locationEncoding
{
    NSString *fields = [NSString stringWithFormat:
                                    @"{ startingLineNumber:%ld, endingLineNumber:%ld, "
                                     "startingColumnNumber:%ld, endingColumnNumber:%ld }",
                                    (long)startingLineNumber, (long)endingLineNumber,
                                    (long)startingColumnNumber, (long)endingColumnNumber];
    if ((startingLineNumber == NSNotFound) != (endingLineNumber == NSNotFound)) {
        return [@"Only one of the line numbers is NSNotFound. " stringByAppendingString:fields];
    }
    if ((startingColumnNumber == NSNotFound) != (endingColumnNumber == NSNotFound)) {
        return [@"Only one of the column numbers is NSNotFound. " stringByAppendingString:fields];
    }
    if (startingLineNumber != NSNotFound && startingLineNumber > endingLineNumber) {
        return [@"startingLine > endingLine " stringByAppendingString:fields];
    }
    if (startingLineNumber == endingLineNumber && startingColumnNumber != NSNotFound &&
        startingColumnNumber > endingColumnNumber) {
        return [@"startingColumn > endingColumn " stringByAppendingString:fields];
    }
    return nil;
}

+ (BOOL)validateStartingColumnNumber:(NSInteger)startingColumnNumber
                  endingColumnNumber:(NSInteger)endingColumnNumber
                   startingLineNumber:(NSInteger)startingLineNumber
                     endingLineNumber:(NSInteger)endingLineNumber
                      characterRange:(NSRange)characterRange
                    locationEncoding:(NSInteger)locationEncoding
                              error:(NSError **)error
{
    NSString *message = [self validateFailureMessageForStartingColumnNumber:startingColumnNumber
                                                           endingColumnNumber:endingColumnNumber
                                                            startingLineNumber:startingLineNumber
                                                              endingLineNumber:endingLineNumber
                                                               characterRange:characterRange
                                                             locationEncoding:locationEncoding];
    if (message == nil) {
        return YES;
    }
    if (error != NULL) {
        *error = [NSError errorWithDomain:DVTLocationErrorDomain
                                     code:DVTLocationGenericErrorCode
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

+ (void)assertValidityOfStartingColumnNumber:(NSInteger)startingColumnNumber
                         endingColumnNumber:(NSInteger)endingColumnNumber
                          startingLineNumber:(NSInteger)startingLineNumber
                            endingLineNumber:(NSInteger)endingLineNumber
                             characterRange:(NSRange)characterRange
                           locationEncoding:(NSInteger)locationEncoding
{
    NSError *error = nil;
    if (![self validateStartingColumnNumber:startingColumnNumber
                          endingColumnNumber:endingColumnNumber
                           startingLineNumber:startingLineNumber
                             endingLineNumber:endingLineNumber
                              characterRange:characterRange
                            locationEncoding:locationEncoding
                                      error:&error]) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"%@", error.localizedDescription];
    }
}

#pragma mark - Identity

- (BOOL)isEqualToCounterpartWithIdenticalClass:(DVTDocumentLocation *)counterpart
                             compareTimestamps:(BOOL)compareTimestamps
{
    if (![super isEqualToCounterpartWithIdenticalClass:counterpart compareTimestamps:compareTimestamps]) {
        return NO;
    }
    DVTTextDocumentLocation *other = (DVTTextDocumentLocation *)counterpart;
    return _locationEncoding == other->_locationEncoding &&
           _startingColumnNumber == other->_startingColumnNumber &&
           _endingColumnNumber == other->_endingColumnNumber &&
           _startingLineNumber == other->_startingLineNumber &&
           _endingLineNumber == other->_endingLineNumber &&
           NSEqualRanges(_characterRange, other->_characterRange);
}

/*
 Each step multiplies the running value by 33 before adding, in the order
 startingLineNumber then characterRange.length. The character range's *location*
 is not hashed, and neither are the columns, the ending line or the encoding.
 */
- (NSUInteger)hash
{
    NSUInteger value = [super hash];
    value = value * 33 + (NSUInteger)_startingLineNumber;
    value = value * 33 + (NSUInteger)_characterRange.length;
    return value;
}

/*
 Ordering is by URL first, as in the superclass. -locationEncoding is not part of
 the ordering even though it is part of equality, so two locations differing only
 in encoding order as the same.
 */
- (NSComparisonResult)compare:(id)object
{
    if (self == object) {
        return NSOrderedSame;
    }
    if (![object isKindOfClass:[DVTTextDocumentLocation class]]) {
        return NSOrderedDescending;
    }
    DVTTextDocumentLocation *other = object;
    NSComparisonResult result = [self.documentURLString compare:other.documentURLString];
    if (result != NSOrderedSame) {
        return result;
    }
    if (_startingLineNumber != other->_startingLineNumber) {
        return _startingLineNumber < other->_startingLineNumber ? NSOrderedAscending : NSOrderedDescending;
    }
    if (_endingLineNumber != other->_endingLineNumber) {
        return _endingLineNumber < other->_endingLineNumber ? NSOrderedAscending : NSOrderedDescending;
    }
    if (_characterRange.location != other->_characterRange.location) {
        return _characterRange.location < other->_characterRange.location ? NSOrderedAscending
                                                                          : NSOrderedDescending;
    }
    if (_characterRange.length != other->_characterRange.length) {
        return _characterRange.length < other->_characterRange.length ? NSOrderedAscending
                                                                     : NSOrderedDescending;
    }
    return NSOrderedSame;
}

#pragma mark - Presentation

- (NSString *)description
{
    return [NSString stringWithFormat:
                         @"%@, line and column range: %ld:%ld - %ld:%ld, "
                         @"character range: {%ld, %ld}, location encoding: %ld",
                         [super description], (long)_startingLineNumber, (long)_startingColumnNumber,
                         (long)_endingLineNumber, (long)_endingColumnNumber, (long)_characterRange.location,
                         (long)_characterRange.length, (long)_locationEncoding];
}

- (NSString *)pasteboardRepresentation
{
    return self.documentURL.path;
}

#pragma mark - Copying

- (instancetype)copyWithURL:(NSURL *)url
{
    return [[[self class] alloc] initWithDocumentURL:url
                                           timestamp:self.timestamp
                                startingColumnNumber:_startingColumnNumber
                                  endingColumnNumber:_endingColumnNumber
                                   startingLineNumber:_startingLineNumber
                                     endingLineNumber:_endingLineNumber
                                      characterRange:_characterRange
                                    locationEncoding:_locationEncoding];
}

#pragma mark - Persistent parameters

/*
  Apple overrides both of these on the text subclass and still hands back an empty
  dictionary, so they stay pass-throughs here. The fields themselves are added by
  -DVTPopulatePersistentParameters in the superclass, which is where the closed
  family of document locations is spelled out.

  -initWithURL:locationParameters:error: is where a text location does read its own
  keys back, since the fragment it is handed is entirely its own.
 */
- (void)populateLocationParameters:(NSMutableDictionary<NSString *, id> *)locationParameters
{
    [super populateLocationParameters:locationParameters];
}

- (BOOL)_populateLocationParameters:(NSMutableDictionary<NSString *, id> *)locationParameters
              decodableClassName:(NSString **)decodableClassName
                             error:(NSError **)error
{
    return [super _populateLocationParameters:locationParameters decodableClassName:decodableClassName
                                        error:error];
}

#pragma mark - Coding

/*
  The superclass decodes only its own two fields, so the text fields are decoded
  here as well as in -dvt_initFromDeserializer:. Both entry points write the same
  keys in the same order, which is what keeps the two archives identical.
 */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    DVTTextDocumentLocation *decoded = [super initWithCoder:coder];
    if (decoded == nil) {
        return nil;
    }
    _startingColumnNumber = [coder decodeIntegerForKey:DVTStartingColumnNumberKey];
    _endingColumnNumber = [coder decodeIntegerForKey:DVTEndingColumnNumberKey];
    _startingLineNumber = [coder decodeIntegerForKey:DVTStartingLineNumberKey];
    _endingLineNumber = [coder decodeIntegerForKey:DVTEndingLineNumberKey];
    _characterRange = NSMakeRange([coder decodeIntegerForKey:DVTCharacterRangeLocationKey],
                                  [coder decodeIntegerForKey:DVTCharacterRangeLengthKey]);
    _locationEncoding = [coder decodeIntegerForKey:DVTLocationEncodingKey];
    return decoded;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeInteger:_startingColumnNumber forKey:DVTStartingColumnNumberKey];
    [coder encodeInteger:_endingColumnNumber forKey:DVTEndingColumnNumberKey];
    [coder encodeInteger:_startingLineNumber forKey:DVTStartingLineNumberKey];
    [coder encodeInteger:_endingLineNumber forKey:DVTEndingLineNumberKey];
    [coder encodeInteger:(NSInteger)_characterRange.location forKey:DVTCharacterRangeLocationKey];
    [coder encodeInteger:(NSInteger)_characterRange.length forKey:DVTCharacterRangeLengthKey];
    [coder encodeInteger:_locationEncoding forKey:DVTLocationEncodingKey];
}

- (instancetype)dvt_initFromDeserializer:(NSCoder *)deserializer
{
    DVTDocumentLocation *decoded = [super dvt_initFromDeserializer:deserializer];
    if (decoded == nil) {
        return nil;
    }
    _startingColumnNumber = [deserializer decodeIntegerForKey:DVTStartingColumnNumberKey];
    _endingColumnNumber = [deserializer decodeIntegerForKey:DVTEndingColumnNumberKey];
    _startingLineNumber = [deserializer decodeIntegerForKey:DVTStartingLineNumberKey];
    _endingLineNumber = [deserializer decodeIntegerForKey:DVTEndingLineNumberKey];
    _characterRange = NSMakeRange([deserializer decodeIntegerForKey:DVTCharacterRangeLocationKey],
                                  [deserializer decodeIntegerForKey:DVTCharacterRangeLengthKey]);
    _locationEncoding = [deserializer decodeIntegerForKey:DVTLocationEncodingKey];
    return (DVTTextDocumentLocation *)decoded;
}

- (void)dvt_writeToSerializer:(NSCoder *)serializer
{
    [super dvt_writeToSerializer:serializer];
    [serializer encodeInteger:_startingColumnNumber forKey:DVTStartingColumnNumberKey];
    [serializer encodeInteger:_endingColumnNumber forKey:DVTEndingColumnNumberKey];
    [serializer encodeInteger:_startingLineNumber forKey:DVTStartingLineNumberKey];
    [serializer encodeInteger:_endingLineNumber forKey:DVTEndingLineNumberKey];
    [serializer encodeInteger:(NSInteger)_characterRange.location forKey:DVTCharacterRangeLocationKey];
    [serializer encodeInteger:(NSInteger)_characterRange.length forKey:DVTCharacterRangeLengthKey];
    [serializer encodeInteger:_locationEncoding forKey:DVTLocationEncodingKey];
}

#pragma mark - Construction

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
