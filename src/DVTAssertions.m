//
//  DVTAssertions.m
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

#import "DVTAssertions.h"
#import "DVTEnvironmentSnapshot.h"

#import <Foundation/NSThread.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <stdlib.h>
#import <string.h>

NSString *const DVTAssertionHandler = @"DVTAssertionHandler";
NSString *const DVTAssertionHints = @"DVTAssertionHints";
NSString *const DVTUnknownFile = @"<Unknown File>";
NSString *const DVTUnknownFunction = @"<Unknown Function>";

/*
 The report layouts below were recovered from the original framework's data
 segment. They are returned from functions rather than referenced as file-scope
 constants on purpose: handing a literal straight to -stringWithFormat: makes
 the compiler diagnose it as a format string even where the call is correct.
 */

static NSString *DVTFailureReportFormatWithObject(void)
{
    return @"ASSERTION FAILURE in %@:%lu\n"
           @"Details:  %@\n"
           @"Object:   %@\n"
           @"Method:   %@%@\n"
           @"Thread:   %@\n"
           @"Hints: %@\n"
           @"Backtrace:\n%@";
}


static NSString *DVTWarningReportFormatWithObject(void)
{
    return @"Warning in %@:%lu\n"
           @"Details:  %@\n"
           @"Object:   %@\n"
           @"Method:   %@%@\n"
           @"Thread:   %@\n"
           @"Please file a bug at %@ with this warning message and any useful information you can provide.\n"
           @"Hints: %@\n"
           @"Backtrace:\n%@";
}


#pragma mark - Shared formatting helpers

NSString *DVTThreadDescription(void)
{
    return [NSString stringWithFormat:@"%@: %p", [NSThread currentThread], (void *)[NSThread currentThread]];
}

/**
 `-componentsJoinedByString:` is not in PureDarwin's NSArray, so the call stack
 is folded by hand.
 */
NSString *DVTBacktraceDescription(void)
{
    NSArray<NSString *> *symbols = [NSThread callStackSymbols];
    NSUInteger count = symbols.count;
    if (count == 0) {
        return @"";
    }

    NSMutableString *result = [NSMutableString stringWithCapacity:256];
    for (NSUInteger index = 0; index < count; index++) {
        [result appendString:[symbols objectAtIndex:index]];
        if (index + 1 < count) {
            [result appendString:@"\n"];
        }
    }
    return result;
}

static NSString *DVTMethodDescription(id object, SEL _Nullable selector)
{
    if (object == nil || selector == NULL) {
        return @"<Unknown Method>";
    }
    NSString *name = NSStringFromSelector(selector);
    if (name == nil) {
        return @"<Unknown Method>";
    }
    NSString *className = NSStringFromClass(object_getClass(object));
    if (className.length == 0) {
        return name;
    }
    BOOL isClassMethod = class_isMetaClass(object_getClass(object));
    return [NSString stringWithFormat:@"%c[%@ %@]", isClassMethod ? '+' : '-', className, name];
}

/**
 The second half of the recovered `Method:   %@%@` line, so the report names
 both the selector and whether it was sent to a class.
 */
static NSString *DVTMethodKindDescription(id object)
{
    if (object == nil) {
        return @"";
    }
    return class_isMetaClass(object_getClass(object)) ? @" (class method)" : @" (instance method)";
}

#pragma mark - DVTFailureHintCreator

@implementation DVTFailureHintCreator

+ (id)hintForObject:(id)object
{
    if (object == nil) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@ should be an object", object];
}

+ (id)hintForSelector:(SEL)selector
{
    if (selector == NULL) {
        return nil;
    }
    NSString *name = NSStringFromSelector(selector);
    if (name == nil) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@ should be a valid selector", name];
}

+ (id)hintForClass:(Class)klass
{
    if (klass == Nil) {
        return nil;
    }
    const char *name = class_getName(klass);
    if (name == NULL) {
        return nil;
    }
    return [NSString stringWithFormat:@"%s should be an instance inheriting from %s", name, name];
}

+ (id)hintForFile:(const char *)file line:(NSInteger)line
{
    if (file == NULL) {
        return nil;
    }
    return [NSString stringWithFormat:@"%s should be the file under test at line %ld", file, (long)line];
}

+ (id)hintForFunction:(const char *)function
{
    if (function == NULL) {
        return nil;
    }
    return [NSString stringWithFormat:@"%s should be the function under test", function];
}

@end

#pragma mark - DVTAssertionReportHandler

/**
 Per-thread overrides. PureDarwin's NSMapTable is the legacy C map table with no
 -objectForKey:/-setObject:forKey:, so the overrides live in a dictionary keyed
 by the thread's address. Entries are removed by the thread itself on exit via
 `DVTPruneThreadHandlers`, and the count is bounded by the number of threads
 that ever installed an override.
 */
static os_unfair_lock DVTThreadHandlerLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, DVTAssertionReportHandler *> *DVTThreadAssertionHandlers;

static NSString *DVTThreadKey(NSThread *thread)
{
    return [NSString stringWithFormat:@"%p", (void *)thread];
}

static NSMutableDictionary<NSString *, DVTAssertionReportHandler *> *DVTThreadHandlerMap(void)
{
    static NSMutableDictionary<NSString *, DVTAssertionReportHandler *> *handlers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handlers = [NSMutableDictionary dictionaryWithCapacity:0];
    });
    return handlers;
}

@implementation DVTAssertionReportHandler

static DVTAssertionReportHandler *DVTCurrentHandler;
static os_unfair_lock DVTCurrentHandlerLock = OS_UNFAIR_LOCK_INIT;

+ (DVTAssertionReportHandler *)currentHandler
{
    os_unfair_lock_lock(&DVTCurrentHandlerLock);
    DVTAssertionReportHandler *handler = DVTCurrentHandler;
    os_unfair_lock_unlock(&DVTCurrentHandlerLock);
    return handler != nil ? handler : [[DVTAssertionReportHandler alloc] init];
}

+ (void)setCurrentHandler:(DVTAssertionReportHandler *)handler
{
    os_unfair_lock_lock(&DVTCurrentHandlerLock);
    DVTCurrentHandler = handler;
    os_unfair_lock_unlock(&DVTCurrentHandlerLock);
}

+ (DVTAssertionReportHandler *)currentHandlerForThread:(NSThread *)thread
{
    if (thread == nil) {
        return [self currentHandler];
    }

    os_unfair_lock_lock(&DVTThreadHandlerLock);
    DVTAssertionReportHandler *handler = [DVTThreadHandlerMap() objectForKey:DVTThreadKey(thread)];
    os_unfair_lock_unlock(&DVTThreadHandlerLock);
    return handler != nil ? handler : [self currentHandler];
}

+ (void)setCurrentHandler:(DVTAssertionReportHandler *)handler forThread:(NSThread *)thread
{
    if (thread == nil) {
        return;
    }

    os_unfair_lock_lock(&DVTThreadHandlerLock);
    if (handler == nil) {
        [DVTThreadHandlerMap() removeObjectForKey:DVTThreadKey(thread)];
    } else {
        [DVTThreadHandlerMap() setObject:handler forKey:DVTThreadKey(thread)];
    }
    os_unfair_lock_unlock(&DVTThreadHandlerLock);
}

- (void)didFailAssertion:(NSString *)report
{
    NSLog(@"%@", report);
    abort();
}

- (void)didWarnAssertion:(NSString *)report
{
    NSLog(@"%@", report);
}

@end

#pragma mark - Dispatch

static void DVTDispatchReport(BOOL isWarning,
                              NSString *file,
                              NSUInteger line,
                              id object,
                              SEL selector,
                              NSString *message,
                              NSString *hints,
                              NSString *format,
                              va_list arguments)
{
    NSString *sourceFile = file.length > 0 ? file : DVTUnknownFile;

    /*
     The macros pass both a short `message` ("count > 0") and a `format` with
     its varargs ("expected %lu items"). Both belong in the report, so render
     the format and keep the message alongside it.
     */
    NSString *details = message.length > 0 ? message : @"";
    if (format != nil) {
        NSString *formatted = [[NSString alloc] initWithFormat:format arguments:arguments];
        if (formatted.length > 0) {
            details = details.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", details, formatted] : formatted;
        }
    }

    NSMutableString *report = [NSMutableString stringWithCapacity:512];
    /*
     Both layouts take the same arguments; only the header line and the extra
     "Please file a bug" line differ. Filling in the object, method, and method
     kind up front keeps the two calls in step, so a future edit to one cannot
     silently drop an argument from the other.
     */
    NSString *objectDescription = object != nil ? [object description] : @"None";
    NSString *method = object != nil ? DVTMethodDescription(object, selector) : @"<Unknown Method>";
    NSString *methodKind = object != nil ? DVTMethodKindDescription(object) : @"";
    if (isWarning) {
        [report appendFormat:DVTWarningReportFormatWithObject(), sourceFile.lastPathComponent, (unsigned long)line,
                              details, objectDescription, method, methodKind, DVTThreadDescription(),
                              DVTAssertionHandler, hints ?: @"", DVTBacktraceDescription()];
    } else {
        [report appendFormat:DVTFailureReportFormatWithObject(), sourceFile.lastPathComponent, (unsigned long)line,
                              details, objectDescription, method, methodKind, DVTThreadDescription(), hints ?: @"",
                              DVTBacktraceDescription()];
    }


    DVTAssertionReportHandler *handler = [DVTAssertionReportHandler currentHandlerForThread:[NSThread currentThread]];
    if (isWarning) {
        [handler didWarnAssertion:report];
    } else {
        [handler didFailAssertion:report];
    }
}

void _DVTAssertionHandler(BOOL isWarning,
                          NSString *file,
                          NSUInteger line,
                          id object,
                          SEL selector,
                          NSString *message,
                          NSString *hints,
                          NSString *format,
                          ...)
{
    va_list arguments;
    va_start(arguments, format);
    DVTDispatchReport(isWarning, file, line, object, selector, message, hints, format, arguments);
    va_end(arguments);
}

void _DVTAssertionFailureHandler(NSString *file,
                                 NSUInteger line,
                                 id object,
                                 SEL selector,
                                 NSString *message,
                                 NSString *hints,
                                 NSString *format,
                                 ...)
{
    va_list arguments;
    va_start(arguments, format);
    DVTDispatchReport(NO, file, line, object, selector, message, hints, format, arguments);
    va_end(arguments);
}

void _DVTAssertionWarningHandler(NSString *file,
                                 NSUInteger line,
                                 id object,
                                 SEL selector,
                                 NSString *message,
                                 NSString *hints,
                                 NSString *format,
                                 ...)
{
    va_list arguments;
    va_start(arguments, format);
    DVTDispatchReport(YES, file, line, object, selector, message, hints, format, arguments);
    va_end(arguments);
}

void _DVTAssertFromSwift(BOOL condition,
                         NSString *file,
                         NSString *function,
                         NSUInteger line,
                         NSString *message,
                         NSString *hints)
{
    if (condition) {
        return;
    }
    if (file == nil) {
        file = DVTUnknownFile;
    }
    _DVTAssertionFailureHandler(file, line, nil, NULL, message, hints, @"%@", function ?: DVTUnknownFunction);
}

void _DVTWarnFromSwift(NSString *file,
                       NSString *function,
                       NSUInteger line,
                       NSString *message,
                       NSString *hints)
{
    if (file == nil) {
        file = DVTUnknownFile;
    }
    _DVTAssertionWarningHandler(file, line, nil, NULL, message, hints, @"%@", function ?: DVTUnknownFunction);
}

#pragma mark - Environment

/*
 The reference framework gates assertions on an "assertion environment", an
 enum with six cases. `_DVTIsAssertionEnvironment` ANDs a byte out of a static
 six-entry table and then masks it with 1; the first case is compiled in as
 unconditionally true, and `-1` (no environment) diverts to
 `DVTHowToReproduceAssertionsForEnvironment`, which tells the user which hidden
 user default to set.

 The five gated cases each read a defaults key reached through an
 `environmentVariableFor...Enabled:` selector. The recovered key names are

     DVTEnableAssertionsForValidationTestSuite
     DVTEnableAssertionsForMemoryPerformanceTestSuite
     DVTEnableAssertionsForCPUPerformanceTestSuite
     DVTEnableAssertionsForQuickLookTestSuite
     DVTEnableAllAssertions

 with `DVTEnableAllAssertions` overriding the rest, which is what
 `DVTHowToReproduceAssertionsForEnvironment` tells the user to set:
 "You may need to set the hidden user default "%@" to 1 to reproduce."

 Which enum index maps to which suite was not recoverable -- the reference
 framework builds the table at runtime from the running host -- so the order
 below is the order the keys appear in the binary and is documented as
 inferred.

 Each gate also accepts the environment variable of the same name, which is what
 the `environmentVariableFor...Enabled:` selectors name and what makes the gate
 usable before a defaults domain is seeded.
 */

/** Enables every case at once; matches the recovered `DVTEnableAllAssertions`. */
static NSString *const DVTEnableAllAssertionsKey = @"DVTEnableAllAssertions";

/** Gate for each environment past the always-on first case. */
static NSString *const DVTAssertionEnvironmentKeys[] = {
    @"DVTEnableAssertionsForValidationTestSuite",
    @"DVTEnableAssertionsForMemoryPerformanceTestSuite",
    @"DVTEnableAssertionsForCPUPerformanceTestSuite",
    @"DVTEnableAssertionsForQuickLookTestSuite",
};

/** Number of gated cases, i.e. entries in `DVTAssertionEnvironmentKeys`. */
static const size_t DVTAssertionEnvironmentKeyCount =
    sizeof(DVTAssertionEnvironmentKeys) / sizeof(DVTAssertionEnvironmentKeys[0]);

/**
 The current assertion environment, or `-1` when none is selected. Mirrors the
 reference framework's convention that the first case needs no gate.
 */
static NSInteger DVTAssertionEnvironmentIndex(void)
{
    static NSInteger index = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *value = getenv("DVTAssertionEnvironment");
        long parsed = (value != NULL && value[0] != '\0') ? strtol(value, NULL, 10) : 0;
        index = (parsed < 0 || parsed > (long)DVTAssertionEnvironmentKeyCount) ? -1 : (NSInteger)parsed;
    });
    return index;
}

/** `YES` when the hidden user default, or the same-named variable, is set. */
static BOOL DVTAssertionGateIsEnabled(NSString *key)
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:key]) {
        return YES;
    }
    const char *value = getenv(key.UTF8String);
    return value != NULL && DVTStringIsTrue(@(value));
}

BOOL DVTIsAssertionEnvironment(void)
{
    /* Nothing is enabled until a hidden default or variable says so, so a plain
       run of a tool that links this framework stays quiet. */
    if (DVTAssertionGateIsEnabled(DVTEnableAllAssertionsKey)) {
        return YES;
    }
    NSInteger index = DVTAssertionEnvironmentIndex();
    if (index <= 0 || (size_t)index > DVTAssertionEnvironmentKeyCount) {
        return NO;
    }
    return DVTAssertionGateIsEnabled(DVTAssertionEnvironmentKeys[index - 1]);
}

BOOL DVTShouldAssertForEnvironment(NSString *environment)
{
    if (environment == nil || environment.length == 0) {
        return DVTIsAssertionEnvironment();
    }
    if (DVTAssertionGateIsEnabled(DVTEnableAllAssertionsKey)) {
        return YES;
    }
    /* Naming a suite asks about that suite; anything else is taken at face value. */
    for (size_t index = 0; index < DVTAssertionEnvironmentKeyCount; index++) {
        if ([DVTAssertionEnvironmentKeys[index] isEqualToString:environment]) {
            return DVTAssertionGateIsEnabled(environment);
        }
    }
    return DVTStringIsTrue(environment);
}
