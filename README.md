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
of which is also read from the environment of the same name. Nothing is enabled
by default, so a plain run stays quiet. `DVTFailureHintCreator` turns an object,
a selector, or a class into the hint text that appears in the report.

### Foundation additions

Nil-tolerant insertion, identity-sensitive lookup, array derivation
(`dvt_arrayByRemovingObject:`, `dvt_arrayByReversingObjects`, …), a command-line
renderer, and an `NSHashTable` addition. See
`include/DVTFoundationClassAdditions.h` for all 33 methods.

### Errors

`DVTFoundationErrorDomain` and `DVTMachOErrorDomain` are exported as data
symbols. `IDETools` resolves `DVTFoundationErrorDomain` with `dlsym` before
relying on it, so it has to remain a real exported symbol.

## Testing

`make test` builds `tests/dvt_tests.m` against the freshly built framework and
runs it. The suite covers the environment snapshot modes, thin/fat/byte-swapped
Mach-O files (including synthetic ones it writes itself), a header that claims
more load commands than the file holds, the collection additions, the
command-line rendering table, and both assertion report layouts.

Current status: **131 checks, 0 failures**.

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

Inferred, and therefore liable to differ from Apple:

- the exact order of the six assertion-environment cases; the mapping from a
  selected environment to a suite default is a best reading of the recovered
  control flow
- the shell metacharacter set used by
  `dvt_stringByConcatenatingAsCommandLineArguments` (space, both quote kinds,
  and backslash are escaped; an empty argument becomes `''`, and `NSNull` is
  described and escaped so argument count is preserved)
- `dvt_arrayByRemovingObject:` removes the first matching occurrence, matching
  the "FirstOccurrence" wording of its sibling method
- re-exported libraries report the `LC_REEXPORT_DYLIB` path rather than
  resolving the re-export target

Known gaps: the Swift overlay entry points
(`_DVTAssertFromSwift`, `_DVTWarnFromSwift`) are declared and defined but have
not been exercised from Swift, and `DVTSetupWeakPropertyKVOAssertions` is a stub.

## License

BSD-3-Clause. See [LICENSE](LICENSE).

Files created for this project carry a `Copyright (C) 2026, LibreDarwin`
header.
