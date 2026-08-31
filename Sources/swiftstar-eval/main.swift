import Foundation
import SwiftStarKit

// swiftstar-eval — the one eval CLI (P27/eval-cli), consolidating
// swiftstar-analyze, swiftstar-drive and swiftstar-agenttest.
//
// Dispatch is a registry, not a switch: each verb family lives in its own
// file and contributes a `[String: ([String]) -> Void]` of its own, merged
// below. A later task adds a verb by adding a merge line here and a new file
// — it never edits another family's handlers.
//
//   Task 6: the ten swiftstar-analyze verbs               — AnalyzeVerbs.swift
//   Task 5: `run`                                         — RunVerb.swift
//   Task 7 (lands separately): `experiment`, `verdict`     — ExperimentVerb.swift

let verbHandlers: [String: @Sendable ([String]) -> Void] = analyzeVerbHandlers
    .merging(runVerbHandlers) { a, _ in a }
    .merging(experimentVerbHandlers) { a, _ in a }

let args = CommandLine.arguments
guard args.count >= 2,
      EvalArguments.isKnownVerb(args[1]),
      let handler = verbHandlers[args[1]]
else { usage() }

handler(Array(args.dropFirst(2)))
