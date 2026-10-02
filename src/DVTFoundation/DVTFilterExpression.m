//
//  DVTFilterExpression.m
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

#import "DVTFilterExpression.h"
#import "DVTAssertions.h"

/*
 All three functions here assert on an out-of-range argument and then return a
 table entry anyway. Apple does the same: the assert path materialises a string
 on its way out. In a default environment the assert aborts, so the returned
 value is only reachable when the assertion handler has been made non-fatal, and
 the tables are laid out so that value is always a valid string.

 The bounds tests are unsigned comparisons, matching Apple, so a negative value
 asserts rather than indexing off the front of the table.
 */

static NSString *const DVTStringsForFilterCompoundExpressionOperator[2] = {
    @"AND",
    @"OR",
};

NSString *DVTStringForFilterExpressionOperator(DVTFilterCompoundExpressionOperator op)
{
    if ((NSUInteger)op >= 2) {
        DVTAssert(NO, @"Filter expression operator out of range", nil, @"%ld", (long)op);
    }
    return DVTStringsForFilterCompoundExpressionOperator[(NSUInteger)op < 2 ? (NSUInteger)op : 0];
}

static NSString *const DVTStringsForNumericalFilterComparisonType[3] = {
    @"=",
    @"<",
    @">",
};

NSString *DVTNumericalFilterComparisonTypeDisplayString(DVTNumericalFilterComparisonType type)
{
    if ((NSUInteger)type >= 3) {
        DVTAssert(NO, @"Numerical filter comparison type out of range", nil, @"%ld", (long)type);
    }
    return DVTStringsForNumericalFilterComparisonType[(NSUInteger)type < 3 ? (NSUInteger)type : 0];
}

static NSString *const DVTStringsForTextFilterComparisonType[6] = {
    @"Equals",
    @"Contains",
    @"Does Not Contain",
    @"Begins With",
    @"Ends With",
    @"Like",
};

NSString *DVTTextFilterComparisonTypeDisplayString(DVTTextFilterComparisonType type)
{
    if ((NSUInteger)type >= 6) {
        DVTAssert(NO, @"Text filter comparison type out of range", nil, @"%ld", (long)type);
    }
    return DVTStringsForTextFilterComparisonType[(NSUInteger)type < 6 ? (NSUInteger)type : 0];
}