//
//  DVTMachO.m
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

#import "DVTMachO.h"

#import <Foundation/NSData.h>
#import <Foundation/NSFileManager.h>
#import <mach-o/fat.h>
#import <stddef.h>
#import <string.h>

NSString *const DVTMachOErrorDomain = @"DVTMachOErrorDomain";

enum {
    DVTMachOErrorCodeUnreadable = 1,
    DVTMachOErrorCodeTruncated = 2,
};

#pragma mark - Byte order

/*
 PureDarwin's SDK does not pull in the byte-order helpers, so swap by hand
 rather than depending on a header the framework should not need.
 */
static uint32_t DVT32Swap(uint32_t value)
{
    return ((value & 0x000000FFu) << 24) | ((value & 0x0000FF00u) << 8) | ((value & 0x00FF0000u) >> 8) |
           ((value & 0xFF000000u) >> 24);
}

static uint64_t DVT64Swap(uint64_t value)
{
    return ((uint64_t)DVT32Swap((uint32_t)(value & 0xFFFFFFFFull)) << 32) |
           (uint64_t)DVT32Swap((uint32_t)(value >> 32));
}

/** Reads a 32-bit field, byte swapping it when the file is big endian. */
static uint32_t DVTRead32(const void *base, uint32_t fieldOffset, BOOL swap)
{
    uint32_t value = 0;
    memcpy(&value, (const uint8_t *)base + fieldOffset, sizeof(value));
    return swap ? DVT32Swap(value) : value;
}

static uint64_t DVTRead64(const void *base, uint32_t fieldOffset, BOOL swap)
{
    uint64_t value = 0;
    memcpy(&value, (const uint8_t *)base + fieldOffset, sizeof(value));
    return swap ? DVT64Swap(value) : value;
}

#pragma mark - Small helpers

/** Index of `string` in `strings`, or `NSNotFound`. */
static NSUInteger DVTIndexOfString(NSArray<NSString *> *strings, NSString *string)
{
    NSUInteger count = strings.count;
    for (NSUInteger index = 0; index < count; index++) {
        if ([[strings objectAtIndex:index] isEqualToString:string]) {
            return index;
        }
    }
    return NSNotFound;
}

/** Formats a 16 byte LC_UUID payload as a canonical uppercase dashed string. */
static NSString *DVTUUIDStringFromBytes(const uint8_t *uuid)
{
    NSMutableString *result = [NSMutableString stringWithCapacity:36];
    for (NSUInteger index = 0; index < 16; index++) {
        if (index == 4 || index == 6 || index == 8 || index == 10) {
            [result appendString:@"-"];
        }
        [result appendFormat:@"%02X", uuid[index]];
    }
    return result;
}

#pragma mark - Magic numbers

static BOOL DVTIsFatMagic(uint32_t magic)
{
    return magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64;
}

/**
 Classifies a thin Mach-O header's magic.

 @param is64Bit  Set to `YES` for a 64-bit header.
 @param swapped  Set to `YES` when the file's byte order is the opposite of the
                 host's, in which case every field read must be swapped.
 */
static BOOL DVTIsMachMagic(uint32_t magic, BOOL *is64Bit, BOOL *swapped)
{
    switch (magic) {
    case MH_MAGIC:
        *is64Bit = NO;
        *swapped = NO;
        return YES;
    case MH_CIGAM:
        *is64Bit = NO;
        *swapped = YES;
        return YES;
    case MH_MAGIC_64:
        *is64Bit = YES;
        *swapped = NO;
        return YES;
    case MH_CIGAM_64:
        *is64Bit = YES;
        *swapped = YES;
        return YES;
    default:
        return NO;
    }
}

static BOOL DVTIsArchiveMagic(const uint8_t *bytes, NSUInteger available)
{
    static const char archiveMagic[] = "!<arch>\n";
    if (available < sizeof(archiveMagic) - 1) {
        return NO;
    }
    return memcmp(bytes, archiveMagic, sizeof(archiveMagic) - 1) == 0;
}

#pragma mark - File access

static NSData *DVTReadFile(NSString *executablePath, NSError **error)
{
    if (executablePath == nil) {
        return nil;
    }
    NSData *data = [[NSFileManager defaultManager] contentsAtPath:executablePath];
    if (data == nil && error != NULL) {
        *error = [NSError errorWithDomain:DVTMachOErrorDomain code:DVTMachOErrorCodeUnreadable userInfo:nil];
    }
    return data;
}

static void DVTFillError(NSError **error, NSInteger code, NSString *reason)
{
    if (error == NULL) {
        return;
    }
    *error = [NSError errorWithDomain:DVTMachOErrorDomain
                                  code:code
                              userInfo:[NSDictionary dictionaryWithObjectsAndKeys:reason, @"NSLocalizedDescription",
                                                                          nil]];
}

#pragma mark - Slice discovery

/**
 Splits `fileData` into its architectures. A thin file yields a single slice
 holding the whole buffer; a fat file yields one slice per `fat_arch`, with the
 fat header stripped. Returns `nil` when the data is neither.
 */
static NSArray<NSData *> *DVTSlicesInData(NSData *fileData, NSError **error)
{
    NSUInteger length = fileData.length;
    if (length < sizeof(struct mach_header)) {
        DVTFillError(error, DVTMachOErrorCodeTruncated, @"file is too small to be a Mach-O");
        return nil;
    }

    const uint8_t *bytes = (const uint8_t *)[fileData bytes];
    uint32_t magic = DVTRead32(bytes, 0, NO);
    BOOL ignored64 = NO;
    BOOL ignoredSwap = NO;
    if (DVTIsMachMagic(magic, &ignored64, &ignoredSwap)) {
        return [NSArray arrayWithObjects:fileData, nil];
    }

    if (!DVTIsFatMagic(magic)) {
        DVTFillError(error, DVTMachOErrorCodeTruncated, @"file is not a Mach-O image");
        return nil;
    }

    BOOL fatIs64 = (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64);
    BOOL swap = (magic == FAT_CIGAM || magic == FAT_CIGAM_64);
    uint32_t architectureSize = fatIs64 ? (uint32_t)sizeof(struct fat_arch_64) : (uint32_t)sizeof(struct fat_arch);

    uint32_t architectureCount = DVTRead32(bytes, offsetof(struct fat_header, nfat_arch), swap);
    uint64_t tableOffset = (uint64_t)sizeof(struct fat_header);
    if ((uint64_t)architectureCount * architectureSize + tableOffset > (uint64_t)length) {
        DVTFillError(error, DVTMachOErrorCodeTruncated, @"fat architecture table runs past end of file");
        return nil;
    }

    NSMutableArray<NSData *> *slices = [NSMutableArray arrayWithCapacity:architectureCount];
    for (uint32_t index = 0; index < architectureCount; index++) {
        const uint8_t *entry = bytes + tableOffset + (uint64_t)index * architectureSize;
        uint64_t offset;
        uint64_t size;
        if (fatIs64) {
            offset = DVTRead64(entry, offsetof(struct fat_arch_64, offset), swap);
            size = DVTRead64(entry, offsetof(struct fat_arch_64, size), swap);
        } else {
            offset = DVTRead32(entry, offsetof(struct fat_arch, offset), swap);
            size = DVTRead32(entry, offsetof(struct fat_arch, size), swap);
        }

        if (offset > (uint64_t)length || size > (uint64_t)length - offset) {
            DVTFillError(error, DVTMachOErrorCodeTruncated, @"fat slice runs past end of file");
            return nil;
        }
        [slices addObject:[fileData subdataWithRange:NSMakeRange((NSUInteger)offset, (NSUInteger)size)]];
    }

    return slices;
}

/**
 Invokes `block` once per architecture selected by `sliceIndex`, where a
 negative index means every slice. Returns `NO` (without an error) when the
 file cannot be read or is not a Mach-O.
 */
static BOOL DVTForEachSelectedSlice(NSString *executablePath,
                                    NSInteger sliceIndex,
                                    NSError **error,
                                    void (^visit)(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit))
{
    NSData *fileData = DVTReadFile(executablePath, error);
    if (fileData == nil) {
        return NO;
    }

    NSArray<NSData *> *slices = DVTSlicesInData(fileData, error);
    if (slices == nil) {
        return NO;
    }

    NSUInteger count = slices.count;
    if (sliceIndex < 0) {
        for (NSUInteger index = 0; index < count; index++) {
            NSData *slice = [slices objectAtIndex:index];
            BOOL ignored64 = NO;
            BOOL ignoredSwap = NO;
            DVTIsMachMagic(DVTRead32([slice bytes], 0, NO), &ignored64, &ignoredSwap);
            visit(slice, index, ignoredSwap, ignored64);
        }
        return YES;
    }

    if ((NSUInteger)sliceIndex >= count) {
        return YES;
    }

    NSData *slice = [slices objectAtIndex:(NSUInteger)sliceIndex];
    BOOL ignored64 = NO;
    BOOL ignoredSwap = NO;
    DVTIsMachMagic(DVTRead32([slice bytes], 0, NO), &ignored64, &ignoredSwap);
    visit(slice, (NSUInteger)sliceIndex, ignoredSwap, ignored64);
    return YES;
}

/** Walks the load commands of one slice, invoking `block` for each command. */
static void DVTForEachLoadCommand(NSData *slice,
                                  BOOL swap,
                                  BOOL is64Bit,
                                  void (^visit)(const struct load_command *command, uint32_t commandSize))
{
    NSUInteger length = slice.length;
    if (length == 0) {
        return;
    }

    const uint8_t *bytes = (const uint8_t *)[slice bytes];
    uint32_t headerSize = is64Bit ? (uint32_t)sizeof(struct mach_header_64) : (uint32_t)sizeof(struct mach_header);
    if (length < headerSize) {
        return;
    }

    uint32_t commandCount = DVTRead32(bytes, is64Bit ? offsetof(struct mach_header_64, ncmds)
                                                    : offsetof(struct mach_header, ncmds),
                                     swap);
    uint32_t commandsSize = DVTRead32(bytes, is64Bit ? offsetof(struct mach_header_64, sizeofcmds)
                                                      : offsetof(struct mach_header, sizeofcmds),
                                       swap);
    if (commandsSize > length - headerSize) {
        return;
    }

    /*
     Walk only the region the header declares, in pointer-width arithmetic. A
     corrupt or byte-swapped `cmdsize` must not be able to wrap a 32-bit
     addition and so pass the bounds check below.
     */
    NSUInteger regionEnd = (NSUInteger)headerSize + (NSUInteger)commandsSize;
    NSUInteger cursor = headerSize;
    for (uint32_t index = 0; index < commandCount; index++) {
        if (cursor + sizeof(struct load_command) > regionEnd) {
            return;
        }
        const struct load_command *command = (const struct load_command *)(bytes + cursor);
        uint32_t commandSize = DVTRead32(command, offsetof(struct load_command, cmdsize), swap);
        if (commandSize < sizeof(struct load_command) || cursor + (NSUInteger)commandSize > regionEnd) {
            return;
        }
        visit(command, commandSize);
        cursor += (NSUInteger)commandSize;
    }
}

#pragma mark - Public API: file classification

BOOL DVTMachOIsArchive(NSString *executablePath)
{
    NSData *fileData = DVTReadFile(executablePath, NULL);
    if (fileData == nil || fileData.length == 0) {
        return NO;
    }
    return DVTIsArchiveMagic((const uint8_t *)[fileData bytes], fileData.length);
}

BOOL DVTMachOHasFatHeader(NSString *executablePath)
{
    NSData *fileData = DVTReadFile(executablePath, NULL);
    if (fileData == nil || fileData.length < sizeof(uint32_t)) {
        return NO;
    }
    return DVTIsFatMagic(DVTRead32((const uint8_t *)[fileData bytes], 0, NO));
}

BOOL DVTMachOEnumerateSlices(NSString *executablePath,
                             NSError **error,
                             DVTMachOEnumerationBlock block)
{
    if (block == nil) {
        return NO;
    }

    __block BOOL keepGoing = YES;
    BOOL read = DVTForEachSelectedSlice(executablePath, -1, error, ^(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit) {
        (void)swap;
        (void)is64Bit;
        if (!keepGoing) {
            return;
        }
        if (!block(slice, index)) {
            keepGoing = NO;
        }
    });
    return read && keepGoing;
}

BOOL DVTMachOEnumerateLoadCommands(NSString *executablePath,
                                   uint32_t cmd,
                                   uint32_t cmdsize,
                                   NSError **error,
                                   DVTMachOEnumerationLoadCommandsBlock block)
{
    if (block == nil) {
        return NO;
    }

    __block BOOL keepGoing = YES;
    return DVTForEachSelectedSlice(executablePath, -1, error, ^(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit) {
        (void)index;
        if (!keepGoing) {
            return;
        }
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            if (!keepGoing) {
                return;
            }
            uint32_t commandType = DVTRead32(command, offsetof(struct load_command, cmd), swap);
            if (cmd != 0 && commandType != cmd) {
                return;
            }
            if (cmdsize != 0 && commandSize != cmdsize) {
                return;
            }
            if (!block(command, slice)) {
                keepGoing = NO;
            }
        });
    }) && keepGoing;
}

#pragma mark - Public API: slice metadata

NSArray<NSNumber *> *DVTMachOFileTypes(NSString *executablePath)
{
    NSMutableArray<NSNumber *> *types = [NSMutableArray arrayWithCapacity:1];
    DVTForEachSelectedSlice(executablePath, -1, NULL, ^(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit) {
        (void)slice;
        (void)index;
        uint32_t fileType = DVTRead32((const uint8_t *)[slice bytes],
                                     is64Bit ? offsetof(struct mach_header_64, filetype)
                                            : offsetof(struct mach_header, filetype),
                                     swap);
        [types addObject:[NSNumber numberWithUnsignedInt:fileType]];
    });
    return types;
}

static NSString *DVTArchitectureName(cpu_type_t cpuType, cpu_subtype_t cpuSubtype)
{
    switch (cpuType) {
    case CPU_TYPE_X86_64:
        return @"x86_64";
    case CPU_TYPE_X86:
        return (cpuSubtype == 3) ? @"i386" : @"x86";
    case CPU_TYPE_ARM64:
        return @"arm64";
    case CPU_TYPE_ARM:
        return @"arm";
    case CPU_TYPE_POWERPC:
        return @"ppc";
    case CPU_TYPE_POWERPC64:
        return @"ppc64";
    default:
        return [NSString stringWithFormat:@"cpu(%d,%d)", (int)cpuType, (int)cpuSubtype];
    }
}

NSArray<NSString *> *DVTMachOArchitecturesForExecutable(NSString *executablePath)
{
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:1];
    DVTForEachSelectedSlice(executablePath, -1, NULL, ^(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit) {
        (void)slice;
        (void)index;
        const uint8_t *bytes = (const uint8_t *)[slice bytes];
        uint32_t cpuType = DVTRead32(bytes, is64Bit ? offsetof(struct mach_header_64, cputype)
                                                    : offsetof(struct mach_header, cputype),
                                     swap);
        uint32_t cpuSubtype = DVTRead32(bytes, is64Bit ? offsetof(struct mach_header_64, cpusubtype)
                                                       : offsetof(struct mach_header, cpusubtype),
                                        swap);
        [names addObject:DVTArchitectureName((cpu_type_t)cpuType, (cpu_subtype_t)cpuSubtype)];
    });
    return names;
}

NSArray<NSString *> *DVTMachOUUIDsForExecutable(NSString *executablePath)
{
    NSMutableArray<NSString *> *uuids = [NSMutableArray arrayWithCapacity:1];
    DVTForEachSelectedSlice(executablePath, -1, NULL, ^(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit) {
        (void)index;
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            (void)commandSize;
            if (DVTRead32(command, offsetof(struct load_command, cmd), swap) != LC_UUID) {
                return;
            }
            if (commandSize < sizeof(struct uuid_command)) {
                return;
            }
            const struct uuid_command *uuidCommand = (const struct uuid_command *)command;
            [uuids addObject:DVTUUIDStringFromBytes(uuidCommand->uuid)];
        });
    });
    return uuids;
}

#pragma mark - Public API: platforms

static void DVTCollectPlatform(NSData *slice, BOOL swap, BOOL is64Bit, NSMutableArray<NSNumber *> *platforms)
{
    DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
        uint32_t commandType = DVTRead32(command, offsetof(struct load_command, cmd), swap);
        if (commandType == LC_BUILD_VERSION) {
            if (commandSize < offsetof(struct build_version_command, minos) + sizeof(uint32_t)) {
                return;
            }
            const struct build_version_command *build = (const struct build_version_command *)command;
            [platforms addObject:[NSNumber numberWithUnsignedInt:build->platform]];
        } else if (commandType == LC_VERSION_MIN_MACOSX) {
            [platforms addObject:[NSNumber numberWithUnsignedInt:PLATFORM_MACOS]];
        }
    });
}

NSSet<NSNumber *> *DVTMachOPlatformsForExecutable(NSString *executablePath)
{
    NSMutableArray<NSNumber *> *platforms = [NSMutableArray arrayWithCapacity:1];
    DVTForEachSelectedSlice(executablePath, -1, NULL, ^(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit) {
        (void)index;
        DVTCollectPlatform(slice, swap, is64Bit, platforms);
    });
    return [NSSet setWithArray:platforms];
}

BOOL DVTMachOHasPlatform(NSString *executablePath, uint32_t platform)
{
    NSSet<NSNumber *> *platforms = DVTMachOPlatformsForExecutable(executablePath);
    return [platforms containsObject:[NSNumber numberWithUnsignedInt:platform]];
}

#pragma mark - Public API: libraries and rpaths

/**
 Reads the NUL terminated path a `dylib_command`/`rpath_command` points at.
 `offset` is relative to the start of the command.
 */
static NSString *DVTPathInDylibCommand(const struct load_command *command, uint32_t commandSize, BOOL swap)
{
    if (commandSize < sizeof(struct dylib_command)) {
        return nil;
    }
    /* The offset is relative to the start of the command, so read from `command`. */
    uint32_t pathOffset = DVTRead32(command, offsetof(struct dylib_command, dylib.name.offset), swap);
    if (pathOffset == 0 || pathOffset >= commandSize) {
        return nil;
    }

    const char *path = (const char *)command + pathOffset;
    size_t remaining = commandSize - pathOffset;
    size_t length = strnlen(path, remaining);
    if (length == 0) {
        return nil;
    }
    return [[NSString alloc] initWithBytes:path length:length encoding:NSUTF8StringEncoding];
}

static BOOL DVTIsDylibLoadCommand(uint32_t commandType)
{
    switch (commandType) {
    case LC_LOAD_DYLIB:
    case LC_LOAD_WEAK_DYLIB:
    case LC_REEXPORT_DYLIB:
    case LC_LOAD_UPWARD_DYLIB:
    case LC_LAZY_LOAD_DYLIB:
        return YES;
    default:
        return NO;
    }
}

NSString *DVTMachOLibraryNameForLoadCommand(const struct load_command *loadCommand)
{
    if (loadCommand == NULL) {
        return nil;
    }
    return DVTPathInDylibCommand(loadCommand, DVTRead32(loadCommand, offsetof(struct load_command, cmdsize), NO), NO);
}

static NSArray<NSString *> *DVTDylibNames(NSString *executablePath,
                                          NSInteger sliceIndex,
                                          BOOL includeWeak,
                                          BOOL reexportsOnly)
{
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:8];
    DVTForEachSelectedSlice(executablePath, sliceIndex, NULL, ^(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit) {
        (void)index;
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            uint32_t commandType = DVTRead32(command, offsetof(struct load_command, cmd), swap);
            if (reexportsOnly) {
                if (commandType != LC_REEXPORT_DYLIB) {
                    return;
                }
            } else if (!DVTIsDylibLoadCommand(commandType)) {
                return;
            } else if (!includeWeak && commandType == LC_LOAD_WEAK_DYLIB) {
                return;
            }

            NSString *name = DVTPathInDylibCommand(command, commandSize, swap);
            if (name != nil && DVTIndexOfString(names, name) == NSNotFound) {
                [names addObject:name];
            }
        });
    });
    return names;
}

NSArray<NSString *> *DVTMachOLinkedLibrariesForExecutable(NSString *executablePath,
                                                          NSInteger sliceIndex,
                                                          NSError **error)
{
    (void)error;
    return DVTDylibNames(executablePath, sliceIndex, NO, NO);
}

NSArray<NSString *> *DVTMachOLinkedLibrariesForExecutableIncludingWeakLinks(NSString *executablePath,
                                                                           NSInteger sliceIndex,
                                                                           NSError **error)
{
    (void)error;
    return DVTDylibNames(executablePath, sliceIndex, YES, NO);
}

NSArray<NSString *> *DVTMachOReexportedLibrariesForExecutable(NSString *executablePath,
                                                                NSInteger sliceIndex,
                                                                NSError **error)
{
    (void)error;
    return DVTDylibNames(executablePath, sliceIndex, YES, YES);
}

NSArray<NSString *> *DVTMachORPathsForExecutable(NSString *executablePath, NSInteger sliceIndex, NSError **error)
{
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:4];
    DVTForEachSelectedSlice(executablePath, sliceIndex, error, ^(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit) {
        (void)index;
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            if (DVTRead32(command, offsetof(struct load_command, cmd), swap) != LC_RPATH) {
                return;
            }
            NSString *path = DVTPathInDylibCommand(command, commandSize, swap);
            if (path != nil && DVTIndexOfString(paths, path) == NSNotFound) {
                [paths addObject:path];
            }
        });
    });
    return paths;
}

#pragma mark - Public API: code presence

BOOL DVTMachOBinaryHasAnyMachineCode(NSString *executablePath)
{
    __block BOOL hasCode = NO;
    DVTForEachSelectedSlice(executablePath, -1, NULL, ^(NSData *slice, NSUInteger index, BOOL swap, BOOL is64Bit) {
        (void)slice;
        (void)index;
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            (void)commandSize;
            uint32_t commandType = DVTRead32(command, offsetof(struct load_command, cmd), swap);
            if (commandType != LC_SEGMENT && commandType != LC_SEGMENT_64) {
                return;
            }
            if (commandSize < sizeof(struct segment_command)) {
                return;
            }
            char name[17] = {0};
            memcpy(name, command + 1, sizeof(name) - 1);
            if (strncmp(name, "__TEXT", sizeof("__TEXT") - 1) == 0) {
                hasCode = YES;
            }
        });
    });
    return hasCode;
}

void DVTSetupWeakPropertyKVOAssertions(void)
{
    /* The original compiles this away entirely; kept for source compatibility. */
}
