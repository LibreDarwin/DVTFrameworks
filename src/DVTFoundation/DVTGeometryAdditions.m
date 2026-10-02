//
//  DVTGeometryAdditions.m
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

#import "DVTGeometryAdditions.h"

/* CoreGraphics' CGRectGetMinX and friends are real exported functions, not
   inline arithmetic, and Apple calls them directly. They are *geometric*: for a
   rect built with a negative width the "min" X is the origin shifted left by the
   width, not the origin. Reproduced here rather than linked, because those
   symbols are not exported by the SDK's CoreGraphics on all configurations and
   these functions are hot enough to be worth keeping branch-predictable.
   Verified against Apple's binary, including the zero-size cases. */
static inline CGFloat DVTRectMinX(CGRect rect)
{
    return rect.size.width < 0.0 ? rect.origin.x + rect.size.width : rect.origin.x;
}

static inline CGFloat DVTRectMaxX(CGRect rect)
{
    return rect.size.width < 0.0 ? rect.origin.x : rect.origin.x + rect.size.width;
}

static inline CGFloat DVTRectMinY(CGRect rect)
{
    return rect.size.height < 0.0 ? rect.origin.y + rect.size.height : rect.origin.y;
}

static inline CGFloat DVTRectMaxY(CGRect rect)
{
    return rect.size.height < 0.0 ? rect.origin.y : rect.origin.y + rect.size.height;
}

/* An arm64 fcmp's "less than" condition is N != V, which is *also* satisfied
   when the comparison is unordered. That matters only in UpOrDownIntoRect
   below, which branches on "less than"; the other two branch on "greater than
   or equal", and C's >= already matches arm64's ge (both are false when
   unordered). Spelling that one as !(a >= b) reproduces it; (a < b) would not. */
static inline BOOL DVTAspectIsLessOrUnordered(CGFloat a, CGFloat b)
{
    return !(a >= b);
}

static inline CGRect DVTCentered(CGRect rect, CGFloat width, CGFloat height)
{
    return CGRectMake(rect.origin.x + (rect.size.width - width) * 0.5,
                      rect.origin.y + (rect.size.height - height) * 0.5,
                      width,
                      height);
}

/* The three scaling entry points are near-clones that each pick their two
   branches differently, so they are kept separate rather than merged. Each
   comment records the branch its binary takes and what that produces. */

/* ge -> {rect.width, rect.width/aspect}; less -> {rect.height*aspect, rect.height} */
static inline CGRect DVTScaleIntoRect(CGSize size, CGRect rect)
{
    CGFloat aspect = size.width / size.height;
    CGFloat width;
    CGFloat height;

    if (aspect >= rect.size.width / rect.size.height) {
        width = rect.size.width;
        height = rect.size.width / aspect;
    } else {
        width = rect.size.height * aspect;
        height = rect.size.height;
    }

    return DVTCentered(rect, width, height);
}

/* ge -> {rect.height*aspect, rect.height}; less -> {rect.width, rect.width/aspect} */
static inline CGRect DVTScaleToFillRect(CGSize size, CGRect rect)
{
    CGFloat aspect = size.width / size.height;
    CGFloat width;
    CGFloat height;

    if (aspect >= rect.size.width / rect.size.height) {
        width = rect.size.height * aspect;
        height = rect.size.height;
    } else {
        width = rect.size.width;
        height = rect.size.width / aspect;
    }

    return DVTCentered(rect, width, height);
}

/* less -> {rect.height*aspect, rect.height}; else -> {rect.width, rect.width/aspect}.
   Identical to DVTScaleToFillRect except when the aspect comparison is
   unordered, where this one takes the "less" branch and that one does not. */
static inline CGRect DVTScaleUpOrDown(CGSize size, CGRect rect)
{
    CGFloat aspect = size.width / size.height;
    CGFloat width;
    CGFloat height;

    if (DVTAspectIsLessOrUnordered(aspect, rect.size.width / rect.size.height)) {
        width = rect.size.height * aspect;
        height = rect.size.height;
    } else {
        width = rect.size.width;
        height = rect.size.width / aspect;
    }

    return DVTCentered(rect, width, height);
}

CGFloat DVTDistanceBetweenPoints(CGPoint point, CGPoint otherPoint)
{
    CGFloat dx = point.x - otherPoint.x;
    CGFloat dy = point.y - otherPoint.y;
    return sqrt(dx * dx + dy * dy);
}

CGRect DVTRectByInsettingRect(CGRect rect, CGRect insets)
{
    /* The y axis reads insets' *size* rather than its origin, which is what the
       binary does. Verified against Apple; see the header. */
    CGFloat x = rect.origin.x + insets.origin.x;
    CGFloat y = rect.origin.y + insets.size.width;
    CGFloat width = rect.size.width - insets.origin.x - insets.origin.y;
    CGFloat height = rect.size.height - insets.size.width - insets.size.height;

    /* An over-inset collapses to a zero-size rect centred on the span it would
       have occupied, rather than producing a negative dimension. The compare is
       "greater than" (fcsel .. hi), so this also triggers on NaN. */
    if (!(width > 0.0)) {
        x += width / 2.0;
        width = 0.0;
    }
    if (!(height > 0.0)) {
        y += height / 2.0;
        height = 0.0;
    }

    return CGRectMake(x, y, width, height);
}

CGRect DVTRectBySettingWidth(CGRect rect, CGFloat width)
{
    rect.size.width = width;
    return rect;
}

CGRect DVTRectBySettingHeight(CGRect rect, CGFloat height)
{
    rect.size.height = height;
    return rect;
}

CGRect DVTRectBySettingHeightAndPinningMaxY(CGRect rect, CGFloat height)
{
    rect.origin.y += rect.size.height - height;
    rect.size.height = height;
    return rect;
}

CGRect DVTRectForScalingSizeIntoRect(CGSize size, CGRect rect)
{
    /* Skip scaling only when the size fits on *both* axes; the binary tests this
       as a pair of "less than or equal" compares, so an overflow on either axis
       is what triggers the scale. */
    BOOL overflows = (size.width > rect.size.width) || (size.height > rect.size.height);
    if (overflows) {
        return DVTScaleIntoRect(size, rect);
    }

    return CGRectMake(rect.origin.x + (rect.size.width - size.width) / 2.0,
                      rect.origin.y + (rect.size.height - size.height) / 2.0,
                      size.width,
                      size.height);
}

CGRect DVTRectForScalingSizeToFillRect(CGSize size, CGRect rect)
{
    return DVTScaleToFillRect(size, rect);
}

CGRect DVTRectForScalingSizeUpOrDownIntoRect(CGSize size, CGRect rect)
{
    return DVTScaleUpOrDown(size, rect);
}

CGRect DVTInsetFromRectToRect(CGRect rect, CGRect container)
{
    /* The two x deltas land in the origin and the two y deltas in the size.
       Crossed, and reproduced as found; see the header. */
    return CGRectMake(DVTRectMinX(container) - DVTRectMinX(rect),
                      DVTRectMaxX(rect) - DVTRectMaxX(container),
                      DVTRectMinY(container) - DVTRectMinY(rect),
                      DVTRectMaxY(rect) - DVTRectMaxY(container));
}

CGRect DVTPlaceRectInsideRect(CGRect rect, CGRect container)
{
    CGFloat width = rect.size.width;
    CGFloat height = rect.size.height;
    CGFloat x = rect.origin.x;
    CGFloat y = rect.origin.y;

    /* Push the leading edges in first, against the *geometric* min... */
    if (DVTAspectIsLessOrUnordered(DVTRectMinX(rect), DVTRectMinX(container))) {
        x = DVTRectMinX(container);
    }
    if (DVTAspectIsLessOrUnordered(DVTRectMinY(rect), DVTRectMinY(container))) {
        y = DVTRectMinY(container);
    }

    /* ...then pull them back if that pushed the trailing edges out. Note this
       re-measures with the already-adjusted rect, and the size is never altered,
       so a rect larger than the container still ends up spilling out. */
    CGRect moved = CGRectMake(x, y, width, height);
    if (DVTRectMaxX(moved) > DVTRectMaxX(container)) {
        x = DVTRectMaxX(container) - width;
    }
    moved = CGRectMake(x, y, width, height);
    if (DVTRectMaxY(moved) > DVTRectMaxY(container)) {
        y = DVTRectMaxY(container) - height;
    }

    return CGRectMake(x, y, width, height);
}