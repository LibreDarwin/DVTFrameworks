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
#import <fcntl.h>
#import <mach-o/fat.h>
#import <stddef.h>
#import <string.h>
#import <unistd.h>

NSString *const DVTMachOErrorDomain = @"DVTMachOErrorDomain";

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
        DVTFillError(error, DVTMachOErrorCodeNotMachO, @"file is not a Mach-O image");
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

#pragma mark - Reading a file the way the original does

/**
  Reads `executablePath` for the path-taking API.

  A directory, or anything else the file system can describe but not read as a
  file, reports the `NSCocoaErrorDomain` failure the reading API produced. A
  file that is present but cannot be turned into a Mach-O reports
  `DVTMachOErrorCodeFileUnreadable`, which is what the original reports for the
  binaries that now live only in the dyld shared cache.
 */
static NSData *DVTReadMachOFile(NSString *executablePath, NSError **error)
{
    if (executablePath == nil) {
        DVTFillError(error, DVTMachOErrorCodeFileUnreadable, @"no path given");
        return nil;
    }

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:executablePath options:0 error:&readError];
    if (data == nil) {
        if (readError != nil && [readError.domain isEqualToString:NSCocoaErrorDomain]) {
            /*
             A directory (NSFileReadUnknownError) or a path that is not a file
             at all: report the reading failure itself rather than a Mach-O
             error, because the file was never the problem.
             */
            if (error != NULL) {
                *error = readError;
            }
            return nil;
        }
        DVTFillError(error, DVTMachOErrorCodeFileUnreadable, @"file could not be read");
        return nil;
    }
    return data;
}

#pragma mark - Slice iteration over data

/** The `cputype`/`cpusubtype` of a slice, read from its Mach-O header. */
static void DVTSliceCPU(NSData *slice, BOOL swap, BOOL is64Bit, cpu_type_t *outType, cpu_subtype_t *outSubType)
{
    const uint8_t *bytes = (const uint8_t *)[slice bytes];
    uint32_t fieldOffset = is64Bit ? offsetof(struct mach_header_64, cputype) : offsetof(struct mach_header, cputype);
    *outType = (cpu_type_t)DVTRead32(bytes, fieldOffset, swap);
    fieldOffset = is64Bit ? offsetof(struct mach_header_64, cpusubtype) : offsetof(struct mach_header, cpusubtype);
    *outSubType = (cpu_subtype_t)DVTRead32(bytes, fieldOffset, swap);
}

/** Invokes `visit` for every slice, reporting the slice's CPU to the callback. */
static BOOL DVTForEachSliceInData(NSData *fileData,
                                 NSError **error,
                                 void (^visit)(NSData *slice, cpu_type_t cpuType, cpu_subtype_t cpuSubType, BOOL is64Bit,
                                               BOOL swap))
{
    NSArray<NSData *> *slices = DVTSlicesInData(fileData, error);
    if (slices == nil) {
        return NO;
    }

    for (NSData *slice in slices) {
        BOOL is64Bit = NO;
        BOOL swap = NO;
        DVTIsMachMagic(DVTRead32([slice bytes], 0, NO), &is64Bit, &swap);
        cpu_type_t cpuType = CPU_TYPE_ANY;
        cpu_subtype_t cpuSubType = 0;
        DVTSliceCPU(slice, swap, is64Bit, &cpuType, &cpuSubType);
        visit(slice, cpuType, cpuSubType, is64Bit, swap);
    }
    return YES;
}

#pragma mark - Public API: file classification

NSNumber *DVTMachOIsArchive(NSData *fileData, NSError **error)
{
    /*
     The original answers "no" only for a file it could parse. Data that holds
     no Mach-O at all yields nil plus an error, so a caller can distinguish
     "not an archive" from "not something this function understands".
     */
    __block BOOL isArchive = NO;
    BOOL parsed = DVTMachOEnumerateSlices(fileData, error, ^BOOL(NSData *slice, cpu_type_t cpuType,
                                                                 cpu_subtype_t cpuSubType, BOOL *stop, NSError **sliceError) {
        (void)cpuType;
        (void)cpuSubType;
        (void)stop;
        (void)sliceError;
        isArchive = isArchive || DVTIsArchiveMagic((const uint8_t *)[slice bytes], slice.length);
        return YES;
    });
    if (!parsed) {
        return nil;
    }
    return [NSNumber numberWithBool:isArchive];
}

NSNumber *DVTMachOHasFatHeader(NSData *fileData, NSError **error)
{
    (void)error;
    if (fileData == nil || fileData.length < sizeof(uint32_t)) {
        return [NSNumber numberWithBool:NO];
    }
    /*
     The name is literal: this reports whether the data starts with a *fat*
     header, so a thin Mach-O answers NO. Only FAT_MAGIC/FAT_CIGAM qualify.
     */
    uint32_t magic = DVTRead32((const uint8_t *)[fileData bytes], 0, NO);
    return [NSNumber numberWithBool:DVTIsFatMagic(magic)];
}

BOOL DVTMachOEnumerateSlices(NSData *fileData, NSError **error, DVTMachOEnumerationBlock block)
{
    if (block == nil || fileData == nil) {
        return NO;
    }

    __block BOOL keepGoing = YES;
    __block BOOL stop = NO;
    __block NSError *blockError = nil;
    BOOL parsed = DVTForEachSliceInData(fileData, error, ^(NSData *slice, cpu_type_t cpuType, cpu_subtype_t cpuSubType,
                                                           BOOL is64Bit, BOOL swap) {
        (void)is64Bit;
        (void)swap;
        if (!keepGoing || stop) {
            return;
        }
        NSError *sliceError = nil;
        if (!block(slice, cpuType, cpuSubType, &stop, &sliceError)) {
            keepGoing = NO;
        }
        if (sliceError != nil) {
            blockError = sliceError;
            keepGoing = NO;
        }
    });
    if (blockError != nil && error != NULL) {
        *error = blockError;
    }
    return parsed && keepGoing;
}

BOOL DVTMachOEnumerateLoadCommands(NSData *fileData, NSError **error, DVTMachOEnumerationLoadCommandsBlock block)
{
    if (block == nil || fileData == nil) {
        return NO;
    }

    __block BOOL keepGoing = YES;
    __block BOOL stop = NO;
    __block NSError *blockError = nil;
    BOOL parsed = DVTForEachSliceInData(fileData, error, ^(NSData *slice, cpu_type_t cpuType, cpu_subtype_t cpuSubType,
                                                           BOOL is64Bit, BOOL swap) {
        (void)cpuType;
        (void)cpuSubType;
        if (!keepGoing || stop) {
            return;
        }
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            (void)commandSize;
            if (!keepGoing || stop) {
                return;
            }
            NSError *commandError = nil;
            if (!block(command, &stop, &commandError)) {
                keepGoing = NO;
            }
            if (commandError != nil) {
                blockError = commandError;
                keepGoing = NO;
            }
        });
    });
    if (blockError != nil && error != NULL) {
        *error = blockError;
    }
    return parsed && keepGoing;
}

BOOL DVTMachOEnumerateSegments(NSData *fileData, NSError **error, DVTMachOEnumerationSegmentsBlock block)
{
    if (block == nil || fileData == nil) {
        return NO;
    }

    __block BOOL keepGoing = YES;
    __block BOOL stop = NO;
    __block NSError *blockError = nil;
    BOOL parsed = DVTForEachSliceInData(fileData, error, ^(NSData *slice, cpu_type_t cpuType, cpu_subtype_t cpuSubType,
                                                           BOOL is64Bit, BOOL swap) {
        (void)cpuType;
        (void)cpuSubType;
        if (!keepGoing || stop) {
            return;
        }
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            uint32_t commandType = DVTRead32(command, offsetof(struct load_command, cmd), swap);
            if (!keepGoing || stop) {
                return;
            }
            const struct segment_command *command32 = NULL;
            const struct segment_command_64 *command64 = NULL;
            if (commandType == LC_SEGMENT && commandSize >= sizeof(struct segment_command)) {
                command32 = (const struct segment_command *)command;
            } else if (commandType == LC_SEGMENT_64 && commandSize >= sizeof(struct segment_command_64)) {
                command64 = (const struct segment_command_64 *)command;
            }
            if (command32 == NULL && command64 == NULL) {
                return;
            }
            NSError *segmentError = nil;
            if (!block(command32, command64, &stop, &segmentError)) {
                keepGoing = NO;
            }
            if (segmentError != nil) {
                blockError = segmentError;
                keepGoing = NO;
            }
        });
    });
    if (blockError != nil && error != NULL) {
        *error = blockError;
    }
    return parsed && keepGoing;
}

BOOL DVTMachOEnumerateSections(NSData *fileData,
                               const struct segment_command *command32,
                               const struct segment_command_64 *command64,
                               NSError **error,
                               DVTMachOEnumerationSectionsBlock block)
{
    if (block == nil || fileData == nil || (command32 == NULL && command64 == NULL)) {
        return NO;
    }

    /*
     The section list lives inside the segment command, so this reads the
     segment's own bytes rather than walking load commands: the caller already
     has the command and only needs the buffer to resolve its offsets.
     `sections` is a trailing flexible array, so the list starts at the size of
     the command itself.
     */
    const uint8_t *segmentBytes = (const uint8_t *)(command32 != NULL ? (const void *)command32 : (const void *)command64);
    uint32_t nsects = command32 != NULL ? command32->nsects : command64->nsects;
    uint32_t sectionSize = command32 != NULL ? (uint32_t)sizeof(struct section) : (uint32_t)sizeof(struct section_64);
    uint32_t listOffset = command32 != NULL ? (uint32_t)sizeof(struct segment_command)
                                            : (uint32_t)sizeof(struct segment_command_64);

    /* A segment command cannot claim more sections than the file can hold. */
    uint64_t listEnd = (uint64_t)listOffset + (uint64_t)nsects * (uint64_t)sectionSize;
    NSUInteger available = fileData.length;
    NSUInteger commandStart = (NSUInteger)(segmentBytes - (const uint8_t *)[fileData bytes]);
    if (commandStart > available || listEnd > (uint64_t)(available - commandStart)) {
        DVTFillError(error, DVTMachOErrorCodeTruncated, @"section list runs past end of file");
        return NO;
    }

    for (uint32_t index = 0; index < nsects; index++) {
        const uint8_t *entry = segmentBytes + listOffset + (uint64_t)index * sectionSize;
        const struct section *section32 = NULL;
        const struct section_64 *section64 = NULL;
        if (command32 != NULL) {
            section32 = (const struct section *)entry;
        } else {
            section64 = (const struct section_64 *)entry;
        }
        BOOL stop = NO;
        NSError *sectionError = nil;
        if (!block(section32, section64, &stop, &sectionError)) {
            return NO;
        }
        if (sectionError != nil) {
            if (error != NULL) {
                *error = sectionError;
            }
            return NO;
        }
        if (stop) {
            return YES;
        }
    }
    return YES;
}

#pragma mark - Public API: slice metadata

NSArray<NSNumber *> *DVTMachOFileTypes(NSData *fileData, NSError **error)
{
    NSMutableArray<NSNumber *> *types = [NSMutableArray arrayWithCapacity:1];
    BOOL parsed = DVTMachOEnumerateSlices(fileData, error, ^BOOL(NSData *slice, cpu_type_t cpuType,
                                                                 cpu_subtype_t cpuSubType, BOOL *stop, NSError **sliceError) {
        (void)cpuType;
        (void)cpuSubType;
        (void)stop;
        (void)sliceError;
        BOOL is64Bit = NO;
        BOOL swap = NO;
        DVTIsMachMagic(DVTRead32((const uint8_t *)[slice bytes], 0, NO), &is64Bit, &swap);
        uint32_t fieldOffset = is64Bit ? offsetof(struct mach_header_64, filetype) : offsetof(struct mach_header, filetype);
        uint32_t fileType = DVTRead32((const uint8_t *)[slice bytes], fieldOffset, swap);
        [types addObject:@(fileType)];
        return YES;
    });
    if (!parsed) {
        return nil;
    }
    return types;
}

NSArray<NSString *> *DVTMachOArchitecturesForExecutable(NSString *executablePath, NSError **error)
{
    NSData *fileData = DVTReadMachOFile(executablePath, error);
    if (fileData == nil) {
        return nil;
    }

    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:1];
    BOOL parsed = DVTForEachSliceInData(fileData, error, ^(NSData *slice, cpu_type_t cpuType, cpu_subtype_t cpuSubType,
                                                           BOOL is64Bit, BOOL swap) {
        (void)slice;
        (void)is64Bit;
        (void)swap;
        DVTArchitecture *architecture = [DVTArchitecture architectureWithCPUType:cpuType subType:cpuSubType];
        NSString *name = architecture.canonicalName;
        if (name == nil) {
            name = [NSString stringWithFormat:@"cpu(%d,%d)", (int)cpuType, (int)cpuSubType];
        }
        [names addObject:name];
    });
    if (!parsed) {
        return nil;
    }
    return names;
}

NSArray<NSString *> *DVTMachOUUIDsForExecutable(NSString *executablePath, NSError **error)
{
    NSData *fileData = DVTReadMachOFile(executablePath, error);
    if (fileData == nil) {
        return nil;
    }

    NSMutableArray<NSString *> *uuids = [NSMutableArray arrayWithCapacity:1];
    BOOL parsed = DVTMachOEnumerateSlices(fileData, error, ^BOOL(NSData *slice, cpu_type_t cpuType,
                                                                 cpu_subtype_t cpuSubType, BOOL *stop, NSError **sliceError) {
        (void)cpuType;
        (void)cpuSubType;
        (void)stop;
        (void)sliceError;
        BOOL is64Bit = NO;
        BOOL swap = NO;
        DVTIsMachMagic(DVTRead32((const uint8_t *)[slice bytes], 0, NO), &is64Bit, &swap);
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            if (DVTRead32(command, offsetof(struct load_command, cmd), swap) != LC_UUID) {
                return;
            }
            if (commandSize < sizeof(struct uuid_command)) {
                return;
            }
            const struct uuid_command *uuidCommand = (const struct uuid_command *)command;
            [uuids addObject:DVTUUIDStringFromBytes(uuidCommand->uuid)];
        });
        return YES;
    });
    if (!parsed) {
        return nil;
    }
    return uuids;
}

NSArray<NSNumber *> *DVTMachOSwiftABIVersion(NSString *executablePath, NSError **error)
{
    NSData *fileData = DVTReadMachOFile(executablePath, error);
    if (fileData == nil) {
        return nil;
    }

    NSMutableArray<NSNumber *> *versions = [NSMutableArray arrayWithCapacity:1];
    BOOL parsed = DVTMachOEnumerateSlices(fileData, error, ^BOOL(NSData *slice, cpu_type_t cpuType,
                                                                 cpu_subtype_t cpuSubType, BOOL *stop, NSError **sliceError) {
        (void)cpuType;
        (void)cpuSubType;
        (void)stop;
        (void)sliceError;
        BOOL is64Bit = NO;
        BOOL swap = NO;
        DVTIsMachMagic(DVTRead32((const uint8_t *)[slice bytes], 0, NO), &is64Bit, &swap);
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            uint32_t commandType = DVTRead32(command, offsetof(struct load_command, cmd), swap);
            /*
             LC_SWIFT_VERSION and `struct swift_version_command` are not in the
             public headers, but the layout is fixed: a load command followed by
             a single uint32_t version field.
             */
            const uint32_t swiftVersionCommandType = 0x2A;
            const uint32_t versionOffset = offsetof(struct load_command, cmdsize) + sizeof(uint32_t);
            if (commandType != swiftVersionCommandType || commandSize < versionOffset + sizeof(uint32_t)) {
                return;
            }
            [versions addObject:@(DVTRead32(command, versionOffset, swap))];
        });
        return YES;
    });
    if (!parsed) {
        return nil;
    }
    return versions;
}

#pragma mark - Public API: platforms

/** Collects the `platform` value of every `LC_BUILD_VERSION`/`LC_VERSION_MIN_*`. */
/** Appends a platform unless that platform is already listed, preserving order. */
static void DVTAddPlatform(NSMutableArray<NSNumber *> *platforms, uint32_t platform)
{
    NSNumber *value = @(platform);
    if (![platforms containsObject:value]) {
        [platforms addObject:value];
    }
}

static void DVTCollectPlatform(NSData *slice, BOOL swap, BOOL is64Bit, NSMutableArray<NSNumber *> *platforms)
{
    DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
        uint32_t commandType = DVTRead32(command, offsetof(struct load_command, cmd), swap);
        if (commandType == LC_BUILD_VERSION) {
            if (commandSize < offsetof(struct build_version_command, minos) + sizeof(uint32_t)) {
                return;
            }
            const struct build_version_command *build = (const struct build_version_command *)command;
            DVTAddPlatform(platforms, (uint32_t)build->platform);
        } else if (commandType == LC_VERSION_MIN_MACOSX || commandType == LC_VERSION_MIN_IPHONEOS ||
                   commandType == LC_VERSION_MIN_WATCHOS || commandType == LC_VERSION_MIN_TVOS) {
            /* The pre-LC_BUILD_VERSION commands only ever describe macOS. */
            DVTAddPlatform(platforms, PLATFORM_MACOS);
        }
    });
}

/**
  Reports a failure the way the platform queries do.

  A file that is not a Mach-O at all is reported as an unsupported format
  rather than as a generic "not a Mach-O", which is the distinction the original
  draws between the platform lookups and the slice-level ones.
 */
static void DVTFillPlatformError(NSError **error, NSError *cause)
{
    if (error == NULL) {
        return;
    }
    if (cause != nil && [cause.domain isEqualToString:DVTMachOErrorDomain] &&
        cause.code == DVTMachOErrorCodeNotMachO) {
        *error = [NSError errorWithDomain:DVTMachOErrorDomain
                                      code:DVTMachOErrorCodeUnsupportedFormat
                                  userInfo:cause.userInfo];
        return;
    }
    *error = cause;
}

NSArray<NSNumber *> *DVTMachOPlatformsForExecutable(NSString *executablePath, NSError **error)
{
    NSData *fileData = DVTReadMachOFile(executablePath, error);
    if (fileData == nil) {
        return nil;
    }

    NSMutableArray<NSNumber *> *platforms = [NSMutableArray arrayWithCapacity:1];
    NSError *sliceError = nil;
    BOOL parsed = DVTForEachSliceInData(fileData, &sliceError, ^(NSData *slice, cpu_type_t cpuType,
                                                                cpu_subtype_t cpuSubType, BOOL is64Bit, BOOL swap) {
        (void)cpuType;
        (void)cpuSubType;
        DVTCollectPlatform(slice, swap, is64Bit, platforms);
    });
    if (!parsed) {
        DVTFillPlatformError(error, sliceError);
        return nil;
    }
    return platforms;
}

NSNumber *DVTMachOHasPlatform(NSString *executablePath, DVTMachOPlatform platform, NSError **error)
{
    NSArray<NSNumber *> *platforms = DVTMachOPlatformsForExecutable(executablePath, error);
    if (platforms == nil) {
        return nil;
    }
    for (NSNumber *candidate in platforms) {
        if (candidate.unsignedIntegerValue == (NSUInteger)platform) {
            return [NSNumber numberWithBool:YES];
        }
    }
    return [NSNumber numberWithBool:NO];
}

DVTMachOPlatform DVTMachOPlatformForExecutable(NSString *executablePath, NSError **error)
{
    NSArray<NSNumber *> *platforms = DVTMachOPlatformsForExecutable(executablePath, error);
    NSUInteger first = platforms.firstObject.unsignedIntegerValue;
    return (DVTMachOPlatform)first;
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

NSNumber *DVTMachOBinaryHasAnyMachineCode(NSString *executablePath, NSError **error)
{
    NSData *fileData = DVTReadMachOFile(executablePath, error);
    if (fileData == nil) {
        return nil;
    }

    __block BOOL hasCode = NO;
    BOOL parsed = DVTMachOEnumerateSlices(fileData, error, ^BOOL(NSData *slice, cpu_type_t cpuType,
                                                                 cpu_subtype_t cpuSubType, BOOL *stop, NSError **sliceError) {
        (void)cpuType;
        (void)cpuSubType;
        (void)stop;
        (void)sliceError;
        BOOL is64Bit = NO;
        BOOL swap = NO;
        DVTIsMachMagic(DVTRead32((const uint8_t *)[slice bytes], 0, NO), &is64Bit, &swap);
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
        return YES;
    });
    if (!parsed) {
        return nil;
    }
    return [NSNumber numberWithBool:hasCode];
}

#pragma mark - Public API: is this file a Mach-O at all

NSNumber *DVTFileAtPathIsMachO(NSString *path, NSError **error)
{
    if (path == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
        }
        return nil;
    }

    /*
     Read four bytes with open/pread rather than through NSData so the failure
     reported is the one the file system actually gave — which is what callers
     use to tell "not a file" from "not a Mach-O".
     */
    int descriptor = open(path.fileSystemRepresentation, O_RDONLY);
    if (descriptor < 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        return nil;
    }

    uint32_t magic = 0;
    ssize_t read = pread(descriptor, &magic, sizeof(magic), 0);
    int readErrno = errno;
    close(descriptor);

    if (read < 0) {
        /*
         A directory opens but cannot be read, and the original reports that as
         a plain "no" rather than an error: a directory is simply not a Mach-O.
         Every other read failure is a real filesystem error worth surfacing.
         */
        if (readErrno == EISDIR) {
            return [NSNumber numberWithBool:NO];
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:readErrno userInfo:nil];
        }
        return nil;
    }
    if (read != (ssize_t)sizeof(magic)) {
        return [NSNumber numberWithBool:NO];
    }

    BOOL is64Bit = NO;
    BOOL swap = NO;
    BOOL isMachO = DVTIsMachMagic(magic, &is64Bit, &swap) || DVTIsFatMagic(magic);
    return [NSNumber numberWithBool:isMachO];
}

#pragma mark - Public API: minimum OS and source versions

/** Expands a packed `x.y.z` version as `LC_BUILD_VERSION` stores it. */
static DVTVersion *DVTVersionFromPacked32(uint32_t packed)
{
    return [DVTVersion versionWithMajorComponent:(packed >> 16) & 0xFFFFu
                                 minorComponent:(packed >> 8) & 0xFFu
                                 updateComponent:packed & 0xFFu];
}

/**
  Expands a 64-bit `LC_SOURCE_VERSION`.

  The load command packs the version into a single 64-bit field, most
  significant byte first, so the components are read back out as bytes: that
  reproduces the original's dotted rendering, including the trailing components
  a short version leaves at zero.
 */
static NSString *DVTSourceVersionString(uint64_t packed)
{
    NSUInteger length = 0;
    while (length < sizeof(packed) && ((packed >> (8 * (sizeof(packed) - 1 - length))) & 0xFFu) != 0) {
        length++;
    }
    if (length == 0) {
        length = 1;
    }

    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < length; index++) {
        if (index != 0) {
            [result appendString:@"."];
        }
        uint8_t component = (uint8_t)((packed >> (8 * (sizeof(packed) - 1 - index))) & 0xFFu);
        [result appendFormat:@"%u", component];
    }
    return result;
}

/** The `LC_VERSION_MIN_*` value of `slice`, or `nil` when it declares none. */
static DVTVersion *DVTSliceMinimumVersion(NSData *slice, BOOL swap, BOOL is64Bit)
{
    (void)is64Bit;
    __block DVTVersion *minimum = nil;
    DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
        uint32_t commandType = DVTRead32(command, offsetof(struct load_command, cmd), swap);
        if (minimum != nil) {
            return;
        }
        if (commandType == LC_BUILD_VERSION) {
            if (commandSize >= offsetof(struct build_version_command, minos) + sizeof(uint32_t)) {
                minimum = DVTVersionFromPacked32(DVTRead32(command, offsetof(struct build_version_command, minos), swap));
            }
        } else {
            uint32_t offset = UINT32_MAX;
            if (commandType == LC_VERSION_MIN_MACOSX && commandSize >= sizeof(struct version_min_command)) {
                offset = offsetof(struct version_min_command, version);
            } else if (commandType == LC_VERSION_MIN_IPHONEOS && commandSize >= sizeof(struct version_min_command)) {
                offset = offsetof(struct version_min_command, version);
            } else if (commandType == LC_VERSION_MIN_TVOS && commandSize >= sizeof(struct version_min_command)) {
                offset = offsetof(struct version_min_command, version);
            } else if (commandType == LC_VERSION_MIN_WATCHOS && commandSize >= sizeof(struct version_min_command)) {
                offset = offsetof(struct version_min_command, version);
            }
            if (offset != UINT32_MAX) {
                minimum = DVTVersionFromPacked32(DVTRead32(command, offset, swap));
            }
        }
    });
    return minimum;
}

DVTVersion *DVTMachOOSVersionMinForArch(NSData *fileData,
                                        DVTArchitecture *architecture,
                                        DVTMachOPlatform platform,
                                        NSError **error)
{
    (void)platform;
    if (fileData == nil || architecture == nil) {
        return nil;
    }

    __block DVTVersion *minimum = nil;
    __block BOOL found = NO;
    BOOL parsed = DVTMachOEnumerateSlices(fileData, error, ^BOOL(NSData *slice, cpu_type_t cpuType,
                                                                 cpu_subtype_t cpuSubType, BOOL *stop, NSError **sliceError) {
        (void)stop;
        (void)sliceError;
        if (![architecture matchesCPUType:cpuType andSubType:cpuSubType]) {
            return YES;
        }
        found = YES;
        BOOL is64Bit = NO;
        BOOL swap = NO;
        DVTIsMachMagic(DVTRead32((const uint8_t *)[slice bytes], 0, NO), &is64Bit, &swap);
        minimum = DVTSliceMinimumVersion(slice, swap, is64Bit);
        return YES;
    });
    if (!parsed || !found) {
        return nil;
    }
    return minimum;
}

NSDictionary<DVTArchitecture *, DVTVersion *> *DVTMachOOSVersionMinForPlatform(NSString *executablePath,
                                                                               DVTMachOPlatform platform,
                                                                               NSError **error)
{
    NSData *fileData = DVTReadMachOFile(executablePath, error);
    if (fileData == nil) {
        return nil;
    }

    NSMutableDictionary<DVTArchitecture *, DVTVersion *> *result = [NSMutableDictionary dictionary];
    BOOL parsed = DVTForEachSliceInData(fileData, error, ^(NSData *slice, cpu_type_t cpuType, cpu_subtype_t cpuSubType,
                                                           BOOL is64Bit, BOOL swap) {
        DVTVersion *minimum = DVTSliceMinimumVersion(slice, swap, is64Bit);
        if (minimum == nil) {
            return;
        }
        DVTArchitecture *architecture = [DVTArchitecture architectureWithCPUType:cpuType subType:cpuSubType];
        if (architecture != nil) {
            result[architecture] = minimum;
        }
    });
    if (!parsed) {
        return nil;
    }
    if (result.count == 0) {
        /* No slice declared a minimum version, which is a failure, not an empty answer. */
        DVTFillError(error, DVTMachOErrorCodeTruncated, @"no LC_BUILD_VERSION or LC_VERSION_MIN_* found");
        return nil;
    }
    return result;
}

NSString *DVTMachOSourceVersionForArch(NSData *fileData, DVTArchitecture *architecture, NSError **error)
{
    if (fileData == nil || architecture == nil) {
        return nil;
    }

    __block NSString *sourceVersion = nil;
    __block BOOL found = NO;
    BOOL parsed = DVTMachOEnumerateSlices(fileData, error, ^BOOL(NSData *slice, cpu_type_t cpuType,
                                                                 cpu_subtype_t cpuSubType, BOOL *stop, NSError **sliceError) {
        (void)stop;
        (void)sliceError;
        if (![architecture matchesCPUType:cpuType andSubType:cpuSubType]) {
            return YES;
        }
        found = YES;
        BOOL is64Bit = NO;
        BOOL swap = NO;
        DVTIsMachMagic(DVTRead32((const uint8_t *)[slice bytes], 0, NO), &is64Bit, &swap);
        DVTForEachLoadCommand(slice, swap, is64Bit, ^(const struct load_command *command, uint32_t commandSize) {
            uint32_t commandType = DVTRead32(command, offsetof(struct load_command, cmd), swap);
            if (commandType != LC_SOURCE_VERSION || commandSize < sizeof(struct source_version_command)) {
                return;
            }
            uint64_t packed = DVTRead64(command, offsetof(struct source_version_command, version), swap);
            sourceVersion = DVTSourceVersionString(packed);
        });
        return YES;
    });
    if (!parsed || !found) {
        return nil;
    }
    return sourceVersion;
}

void DVTSetupWeakPropertyKVOAssertions(void)
{
    /* The original compiles this away entirely; kept for source compatibility. */
}
