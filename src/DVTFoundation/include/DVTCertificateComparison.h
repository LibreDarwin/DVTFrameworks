//
//  DVTCertificateComparison.h
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

#ifndef DVT_CERTIFICATE_COMPARISON_H
#define DVT_CERTIFICATE_COMPARISON_H

#import <Foundation/Foundation.h>
#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/**
  The seven code-signing leaf-certificate OIDs that have a defined kind, paired
  with the rank that kind sorts at:

      1.2.840.113635.100.6.1.2   -> 0    iOS Development
      1.2.840.113635.100.6.1.4   -> 1    iOS Distribution
      1.2.840.113635.100.6.1.12  -> 2    Mac Development
      1.2.840.113635.100.6.1.7   -> 3    Mac App Distribution
      1.2.840.113635.100.6.1.8   -> 4    Mac Installer Distribution
      1.2.840.113635.100.6.1.13  -> 5    Developer ID Application
      1.2.840.113635.100.6.1.14  -> 6

  The OIDs are the `1.2.840.113635.100.6.1` family Apple stamps into a signing
  certificate to say what it is for. The rank is the index into the kind
  ordering, which is *not* the OID's numeric order: `...6.1.12` sorts before
  `...6.1.7`.

  This is a private lazily-built table. It is deliberately not exported, because
  Apple's binary does not export it either; only the two comparison functions
  below leave the framework.
 */

/**
  Three-way comparison of two certificate kinds, given as the OID string above.

  Both operands are looked up in `DVTCertificateKindRanks` and the *ranks* are
  compared, so the result follows the kind ordering rather than the OID text.
  That is the only reason this is not just `[lhs compare:rhs]`: it puts the
  recognised kinds into a single order so that a certificate's purpose can be
  compared without the caller knowing the OID numbering.

  Behaviour for the cases the table does not settle:

  - Identical operands compare `NSOrderedSame`, including two `nil`s.
  - If exactly one operand is `nil`, the answer is decided by *pointer* order,
    so `nil` sorts before anything (`-1`) and after nothing (`1`).
  - If both operands are unknown to the table, the answer falls through to
    `[lhs compare:rhs]` on the operands themselves. A pair of unknown kinds
    therefore orders by OID text, and two different objects that compare equal
    still give `NSOrderedSame`.
  - If exactly one operand is known, the answer is decided by pointer order
    between the looked-up rank and `nil`, so a known kind always sorts *after* an
    unknown one, regardless of which side it is on. This is a comparison of
    object addresses, not of anything meaningful, and it is the reason the
    fallback cannot be reproduced by simply comparing the two ranks.

  `-compare:` and the `nil` handling are not guarded, so an operand that raises
  propagates the exception.
 */
DVT_EXTERN NSComparisonResult DVTCompareCertificateKinds(id _Nullable lhs, id _Nullable rhs);

/**
  Three-way comparison of two *sets* of certificate kinds, given as arrays of OID
  strings.

  Both arrays are sorted with `dvt_sortedArrayUsingComparator:` and the first
  element of each sorted result is compared with `DVTCompareCertificateKinds`, so
  this orders the sets by their lowest-ranked member.

  This function cannot succeed. `dvt_sortedArrayUsingComparator:` is referenced
  but not implemented, in Apple's framework and in this one, so every call raises
  `NSInvalidArgumentException` from `- unrecognized selector sent to instance`.
  The exception surfaces on the first array that is sent the message; a `nil`
  array is not an escape from it, because messaging `nil` returns `nil` and the
  *other* array still raises. The body is reproduced faithfully anyway, since the
  point of this project is to match what the shipped binary does rather than to
  repair it.
 */
DVT_EXTERN NSComparisonResult DVTCompareCertificateKindSets(NSArray *_Nullable lhs, NSArray *_Nullable rhs);

NS_ASSUME_NONNULL_END

#endif /* DVT_CERTIFICATE_COMPARISON_H */
