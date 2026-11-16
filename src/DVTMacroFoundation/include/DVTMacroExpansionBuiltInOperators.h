/* Copyright (C) 2026, LibreDarwin
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Internal declarations for the built-in macro expansion operator classes.
 * Apple ships one public header per class; this port groups them because they
 * share a single implementation file and are only referenced by the parser.
 */

#ifndef DVTMACROFOUNDATION_DVTMACROEXPANSIONBUILTINOPERATORS_H
#define DVTMACROFOUNDATION_DVTMACROEXPANSIONBUILTINOPERATORS_H

#import <Foundation/Foundation.h>

#import "DVTMacroExpansionReplacementOperator.h"
#import "DVTMacroExpansionRetrievalOperator.h"

@interface DVTMacroExpansionRetrievalOperator_quote : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_upper : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_lower : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_identifier : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_rfc1034identifier : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_c99extidentifier : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_dir : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_file : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_base : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_suffix : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_standardizepath : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionRetrievalOperator_xml : DVTMacroExpansionRetrievalOperator
@end

@interface DVTMacroExpansionReplacementOperator_dir : DVTMacroExpansionReplacementOperator
@end

@interface DVTMacroExpansionReplacementOperator_file : DVTMacroExpansionReplacementOperator
@end

@interface DVTMacroExpansionReplacementOperator_base : DVTMacroExpansionReplacementOperator
@end

@interface DVTMacroExpansionReplacementOperator_suffix : DVTMacroExpansionReplacementOperator
@end

@interface DVTMacroExpansionReplacementOperator_relativeto : DVTMacroExpansionReplacementOperator
@end

@interface DVTMacroExpansionReplacementOperator_default : DVTMacroExpansionReplacementOperator
@end

#endif	/* DVTMACROFOUNDATION_DVTMACROEXPANSIONBUILTINOPERATORS_H */
