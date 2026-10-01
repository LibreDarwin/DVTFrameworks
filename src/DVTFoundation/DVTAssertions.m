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
 integer selector with six cases. `_DVTIsAssertionEnvironment` switches on the
 integer directly, reading one byte out of a static table and masking it with 1:

     0             compiled in as unconditionally true
     1             gate 0x3b0  -- named by no string in the binary
     2             gate 0x3b1  -- DVTEnableAssertionsForQuickLookTestSuite
     3             gate 0x3b2  -- DVTEnableAssertionsForCPUPerformanceTestSuite
     4             gate 0x3b3  -- DVTEnableAssertionsForMemoryPerformanceTestSuite
     5             gate 0x3b4  -- DVTEnableAssertionsForValidationTestSuite
     anything else            false

 `DVTEnableAllAssertions` is not one of those five cases. It is the byte at
 0x3b5, which only `_DVTShouldAssertForEnvironment` reads: switching it on
 leaves `Is` reporting NO for every gated case while `Should` reports YES for
 every selector, including out-of-range ones. Each gate accepts either the
 hidden user default of the same name or an environment variable of the same
 name, and both use NSUserDefaults boolean parsing -- "1", "YES", "true" and
 "yes" are on; "0", "NO" and anything unrecognised are off. The five
 `environmentVariableFor...Enabled:` selectors in the binary are what name that
 pairing.

 None of this was taken from the disassembly alone. Every gate-to-case mapping
 and every answer below was recorded by driving all 32 combinations of the five
 keys through the reference framework's own exported functions, because the
 order the keys appear in the binary is not the order the cases are numbered
 in and reading it straight off the string table gets it backwards.
 */

/**
 Enables every case at once.

 This is the master switch, not a sixth environment: `_DVTIsAssertionEnvironment`
 never reads it, and `_DVTShouldAssertForEnvironment` consults it as the last
 step of every selector including the ones outside the known cases.
 */
static NSString *const DVTEnableAllAssertionsKey = @"DVTEnableAllAssertions";

/**
 Gates for environments 1 through 5, indexed from 1.

 Environment 1 is gated but no string in the binary names its key, so it can
 never be switched on here and its slot is nil. The other four are numbered in
 the order `DVTEnableAssertionsForQuickLookTestSuite`,
 `...CPUPerformanceTestSuite`, `...MemoryPerformanceTestSuite`,
 `...ValidationTestSuite` -- which is neither the order the keys appear in the
 binary nor the order they are declared in the reference headers.

 Nothing in this list is enabled by default, and a process that selects no
 environment has to land outside the known cases: `0` is the case that asserts
 without consulting a gate, so defaulting to it would switch assertions on for
 every process that links this framework.
 */
static NSString *const DVTAssertionEnvironmentKeys[] = {
    nil,
    @"DVTEnableAssertionsForQuickLookTestSuite",
    @"DVTEnableAssertionsForCPUPerformanceTestSuite",
    @"DVTEnableAssertionsForMemoryPerformanceTestSuite",
    @"DVTEnableAssertionsForValidationTestSuite",
};

/** Number of gated cases, i.e. entries in `DVTAssertionEnvironmentKeys`. */
static const NSInteger DVTAssertionEnvironmentKeyCount =
    (NSInteger)(sizeof(DVTAssertionEnvironmentKeys) / sizeof(DVTAssertionEnvironmentKeys[0]));

/** `YES` when the hidden user default, or the same-named variable, is set. */
static BOOL DVTAssertionGateIsEnabled(NSString *_Nullable key)
{
    if (key == nil) {
        return NO;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:key]) {
        return YES;
    }
    const char *value = getenv(key.UTF8String);
    return value != NULL && DVTStringIsTrue(@(value));
}

BOOL DVTIsAssertionEnvironment(NSInteger environment)
{
    /* The reference framework switches on this integer directly. Case 0 is the
       one that needs no gate; anything outside the known cases is simply not an
       assertion environment. The master switch is deliberately not consulted
       here, because Apple keeps it out of this function. */
    if (environment == 0) {
        return YES;
    }
    if (environment >= 1 && environment <= DVTAssertionEnvironmentKeyCount) {
        return DVTAssertionGateIsEnabled(DVTAssertionEnvironmentKeys[environment - 1]);
    }
    return NO;
}

BOOL DVTShouldAssertForEnvironment(NSInteger environment)
{
    if (environment == 0) {
        return YES;
    }
    /* The reference switch falls through, so a case that finds its own gate
       closed asks every later gate in turn before deferring to the master
       switch. For a selector outside the known cases the master switch is the
       whole answer. */
    if (environment >= 1 && environment <= DVTAssertionEnvironmentKeyCount) {
        for (NSInteger index = environment; index <= DVTAssertionEnvironmentKeyCount; index++) {
            if (DVTAssertionGateIsEnabled(DVTAssertionEnvironmentKeys[index - 1])) {
                return YES;
            }
        }
    }
    return DVTAssertionGateIsEnabled(DVTEnableAllAssertionsKey);
}
