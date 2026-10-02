//
//  DVTGeometryAdditions.h
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
#import <CoreGraphics/CoreGraphics.h>
#import "DVTDefines.h"

#ifndef DVT_GEOMETRY_ADDITIONS_H
#define DVT_GEOMETRY_ADDITIONS_H

NS_ASSUME_NONNULL_BEGIN

/**
 The straight-line distance between two points.

 @param point      The first point.
 @param otherPoint The second point.
 @return The distance, which is never negative.
 */
DVT_EXTERN CGFloat DVTDistanceBetweenPoints(CGPoint point, CGPoint otherPoint);

/**
 Returns the rectangle resulting from insetting `rect` by `insets`.

 This is deliberately *not* `CGRectInset`, and two of its behaviours were
 confirmed against Apple's binary rather than inferred:

 1. The vertical inset is read from the wrong field. The leading edge moves by
    `insets.size.width`, and the trailing edge by `insets.size.width` plus
    `insets.size.height`, so the y axis is driven by how *wide* `insets` is
    rather than by its origin.y. Passing the usual
    `CGRectMake(x, y, w, h)` margin therefore produces a y inset of `w`.
 2. An over-inset collapses instead of inverting. Where the width or height
    would come out at zero or below, the size becomes exactly zero and the
    origin moves to the midpoint of the intended span. The result is always
    non-degenerate and never has a negative dimension.

 @param rect   The rectangle to inset.
 @param insets The insets to apply, whose origin and size are both read.
 @return The inset rectangle, with a size no smaller than `CGRectZero`.
 */
DVT_EXTERN CGRect DVTRectByInsettingRect(CGRect rect, CGRect insets);

/**
 Returns `rect` with its width replaced, leaving its origin and height alone.

 @param rect  The rectangle to modify.
 @param width The replacement width.
 @return The modified rectangle.
 */
DVT_EXTERN CGRect DVTRectBySettingWidth(CGRect rect, CGFloat width);

/**
 Returns `rect` with its height replaced, leaving its origin and width alone.

 @param rect    The rectangle to modify.
 @param height  The replacement height.
 @return The modified rectangle.
 */
DVT_EXTERN CGRect DVTRectBySettingHeight(CGRect rect, CGFloat height);

/**
 Returns `rect` with its height replaced while its maximum Y edge stays put, so
 the rectangle grows or shrinks downwards from a fixed baseline.

 @param rect    The rectangle to modify.
 @param height  The replacement height.
 @return The modified rectangle, whose `maxY` equals the original's.
 */
DVT_EXTERN CGRect DVTRectBySettingHeightAndPinningMaxY(CGRect rect, CGFloat height);

/**
 Centres `size` in `rect`, scaling it by its own aspect ratio only if it does
 not already fit.

 If `size` fits inside `rect` on *both* axes it is left at its original size and
 merely centred. Otherwise it is scaled down until it fits, exactly as
 -DVTRectForScalingSizeUpOrDownIntoRect would. So this scales up only via
 -DVTRectForScalingSizeToFillRect, never on its own.

 @param size The size to scale.
 @param rect The rectangle to scale into.
 @return The scaled, centred rectangle.
 */
DVT_EXTERN CGRect DVTRectForScalingSizeIntoRect(CGSize size, CGRect rect);

/**
 Always scales `size` by its aspect ratio so that it *covers* `rect`, then
 centres the result, which therefore overflows `rect` on one axis unless the two
 aspect ratios happen to match. Unlike -DVTRectForScalingSizeIntoRect, a size
 that already fits is scaled up rather than left alone.

 @param size The size to scale.
 @param rect The rectangle to fill.
 @return The scaled, centred rectangle.
 */
DVT_EXTERN CGRect DVTRectForScalingSizeToFillRect(CGSize size, CGRect rect);

/**
 Always scales `size` by its aspect ratio so that it fits *inside* `rect`, then
 centres the result. Scales up as well as down, so this is the unconditional
 form of -DVTRectForScalingSizeIntoRect's scaling branch. Contrast with
 -DVTRectForScalingSizeToFillRect, which scales to cover instead; the two differ
 for every input whose aspect ratio is not exactly the rect's.

 @param size The size to scale.
 @param rect The rectangle to fill.
 @return The scaled, centred rectangle.
 */
DVT_EXTERN CGRect DVTRectForScalingSizeUpOrDownIntoRect(CGSize size, CGRect rect);

/**
 Returns the per-edge distances that would move `rect`'s edges onto
 `container`'s edges.

 The result crosses the axes: the x deltas become origin.x and origin.y, and the
 y deltas become the size. This reads like a mistake, and probably is one, but
 it is what Apple's implementation does and callers are calibrated to it.

 @param rect      The rectangle being measured.
 @param container The rectangle it is measured against.
 @return A rectangle whose fields hold the four edge deltas.
 */
DVT_EXTERN CGRect DVTInsetFromRectToRect(CGRect rect, CGRect container);

/**
 Returns `rect` translated, unchanged in size, so that it lies wholly inside
 `container` where that is possible.

 The origin is first pushed to at least the container's origin, then clamped
 back if that pushed the far edge out; the size is never changed. Edge tests go
 through CoreGraphics' *geometric* min/max, so a rect with a negative width is
 compared by the edge it actually spans. A rect larger than `container` cannot be
 made to fit and ends up spilling out of it.

 @param rect      The rectangle to place.
 @param container The rectangle to place it inside.
 @return The translated rectangle.
 */
DVT_EXTERN CGRect DVTPlaceRectInsideRect(CGRect rect, CGRect container);

NS_ASSUME_NONNULL_END

#endif /* DVT_GEOMETRY_ADDITIONS_H */