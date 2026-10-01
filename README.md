# LibreDarwin DVTFoundation.framework

An open source reimplementation of Apple's `DVTFoundation.framework`, the
foundation layer that Xcode's IDE stack builds on. `DVTFoundation` is used by
`IDETools`; see `Sources/IDETools` for that side of the picture.

The goal is byte-identical output where that is achievable, and function
compatibility everywhere else. What is recovered from Apple's binary and what
is inferred is called out explicitly in [Fidelity notes](#fidelity-notes).

## Layout

| Path | Contents |
| --- | --- |
| `include/` | Public headers. `DVTFoundation.h` is the umbrella. |
| `src/` | Implementations, one file per subsystem. |
| `tests/` | A single-file test runner, `dvt_tests.m`. |
| `Makefile` | Framework, test, and install rules. |

## Building

```sh
make            # build build/DVTFoundation.framework
make test       # build and run the test suite
make clean      # remove build/
make install    # copy the framework into $(DESTDIR)/Library/Frameworks
```

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
`DVTEnableAssertionsForValidationTestSuite`,
`DVTEnableAssertionsForMemoryPerformanceTestSuite`,
`DVTEnableAssertionsForCPUPerformanceTestSuite`,
`DVTEnableAssertionsForQuickLookTestSuite`, and `DVTEnableAllAssertions` — each
of which is also read from the environment of the same name.

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

### Foundation additions

Nil-tolerant insertion, identity-sensitive lookup, array derivation
(`dvt_arrayByRemovingObject:`, `dvt_arrayByReversingObjects`, …), a command-line
renderer, and an `NSHashTable` addition. See
`include/DVTFoundationClassAdditions.h` for the 38 methods implemented here.

### Errors

`DVTFoundationErrorDomain` and `DVTMachOErrorDomain` are exported as data
symbols. `IDETools` resolves `DVTFoundationErrorDomain` with `dlsym` before
relying on it, so it has to remain a real exported symbol.

## Testing

`make test` builds both test runners against the freshly built framework and
runs them:

- `tests/dvt_tests.m` — 161 checks covering the environment snapshot modes,
  thin/fat/byte-swapped Mach-O files (including synthetic ones it writes itself),
  a header that claims more load commands than the file holds, the collection
  additions, the command-line rendering table, and both assertion report
  layouts.
- `tests/dvt_swift_overlay_test.swift` — 13 checks driving `_DVTAssertFromSwift`
  and `_DVTWarnFromSwift` from Swift, including the placeholder substitutions
  for nil arguments.

Current status: **161 checks + 13 Swift checks, 0 failures**, on either SDK.

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
  Selector `0` asserts without consulting a gate, `1`–`5` map to the gates in
  order, and the permissive variant falls through to the later gates

Inferred, and therefore liable to differ from Apple:

- re-exported libraries report the `LC_REEXPORT_DYLIB` path rather than
  resolving the re-export target

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
