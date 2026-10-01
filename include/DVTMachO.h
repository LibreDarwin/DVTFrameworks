//
//  DVTMachO.h
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
#import <mach-o/loader.h>
#import <mach/machine.h>
#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Invoked once per architecture contained in a Mach-O file.

 @param sliceData   The mapped bytes of the individual slice (fat header
                     stripped).
 @param sliceIndex  The architecture index within the file; `0` for a thin
                     file, `0..n-1` for a fat file.
 @return `YES` to continue enumerating.
 */
typedef BOOL (^DVTMachOEnumerationBlock)(NSData *sliceData, NSUInteger sliceIndex);

/**
 Invoked once per load command of a given `cmd`/`cmdsize` pair.

 @param loadCommand A pointer to the raw `struct load_command`.
 @param sliceData   The mapped bytes of the owning slice.
 @return `YES` to continue enumerating.
 */
typedef BOOL (^DVTMachOEnumerationLoadCommandsBlock)(const struct load_command *loadCommand, NSData *sliceData);

/**
 Returns `YES` when `executablePath` is a static or dynamic archive (`!<arch>\n`).
 */
DVT_EXTERN BOOL DVTMachOIsArchive(NSString *executablePath);

/**
 Returns `YES` when `executablePath` begins with a fat Mach-O header.
 */
DVT_EXTERN BOOL DVTMachOHasFatHeader(NSString *executablePath);

/**
 Enumerates every architecture in `executablePath`. Thin files yield exactly one
 invocation; fat files yield one per slice. Recognises 32- and 64-bit, little-
 and big-endian, and fat magics.

 Returning `NO` from `block` stops the enumeration.
 */
DVT_EXTERN BOOL DVTMachOEnumerateSlices(NSString *executablePath,
                                        NSError *_Nullable *_Nullable error,
                                        DVTMachOEnumerationBlock block);

/**
 Enumerates every load command in every slice of `executablePath` for which
 `cmd`/`cmdsize` match the supplied selectors.

 `cmd` and `cmdsize` may be `0` to match any value, which is how the original
 framework implements the "all load commands" and "all dylib commands" cases.
 */
DVT_EXTERN BOOL DVTMachOEnumerateLoadCommands(NSString *executablePath,
                                              uint32_t cmd,
                                              uint32_t cmdsize,
                                              NSError *_Nullable *_Nullable error,
                                              DVTMachOEnumerationLoadCommandsBlock block);

/**
 Returns the `MH_*` file type of every slice, in slice order.
 */
DVT_EXTERN NSArray<NSNumber *> *DVTMachOFileTypes(NSString *executablePath);

/**
 Returns the set of platform IDs (`PLATFORM_*`) present across all slices.
 */
DVT_EXTERN NSSet<NSNumber *> *DVTMachOPlatformsForExecutable(NSString *executablePath);

/**
 Returns `YES` when any slice of `executablePath` targets `platform`.
 */
DVT_EXTERN BOOL DVTMachOHasPlatform(NSString *executablePath, uint32_t platform);

/**
 Returns the architecture name of every slice, e.g. `"arm64"` or `"x86_64"`.

 The original returns a collection whose element type could not be recovered
 from the binary; architecture names are the most useful thing a caller can do
 with the result, and they keep the API buildable where `NSUUID` is absent.
 */
DVT_EXTERN NSArray<NSString *> *DVTMachOArchitecturesForExecutable(NSString *executablePath);

/**
 Returns the `LC_UUID` of every slice as a canonical uppercase dashed string, or
 an empty array when the file carries no UUID.
 */
DVT_EXTERN NSArray<NSString *> *DVTMachOUUIDsForExecutable(NSString *executablePath);

/**
 Returns the `LC_RPATH` entries of the slice at `sliceIndex`.

 @param sliceIndex `-1` matches every slice, otherwise the index of the slice
                    to inspect.
 @return The runpath search paths, de-duplicated and in load-command order.
 */
DVT_EXTERN NSArray<NSString *> *DVTMachORPathsForExecutable(NSString *executablePath,
                                                            NSInteger sliceIndex,
                                                            NSError *_Nullable *_Nullable error);

/**
 Returns the dylib names linked by `loadCommand` (`LC_LOAD_DYLIB`,
 `LC_LOAD_WEAK_DYLIB`, `LC_REEXPORT_DYLIB`, `LC_LOAD_UPWARD_DYLIB`, ...).
 */
DVT_EXTERN NSString *_Nullable DVTMachOLibraryNameForLoadCommand(const struct load_command *loadCommand);

/**
 Returns the install names of every non-weak dylib dependency of the slice at
 `sliceIndex`. A `sliceIndex` of `-1` inspects every slice.
 */
DVT_EXTERN NSArray<NSString *> *DVTMachOLinkedLibrariesForExecutable(NSString *executablePath,
                                                                    NSInteger sliceIndex,
                                                                    NSError *_Nullable *_Nullable error);

/**
 As `DVTMachOLinkedLibrariesForExecutable()`, but also includes
 `LC_LOAD_WEAK_DYLIB` dependencies.
 */
DVT_EXTERN NSArray<NSString *> *DVTMachOLinkedLibrariesForExecutableIncludingWeakLinks(NSString *executablePath,
                                                                                       NSInteger sliceIndex,
                                                                                       NSError *_Nullable *_Nullable error);

/**
 Returns the `LC_REEXPORT_DYLIB` dependencies of the slice at `sliceIndex`, i.e.
 the dylibs the image re-exports symbols from.

 @note The selector comes from the original framework's symbol table, but its
       behaviour could not be confirmed from the disassembly: an equally
       plausible reading is that it returns the slice's own `LC_ID_DYLIB`
       install name. This implementation follows the selector's name.
 */
DVT_EXTERN NSArray<NSString *> *DVTMachOReexportedLibrariesForExecutable(NSString *executablePath,
                                                                          NSInteger sliceIndex,
                                                                          NSError *_Nullable *_Nullable error);

/**
 Returns `YES` when any slice contains an `LC_SEGMENT`/`LC_SEGMENT_64` carrying
 a `__TEXT` section, i.e. the file actually holds machine code.
 */
DVT_EXTERN BOOL DVTMachOBinaryHasAnyMachineCode(NSString *executablePath);

/**
 Present for source compatibility with the original framework. The original
 compiles the body away entirely, so this is a documented no-op.
 */
DVT_EXTERN void DVTSetupWeakPropertyKVOAssertions(void);

NS_ASSUME_NONNULL_END
