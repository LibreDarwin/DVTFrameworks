//
//  DVTPropertyListValue.m
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

#import "DVTPropertyListValue.h"
#import "DVTFoundationClassAdditions.h"

NSString *const DVTPropertyListValueDecodingErrorDomain = @"DVTPropertyListValueDecoding";

/*
 The whole family is one question asked six ways, and the answer is the same
 every time: hand back the receiver if it already is the requested plist type,
 otherwise say no. Apple compiles each of the thirty-six methods down to a bare
 `RET` or a `MOVZ X0, #0; RET` with no call at all, so there is no hidden
 conversion to recover -- the methods really are that small, and are written out
 literally rather than routed through a shared helper.
 */

/*
 The two dictionary lookups differ from the rest in that they have to explain a
 failure, and the two failures a dictionary can have are not the same failure:
 "there was no such key" and "there was, but it was the wrong type" call for
 different fixes at the call site.

 The value is rendered with `-debugDescription`, not `-description`, and the two
 disagree on exactly the types most likely to turn up here: empty data prints as
 `<>` rather than `{length = 0, bytes = 0x}`, and an array prints as
 `<NSConstantArray 0x…>(\n    1\n)`. Both were confirmed against Apple's binary.
 */
static id DVTPlistValueForKey(NSDictionary *dictionary, NSString *key, Class plistClass, NSError **error)
{
    id value = dictionary[key];
    if (value == nil) {
        if (error) {
            *error = [NSError dvt_errorWithDomain:DVTPropertyListValueDecodingErrorDomain
                                        errorCode:0
                                    messageFormat:@"Missing %@ value for key: %@",
                                                  NSStringFromClass(plistClass), key];
        }
        return nil;
    }

    if (![value isKindOfClass:plistClass]) {
        if (error) {
            *error = [NSError dvt_errorWithDomain:DVTPropertyListValueDecodingErrorDomain
                                        errorCode:0
                                    messageFormat:@"Found %@ value (%@), instead of %@ for key: %@",
                                                  NSStringFromClass([value class]), [value debugDescription],
                                                  NSStringFromClass(plistClass), key];
        }
        return nil;
    }

    return value;
}

@implementation NSString (DVTPropertyListValue)

- (id)dvt_plistStringValue
{
    return self;
}

- (id)dvt_plistNumberValue
{
    return nil;
}

- (id)dvt_plistDateValue
{
    return nil;
}

- (id)dvt_plistArrayValue
{
    return nil;
}

- (id)dvt_plistDictionaryValue
{
    return nil;
}

- (id)dvt_plistDataValue
{
    return nil;
}

@end

@implementation NSData (DVTPropertyListValue)

- (id)dvt_plistStringValue
{
    return nil;
}

- (id)dvt_plistDataValue
{
    return self;
}

- (id)dvt_plistNumberValue
{
    return nil;
}

- (id)dvt_plistDateValue
{
    return nil;
}

- (id)dvt_plistArrayValue
{
    return nil;
}

- (id)dvt_plistDictionaryValue
{
    return nil;
}

@end

@implementation NSDate (DVTPropertyListValue)

- (id)dvt_plistStringValue
{
    return nil;
}

- (id)dvt_plistDataValue
{
    return nil;
}

- (id)dvt_plistNumberValue
{
    return nil;
}

- (id)dvt_plistDateValue
{
    return self;
}

- (id)dvt_plistArrayValue
{
    return nil;
}

- (id)dvt_plistDictionaryValue
{
    return nil;
}

@end

@implementation NSNumber (DVTPropertyListValue)

/*
 The one method in the family that builds something. A number is the only plist
 type with a canonical textual form, and `stringValue` is what already produces
 it -- including its two sharp edges, which are inherited on purpose: `@YES`
 stringifies as `1`, not `YES`, and a double keeps whatever precision it has.
 Formatting it any other way would produce strings Apple's callers never see.
 */
- (id)dvt_plistStringValue
{
    return [self stringValue];
}

- (id)dvt_plistDataValue
{
    return nil;
}

- (id)dvt_plistNumberValue
{
    return self;
}

- (id)dvt_plistDateValue
{
    return nil;
}

- (id)dvt_plistArrayValue
{
    return nil;
}

- (id)dvt_plistDictionaryValue
{
    return nil;
}

@end

@implementation NSArray (DVTPropertyListValue)

- (id)dvt_plistStringValue
{
    return nil;
}

- (id)dvt_plistDataValue
{
    return nil;
}

- (id)dvt_plistNumberValue
{
    return nil;
}

- (id)dvt_plistDateValue
{
    return nil;
}

- (id)dvt_plistArrayValue
{
    return self;
}

- (id)dvt_plistDictionaryValue
{
    return nil;
}

- (NSArray *)dvt_decodeObjectsOfClass:(Class)klass error:(NSError **)error
{
    NSError * __autoreleasing *outError = error;
    return [self dvt_arrayByApplyingBlockStrictly:^id(id value) {
        return [[klass alloc] initWithPropertyListValue:value error:outError];
    }];
}

@end

@implementation NSDictionary (DVTPropertyListValue)

- (id)dvt_plistStringValue
{
    return nil;
}

- (id)dvt_plistDataValue
{
    return nil;
}

- (id)dvt_plistNumberValue
{
    return nil;
}

- (id)dvt_plistDateValue
{
    return nil;
}

- (id)dvt_plistArrayValue
{
    return nil;
}

- (id)dvt_plistDictionaryValue
{
    return self;
}

- (NSArray *)dvt_plistArrayForKey:(NSString *)key error:(NSError **)error
{
    return DVTPlistValueForKey(self, key, [NSArray class], error);
}

- (NSDictionary *)dvt_plistDictionaryForKey:(NSString *)key error:(NSError **)error
{
    return DVTPlistValueForKey(self, key, [NSDictionary class], error);
}

/*
  The chain in miniature: everything a missing key has to say, the decoder says;
  everything a present value has to say, only the decoder can. There is no third
  failure belonging to this method, which is why the `error` pointer is passed
  along untouched on the present-value path -- Apple's code never writes to it
  there, and neither do we.
*/
- (id)dvt_decodePlistObjectForKey:(NSString *)key
                          ofClass:(Class)ofClass
                            error:(NSError **)error
{
    id value = self[key];
    if (value != nil) {
        return [[ofClass alloc] initWithPropertyListValue:value error:error];
    }

    if (error) {
        *error = [NSError dvt_errorWithDomain:DVTPropertyListValueDecodingErrorDomain
                                    errorCode:0
                                messageFormat:@"Missing plist representation of %@ for key: %@",
                                              NSStringFromClass(ofClass), key];
    }
    return nil;
}

- (NSArray *)dvt_decodePlistArrayForKey:(NSString *)key
                         objectsOfClass:(Class)klass
                                  error:(NSError **)error
{
    return [[self dvt_plistArrayForKey:key error:error] dvt_decodeObjectsOfClass:klass error:error];
}

@end
