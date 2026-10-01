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

Architectures are reported as strings (`@"arm64"`, `"x86_64"`, …) and UUIDs as
canonical uppercase dashed strings, because the reduced Foundation in this SDK
has no `NSUUID`.

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
(`dvt_arrayByRemovingObject:`, `dvt_arrayByReversingObjects`, …), a command-line
renderer, and an `NSHashTable` addition. See
`src/DVTFoundation/include/DVTFoundationClassAdditions.h` for the 38 methods
implemented here.

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

Still missing from this family: `_DVTSigningCertificateDisplayNameForCertificateKind`.
Apple exports the seven `DVTCertificateKind_*` identifiers alongside seven
`DVTCertificateKindName_*` values, but the two sets do not pair up by name —
there is a `Developer ID Application` display string with no matching kind — so
the mapping is not recoverable by inspection and is left alone rather than
guessed at.

### Errors

`DVTFoundationErrorDomain` and `DVTMachOErrorDomain` are exported as data
symbols. `IDETools` resolves `DVTFoundationErrorDomain` with `dlsym` before
relying on it, so it has to remain a real exported symbol.

## Testing

`make test` builds both test runners against the freshly built framework and
runs them:

- `tests/dvt_tests.m` — 272 checks covering the environment snapshot modes,
  thin/fat/byte-swapped Mach-O files (including synthetic ones it writes itself),
  a header that claims more load commands than the file holds, the collection
  additions, the command-line rendering table, both assertion report layouts,
  and the three-way and epsilon comparison helpers.
- `tests/dvt_swift_overlay_test.swift` — 13 checks driving `_DVTAssertFromSwift`
  and `_DVTWarnFromSwift` from Swift, including the placeholder substitutions
  for nil arguments.

Current status: **272 checks + 13 Swift checks, 0 failures**, on either SDK.

The suite contains assertions that fail on purpose (its own
`ASSERTION FAILURE in …` output is expected); the count of failures is what the
run reports at the end.

## Scope

This is a partial reimplementation. Apple's `DVTFoundation` defines 526 distinct
`dvt_` Objective-C methods across its categories, 250 of them in
`DVTFoundationClassAdditions` alone. These are local Objective-C methods, not
exported C entry points, so they are absent from `nm`'s export list and only
show up when the selector itself is read. This project implements 43 of them,
chosen for what `IDETools` and the recovered usage actually reach. Callers using
any of the other 483 will not find it here.

What is implemented is matched against Apple's binary rather than guessed; what
is not implemented is not stubbed out, so its absence is visible as a missing
selector instead of a wrong answer.

## Fidelity notes

Recovered from Apple's binary, or matched against it byte for byte:

- install name, dylib versions, and bundle layout
- `DVTFoundationErrorDomain` (`@"DVTFoundationErrorDomain"`)
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

## License

BSD-3-Clause. See [LICENSE](LICENSE).

Files created for this project carry a `Copyright (C) 2026, LibreDarwin`
header.
