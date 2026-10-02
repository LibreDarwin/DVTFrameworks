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

#import "DVTArchitecture.h"
#import "DVTDefines.h"
#import "DVTVersion.h"

NS_ASSUME_NONNULL_BEGIN

/** The `NSError` domain used for failures that originate in Mach-O parsing. */
DVT_EXTERN NSString *const DVTMachOErrorDomain;

/** Error codes reported under `DVTMachOErrorDomain`. */
typedef NS_ENUM(NSInteger, DVTMachOErrorCode) {
    /** The data could be read but holds no Mach-O image. */
    DVTMachOErrorCodeNotMachO = 0,
    /** A read ran off the end of the buffer. */
    DVTMachOErrorCodeUnreadable = 1,
    /** The image is cut short: a header or command table does not fit. */
    DVTMachOErrorCodeTruncated = 2,
    /** The bytes are not a Mach-O image of any supported kind. */
    DVTMachOErrorCodeUnsupportedFormat = 3,
    /** The named platform could not be read or is not in any load command. */
    DVTMachOErrorCodeFileUnreadable = 5,
};

/**
  The platform a Mach-O image targets, matching the `platform` field of
  `LC_BUILD_VERSION` and the `PLATFORM_*` constants in `<mach-o/loader.h>`.
 */
typedef NS_ENUM(NSInteger, DVTMachOPlatform) {
    DVTMachOPlatformUnknown = 0,
    DVTMachOPlatformMacOS = 1,
    DVTMachOPlatformiOS = 2,
    DVTMachOPlatformtvOS = 3,
    DVTMachOPlatformWatchOS = 4,
    DVTMachOPlatformBridgeOS = 5,
    DVTMachOPlatformMacCatalyst = 6,
    DVTMachOPlatformiOSSimulator = 7,
    DVTMachOPlatformtvOSSimulator = 8,
    DVTMachOPlatformWatchOSSimulator = 9,
    DVTMachOPlatformDriverKit = 10,
    DVTMachOPlatformVisionOS = 11,
    DVTMachOPlatformVisionOSSimulator = 12,
};

/**
  Invoked once per architecture contained in a Mach-O file.

  @param sliceData     The bytes of the individual slice, fat header stripped.
  @param cpuType       The slice's `cputype`.
  @param cpuSubType    The slice's `cpusubtype`.
  @param stop          Set to `YES` to end the enumeration early.
  @param error         Set to report a failure encountered for this slice.
  @return `YES` to continue enumerating.
 */
typedef BOOL (^DVTMachOEnumerationBlock)(NSData *_Nonnull sliceData,
                                         cpu_type_t cpuType,
                                         cpu_subtype_t cpuSubType,
                                         BOOL *_Nonnull stop,
                                         NSError *_Nullable *_Nonnull error);

/**
  Invoked once per load command of a slice.

  @param loadCommand A pointer to the raw `struct load_command`.
  @param stop        Set to `YES` to end the enumeration early.
  @param error       Set to report a failure encountered for this slice.
  @return `YES` to continue enumerating.
 */
typedef BOOL (^DVTMachOEnumerationLoadCommandsBlock)(const struct load_command *_Nonnull loadCommand,
                                                     BOOL *_Nonnull stop,
                                                     NSError *_Nullable *_Nonnull error);

/**
  Returns `YES` when `fileData` holds an archive.

  Returns `nil` with an error in `error` when the data holds no Mach-O image at
  all, so a caller can tell "not an archive" from "not a Mach-O file".
 */
DVT_EXTERN NSNumber *_Nullable DVTMachOIsArchive(NSData *fileData,
                                                  NSError *_Nullable *_Nullable error);

/**
  Returns `YES` when `fileData` begins with a fat (universal) header.

  The name is literal: a thin 32- or 64-bit Mach-O answers `NO`. Use
  `DVTFileAtPathIsMachO` to ask whether something is a Mach-O at all.
 */
DVT_EXTERN NSNumber *_Nullable DVTMachOHasFatHeader(NSData *fileData,
                                                    NSError *_Nullable *_Nullable error);

/**
  Enumerates every architecture in `fileData`. Thin files yield exactly one
  invocation; fat files yield one per slice. Recognises 32- and 64-bit, little-
  and big-endian, and fat magics.

  Returning `NO` from `block`, or setting `*stop`, ends the enumeration.
 */
DVT_EXTERN BOOL DVTMachOEnumerateSlices(NSData *_Nonnull fileData,
                                        NSError *_Nullable *_Nullable error,
                                        DVTMachOEnumerationBlock _Nonnull block);

/**
  Enumerates every load command in every slice of `fileData`.

  Returning `NO` from `block`, or setting `*stop`, ends the enumeration.
 */
DVT_EXTERN BOOL DVTMachOEnumerateLoadCommands(NSData *_Nonnull fileData,
                                              NSError *_Nullable *_Nullable error,
                                              DVTMachOEnumerationLoadCommandsBlock _Nonnull block);

/**
  Enumerates every segment of every slice of `fileData`, passing the 32- and
  64-bit form of each segment command; exactly one is non-`NULL`.
 */
typedef BOOL (^DVTMachOEnumerationSegmentsBlock)(const struct segment_command *_Nullable command32,
                                                  const struct segment_command_64 *_Nullable command64,
                                                  BOOL *_Nonnull stop,
                                                  NSError *_Nullable *_Nonnull error);

DVT_EXTERN BOOL DVTMachOEnumerateSegments(NSData *_Nonnull fileData,
                                          NSError *_Nullable *_Nullable error,
                                          DVTMachOEnumerationSegmentsBlock _Nonnull block);

/** Enumerates the sections of `command32`/`command64` within `fileData`. */
typedef BOOL (^DVTMachOEnumerationSectionsBlock)(const struct section *_Nullable section32,
                                                  const struct section_64 *_Nullable section64,
                                                  BOOL *_Nonnull stop,
                                                  NSError *_Nullable *_Nonnull error);

DVT_EXTERN BOOL DVTMachOEnumerateSections(NSData *_Nonnull fileData,
                                          const struct segment_command *_Nullable command32,
                                          const struct segment_command_64 *_Nullable command64,
                                          NSError *_Nullable *_Nullable error,
                                          DVTMachOEnumerationSectionsBlock _Nonnull block);

/** Returns the `MH_*` file type of every slice, in slice order. */
DVT_EXTERN NSArray<NSNumber *> *_Nullable DVTMachOFileTypes(NSData *fileData,
                                                            NSError *_Nullable *_Nullable error);

/**
  Returns the platform IDs (`PLATFORM_*`) present across all slices, in slice
  order and without de-duplication.
 */
DVT_EXTERN NSArray<NSNumber *> *_Nullable DVTMachOPlatformsForExecutable(NSString *executablePath,
                                                                        NSError *_Nullable *_Nullable error);

/**
  Returns `YES` when `executablePath` targets `platform` in any slice, `NO` when
  it does not, and `nil` with an error when the file cannot be inspected.
 */
DVT_EXTERN NSNumber *_Nullable DVTMachOHasPlatform(NSString *executablePath,
                                                   DVTMachOPlatform platform,
                                                   NSError *_Nullable *_Nullable error);

/** Returns the platform of `executablePath`, or `0` when it cannot be read. */
DVT_EXTERN DVTMachOPlatform DVTMachOPlatformForExecutable(NSString *_Nonnull executablePath,
                                                           NSError *_Nullable *_Nullable error);

/** Returns the canonical name of every slice, e.g. `"arm64e"` or `"x86_64"`. */
DVT_EXTERN NSArray<NSString *> *_Nullable DVTMachOArchitecturesForExecutable(NSString *executablePath,
                                                                            NSError *_Nullable *_Nullable error);

/**
  Returns the `LC_UUID` of every slice as a canonical uppercase dashed string, or
  an empty array when the file carries no UUID.
 */
DVT_EXTERN NSArray<NSString *> *_Nullable DVTMachOUUIDsForExecutable(NSString *executablePath,
                                                                     NSError *_Nullable *_Nullable error);

/** Returns the Swift ABI version of every slice, as unsigned integers. */
DVT_EXTERN NSArray<NSNumber *> *_Nullable DVTMachOSwiftABIVersion(NSString *executablePath,
                                                                  NSError *_Nullable *_Nullable error);

/**
  Returns the `LC_VERSION_MIN_*` of the slice matching `architecture`, or `nil`
  when the slice declares no minimum version.
 */
DVT_EXTERN DVTVersion *_Nullable DVTMachOOSVersionMinForArch(NSData *_Nonnull fileData,
                                                              DVTArchitecture *_Nonnull architecture,
                                                              DVTMachOPlatform platform,
                                                              NSError *_Nullable *_Nullable error);

/**
  Maps every architecture in `executablePath` to its minimum OS version.

  Returns `nil` with an error when the file declares no minimum version.
 */
DVT_EXTERN NSDictionary<DVTArchitecture *, DVTVersion *> *_Nullable
    DVTMachOOSVersionMinForPlatform(NSString *_Nonnull executablePath,
                                    DVTMachOPlatform platform,
                                    NSError *_Nullable *_Nullable error);

/**
  Returns the `LC_SOURCE_VERSION` of the slice matching `architecture`, or `nil`
  when that slice declares none.

  When `architecture` is `nil` the result is undefined.
 */
DVT_EXTERN NSString *_Nullable DVTMachOSourceVersionForArch(NSData *_Nonnull fileData,
                                                             DVTArchitecture *_Nullable architecture,
                                                             NSError *_Nullable *_Nullable error);

/**
  Returns `YES` when `path` is a Mach-O file.

  Reports a failure to open `path` through `error` using `NSPOSIXErrorDomain`
  and the underlying `errno`.
 */
DVT_EXTERN NSNumber *_Nullable DVTFileAtPathIsMachO(NSString *_Nonnull path,
                                                    NSError *_Nullable *_Nullable error);

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
 */
DVT_EXTERN NSArray<NSString *> *DVTMachOReexportedLibrariesForExecutable(NSString *executablePath,
                                                                          NSInteger sliceIndex,
                                                                          NSError *_Nullable *_Nullable error);

/**
  Returns `YES` when any slice contains an `LC_SEGMENT`/`LC_SEGMENT_64` carrying
  a `__TEXT` section, i.e. the file actually holds machine code.
 */
DVT_EXTERN NSNumber *_Nullable DVTMachOBinaryHasAnyMachineCode(NSString *_Nonnull executablePath,
                                                               NSError *_Nullable *_Nullable error);

/**
  Present for source compatibility with the original framework. The original
  compiles the body away entirely, so this is a documented no-op.
 */
DVT_EXTERN void DVTSetupWeakPropertyKVOAssertions(void);

NS_ASSUME_NONNULL_END
