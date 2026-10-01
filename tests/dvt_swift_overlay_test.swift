//
//  dvt_swift_overlay_test.swift
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

import Foundation

/// Captures reports instead of aborting, so the test can inspect them.
final class CapturingHandler: DVTAssertionReportHandler {
    private(set) var reports: [String] = []
    private(set) var lastWasWarning = false

    override func didFailAssertion(_ report: String) {
        lastWasWarning = false
        reports.append(report)
    }

    override func didWarnAssertion(_ report: String) {
        lastWasWarning = true
        reports.append(report)
    }
}

var failures = 0

func expect(_ condition: Bool, _ what: String) {
    if condition {
        print("ok:   \(what)")
    } else {
        failures += 1
        print("FAIL: \(what)")
    }
}

func expectContains(_ haystack: String, _ needle: String, _ what: String) {
    if haystack.contains(needle) {
        print("ok:   \(what)")
    } else {
        failures += 1
        print("FAIL: \(what)")
        print("       looking for: \(needle)")
    }
}

print("\n== swift overlay ==")

/// `-init` reaches Swift as non-optional under Apple's SDK but as failable under
/// the Internal SDK, where NSObject's `init` carries NS_DESIGNATED_INITIALIZER.
/// Routing the call through an explicit `Optional` compiles under both, instead
/// of a `guard let` or a force-unwrap that only one of them accepts.
func makeHandler() -> CapturingHandler {
    let maybeHandler: CapturingHandler? = CapturingHandler()
    guard let handler = maybeHandler else {
        print("FAIL: could not create the capturing handler")
        exit(1)
    }
    return handler
}

let handler = makeHandler()
// Swift drops the type-name suffix, so this is `current` in Swift, not `currentHandler`.
DVTAssertionReportHandler.current = handler

// A satisfied assertion must stay silent.
_DVTAssertFromSwift(true, "Overlay.swift", "satisfied", 10, "not raised", nil)
expect(handler.reports.isEmpty, "a satisfied Swift assertion is silent")

// A failing one has to reach the handler with its caller's file and line.
_DVTAssertFromSwift(false, "Overlay.swift", "failing", 42, "swift failure", "swift hints")
expect(handler.reports.count == 1, "a failing Swift assertion reports once")

if handler.reports.count == 1 {
    let report = handler.reports[0]
    print("  failure report:\n\(report)")
    expect(report.hasPrefix("ASSERTION FAILURE in Overlay.swift:42"),
           "the Swift failure names the caller's file and line")
    expectContains(report, "Details:  swift failure", "the Swift failure carries the message")
    expectContains(report, "swift hints", "the Swift failure carries the hints")
    expect(!handler.lastWasWarning, "the Swift failure is not a warning")
}

// The warning entry point is separate and must use the warning layout.
_DVTWarnFromSwift("Overlay.swift", "warning", 57, "swift warning", nil)
expect(handler.reports.count == 2, "a Swift warning reports once")
if handler.reports.count == 2 {
    let report = handler.reports[1]
    print("  warning report:\n\(report)")
    expect(report.hasPrefix("Warning in Overlay.swift:57"),
           "the Swift warning uses the warning layout")
    expect(handler.lastWasWarning, "the Swift warning is flagged as such")
}

// nil file and function must not crash; the placeholders take over.
_DVTWarnFromSwift(nil, nil, 0, nil, nil)
expect(handler.reports.count == 3, "a Swift warning with nil arguments still reports")
if handler.reports.count == 3 {
    let report = handler.reports[2]
    print("  placeholder report:\n\(report)")
    expect(report.hasPrefix("Warning in <Unknown File>:0"),
           "a nil file becomes the placeholder file name")
    expectContains(report, "Details:  <Unknown Function>",
                   "a nil function becomes the placeholder function name")
}

// Restoring the default handler has to leave one installed.
DVTAssertionReportHandler.current = nil
expect(DVTAssertionReportHandler.current != nil,
       "there is always a default handler")

print(failures == 0 ? "\nswift overlay: all checks passed" : "\nswift overlay: \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
