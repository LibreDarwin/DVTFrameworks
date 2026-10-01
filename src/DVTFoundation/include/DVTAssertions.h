//
//  DVTAssertions.h
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

#import <Foundation/Foundation.h>
#import "DVTDefines.h"

/* DVTAssertKindOfClass expands to class_getName(). */
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/** Aspect name used when logging assertion activity. */
DVT_EXTERN NSString *const DVTAssertionHandler;
/** Aspect name used when logging assertion hints. */
DVT_EXTERN NSString *const DVTAssertionHints;
/** Placeholder emitted when a failure carries no source file. */
DVT_EXTERN NSString *const DVTUnknownFile;
/** Placeholder emitted when a failure carries no function name. */
DVT_EXTERN NSString *const DVTUnknownFunction;

/**
 Creates the "hint" objects attached to an assertion: a hint describes the
 expectation that failed so the log can explain what the author intended.

 Every method returns `nil` when the corresponding input is `nil`, which is how
 a failed assertion ends up with no hints.
 */
@interface DVTFailureHintCreator : NSObject

+ (nullable id)hintForObject:(nullable id)object;
+ (nullable id)hintForSelector:(nullable SEL)selector;
+ (nullable id)hintForClass:(nullable Class)klass;
+ (nullable id)hintForFile:(const char *_Nullable)file line:(NSInteger)line;
+ (nullable id)hintForFunction:(const char *_Nullable)function;

@end

/**
 Receives a formatted assertion or warning report.

 The default implementation logs through the `DVTAssertionHandler` aspect and
 then aborts for failures. Callers may install their own handler to change the
 reporting behaviour; the report is a single already-formatted `NSString`.
 */
@interface DVTAssertionReportHandler : NSObject

/** The handler used when no per-thread override is installed. Assign `nil` to
 restore the default handler. Swift imports this as `DVTAssertionReportHandler.current`,
 having dropped the suffix that repeats the class name. */
@property (class, nonatomic, strong, nullable) DVTAssertionReportHandler *currentHandler;
/** The handler installed for `thread`, if any. */
+ (nullable DVTAssertionReportHandler *)currentHandlerForThread:(NSThread *)thread;
+ (void)setCurrentHandler:(nullable DVTAssertionReportHandler *)handler forThread:(NSThread *)thread;

/** Overridable hook. Reports a failure; the base implementation aborts. */
- (void)didFailAssertion:(NSString *)report;
/** Overridable hook. Reports a warning. The base implementation only logs. */
- (void)didWarnAssertion:(NSString *)report;

@end

/**
 Formats and dispatches an assertion report. `isWarning` selects between the
 warning and failure report layouts; both are derived from the format strings
 recovered from the original framework.
 */
DVT_EXTERN void _DVTAssertionHandler(BOOL isWarning,
                                     NSString *file,
                                     NSUInteger line,
                                     id _Nullable object,
                                     SEL _Nullable _cmd,
                                     NSString *message,
                                     NSString *_Nullable hints,
                                     NSString *format, ...) NS_FORMAT_FUNCTION(8, 9);

/** Formats and dispatches a failure report. */
DVT_EXTERN void _DVTAssertionFailureHandler(NSString *file,
                                            NSUInteger line,
                                            id _Nullable object,
                                            SEL _Nullable _cmd,
                                            NSString *message,
                                            NSString *_Nullable hints,
                                            NSString *format, ...) NS_FORMAT_FUNCTION(7, 8);

/** Formats and dispatches a warning report. */
DVT_EXTERN void _DVTAssertionWarningHandler(NSString *file,
                                            NSUInteger line,
                                            id _Nullable object,
                                            SEL _Nullable _cmd,
                                            NSString *message,
                                            NSString *_Nullable hints,
                                            NSString *format, ...) NS_FORMAT_FUNCTION(7, 8);

/** Entry points used by the Swift overlay. */
/* `file`, `function`, and `message` are nullable: a placeholder is substituted
   for each one that is missing, which is what a `#file`-less Swift build site or
   a synthesised call from another language ends up passing. */
DVT_EXTERN void _DVTAssertFromSwift(BOOL condition, NSString *_Nullable file, NSString *_Nullable function,
                                   NSUInteger line, NSString *_Nullable message, NSString *_Nullable hints);
DVT_EXTERN void _DVTWarnFromSwift(NSString *_Nullable file, NSString *_Nullable function, NSUInteger line,
                                  NSString *_Nullable message, NSString *_Nullable hints);

/**
 Returns `YES` when `environment` is an environment whose own gate is set.

 The argument is a small integer environment selector, not a name. The
 reference framework switches on it directly and never messages it: `0` needs
 no gate and asserts, `1` through `5` are decided by the gate for that case,
 and anything else is not an assertion environment at all.

 The cases are numbered independently of the order the gate names appear in
 Apple's binary: `2` is the QuickLook suite, `3` the CPUPerformance suite, `4`
 the MemoryPerformance suite, and `5` the Validation suite. Case `1` is gated
 but no string in the binary names its key, so it cannot be switched on through
 any supported default or variable.

 This function does not consult `DVTEnableAllAssertions`, which matches Apple
 and is easy to get wrong.
 */
DVT_EXTERN BOOL DVTIsAssertionEnvironment(NSInteger environment);

/**
 Returns `YES` when `environment` should run assertions.

 Same integer selector as `DVTIsAssertionEnvironment`, but permissive: a case
 that finds its own gate closed falls through to every later gate, and an
 unrecognised selector defers to `DVTEnableAllAssertions`. A gated selector
 whose gates are all closed also defers to `DVTEnableAllAssertions`, so
 enabling that master switch answers `YES` for every selector, including
 out-of-range ones.
 */
DVT_EXTERN BOOL DVTShouldAssertForEnvironment(NSInteger environment);

/** A one-line description of the calling thread, for report headers. */
DVT_EXTERN NSString *DVTThreadDescription(void);

/**
 The current thread's call stack, one frame per line, as
 `+[NSThread callStackSymbols]` reports it. Empty when the runtime provides no
 symbols.
 */
DVT_EXTERN NSString *DVTBacktraceDescription(void);

NS_ASSUME_NONNULL_END

/**
 Fails (and aborts) when `condition` is false.

 @param condition The expression under test.
 @param message   A short description of the expectation, e.g. `@"count > 0"`.
 @param hint      Optional `DVTFailureHintCreator` output.
 @param format    A `NSString` format string describing the failure.
 */
#define DVTAssert(condition, message, hint, format, ...)                                                        \
    do {                                                                                                         \
        if (!(condition)) {                                                                                      \
            _DVTAssertionFailureHandler(@__FILE__, (NSUInteger)__LINE__, nil, NULL, message, hint, format,      \
                                        ##__VA_ARGS__);                                                          \
        }                                                                                                        \
    } while (0)

/** As `DVTAssert`, but the caller supplies the hints explicitly. */
#define DVTAssertWithFailureHint(condition, message, hint, format, ...)                                          \
    DVTAssert(condition, message, hint, format, ##__VA_ARGS__)

/**
 Logs a warning without aborting. The `hint` argument is evaluated eagerly, so
 pass `nil` (or a lazily built hint) when it is expensive.
 */
#define DVTWarning(message, hint, format, ...)                                                                  \
    do {                                                                                                         \
        _DVTAssertionWarningHandler(@__FILE__, (NSUInteger)__LINE__, nil, NULL, message, hint, format,           \
                                     ##__VA_ARGS__);                                                             \
    } while (0)

/** Fails at runtime when control reaches an unimplemented function. */
#define DVTAssertFunctionNotImplemented(functionName)                                                            \
    DVTAssert(NO, @"Function not implemented", nil, @"%@", functionName)

/** Fails when `object` is `nil`. */
#define DVTAssertNotNil(object, message, ...)                                                                   \
    DVTAssert((object) != nil, message, [DVTFailureHintCreator hintForObject:(object)],                          \
              @"object should not be nil")

/** Fails when `object` is not an instance of `klass`. */
#define DVTAssertKindOfClass(object, klass, message, ...)                                                       \
    DVTAssert([(object) isKindOfClass:[klass class]], message,                                                    \
              [DVTFailureHintCreator hintForClass:[klass class]],                                                 \
              @"object should be an instance of %s", class_getName([klass class]))
