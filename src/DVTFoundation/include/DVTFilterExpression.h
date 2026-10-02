//
//  DVTFilterExpression.h
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

#ifndef DVT_FILTER_EXPRESSION_H
#define DVT_FILTER_EXPRESSION_H

#import <Foundation/Foundation.h>
#import "DVTDefines.h"

NS_ASSUME_NONNULL_BEGIN

/** How a compound filter expression joins its sub-expressions. */
typedef NS_ENUM(NSInteger, DVTFilterCompoundExpressionOperator) {
    DVTFilterCompoundExpressionOperatorAnd = 0,
    DVTFilterCompoundExpressionOperatorOr = 1,
};

/**
 How a numeric filter field is compared against its value.

 These render as single characters, and only these three -- there is no
 greater-than-or-equal or less-than-or-equal variant.
 */
typedef NS_ENUM(NSInteger, DVTNumericalFilterComparisonType) {
    DVTNumericalFilterComparisonTypeEqualTo = 0,
    DVTNumericalFilterComparisonTypeLessThan = 1,
    DVTNumericalFilterComparisonTypeGreaterThan = 2,
};

/** How a textual filter field is compared against its value. */
typedef NS_ENUM(NSInteger, DVTTextFilterComparisonType) {
    DVTTextFilterComparisonTypeEquals = 0,
    DVTTextFilterComparisonTypeContains = 1,
    DVTTextFilterComparisonTypeDoesNotContain = 2,
    DVTTextFilterComparisonTypeBeginsWith = 3,
    DVTTextFilterComparisonTypeEndsWith = 4,
    DVTTextFilterComparisonTypeLike = 5,
};

/**
 The display string for a compound expression operator.

 Unlike -DVTStringFromFindMatchStyle this *asserts* on an out-of-range value
 rather than substituting a fallback; the returned string is only meaningful if
 the assertion was configured not to abort.
 */
DVT_EXTERN NSString *DVTStringForFilterExpressionOperator(DVTFilterCompoundExpressionOperator op);

/** The single-character display string for a numeric comparison type. Asserts when out of range. */
DVT_EXTERN NSString *DVTNumericalFilterComparisonTypeDisplayString(DVTNumericalFilterComparisonType type);

/** The display string for a textual comparison type. Asserts when out of range. */
DVT_EXTERN NSString *DVTTextFilterComparisonTypeDisplayString(DVTTextFilterComparisonType type);

NS_ASSUME_NONNULL_END

#endif /* DVT_FILTER_EXPRESSION_H */