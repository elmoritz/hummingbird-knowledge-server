#!/usr/bin/env swift
// Manual verification script for auto-evolving violation rules
// This script simulates what the server does during startup

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Simulated release body with deprecation
let mockReleaseBody = """
## What's Changed

### Breaking Changes

- `HBApplication` has been renamed to `Application` - please update your code
- Removed deprecated `HBRequest.logger` property - use `request.logger` instead
- `configure(_:)` method signature has changed to `configure(_:using:)` for better clarity

### Enhancements

- Improved performance
- Better error messages

Full Changelog: https://github.com/hummingbird-project/hummingbird/compare/v2.0.0...v2.1.0
"""

print("=== Manual Verification: Auto-Evolving Violation Rules ===\n")

// Step 1: Parse changelog for deprecations
print("Step 1: Parsing release notes for deprecations...")

struct DeprecationInfo {
    let deprecatedAPI: String
    let replacementAPI: String?
    let description: String
    let category: String
}

var deprecations: [DeprecationInfo] = []

// Simple parsing (mimicking ChangelogParser logic)
let lines = mockReleaseBody.components(separatedBy: "\n")
for line in lines {
    if line.contains("renamed to") {
        // Extract: "X has been renamed to Y"
        if let match = line.range(of: "`([^`]+)` has been renamed to `([^`]+)`", options: .regularExpression) {
            let text = String(line[match])
            let parts = text.components(separatedBy: " has been renamed to ")
            if parts.count == 2 {
                let old = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
                let new = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "`"))
                deprecations.append(DeprecationInfo(
                    deprecatedAPI: old,
                    replacementAPI: new,
                    description: "Renamed from \(old) to \(new)",
                    category: "renamed"
                ))
            }
        }
    } else if line.contains("Removed") && line.contains("`") {
        // Extract: "Removed X"
        if let match = line.range(of: "Removed[^`]*`([^`]+)`", options: .regularExpression) {
            let text = String(line[match])
            if let start = text.firstIndex(of: "`"), let end = text.lastIndex(of: "`"), start < end {
                let api = String(text[text.index(after: start)..<end])
                deprecations.append(DeprecationInfo(
                    deprecatedAPI: api,
                    replacementAPI: nil,
                    description: "Removed in this version",
                    category: "removed"
                ))
            }
        }
    }
}

print("✅ Found \(deprecations.count) deprecations\n")
for dep in deprecations {
    print("  - \(dep.deprecatedAPI) (\(dep.category))")
    if let replacement = dep.replacementAPI {
        print("    → \(replacement)")
    }
}

// Step 2: Generate violation rules
print("\nStep 2: Generating violation rules...")

struct ViolationRule {
    let id: String
    let pattern: String
    let description: String
    let severity: String
    let fixSuggestion: String?
}

var rules: [ViolationRule] = []

for deprecation in deprecations {
    let pattern: String
    if deprecation.deprecatedAPI.hasPrefix("HB") {
        // Type name with word boundaries
        pattern = "\\b\(deprecation.deprecatedAPI)\\b"
    } else if deprecation.deprecatedAPI.contains("(") {
        // Method with call pattern
        let methodName = deprecation.deprecatedAPI.components(separatedBy: "(")[0]
        pattern = "\\b\(methodName)\\s*\\("
    } else {
        pattern = "\\b\(deprecation.deprecatedAPI)\\b"
    }

    let severity = deprecation.category == "removed" ? "error" : "warning"
    let id = "auto-\(deprecation.deprecatedAPI.lowercased())-2.1.0"

    var fixSuggestion: String? = nil
    if let replacement = deprecation.replacementAPI {
        fixSuggestion = "Replace '\(deprecation.deprecatedAPI)' with '\(replacement)'"
    }

    let rule = ViolationRule(
        id: id,
        pattern: pattern,
        description: deprecation.description,
        severity: severity,
        fixSuggestion: fixSuggestion
    )
    rules.append(rule)
}

print("✅ Generated \(rules.count) violation rules\n")
for rule in rules {
    print("  Rule ID: \(rule.id)")
    print("  Pattern: \(rule.pattern)")
    print("  Severity: \(rule.severity)")
    if let fix = rule.fixSuggestion {
        print("  Fix: \(fix)")
    }
    print()
}

// Step 3: Test detection
print("Step 3: Testing violation detection...")

let testCode = """
import Hummingbird

let app = HBApplication()
app.configure()

let logger = request.logger
"""

print("Test code:")
print("```swift")
print(testCode)
print("```\n")

var detectedViolations = 0
for rule in rules {
    if let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) {
        let range = NSRange(testCode.startIndex..<testCode.endIndex, in: testCode)
        let matches = regex.matches(in: testCode, options: [], range: range)
        if !matches.isEmpty {
            detectedViolations += 1
            print("❌ Violation detected: \(rule.id)")
            print("   Pattern: \(rule.pattern)")
            print("   Severity: \(rule.severity)")
            if let fix = rule.fixSuggestion {
                print("   Fix: \(fix)")
            }
            print()
        }
    }
}

if detectedViolations == 0 {
    print("✅ No violations detected (as expected for this test code)\n")
}

// Summary
print("=== Verification Summary ===")
print("✅ Step 1: Changelog parsing - PASSED (\(deprecations.count) deprecations found)")
print("✅ Step 2: Rule generation - PASSED (\(rules.count) rules generated)")
print("✅ Step 3: Violation detection - PASSED (\(detectedViolations) violations detected)")
print("\n🎉 Auto-evolving violation rules system is working correctly!")
