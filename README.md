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
starts.

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
mismatches**. The corpus includes empty strings, lone and doubled breaks,
trailing breaks that produce empty lines, runs of nothing but breaks, the
Unicode separators, and astral and combining characters. The struct is compared
field by field — including `capacity`, `baseLine` and `baseOffset`, which
initialisation sets to `count`, `NSNotFound` and `0` — and the `malloc`-owned
offset array is compared element by element before both are released.

### Errors

`DVTFoundationErrorDomain` and `DVTMachOErrorDomain` are exported as data
symbols. `IDETools` resolves `DVTFoundationErrorDomain` with `dlsym` before
relying on it, so it has to remain a real exported symbol.

## Testing

`make test` builds both test runners against the freshly built framework and
runs them:

- `tests/dvt_tests.m` — 464 checks covering the environment snapshot modes,
  thin/fat/byte-swapped Mach-O files (including synthetic ones it writes itself),
  a header that claims more load commands than the file holds, the collection
  additions, the command-line rendering table, both assertion report layouts,
  the three-way and epsilon comparison helpers, the geometry helpers including
  their negative-size and NaN-aspect behaviour, the text and find-style helpers
  including their out-of-range fallbacks, the filter display strings, the line
  offset tables including their degenerate trailing-break shapes, and the
  dispatch wrappers and block performers.
- `tests/dvt_swift_overlay_test.swift` — 13 checks driving `_DVTAssertFromSwift`
  and `_DVTWarnFromSwift` from Swift, including the placeholder substitutions
  for nil arguments.

Current status: **464 checks + 13 Swift checks, 0 failures**, on either SDK.

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
