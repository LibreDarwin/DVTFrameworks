//
//  DVTDocumentLocationInternal.h
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

#ifndef DVT_DOCUMENT_LOCATION_INTERNAL_H
#define DVT_DOCUMENT_LOCATION_INTERNAL_H

#import "DVTDocumentLocation.h"

NS_ASSUME_NONNULL_BEGIN

/**
  The error domain and generic code the document-location family reports.

 Apple reports validation failures in `com.apple.DVTFoundation` with code `-1`,
 which is deliberately distinct from this framework's own
 `DVTFoundationErrorDomain`.
 */
DVT_HIDDEN_EXTERN NSString *const DVTLocationErrorDomain;
DVT_HIDDEN_EXTERN NSInteger const DVTLocationGenericErrorCode;

/**
  Parses the `key=value&key=value` fragment a persistable URL carries.

  Returns an empty dictionary for a nil or empty fragment. Values are taken
  verbatim, without percent-decoding, because a fragment written by
  -persistableURLRepresentationAndDecodableClassName:error: is already literal.
  */
DVT_HIDDEN_EXTERN NSDictionary<NSString *, NSString *> *DVTPersistentParametersFromFragment(NSString *fragment);

/**
  The keys a persistable fragment spells its fields with.

  Both directions of the representation have to agree on these, so they live here
  rather than in either implementation.
 */
DVT_HIDDEN_EXTERN NSString *const DVTPersistentTimestampKey;
DVT_HIDDEN_EXTERN NSString *const DVTPersistentStartingColumnNumberKey;
DVT_HIDDEN_EXTERN NSString *const DVTPersistentEndingColumnNumberKey;
DVT_HIDDEN_EXTERN NSString *const DVTPersistentStartingLineNumberKey;
DVT_HIDDEN_EXTERN NSString *const DVTPersistentEndingLineNumberKey;
DVT_HIDDEN_EXTERN NSString *const DVTPersistentCharacterRangeLocationKey;
DVT_HIDDEN_EXTERN NSString *const DVTPersistentCharacterRangeLengthKey;
DVT_HIDDEN_EXTERN NSString *const DVTPersistentLocationEncodingKey;

NS_ASSUME_NONNULL_END

#endif /* DVT_DOCUMENT_LOCATION_INTERNAL_H */
