# LibreDarwin DVTFrameworks

An open source reimplementation of Apple's DVTFrameworks package, the
lower-level sub-frameworks that power Xcode and Apple's command-line developer
utilities. `DVTFrameworks` is used by `IDETools`; see `Sources/IDETools` for
that side of the picture.

The goal is byte-identical output where that is achievable, and function
compatibility everywhere else. What is recovered from Apple's binary and what
is inferred is called out explicitly in [Fidelity notes](#fidelity-notes).

## Frameworks

The package is 44 frameworks, matching the `DVT*.framework` bundles in Apple's
`Xcode.app/Contents/SharedFrameworks` one for one. Each has a directory under
`src/` so the layout is already in place; only the ones marked implemented have
sources.

| Framework | Status |
| --- | --- |
| `DVTFoundation` | Implemented. The core, non-UI layer. |
| `DVTAnalytics` | Not started |
| `DVTAnalyticsClient` | Not started |
| `DVTAnalyticsKit` | Not started |
| `DVTAnalyticsMetrics` | Not started |
| `DVTAnalyticsMetricsClient` | Not started |
| `DVTAppStoreConnect` | Not started |
| `DVTCocoaAdditionsKit` | Not started |
| `DVTCoreDeviceCore` | Not started |
| `DVTCoreGlyphs` | Not started |
| `DVTCrashLogFoundation` | Not started |
| `DVTDeviceFoundation` | Not started |
| `DVTDeviceKit` | Not started |
| `DVTDeviceProvisioning` | Not started |
| `DVTDocumentation` | Not started |
| `DVTExplorableKit` | Not started |
| `DVTFeedbackReporting` | Not started |
| `DVTIconKit` | Not started |
| `DVTInstrumentsAnalysisCore` | Not started |
| `DVTInstrumentsFoundation` | Not started |
| `DVTInstrumentsUtilities` | Not started |
| `DVTITunesSoftware` | Not started |
| `DVTITunesSoftwareServiceFoundation` | Not started |
| `DVTKeychain` | Not started |
| `DVTKeychainService` | Not started |
| `DVTKeychainUtilities` | Not started |
| `DVTKit` | Not started |
| `DVTLibraryKit` | Not started |
| `DVTMacroFoundation` | Not started |
| `DVTMarkup` | Not started |
| `DVTPlaygroundCommunication` | Not started |
| `DVTPlaygroundStubMacServices` | Not started |
| `DVTPortal` | Not started |
| `DVTProducts` | Not started |
| `DVTProductsUI` | Not started |
| `DVTServices` | Not started |
| `DVTSmartSearch` | Not started |
| `DVTSourceControl` | Not started |
| `DVTSourceEditor` | Not started |
| `DVTStructuredLayoutKit` | Not started |
| `DVTSystemPrerequisites` | Not started |
| `DVTSystemPrerequisitesUI` | Not started |
| `DVTUserInterfaceKit` | Not started |
| `DVTViewControllerKit` | Not started |

`DVTFoundation` is the only one with sources so far; the rest carry a
`.gitkeep` so the empty directory is preserved by git, and the `Makefile`
skips any directory without a `.m` file. Everything in this document below
applies to `DVTFoundation` unless it says otherwise.

Note that the five `DVTAnalytics*` frameworks are distinct bundles:
`DVTAnalytics`, `DVTAnalyticsClient`, `DVTAnalyticsKit`,
`DVTAnalyticsMetrics`, and `DVTAnalyticsMetricsClient`. They are separate
libraries in Apple's tree, not variants of one.

## Layout

Each framework is self-contained under `src/`, and carries its own public
headers alongside its implementations.

| Path | Contents |
| --- | --- |
| `include/` | Headers shared by every framework. Currently only `DVTDefines.h`, which defines `DVT_EXTERN` and `DVT_VISIBILITY`. |
| `src/<Framework>/` | That framework's implementations, one file per subsystem. A directory with only a `.gitkeep` is a placeholder. |
| `src/<Framework>/include/` | That framework's public headers. `DVTFoundation.h` is the `DVTFoundation` umbrella. |
| `tests/` | Test runners, currently `dvt_tests.m` and the Swift overlay test. |
| `Makefile` | Framework, test, and install rules. |

A header belongs in `include/` only if more than one framework needs it. Putting
a framework's headers in the shared directory would make them look like part of
every framework's public surface, so each framework's own directory is the
default.

## Building

```sh
make            # build every framework that has sources
make test       # build and run the test suite
make clean      # remove build/
make install    # copy the frameworks into $(DESTDIR)/Library/Frameworks
```

Frameworks are discovered from `src/`, so adding a framework needs only its
directory and sources. `make` builds each one into its own bundle, with the
install name, `Info.plist` identity, and header set derived from the directory
name.

The build defaults to Apple's SDK. The reduced Internal SDK
(`macosx26.5.internal`, 11 frameworks) under the `DEVELOPER_DIR` tree also
builds and passes the suite, so either can be selected:

```sh
make test
make SDK_PATH="$(DEVELOPER_DIR)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.Internal.sdk" test
```

The two SDKs differ in ways worth knowing: the Internal SDK ships the complete
legacy Foundation header set, including `NSObject.h`, whereas the public SDK
has 297 frameworks but leaves the core Foundation declarations to `.apinotes`
and the module map.

The framework links only `Foundation` and `CoreFoundation`, installs as
`@rpath/DVTFoundation.framework/Versions/A/DVTFoundation`, and carries
compatibility and current version `1.0.0` to match Apple.

## What is implemented

### Environment snapshots

`DVTPerformWithEnvironmentSnapshot` runs a block against a process-wide
`DVTEnvironmentSnapshot` — the immutable copy of the environment the framework
caches for the lifetime of the process, so that a long-running IDE does not
observe half-applied mutations. Four modes decide whether a missing snapshot is
created, reused, or treated as a no-op.

Alongside it: `DVTSetEnvironmentVariable`, `DVTRemoveEnvironmentVariable`,
`DVTResetEnvironmentSnapshot`, `DVTStringIsTrue`, and an
`NSProcessInfo (DVTCachedEnvioronmentCompatibility)` category (the misspelling
matches Apple's) that reads and writes the snapshot.

### Mach-O inspection

`DVTMachO*` reads an executable on disk without loading it. It handles thin and
fat files, 32- and 64-bit slices, and byte-swapped files as produced on
big-endian hosts:

- file types, architectures, UUIDs, and platforms
- load-command enumeration, bounded by the `sizeofcmds` region the header
  actually declares
- `@rpath` entries, linked libraries, weak links, and re-exported libraries
- `DVTFileAtPathIsMachO`, which reports whether a path holds a Mach-O at all
  without reading the whole file
- `DVTMachOHasAnyMachineCode`, i.e. whether a binary carries an executable
  `__TEXT` segment
- `DVTMachOSourceVersionForArch` and `DVTMachOOSVersionMinForArch`, exposed as
  `DVTVersion`
- `DVTMachOOSVersionMinForPlatform` and `DVTMachOPlatformForExecutable`

Classifications report through `NSNumber *` plus an `NSError **` out-parameter
rather than a bare `BOOL`, so "is not a Mach-O" is distinguishable from "the
file could not be read". `DVTMachOHasFatHeader` takes the name literally: only a
fat header qualifies, so a thin image answers `NO`.

Architectures are reported as strings (`@"arm64"`, `"x86_64"`, …) and UUIDs as
canonical uppercase dashed strings, because the reduced Foundation in this SDK
has no `NSUUID`.

### Versions and architectures

`DVTVersion` and `DVTArchitecture` are reimplemented to match the originals'
selector lists, property types, and property attributes, so callers that reach
for them through the runtime see the same surface:

- `DVTVersion` parses `major[.minor[.update]]`, ignores extra components, and
  renders `15.0` but not `15.0.0`. `hash` is `major * 10000 + minor * 100 +
  update`; equality and ordering ignore the build number.
- `DVTArchitecture` looks up by canonical name or by `(cpuType, cpuSubType)`.
  Capability bits in the high byte of a subtype are ignored, which keeps
  `arm64` and `arm64e` distinct.

### Assertions

`DVTAssert` and friends report through a swappable `DVTAssertionReportHandler`.
Reports carry the file, line, function, object or selector, a human-readable
message, the formatted details, and a backtrace.

The assertion gates mirror the hidden user defaults found in Apple's binary —
`DVTEnableAssertionsForQuickLookTestSuite`,
`DVTEnableAssertionsForCPUPerformanceTestSuite`,
`DVTEnableAssertionsForMemoryPerformanceTestSuite`,
`DVTEnableAssertionsForValidationTestSuite`, and `DVTEnableAllAssertions` — each
of which is also read from the environment of the same name. Either form uses
`NSUserDefaults` boolean parsing, so `1`, `YES`, `true`, and `yes` are on, while
`0`, `NO`, and anything unrecognised are off.

`DVTIsAssertionEnvironment` and `DVTShouldAssertForEnvironment` both take a small
integer selector, not a suite name. Apple switches on that integer and never
messages it, and both of its call sites pass the literal `2`. Selector `0` is
the one case that asserts without consulting a gate; `1` through `5` are decided
by that case's own gate; anything else is not an assertion environment.
`ShouldAssert` is the permissive variant — a case that finds its own gate closed
falls through to the later gates, and an unrecognised selector defers to
`DVTEnableAllAssertions`. Nothing is enabled by default, so a plain run stays
quiet: a process that selects no environment has to land outside the known
cases, since defaulting to `0` would assert unconditionally.
`DVTFailureHintCreator` turns an object, a selector, or a class into the hint
text that appears in the report.

The gate-to-case mapping above was recorded by driving all 32 combinations of
the five keys through Apple's own exported functions and recording both answers.
Reading it off the string table instead gets it backwards: the cases run
`2` = QuickLook, `3` = CPUPerformance, `4` = MemoryPerformance, `5` = Validation,
which is neither the order the keys appear in the binary nor the order they are
declared in Apple's headers. Case `1` is gated but named by no string in the
binary, so it cannot be switched on. `DVTEnableAllAssertions` is a master
switch rather than a sixth case: it is read only by `ShouldAssert`, which it
answers `YES` for every selector, while `Is` keeps reporting `NO` for every gated
case.

### Foundation additions

Nil-tolerant insertion, identity-sensitive lookup, array derivation
(`dvt_arrayByRemovingObject:`, `dvt_arrayByReversingObjects`, …), in-place
sorting by a derived key, both in place on a mutable array and as a copy on an
array or a set, stable partitioning, shuffling, unique-string lookup,
contiguous-run search, a command-line renderer, and an `NSHashTable`
addition. See
`src/DVTFoundation/include/DVTFoundationClassAdditions.h` for the 99 methods
implemented here.

The `NSMutableArray` `dvt` methods are complete: every one Apple installs on
that class is now reproduced here.

The emptiness pair `dvt_hasContent` / `dvt_isNonEmpty` is the widest thing
Apple declares here: one question asked on six classes — `NSArray`,
`NSDictionary`, `NSMapTable`, `NSOrderedSet`, `NSSet` and `NSString`. All six
answer it identically for both selectors, and the collections (including
`NSMapTable`, which is not a collection in the usual sense but does answer
`count`) are a plain `count != 0`. `NSString` is the one host where the two are
written differently — `length != 0` for `dvt_hasContent`, but
`!isEqualToString:@""` for `dvt_isNonEmpty` — which no string can observe, so
the split is reproduced rather than smoothed into one shared helper. Apple splits
this family across four category names (`DVTFoundationClassAdditions`,
`DVTNSSetAdditions`, `DVTNSOrderedSetAdditions`, `DVTNSMapTableAdditions`) and
so does this project, because the names are readable in the category metadata and
a class dump of the two binaries lines up only if they match.

`NSString` also carries the letter-casing family, where the interesting work is
`dvt_wordsFromString`. Only `a`–`z` are word characters: an uppercase letter
always starts a word, a run of digits holds together, and anything else —
punctuation, whitespace, and non-ASCII alike — is a separator that is dropped.
So `camelCaseString` yields three words but `ALLCAPS` yields seven, one per
character, and an all-CJK string yields none at all. The digit test is widened by
one character, so `:` continues a digit run just as a digit does; the empty range
that can leave behind is skipped rather than emitted as a blank word. The
first-character pair tests `lowercaseLetterCharacterSet` /
`uppercaseLetterCharacterSet` membership on a single UTF-16 code unit and
otherwise returns the receiver, so `ß` uppercases to the two characters `SS` and
a leading surrogate is not a letter. That is why `dvt_stringWithLetterCasing:`
takes a bare `NSUInteger` here even though Apple names the argument
`DVTStringCasingType`: `0` is lowercase, `1` uppercase, `2` capitalized, and
anything else asserts, with Apple's own message text.

`NSString` also carries the identifier family, which is the widest thing Apple
puts on a single class here: five manglers that rewrite a string into something
a compiler would accept, plus the one predicate that asks whether it already is.
Four of those five are direct profiles and the fifth is the dispatcher described
below. Three of the four direct ones canonical-decompose the receiver and then
walk it one UTF-16 code unit at a time, substituting `_` or `-` for anything the
profile rejects; they differ only in which ASCII punctuation survives. Strict C
keeps `_` and substitutes `_`. Bundle identifiers add `.` and `-` to both the
leading and the trailing set and substitute `-`. RFC 1034 adds `-` but not `.`.
The remaining direct profile, `dvt_stringByManglingToLegalC99ExtendedIdentifier`,
skips decomposition and counts a surrogate pair as the single scalar it encodes,
which is why it spends one `_` on an emoji where the other three spend two, and
it is also the only one of the five that keeps non-ASCII text: its table is C99
Annex D, so `é` and `中文` survive intact while every other profile flattens them
to a separator. Legality follows the strict C profile and nothing else, so a name
that is fine as a bundle identifier still reports as illegal.

`dvt_stringByManglingToLegalIdentifierOfType:` dispatches rather than validates:
`0` is the bundle profile, `1` is RFC 1034, and every other value — including
`NSIntegerMin` — falls through to strict C without asserting. All five manglers
return the receiver untouched when it is empty, and return a zero-length result
rather than the receiver's content for one input: `U+FFFF` behaves as
end-of-string, so the three decomposing profiles stop there and silently drop the
rest of the receiver, turning `a<U+FFFF>b` into `a`. The extended profile never
decomposes and keeps going, mangling the same input to `a_b`.

Apple's own C99 Annex D table was recovered by sweeping all 65,536 BMP code
points through both the leading and the trailing position and recording which
were preserved, which yields 249 permitted ranges and 15 ranges that are legal
only after the first character. Those are ASCII digits plus the non-ASCII digit
blocks — Arabic-Indic, Extended Arabic-Indic, Bengali, Gurmukhi, Gujarati,
Oriya, Tamil, Telugu, Kannada, Malayalam, Thai, Lao and Tibetan. The table is
taken from what this build of Apple's binary actually accepts rather than from
the annex text, since the two are not the same thing.

An unpaired UTF-16 surrogate is the one input the extended profile declines to
rewrite, and the rule is narrow enough to state exactly. A surrogate that does
not open a valid pair is copied through verbatim *together with the code unit
after it*, and the walk then resumes at the unit after that. So `a<U+D800>b`
comes back unchanged, while `' '` + `U+D800` + `' '` comes back as `_`, `U+D800`,
and a space that is never rewritten — the trailing space survives a mangler that
would otherwise have replaced it. The same rule explains a case that looks like a
bug until you see it: `U+1F600` spelled as two high surrogates and a low one is
returned untouched rather than collapsing to a single `_`, because the first high
surrogate swallows the second as its verbatim companion and the pair is never
formed. The three decomposing profiles are unaffected and substitute their
replacement character as usual. Note that this is the opposite of the `U+FFFF`
behaviour above, which truncates in the extended profile's absence rather than in
its presence.

### Property list values

A property list can hold exactly six things: string, data, date, number, array,
dictionary. The `DVTPropertyListValue` category asks any object which of those it
already is, and the answer is always either the receiver itself or `nil` — these
are deliberately **not** conversions, because a coercion that could fail has to
report how it failed, and these report only "not this type". See
`src/DVTFoundation/include/DVTPropertyListValue.h` for the 38 methods.

Six selectors — `dvt_plistStringValue`, `dvt_plistDataValue`,
`dvt_plistNumberValue`, `dvt_plistDateValue`, `dvt_plistArrayValue`,
`dvt_plistDictionaryValue` — are each declared on all six Foundation classes, so
every receiver answers the question and answers five of them with `nil`. Three
details are load-bearing:

- The answer is the **receiver**, not an equal copy, so subclasses pass and
  mutable instances pass. Empty instances are their own type too.
- `-[NSNumber dvt_plistStringValue]` is the one method that builds something, and
  it is the family's only exception to "receiver or nil". It returns
  `-stringValue`, inheriting that method's two sharp edges on purpose: `@YES`
  stringifies as `1`, not `YES`, and a double keeps its own precision.
- Nothing parses. `@"12"` is not a number and empty data is not a string.

The two remaining selectors live on `NSDictionary` and are the family's only
methods that explain themselves, because a container can fail two different ways:
`dvt_plistArrayForKey:error:` and `dvt_plistDictionaryForKey:error:` distinguish a
missing key (`Missing NSArray value for key: missing`) from a wrong-typed one
(`Found NSConstantIntegerNumber value (7), instead of NSArray for key: num`). Both
fail with `nil`, error domain `DVTPropertyListValueDecoding`, code `0`, and only
`NSLocalizedDescription` set; `error` may be `NULL` and is left untouched on
success. The value in that message is rendered with **`-debugDescription`, not
`-description`** — the two disagree on precisely the types most likely to appear
here, so empty data prints as `<>` rather than `{length = 0, bytes = 0x}`, and an
array as `<NSConstantArray 0x…>(\n    1\n)`. Both were confirmed against Apple's
binary.

### Comparison helpers

Six exported C functions in `src/DVTFoundation/DVTComparison.m`, declared in
`src/DVTFoundation/include/DVTComparison.h`.

| Function | Behaviour |
| --- | --- |
| `_DVTCompareBools` | Three-way on the two truth values. |
| `_DVTCompareIntegers` | Three-way, with no overflow on the extremes. |
| `_DVTCompareDoubles` | Three-way, with a sign-bit rule for `NaN`. |
| `_DVTEqualDoublesWithEpsilon` | `fabs(a - b) <= eps * fmin(fabs(a), fabs(b))`. |
| `_DVTCompareDoublesWithEpsilon` | `0` within tolerance, otherwise `-1`/`1`. |
| `_DVTCompareArrays` | Sorts with `compare:`, compares count, then elements. |

Three behaviours are worth stating outright because they look like bugs and
would otherwise get "fixed":

- `_DVTCompareDoubles` returns a value even when an operand is `NaN`. Both
  `NaN` compares `0`, a `NaN` on the left gives `1` when the right operand is
  negative and `-1` otherwise, and a `NaN` on the right gives `-1` when the left
  operand is negative and `1` otherwise. The two branches disagree in polarity
  on purpose, so `-0.0` is what separates them: `NaN` against `-0.0` returns
  `1` while `NaN` against `0.0` returns `-1`.
- `_DVTCompareDoublesWithEpsilon` is not that function with a tolerance bolted
  on. Its fallback is `a < b ? -1 : 1`, so *every* remaining case is `1`:
  a `NaN` on either side compares greater regardless of sign, and `INFINITY`
  against `INFINITY` also returns `1`, because two equal infinities differ by
  `NaN` and so fail the tolerance test.
- `_DVTEqualDoublesWithEpsilon(INFINITY, INFINITY)` is `NO` while
  `(INFINITY, -INFINITY)` is `YES`. The first pair has a `NaN` difference; the
  second has an infinite difference measured against an equally infinite
  `epsilon * min`, which the comparison orders as equal.

`_DVTCompareArrays` sorts both operands with `compare:` before anything else, so
element order is irrelevant and `nil` sorts to an empty array and compares as
one. The sort happens first in a way that is observable: `@[@1, @"a"]` against
`@[@1]` raises rather than returning `1` for the longer array, because the sort
of the mixed array fails before the counts are compared. The original does not
guard either the sort or the element walk, so a mixed pair raises from `-compare:`
in both cases, and that parity is preserved here.

These were recovered by differential testing rather than by reading the
assembly, which is worth noting because the disassembly is actively misleading:
`_DVTCompareDoublesWithEpsilon` and `_DVTCompareIntegers` both end in a
`csinv` that decodes as returning only `0` and `-1`, and neither of them does.
Confirmed against Apple's binary at 1,481,809 generated cases — doubles from raw
bit patterns (so `NaN` payloads, subnormals, and both zeros), eight epsilon
values, random 64- and 32-bit integers, and random arrays — with zero mismatches,
including which inputs raise.

### Certificate kind comparison

Two more exported functions in `src/DVTFoundation/DVTCertificateComparison.m`.
They take the `1.2.840.113635.100.6.1` OID that Apple stamps into a signing
certificate to say what the certificate is for, and order certificates by *what
they are for* rather than by OID text. The seven recognised OIDs map to ranks
`0`–`6`, and the rank order is not the OID order: `...6.1.12` sorts *before*
`...6.1.7`, which is the entire reason the indirection exists.

Two of the fallbacks order by **object address**, not by anything meaningful, and
neither can be reproduced by comparing the two ranks:

- An exactly-`nil` operand sorts before everything and after nothing, because
  `nil` is address zero.
- A pair where one side is a recognised kind and the other is not is also
  settled by address, between the looked-up rank and `nil`. So a known kind
  always sorts *after* an unknown one regardless of which side it is on.

When *both* sides are unknown the answer instead falls through to
`[lhs compare:rhs]` on the operands, so unknown kinds order by text. The case
that pins this down is `@7` against `@3`: both look up to `nil`, yet the result
is `1` rather than the `0` that comparing two `nil` ranks would give.

`DVTCompareCertificateKindSets` sorts both operands and compares the lowest
element of each, and **cannot succeed**. `dvt_sortedArrayUsingComparator:` is
referenced but never implemented, in Apple's framework and in this one, so every
call raises `NSInvalidArgumentException`. Two `nil` sets are the single
exception: messaging `nil` returns `nil`, so neither array reaches the missing
selector and the result is `NSOrderedSame`. The body is reproduced rather than
repaired, since matching the shipped binary is the point.

The rank table is deliberately *not* exported — Apple's binary keeps it in a
private lazy static, and adding a public symbol Apple does not have would be its
own kind of infidelity. Verified over 30,638 differential cases: all 49 ordered
pairs of known OIDs, `nil` in every position, unknown strings, non-string
operands, 30,000 random strings, and exception-name parity for the sets. Zero
mismatches.

### Key path equality

`_DVTEqualObjectsUsingKeyPaths(lhs, rhs, mode, keyPaths)` compares two objects by
reading the same key paths out of both and comparing each pair. Its third
argument looks like a key path count and is not: it is a **class-strictness
mode**, and getting that wrong is what made the first round of probes
contradict the disassembly.

| `mode` | class requirement |
| --- | --- |
| `0` | `rhs` is a `kind of` `[lhs class]` |
| `1` | `rhs` is a `member of` exactly `[lhs class]` |
| anything else | never equal |

The check is one-directional — it asks whether the *right* operand is a subclass
of the left one's class — so a derived left operand and a base right operand
fail even in mode `0`. The mode argument is not a count, and a value of `2` is
not "two key paths": it is an unsupported mode.

The order of the checks is observable and none of them can be skipped:

1. Identical operands return `YES` before the mode is even examined, which is
   why an unsupported mode still reports two identical objects as equal, and why
   two `nil`s are equal — `nil == nil`.
2. A single `nil` operand is `NO`.
3. The class check runs next, and failing it returns `NO` without reading a
   single key path.
4. Only then are the key paths enumerated, stopping at the first disagreement.

An empty `keyPaths` therefore passes vacuously, and the class check alone
decides the answer.

Each value pair is compared by **identity first**, and `isEqual:` only when the
two are not the same object. That ordering is deliberate: an object whose
`isEqual:` refuses to accept even itself still compares equal to itself.

Two dependencies had to be reconstructed alongside it. The function sends
`dvt_allObjectsPassTest:` to `keyPaths`, and that selector is implemented in
Apple as a non-exported category method on `NSArray` — so it is a real method
here, not one of the intentionally-missing selectors, and it was added to
`DVTFoundationClassAdditions`. Apple also carries the same selector on `NSSet`
and `NSHashTable`, and all three were disassembled and confirmed to be
structurally identical: a 16-slot fast-enumeration buffer, `YES` when the
enumeration runs out, and an early `NO` at the first element that fails. The
three share one body here. It returns `YES` on exhaustion, which is what makes
the empty `keyPaths` case vacuously true. `-valueForKeyPath:` is plain KVC, but
the SDK used to build this framework does not declare it, so it is declared
locally where it is used.

**One deliberate deviation.** All three of Apple's implementations load the
test block's invoke pointer without a nil check, so a non-empty collection
passed a `nil` block faults — confirmed by running it, crashing at
`ldr x8, [x19, #0x10]` inside Apple's `NSSet` method. This framework returns
`YES` instead. The guard is kept on purpose and is documented at each
declaration; it can only differ in the case where the original crashes.

Exceptions are not caught. An undefined key path raises `NSUnknownKeyException`
out of the function, and a `keyPaths` that is not a collection carrying
`dvt_allObjectsPassTest:` raises `NSInvalidArgumentException`. A `nil`
`keyPaths` messages `nil`, yields `nil`, and `nil` is `NO`.

Verified over 37,216 differential cases: 24 operand types against each other,
modes `0`–`3` plus `4`–`8`, sixteen key path collections including non-collections
and a `nil` one, and `nil` in every position, with exception-name parity. Zero
mismatches.

Still missing from this family: `_DVTSigningCertificateDisplayNameForCertificateKind`.
Apple exports the seven `DVTCertificateKind_*` identifiers alongside seven
`DVTCertificateKindName_*` values, but the two sets do not pair up by name —
there is a `Developer ID Application` display string with no matching kind — so
the mapping is not recoverable by inspection and is left alone rather than
guessed at.

### Dispatch wrappers

Eight GCD wrappers, which between them are referenced by 58 of the frameworks in
`Xcode.app/Contents/SharedFrameworks`. They live in `DVTDispatch`.

`DVTDispatchCreateQueue` is the only one whose shape is not obvious from its
name, and it is worth stating precisely because guessing it produces a queue
that looks fine and is not. The arguments are `(serial, qos, unused, label)` —
the label is the **fourth** argument, and `serial` is inverted relative to how
it reads: a non-zero `serial` selects a null attribute, which is how GCD spells
"serial", while zero selects the concurrent attribute explicitly. The
autorelease frequency is then forced to `WORK_ITEM` on both branches, so the
two differ only in concurrency. The third argument is accepted and ignored;
Apple never reads it either. Verified by probing: a label passed as the first
argument comes back as garbage, and a queue built that way answers to no
recognisable name at all.

The remaining seven are thin pass-throughs to `dispatch_async`,
`dispatch_sync`, `dispatch_after`, `dispatch_barrier_async`,
`dispatch_group_notify` and the two `dispatch_source_set_*_handler` calls, with
argument orders matching GCD's own.

**What is not reproduced.** Every one of these wraps the caller's block rather
than submitting it directly. The wrapper asks a DVT log-aspect group whether a
group is already current: if one is, it invokes the block directly; if not, it
creates a group, clears a per-thread table keyed
`DVTInvalidation_ObjectsReportedToRadarDuringCurrentEventHashTable`, and runs
the block inside it. That bookkeeping is diagnostic instrumentation tied to
machinery this reconstruction does not have, so the blocks here are submitted
unwrapped. Scheduling, ordering, thread and queue semantics are unaffected; the
diagnostic grouping is simply absent.

`DVTDispatchSourceSetCancelHandler` takes a third `dispatch_group_t` argument
that the others do not, and submits through it rather than the source's own
queue. It is accepted and passed to GCD's own cancel-handler registration,
which preserves the serialization but not the group submission.

#### Block performers

Five functions that run a block somewhere, and a generation counter that lets a
caller notice when a block it handed off has been superseded.

`DVTDispatchGetMainQueue` builds a queue that runs on the main thread but keeps
its own identity, label and priority, by creating one at user-initiated priority
and retargeting it at the main queue. That sounds roundabout until you try to
dispatch onto `dispatch_get_main_queue()` from a plain tool: nothing drains it,
so the block simply never runs. `DVTDispatchIsMainQueue` recognises these by a
queue-specific tag attached lazily, on first use, rather than by comparing
pointers — so the real main queue counts too, while every ordinary queue does
not.

`DVTAsyncPerformBlock` and `DVTSyncPerformBlock` branch on that tag. An ordinary
queue is handed to the corresponding dispatch wrapper, which preserves its
diagnostic grouping. A main-thread queue cannot be dispatched onto at all, so
the block goes to the main run loop in common modes instead — asynchronously for
the first, behind a semaphore for the second.

The semaphore is signalled from a `finally`, not after the call. An exception
thrown by the caller's block would otherwise unwind out of the run loop and
leave the waiting thread asleep forever.

`DVTAsyncPerformBlockOnOperationQueue` compares its queue against
`[NSOperationQueue mainQueue]` and routes a match to the run loop, since the main
operation queue has the same problem. Anything else takes a real `NSOperation`.

**Differences from Apple.** Two deliberate ones, both probe-confirmed:

- `DVTDispatchBlockGenerationIsCurrent` answers `*counter == generation`. The
  condition code in Apple's binary decodes to NE, which would answer the
  opposite, so the comparison comes from observed behaviour on Apple's own
  framework. Reading it the intuitive way inverts it and silently rejects every
  block that is still valid.
- `DVTSyncPerformBlock` on a main-thread queue, called *from* the main thread,
  cannot return: it waits on a run loop that the calling thread is itself
  blocking. This is true of Apple's implementation too, and the header says so.
  Call it from another thread in that case.

Two smaller ones. Apple builds operations with a private `DVTOperation` subclass
that adds cancellation-block bookkeeping, decides whether cancellation should hop
to the main thread, and drops dependencies once finished; the public block
operation stands in. And a `NULL` queue is ignored by
`DVTAsyncPerformBlockOnOperationQueue` and answered `NO` by
`DVTDispatchIsMainQueue`, where Apple asserts on both — the arguments are not
documented as nullable.

Differential against Apple covers 33 cases across the two harnesses: post-increment
values and 32-bit wraparound edges, the generation comparison against eight probe
values, label and concurrency for both queue flavours, sync/async/barrier/after/
group-notify/source handling, main-queue recognition for four kinds of queue,
routing and delivery for all three performers, and the semaphore path driven from
a background thread while the main run loop is genuinely serviced. No mismatches.

### Geometry

The ten `DVT*` CGRect helpers live in `DVTGeometryAdditions`. Most are
arithmetically obvious; four are not, and all four were pinned down against
Apple's binary rather than guessed. Each is reproduced exactly, quirks included.

**`DVTRectByInsettingRect` is not `CGRectInset`.** Its y axis reads the *size* of
the insets rather than the origin: the leading edge moves by `insets.size.width`
and the trailing edge by that plus `insets.size.height`. So the usual
`CGRectMake(x, y, w, h)` margin insets y by `w`. Separately, an over-inset
collapses instead of inverting — the dimension goes to exactly zero and the
origin moves to the midpoint of the span it would have occupied, so the result
is never degenerate in a negative direction.

**Edge tests go through CoreGraphics, and those accessors normalise.** Apple calls
the real exported `CGRectGetMinX`/`CGRectGetMaxX` functions, which return the
*geometric* extremes. For a rect built with a negative width the min X is the
origin shifted left, not the origin. `DVTInsetFromRectToRect` and
`DVTPlaceRectInsideRect` both inherit this, and `{40, 60, -30, -40}` and
`{10, 20, 30, 40}` must therefore produce identical results — they span the same
edges. This is why the framework does not link CoreGraphics: those symbols are
not exported by every SDK configuration, and the four helpers replicate the
accessors inline instead.

**The three scaling functions are not interchangeable.** `-IntoRect` leaves a size
that fits on *both* axes alone and merely centres it, otherwise scales it down to
fit. `-UpOrDownIntoRect` always scales to fit inside, scaling up as well as
down. `-ToFillRect` scales to *cover*, so it overflows on one axis whenever the
aspect ratios differ. For `200x100` into a `100x100`, Into and UpOrDown give
`{0, 25, 100, 50}` while ToFill gives `{-50, 0, 200, 100}`.

**NaN aspect ratios take the "less than" branch.** Every aspect test compiles to
an `fcmp`, and arm64's `lt` condition is `N != V`, which is also satisfied when
the comparison is *unordered*. `UpOrDownIntoRect` branches on `lt`, so a NaN
aspect must take the multiply branch; written as `a < b` it would not. The other
two branch on `ge`, which C's `>=` already matches. The three are kept as
separate helpers rather than merged, precisely because they disagree on unordered
inputs.

Differential against Apple compares all ten **bit for bit**, via `memcmp`, so NaN
payloads and signed zeroes have to agree too: 1,210 cases on a structured grid
plus 200,000 randomised rects covering subnormals, ±1e300, mixed signs and zero
dimensions. Zero mismatches.

### Text extras

The string and fragment helpers in `DVTTextExtras` were recovered from Apple's
binary by probing it directly, because three of the four encode an indexing
quirk that no reasonable reimplementation would reproduce.

**`DVTStringFromLineEnding` indexes a three-entry table at `value - 1` and tests
the result unsigned.** `DVTLineEndingNone` (0) is therefore *not* a string, and
neither is any negative value: they underflow to a huge index and fall off the
end. Only 1, 2 and 3 return anything, and every other input returns `nil`.

**`DVTStringFromFindMatchStyle` falls back instead of asserting.** Values past
`EndsWith` return `WholeWords`, not `nil` and not an assertion — which is why
`WholeWords` appears twice in the binary's string pool, once in the table and
once as the fallback. This is the opposite of the filter display strings below.

**`DVTFindMatchStyleFromString` is case sensitive and returns `Contains` for
anything unrecognised.** There is no error case, so a typo parses as `Contains`
rather than failing. Its comparisons are ordered `WholeWords`, `StartsWith`,
`EndsWith`, `Contains`, which only matters because the result is a single value
either way.

**`DVTTextFragmentsForStringPreservingEscapedSpaces` protects escapes with a
placeholder, not an escape.** A literal `\ ` is replaced with the printable
string `\<space>`, the text is split on spaces, empty pieces are dropped, and the
placeholder is turned back into a space. Two consequences are pinned down by the
tests: runs of spaces collapse rather than yielding empty fragments, and passing
the literal text `\<space>` gives the same answer as passing an escaped space,
because the placeholder is indistinguishable from its own output.

### Filter expression display strings

The three display-string functions in `DVTFilterExpression` map their enum to a
user-visible string: `AND`/`OR` for compound operators, the single characters
`=`/`<`/`>` for numeric comparisons, and the spelled-out `Equals` … `Like` for
textual ones. The numeric enum has only the three strict comparisons — there is
no greater-than-or-equal variant.

Unlike `DVTStringFromFindMatchStyle`, **these assert on an out-of-range value**
rather than substituting a fallback; all three abort with `SIGABRT` in a default
environment, verified out of process against Apple. The returned string is
therefore only reachable when the assertion has been made non-fatal, and the
tables are laid out so that path still yields a valid string.

Differential against Apple covers all seven functions: **42,095 checks, zero
mismatches**, driven by a deterministic PRNG over strings built from the
characters that matter here (space, tab, newline, backslash, and the
`<`/`>` of the placeholder), plus 2,000 strings up to 600 characters long. The
range-safe two are driven past their ends on purpose, which is where their `nil`
and fallback behaviour lives.

### Line offset tables

`DVTLineOffsetTableTextExtras` maps UTF-16 offsets onto line indices for the
editor, and was recovered by probing Apple rather than by reading the
disassembly alone — the struct layout and three of the four behaviours are not
what a plausible implementation would choose.

**The table stores line *starts*, then one extra entry holding the string
length.** `count` is therefore the number of line starts plus one, so an empty
string still yields `[0, 0]` and there is never a table with fewer than two
entries. The terminator is what makes `DVTCharacterRangeForLineRange` work
without being handed a length separately: line `i` runs from `offsets[i]` up to
`offsets[i + 1]`.

**Offsets are UTF-16 code units, so they agree with `-[NSString length]` rather
than with a user-perceived character count.** An astral character costs two
units and a combining mark costs one of its own. This is observable in the
tests, where an emoji followed by a newline puts the second line start at 3.

**Line breaks are `\n`, `\r`, `\r\n`, `U+0085`, `U+2028` and `U+2029` — but not
vertical tab or form feed.** `CRLF` counts as a single break, so the next line
starts past both characters.

`DVTCharacterRangeForLineRange` **clamps** a range that runs past the last line
rather than rejecting it, and a zero-length line range is empty wherever it
starts. The clamp applies to *both* endpoints independently: `{99, 0}` and
`{NSNotFound, 0}` both collapse onto the terminating entry, and neither reads
past it.

**Both functions take the table by pointer, never by value.** A by-value
parameter would copy the struct — harmless for the pointers it holds, but it is
not Apple's ABI, and the exported symbols are the ones other code links against.
The table is never modified through the pointer.

**A table adopted onto a larger string shifts its offsets, and
`DVTCharacterRangeForLineRange` is where the shift happens.** `baseLine` names
the first line the table covers and `baseOffset` is added to every line from
there on; `DVTInitializeLineOffsetTable` leaves `baseLine` as `NSNotFound`, so a
table built for a whole string shifts nothing. Each endpoint is shifted
independently, so a range spanning the seam has the shift absorbed into its
*length*: for `"ab\ncd"` (offsets `[0, 3, 5]`) with `baseLine = 1` and
`baseOffset = 100`, line `{0, 1}` yields `{0, 103}` — the start stays at 0 while
the end moves from 3 to 103. Clamping happens before the shift is applied, so an
out-of-range line still resolves to the shifted terminating entry
(`{99, 0}` → `{105, 0}`).

`DVTLineRangeForCharacterRange` never applies the shift, and neither does Apple:
handed a shifted table it reads the raw offsets and reports lines against them,
exactly as this project does. The shift exists to keep `DVTCharacterRangeForLineRange`
in the units of the larger string; resolving a character back to a line is the
caller's to line up.

`DVTLineRangeForCharacterRange` has the one genuinely surprising rule. It
returns the line holding `location` extended far enough to cover `length`, but
the extension is capped at one line past where it started **and** at the last
addressable line, and it deliberately does *not* spill into the terminating
entry. The difference is visible only on strings ending in a break, where the
offsets repeat: for `"\n"` (offsets `[0, 1, 1]`) a two-character range at 0
covers lines 0 and 1 but not the terminator, while a range that already starts
on the last line is allowed to grow into it. Fitting this took most of the
differential work — the naive "advance while the range is not covered" loop
over-extends on exactly these degenerate tables.

Differential against Apple covers all four functions: **250,811 checks, zero
mismatches**, plus a shifted-table sweep replaying every line range against
plain, fully shifted (`baseLine = 0`) and mid-table shifted (`baseLine = 1`)
tables over eight strings. The corpus includes empty strings, lone and doubled
breaks, trailing breaks that produce empty lines, runs of nothing but breaks, the
Unicode separators, and astral and combining characters. The struct is compared
field by field — including `capacity`, `baseLine` and `baseOffset`, which
initialisation sets to `count`, `NSNotFound` and `0` — and the `malloc`-owned
offset array is compared element by element before both are released.

### UTF-8 and UTF-16 offsets

`DVTTextUTF8Correspondence` converts between the two coordinate systems the
editor mixes freely: `-[NSString length]` counts UTF-16 code units, while
`-[NSString lengthOfBytesUsingEncoding:]` and the file layer work in UTF-8
bytes. Four functions do the translation, in both directions and for both a
single offset and a range.

**The shortcut is decided by how the string is stored, not by what it
contains.** An ASCII-backed string — which is what you get from a plain ASCII
literal or a copy of one — answers with the index unchanged, *without
clamping*, so index 99 in `@"hello"` returns 99. A string built from `unichar`
units, or holding any non-ASCII character, has no ASCII backing and takes the
general path, which clamps instead. Two strings whose characters are
byte-for-byte identical therefore answer differently, so the implementation
asks CoreFoundation via `CFStringGetCStringPtr(..., kCFStringEncodingASCII)`
whether a C string is available rather than testing the characters. This is the
single most important thing about the family, and it is why a "reasonable"
character-based implementation fails on literals.

**A byte offset that lands inside a multi-byte sequence resolves forward to the
start of the next whole character**, never backward. In `中` (three UTF-8
bytes), bytes 0, 1 and 2 all map back to index 0, and byte 3 maps to index 1.
The forward direction is the mirror image: a high surrogate contributes four
bytes and *skips* the low surrogate that follows, so the index of the low half
reports the byte position *after* the pair rather than inside it.

**Unpaired surrogates are counted as four bytes, and converting one back stops
one code unit past the end of the string.** `DVTIndexInStringWithCorrespondingUtf8ByteIndex`
applied to a lone `U+D800` at byte 0 returns 2 from a one-unit string. That
result is not a valid offset for a following range — feeding it back as
`location` trips the assertion — so callers are expected to keep UTF-16 and
UTF-8 ranges separate rather than converting one into the other and reusing it.

**`from` is asserted, not clamped.** An offset past the end of the string
aborts, which is why the differential counts aborts as carefully as it counts
values; the assert is load-bearing and the tests do not route around it.

### Caching a string's conversions

Converting one offset walks the string from the start, so a caller translating a
long run of offsets pays for that walk every time.
`DVTInitializeIndexOfStringQueryContext` prepares a
`DVTStringIndexQueryContext` for one string, and the two `…WithQueryContext`
functions convert offsets and ranges against it, remembering the last few
answers and resuming from one when it helps.

The struct is part of the ABI rather than an implementation detail: a caller
allocates it on the stack, so its size and field offsets match the original's
(`sizeof` 264, the string at `0x88`, the two buffers at `0x90` and `0x98`, the
length at `0xC0`, and the two four-entry caches at `0xC8` and `0xE8`). A context
initialized by one implementation can be queried by the other, which the
cross-implementation checks cover in both directions.

Two things about the original are easy to trip over, and both are reproduced:

**An ASCII-backed string stores nothing but the flag.** Every offset is already
an offset there, so the queries answer without consulting the string, and the
initializer returns before writing the string, the buffers, or the length. A
caller that inspects those fields on an ASCII context finds whatever it had
there before.

**A warm cache does not have to agree with the uncached answer.** Asking forwards
for every offset in turn fills the cache, and a filled slot is then used as the
starting point for the next walk, skipping code units an uncached walk would
count again. On a surrogate pair that resumes from the pair's trailing half, so
`emoji` offset 3 answers 4 from a warm context and 3 from a fresh one. This is
the original's behaviour, confirmed against it rather than inferred: a fresh
context always agrees with the uncached function, while a warm one can differ,
and the tests assert only the former.

The general path reads the string in blocks of 64 code units, so a surrogate
pair landing on a block boundary has to carry its skip into the next block. The
implementation does, and the mutation tests below are what established that this
is required rather than incidental.

Differential against Apple covers all four functions: **6,727,258 value checks,
zero mismatches, and 698,060 abort cases matched with zero abort mismatches**.
The corpus is every one of the 65,536 single UTF-16 code units, exhaustively
tripled combinations, surrogate-pair construction, and deterministic random
strings, each probed at every offset. The harness was itself checked by
mutation: corrupting the three-byte width, the four-byte surrogate width, the
surrogate skip, the clamp, the zero-byte early-out, and the block carry flag
each produce tens of thousands of failures, and removing the clamp alone
produces 31,168 abort mismatches with *no* value mismatches — which is the
signature of an assertion-only behaviour that a value-only test would miss.

### Document locations

`DVTDocumentLocation` names a place in a document: a URL, a timestamp, and
nothing else. `DVTTextDocumentLocation` adds the two coordinate systems an
editor keeps side by side — a line-and-column range and a UTF-16 character range
— plus the `-locationEncoding` the range was measured in. There are seven
initializers taking different subsets of those fields; every one of them ends up
calling `-_initWithDocumentURL:timestamp:startingColumnNumber:endingColumnNumber:startingLineNumber:endingLineNumber:characterRange:locationEncoding:`,
which validates before it stores.

**The stored line numbers are exclusive at the end while `-lineRange` is
inclusive**, so the two are not inverses of each other. The initializer stores
`-endingLineNumber` as given, and `-lineRange` reports
`{startingLineNumber, endingLineNumber - startingLineNumber}`. Passing a range
instead converts back with `+ lineRange.length - 1`, which is what makes a
`-lineRange:` initializer read back unchanged. A fresh location has every field
at `NSNotFound` and encoding `0`, and an all-`NSNotFound` line range collapses
to `{NSNotFound, 0}`.

**`+[DVTTextDocumentLocation validate...]` is asserted, not clamped.** An
inverted line range, an inverted column range, or a column range outrunning its
line range all fail through `-_populateLocationParameters:decodableClassName:error:`
with `com.apple.DVTFoundation` code `-1`, while the initializers abort outright.
Both entry points are implemented, because callers reach for both.

**A location is immutable and `-copyWithZone:` returns the receiver** — the copy
is the receiver because there is nothing to copy. `-copyWithURL:` is the one that
builds a new object, and it carries the timestamp across unchanged. Equality and
the hash both ignore the timestamp, so a location survives a re-resolve as a
dictionary key; `-isEqualDisregardingTimestamp:` is spelled out separately for
callers that want to be explicit about it, and `-isEqualToCounterpartWithIdenticalClass:`
is the check that refuses to let a subclass equal its superclass.

**`-hash` folds in only the starting line and the character range's length**,
never the location, the columns or the encoding:
`((superhash * 33 + startingLineNumber) * 33 + characterRange.length)`. Ordering
is by timestamp first (when asked for), then URL, then starting line, then
character range.

**`-pasteboardRepresentation` is the document's path, not its URL.** A persistable
representation, by contrast, spells every field into a sorted fragment:
`-persistableStringRepresentationAndDecodableClassName:error:` on a location with
columns 3–11, lines 2–4, characters `{10, 25}` and encoding 4 returns
`file:///tmp/a.swift#CharacterRangeLen=25&CharacterRangeLoc=10&EndingColumnNumber=11&EndingLineNumber=4&LocationEncoding=4&StartingColumnNumber=3&StartingLineNumber=2&Timestamp=7`,
and the class name comes back as `DVTTextDocumentLocation` so the value can be
decoded later. Unknown fragment keys survive a round trip in sorted order, and
`-locationParameters` is empty in both directions — it exists for subclasses to
populate, not for the base to read.

**A text location consumes its whole fragment**, which is why a text location
built from the persistable string above reports
`documentURL:file:///tmp/a.swift` with no fragment at all, while a base location
built from the same string keeps every field except the timestamp. The base hands
the timestamp over to the superclass through `-locationParameters:`, the one
channel the superclass still reads before it strips the fragment itself.

**A field that is absent, unset or at its default is left out of the fragment
entirely — the omission is per field, not per location.** Established against
Apple by reading back the key set from a decoded fragment: `LocationEncoding` is
written only when it is not `0`, since native is the default; each of the four
line and column numbers is written only when it is not `NSNotFound`, and the two
columns and two lines are judged independently, so a location with a starting
line but no starting column keeps just its lines; `CharacterRangeLoc` is written
only when it is not `NSNotFound`; `CharacterRangeLen` is written only when it is
not `0`, so a range at offset 0 of length 0 keeps only its location; and
`Timestamp` is omitted only when it is `nil`, meaning a timestamp of `0` is
recorded like any other. Reading this wrong is invisible in a round-trip test —
the fragment decodes to the same location either way — so the tests assert on the
key set rather than on the decoded value.

Three differences from Apple's binary are forced by the compiler rather than the
source, and are reproduced here as closely as clang allows. A minimal program
adopting `NSSecureCoding` and `NSCopying` gets four extra properties — `hash`,
`superclass`, `description` and `debugDescription` — inherited from `NSObject`'s
protocols, where Apple lists three properties; Apple's binary predates that
behaviour. `representedObject` is declared `assign`, but clang no longer emits
the `&` flag for it, so the property reads `T@,V_representedObject` against
Apple's `T@,&,V_representedObject`. And `DVTTextDocumentLocation` has no
`.cxx_destruct`, because that method only exists to tear down a strong ivar and
clang rejects a strong ivar backing an assign property.

### Location encoding conversion

`+DVTConvertLocationToUTF8EncodedLocation` and
`+DVTConvertLocationToNativeNSStringEncodedLocation` translate a text location
between the two coordinate systems, taking the string and its line-offset table.
Both are three-argument C functions returning an autoreleased location, and both
are reproduced from the disassembly rather than from a header, since Apple exports
no declaration for them.

**Each converter returns its argument unchanged when there is nothing to do**, and
the two differ on what counts as nothing. Asking for UTF-8 and already having UTF-8
returns the receiver; so does asking for native offsets with native offsets. Only
the native converter also treats a location with no character range *and* no
starting column as nothing to do — asking for UTF-8 on that same location builds a
copy. The URL, the timestamp and both line numbers always pass through, because a
line number means the same thing in either encoding.

**A column is translated inside its own line, not against the whole string.** The
converter slices out the line — running to the *next* line's start, not to this
line's last character, so a column naming the position just past the terminator
still resolves — and translates the column within that slice. A column or line
that is `NSNotFound` is left alone rather than being handed to the correspondence
helper, which would reinterpret `NSNotFound` as an offset from the end of the
string.

**Neither conversion is a bijection across a character boundary.** Column 2 of a
line whose second character is an emoji names the middle of that character, which
has no UTF-8 counterpart: going out to UTF-8 yields byte 5, and byte 5 comes back
as column 3. Likewise a range ending inside a character is widened to cover the
whole character — `{3, 2}` over `b😀` becomes `{4, 5}`, not `{4, 3}`. An unspecified
range location keeps its own length untouched, since that length is meaningful on
its own and reinterpreting it would invent a position the caller never named.

**A line number past the end of the table is clamped, not rejected.** The table
records one offset per line start plus one at the end of the string, so the last
entry is the last nameable line; a location naming a line beyond it is pulled back
to that entry. A column on a line the table cannot describe is then translated
against an empty slice rather than dropped.

Verified against Apple's binary over 13,000 cases — five strings (two-line ASCII,
two-line text with an astral-plane character, empty, a single unterminated line,
and a trailing newline) crossed with every valid span of columns, lines and ranges.
Output is byte-identical, including which cases hand back the receiver and which
build a copy.

### Line-offset-aware string wrapper

`DVTLineOffsetAwareStringWrapper` pairs a string with its line offset table so
that a `DVTDocumentLocation` can be resolved against the text it points into. It
is the class the editor reaches for when a location arrives with line and column
numbers rather than a character range, and it fronts the encoding converters
above.

**The table is built on construction and again on decode, and it is never
derived from the string on demand.** The stored table is what every query uses,
so the wrapper copies its input string up front; a mutable string the caller
later edits cannot change what the wrapper reports.

**`-characterRangeFromDocumentLocation:` reads the location in the string's own
units first, then takes whichever coordinate it was given.** A location recorded
in UTF-8 bytes is translated to native offsets before anything is read from it,
because its byte offsets would otherwise index this string to somewhere else in
the text entirely. After that, a location carrying a character range answers from
that range alone. Failing that, a location carrying lines and no columns resolves
to the whole of those lines. A location with lines *and* columns measures each
column from the start of its own line — not from the start of the range — so the
answer stays correct when the range begins mid-line; the ending column is
anchored to its own line only when the range spans more than one line. A location
that names neither a range nor a line returns `{NSNotFound, length}`, keeping the
length it was given, since a length is meaningful on its own.

**`-debugDescription` is a fixed shape, not `-description`:** `<Class 0xPOINTER
string="text">` with two spaces before `string`. Only the newline is escaped, as a
literal `\n` — quotes, backslashes and every other control character are printed
raw, so a string containing a quote produces a description that does not round
trip through a parser. That is Apple's behaviour and it is reproduced exactly.

**Archiving stores only the string, under the key `string`.** The offset table is
not encoded; it is rebuilt by `initWithCoder:`, which is why a decoded wrapper
answers range queries correctly instead of returning empty ranges. Secure coding
is supported.

The runtime metadata matches Apple's: both ivars with the same names, the same
offsets (`_lineOffsets` at 8, `_string` at 48) and the same 56-byte instance size,
and identical type encodings for all twelve methods. Method *order* differs, which
is not part of any contract.

Verified against Apple's binary by a probe that replays every line range against
plain, shifted and mid-table-shifted tables for eight strings, resolves roughly
100,000 locations through the wrapper, converts each in both directions, prints
the debug description, and round-trips through an `NSKeyedArchiver`: **1,613
lines of output, byte-identical** once object pointers are normalised.

### Errors

`DVTFoundationErrorDomain` and `DVTMachOErrorDomain` are exported as data
symbols. `IDETools` resolves `DVTFoundationErrorDomain` with `dlsym` before
relying on it, so it has to remain a real exported symbol.
`DVTPropertyListValueDecodingErrorDomain` is exported the same way, and holds
Apple's `DVTPropertyListValueDecoding` string.

## Testing

`make test` builds both test runners against the freshly built framework and
runs them:

- `tests/dvt_tests.m` — 56,876 checks covering the environment snapshot modes,
  thin/fat/byte-swapped Mach-O files (including synthetic ones it writes itself),
  a header that claims more load commands than the file holds, the collection
  additions, the string casing, word splitting and identifier mangling, the property list value
  coercions, the command-line rendering table, both assertion report layouts,
  the three-way and epsilon comparison helpers, the geometry helpers including
  their negative-size and NaN-aspect behaviour, the text and find-style helpers
  including their out-of-range fallbacks, the filter display strings, the line
  offset tables including their degenerate trailing-break shapes, the string
  index query context, both document location classes including their sorted
  persistable fragments, identity copies, timestamp-insensitive equality and
  hashing, validation failures, and secure-coding round trips, and the dispatch
  wrappers and block performers.
- `tests/dvt_swift_overlay_test.swift` — 13 checks driving `_DVTAssertFromSwift`
  and `_DVTWarnFromSwift` from Swift, including the placeholder substitutions
  for nil arguments.

Current status: **56,876 checks + 13 Swift checks, 0 failures**, on either SDK.

The suite contains assertions that fail on purpose (its own
`ASSERTION FAILURE in …` output is expected); the count of failures is what the
run reports at the end.

## Scope

This is a partial reimplementation. Apple's `DVTFoundation` installs 714
`dvt`-prefixed methods across the classes it extends — 589 distinct selectors
once the ones installed on more than one class are counted a single time. These
are local Objective-C methods, not exported C entry points, so they are absent
from `nm`'s export list and only show up when the selector itself is read. The
counts come from walking the runtime after loading the binary rather than from
its symbol table, which names 608 selectors and so includes ones that no longer
carry an implementation.

This project implements 163 of those 714, chosen for what `IDETools` and the
recovered usage actually reach. Callers using any of the other 553 will not find
it here. Two of the 163 are additions rather than reproductions:
`-[NSArray dvt_maximumObject]` and `-[NSArray dvt_minimumObject]` take no
argument and order with `compare:`, where Apple's same-named methods take a
comparison block, so the local pair is a convenience this port adds alongside
rather than a match for those variants. The other 161 are reproduced against the
binary.

What is implemented is matched against Apple's binary rather than guessed; what
is not implemented is not stubbed out, so its absence is visible as a missing
selector instead of a wrong answer.

## Fidelity notes

Recovered from Apple's binary, or matched against it byte for byte:

- install name, dylib versions, and bundle layout
- `DVTFoundationErrorDomain` (`@"DVTFoundationErrorDomain"`)
- `DVTPropertyListValueDecodingErrorDomain` (`@"DVTPropertyListValueDecoding"`),
  reported with code `0` and no user info beyond `NSLocalizedDescription`
- the `DVTPropertyListValue` coercion family: 36 identity-or-nil methods that
  compile to a bare return with no conversion, plus two dictionary lookups whose
  messages render the offending value with `-debugDescription`
- the identifier family on `NSString`: the C99 Annex D table recovered by
  sweeping all 65,536 BMP code points through both a leading and a trailing
  position, `U+FFFF` ending the receiver for the three profiles that decompose
  first, an unpaired surrogate being copied through with the code unit after it by
  the extended profile, `dvt_stringByManglingToLegalIdentifierOfType:` dispatching
  `0` to bundle and `1` to RFC 1034 and every other value to strict C without
  asserting, and `dvt_isLegalCIdentifier` following the strict C profile and
  nothing else
- the assertion report layouts, including that a failure report takes nine
  format arguments and a warning report takes ten
- `Method: %@%@` in report details, the second component being
  `DVTMethodKindDescription`
- the hidden assertion defaults listed above
- the diagnostic text
  `You may need to set the hidden user default "%@" to 1 to reproduce.`
- `dvt_arrayByRemovingObject:` drops every element that is pointer-identical to
  or `isEqual:` to the argument, not just the first, despite the singular
  argument name
- `dvt_stringByConcatenatingAsCommandLineArguments` escapes exactly four
  characters — `'`, space, `"`, and tab — and renders an empty argument as `""`.
  A backslash is *not* escaped, and neither is the rest of the shell
  metacharacters, so its output is not shell-safe
- `DVTIsAssertionEnvironment` and `DVTShouldAssertForEnvironment` take an integer
  selector rather than a suite name, and both are called with the literal `2`.
  Selector `0` asserts without consulting a gate, `1`–`5` map to the gates
  QuickLook, CPUPerformance, MemoryPerformance, Validation for `2`–`5` with
  case `1` named by nothing, and the permissive variant falls through to the
  later gates before deferring to the master switch
- the package is 44 frameworks, one per `DVT*.framework` bundle in Apple's
  `SharedFrameworks`
- `DVTMachOReexportedLibrariesForExecutable` is a five-instruction tail call into
  the same enumerator `DVTMachOLinkedLibrariesForExecutable` uses, differing only
  in its filter. Apple does not resolve a re-export target: the path reported is
  the one in the load command, which is what this project returns too
- `DVTStringFromLineEnding` indexes a three-entry table at `value - 1` and tests
  the index unsigned, so `DVTLineEndingNone`, every negative value and every
  value past `CRLF` return `nil` rather than a string
- `DVTStringFromFindMatchStyle` substitutes `WholeWords` for any value past
  `EndsWith` instead of asserting, which is why `WholeWords` appears twice in
  Apple's string pool — once in the table, once as the fallback
- `DVTFindMatchStyleFromString` is case sensitive, compares in the order
  `WholeWords`, `StartsWith`, `EndsWith`, `Contains`, and returns `Contains` for
  anything unrecognised, so there is no error case
- `DVTTextFragmentsForStringPreservingEscapedSpaces` protects an escaped space
  with the printable placeholder `\<space>`, splits on spaces, drops empty
  pieces, then restores. Runs of spaces therefore collapse to no fragments, and
  the literal text `\<space>` is indistinguishable from an escaped space
- `DVTStringForFilterExpressionOperator`,
  `DVTNumericalFilterComparisonTypeDisplayString` and
  `DVTTextFilterComparisonTypeDisplayString` *assert* on an out-of-range value
  rather than falling back; all three abort with `SIGABRT` in a default
  environment, and the numeric enum has only the three strict comparisons
- `-copyWithZone:` on both location classes returns the receiver rather than
  allocating, and `-copyWithURL:` is the only copy that builds a new object
- location equality and `-hash` both ignore the timestamp, so a location
  survives a re-resolve as a dictionary key; the text hash folds in the
  starting line and the character range's *length* and nothing else, as
  `((superhash * 33 + startingLineNumber) * 33 + characterRange.length)`
- the stored `-endingLineNumber` is exclusive while `-lineRange` is inclusive,
  so the initializer stores it as given and the accessor reports
  `{startingLineNumber, endingLineNumber - startingLineNumber}`
- `-locationParameters` returns an empty dictionary in both classes, and
  `-populateLocationParameters:` is a no-op, so the persistable fragment is
  assembled by a helper that inspects the class rather than by an overridable
  method a subclass would be expected to override
- `-pasteboardRepresentation` is the document's *path*, not its URL
- `DVTTextDocumentLocation` consumes the entire URL fragment, so its
  `-documentURL` is bare even for a URL that still carries one

Inferred, and therefore liable to differ from Apple:

- nothing outstanding; the notes above replaced the four that were previously
  listed here

Writing the Swift overlay test turned up three API details that the
Objective-C suite could not have found, all now settled:

- `DVTAssertionReportHandler.currentHandler` is imported by Swift as
  `DVTAssertionReportHandler.current`, because Swift drops a property suffix
  that repeats the class name.
- The Swift entry points substitute `DVTUnknownFile` and
  `DVTUnknownFunction` for a nil file or function, so those parameters are
  declared `_Nullable`. Without that annotation Swift rejects the `nil` that the
  implementation is written to accept.
- `-init` reaches Swift as non-optional under Apple's SDK but as failable under
  the Internal SDK, where `NSObject`'s `init` carries
  `NS_DESIGNATED_INITIALIZER`. The test routes construction through an explicit
  `Optional` so it compiles against both.

Known gap: `DVTSetupWeakPropertyKVOAssertions` is a stub, as it is in Apple's
binary, where it compiles away entirely.

### Deliberate divergence

Three situations are answered differently rather than matched. Initialising a
`DVTTextDocumentLocation` with a `nil` document URL **aborts in Apple's binary**
and survives here: the object is built, and
`-persistableStringRepresentationAndDecodableClassName:error:` then returns `nil`
with an error saying the location has no document URL. The URL is declared
nonnull, so the abort is a programmer-error guard rather than a case Apple
handles; returning an error keeps a recoverable mistake recoverable. Two
candidate divergences were checked and turned out **not** to be differences —
`DVTLineRangeForCharacterRange` on a shifted table ignores `baseLine` and
`baseOffset` in both implementations, and both abort on a line offset table with
fewer than two entries, differing only in the text of the assertion.

A third candidate was also not a divergence, and it was the interesting one.
`dvt_stringByManglingToLegalC99ExtendedIdentifier` on a string holding an
unpaired UTF-16 surrogate was initially written off as an unmodellable artifact
of Apple's UTF-8 conversion failing mid-rewrite, and this project mapped a lone
surrogate to `_` instead. That guess was wrong. Sweeping all 78,931 corpus inputs
through both binaries and comparing hex unit by hex unit put the disagreement at
exactly 2,250 inputs, every one of them containing an unpaired surrogate, which is
too specific to be a buffer artifact — and the first hand-built examples showed
Apple returning strings no mangler could produce, such as `_`, `U+D800`, and a
trailing *space*. The rule behind it is the one described above: a surrogate that
does not open a valid pair is copied through with the code unit after it, and the
walk resumes past both. Reproducing that closes the gap, so the seven selectors
are now byte-identical across all 78,931 inputs, malformed ones included, and
nothing about this family is left documented in place of implemented.


## License

BSD-3-Clause. See [LICENSE](LICENSE).

Files created for this project carry a `Copyright (C) 2026, LibreDarwin`
header.
