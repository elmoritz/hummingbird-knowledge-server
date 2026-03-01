#!/usr/bin/env swift

// validate-violation-rule.swift
//
// Validation script that verifies architectural violation rule contributions.
// Checks: required fields, regex syntax, severity values, test cases, and
// correctionId references.

import Foundation

// MARK: - Data Models

struct ViolationRuleContribution: Codable {
    let id: String
    let pattern: String
    let description: String
    let correctionId: String
    let severity: String
    let testCases: TestCases

    struct TestCases: Codable {
        let positive: [String]  // Code that should match the violation
        let negative: [String]  // Code that should NOT match
    }
}

struct KnowledgeEntry: Codable {
    let id: String
    let title: String
    let content: String
}

// MARK: - Validation Results

enum ValidationError {
    case missingFile(String)
    case invalidJSON(String)
    case missingField(String)
    case emptyField(String)
    case invalidRegex(String, Error)
    case invalidSeverity(String)
    case insufficientTestCases(String)
    case testCaseFailed(String, String)
    case correctionIdNotFound(String)
    case duplicateId(String)

    var message: String {
        switch self {
        case .missingFile(let path):
            return "File not found: \(path)"
        case .invalidJSON(let error):
            return "Invalid JSON: \(error)"
        case .missingField(let field):
            return "Missing required field: \(field)"
        case .emptyField(let field):
            return "Field cannot be empty: \(field)"
        case .invalidRegex(let pattern, let error):
            return "Invalid regex pattern '\(pattern)': \(error.localizedDescription)"
        case .invalidSeverity(let severity):
            return "Invalid severity '\(severity)'. Must be one of: critical, error, warning"
        case .insufficientTestCases(let type):
            return "Insufficient \(type) test cases. Need at least 2, got fewer."
        case .testCaseFailed(let type, let details):
            return "\(type) test case failed: \(details)"
        case .correctionIdNotFound(let id):
            return "Correction ID '\(id)' not found in knowledge base"
        case .duplicateId(let id):
            return "Violation ID '\(id)' already exists in ArchitecturalViolations"
        }
    }
}

struct ValidationResult {
    let isValid: Bool
    let errors: [ValidationError]
    let warnings: [String]

    static func success(warnings: [String] = []) -> ValidationResult {
        ValidationResult(isValid: true, errors: [], warnings: warnings)
    }

    static func failure(errors: [ValidationError], warnings: [String] = []) -> ValidationResult {
        ValidationResult(isValid: false, errors: errors, warnings: warnings)
    }
}

// MARK: - Validator

class ViolationRuleValidator {

    func validate(filePath: String) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [String] = []

        // Check file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            return .failure(errors: [.missingFile(filePath)])
        }

        // Load and parse JSON
        let contribution: ViolationRuleContribution
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoder = JSONDecoder()
            contribution = try decoder.decode(ViolationRuleContribution.self, from: data)
        } catch {
            return .failure(errors: [.invalidJSON(error.localizedDescription)])
        }

        // Validate required fields are not empty
        if contribution.id.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyField("id"))
        }
        if contribution.pattern.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyField("pattern"))
        }
        if contribution.description.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyField("description"))
        }
        if contribution.correctionId.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyField("correctionId"))
        }

        // Validate ID format (kebab-case)
        if !contribution.id.isEmpty && !isKebabCase(contribution.id) {
            warnings.append("ID should use kebab-case format: '\(contribution.id)'")
        }

        // Validate regex pattern compiles
        do {
            _ = try NSRegularExpression(pattern: contribution.pattern, options: [])
        } catch {
            errors.append(.invalidRegex(contribution.pattern, error))
        }

        // Validate severity
        let validSeverities = ["critical", "error", "warning"]
        if !validSeverities.contains(contribution.severity) {
            errors.append(.invalidSeverity(contribution.severity))
        }

        // Validate test cases count
        if contribution.testCases.positive.count < 2 {
            errors.append(.insufficientTestCases("positive"))
        }
        if contribution.testCases.negative.count < 2 {
            errors.append(.insufficientTestCases("negative"))
        }

        // Validate test cases
        if errors.isEmpty {
            // Only run test cases if pattern is valid
            let testErrors = validateTestCases(
                pattern: contribution.pattern,
                positive: contribution.testCases.positive,
                negative: contribution.testCases.negative
            )
            errors.append(contentsOf: testErrors)
        }

        // Check for duplicate ID in ArchitecturalViolations.swift
        if !contribution.id.isEmpty {
            if isDuplicateViolationId(contribution.id) {
                errors.append(.duplicateId(contribution.id))
            }
        }

        // Validate correctionId exists in knowledge base
        if !contribution.correctionId.isEmpty {
            if !correctionIdExists(contribution.correctionId) {
                errors.append(.correctionIdNotFound(contribution.correctionId))
            }
        }

        // Check description quality
        if contribution.description.count < 50 {
            warnings.append("Description is quite short (\(contribution.description.count) chars). Consider adding more context.")
        }

        return errors.isEmpty
            ? .success(warnings: warnings)
            : .failure(errors: errors, warnings: warnings)
    }

    private func isKebabCase(_ str: String) -> Bool {
        let kebabPattern = "^[a-z0-9]+(-[a-z0-9]+)*$"
        return str.range(of: kebabPattern, options: .regularExpression) != nil
    }

    private func validateTestCases(
        pattern: String,
        positive: [String],
        negative: [String]
    ) -> [ValidationError] {
        var errors: [ValidationError] = []

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return errors
        }

        // Positive cases should match
        for (index, testCode) in positive.enumerated() {
            let range = NSRange(testCode.startIndex..., in: testCode)
            let match = regex.firstMatch(in: testCode, options: [], range: range)

            if match == nil {
                errors.append(.testCaseFailed(
                    "Positive",
                    "Test case #\(index + 1) did not match pattern but should have"
                ))
            }
        }

        // Negative cases should NOT match
        for (index, testCode) in negative.enumerated() {
            let range = NSRange(testCode.startIndex..., in: testCode)
            let match = regex.firstMatch(in: testCode, options: [], range: range)

            if match != nil {
                errors.append(.testCaseFailed(
                    "Negative",
                    "Test case #\(index + 1) matched pattern but should not have"
                ))
            }
        }

        return errors
    }

    private func isDuplicateViolationId(_ id: String) -> Bool {
        // Read ArchitecturalViolations.swift and check for duplicate IDs
        let violationsPath = "Sources/HummingbirdKnowledgeServer/KnowledgeBase/ArchitecturalViolations.swift"

        guard let content = try? String(contentsOfFile: violationsPath, encoding: .utf8) else {
            return false
        }

        // Look for id: "violation-id" pattern
        let pattern = #"id:\s*"(\#(id))""#
        return content.range(of: pattern, options: .regularExpression) != nil
    }

    private func correctionIdExists(_ correctionId: String) -> Bool {
        // Read knowledge.json and check if correctionId exists
        let knowledgePath = "Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json"

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: knowledgePath)) else {
            return false
        }

        guard let entries = try? JSONDecoder().decode([KnowledgeEntry].self, from: data) else {
            return false
        }

        return entries.contains { $0.id == correctionId }
    }
}

// MARK: - Reporting

func printUsage() {
    print("""

    USAGE: validate-violation-rule.swift <path-to-json>

    Validates an architectural violation rule contribution.

    ARGUMENTS:
      <path-to-json>    Path to JSON file containing violation rule

    OPTIONS:
      --help            Show this help message

    VALIDATION CHECKS:
      ✓ Required fields present (id, pattern, description, correctionId, severity)
      ✓ Pattern is valid regex
      ✓ Severity is one of: critical, error, warning
      ✓ At least 2 positive test cases provided
      ✓ At least 2 negative test cases provided
      ✓ All positive test cases match the pattern
      ✓ All negative test cases do NOT match the pattern
      ✓ Correction ID exists in knowledge base
      ✓ No duplicate violation IDs

    JSON FORMAT:
      {
        "id": "unique-violation-id",
        "pattern": "regex-pattern",
        "description": "Clear explanation of the violation",
        "correctionId": "knowledge-base-entry-id",
        "severity": "critical",
        "testCases": {
          "positive": ["code that should match", "..."],
          "negative": ["code that should not match", "..."]
        }
      }

    EXIT CODES:
      0    Validation passed
      1    Validation failed

    """)
}

func printResult(_ result: ValidationResult, filePath: String) {
    print("═══════════════════════════════════════════════════════════════")
    print("  VIOLATION RULE VALIDATION")
    print("═══════════════════════════════════════════════════════════════\n")

    print("File: \(filePath)\n")

    if result.isValid {
        print("✅ VALIDATION PASSED\n")

        if !result.warnings.isEmpty {
            print("Warnings:")
            for warning in result.warnings {
                print("  ⚠️  \(warning)")
            }
            print()
        }

        print("All validation checks passed. This violation rule is ready to submit.")
    } else {
        print("❌ VALIDATION FAILED\n")

        print("Errors (\(result.errors.count)):")
        for error in result.errors {
            print("  ✗ \(error.message)")
        }
        print()

        if !result.warnings.isEmpty {
            print("Warnings:")
            for warning in result.warnings {
                print("  ⚠️  \(warning)")
            }
            print()
        }

        print("Please fix the errors above before submitting.")
    }

    print("═══════════════════════════════════════════════════════════════")
}

// MARK: - Main

let args = CommandLine.arguments

if args.count < 2 || args.contains("--help") || args.contains("-h") {
    printUsage()
    exit(args.contains("--help") || args.contains("-h") ? 0 : 1)
}

let filePath = args[1]
let validator = ViolationRuleValidator()
let result = validator.validate(filePath: filePath)

printResult(result, filePath: filePath)

exit(result.isValid ? 0 : 1)
