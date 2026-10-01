//
//  DVTDefines.h
//  DVTFrameworks
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

#ifndef DVT_DEFINES_H
#define DVT_DEFINES_H

#include <Foundation/NSObjCRuntime.h>

#ifdef __cplusplus
#define DVT_EXTERN extern "C" __attribute__((visibility("default")))
#else
#define DVT_EXTERN extern __attribute__((visibility("default")))
#endif

#define DVT_VISIBILITY __attribute__((visibility("default")))

#endif /* DVT_DEFINES_H */
