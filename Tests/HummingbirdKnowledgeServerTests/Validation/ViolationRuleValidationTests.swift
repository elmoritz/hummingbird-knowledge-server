// Tests/HummingbirdKnowledgeServerTests/Validation/ViolationRuleValidationTests.swift
//
// Comprehensive tests for violation rule validation script.
// Validates: required fields, regex syntax, severity values, test cases,
// correctionId references, duplicate detection, and quality checks.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class ViolationRuleValidationTests: XCTestCase {

    var tempDir: URL!
    let scriptPath = "./scripts/validate-violation-rule.swift"

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViolationRuleValidationTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func runValidator(on filePath: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [scriptPath, filePath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (process.terminationStatus, output)
        } catch {
            XCTFail("Failed to run validation script: \(error)")
            return (1, "")
        }
    }

    // MARK: - Valid Inputs

    func testValidViolationRule_Passes() {
        let validRule = """
        {
            "id": "test-violation-rule",
            "pattern": "context\\\\.db",
            "description": "This is a test violation rule that detects inline database calls in route handlers, which violates the separation of concerns principle.",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "critical",
            "testCases": {
                "positive": [
                    "router.get() { req, context in let result = try await context.db.query() }",
                    "router.post() { req, context in return try await context.db.execute() }"
                ],
                "negative": [
                    "router.get() { req, context in let service = context.dependencies.service }",
                    "func getData() async throws { let result = try await db.query() }"
                ]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("valid-rule.json")
        try? validRule.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertEqual(exitCode, 0, "Valid violation rule should pass validation")
        XCTAssertTrue(output.contains("VALIDATION PASSED"), "Output should indicate success")
    }

    // MARK: - File Errors

    func testMissingFile_ReturnsError() {
        let (exitCode, output) = runValidator(on: "/nonexistent/file.json")

        XCTAssertNotEqual(exitCode, 0, "Missing file should fail validation")
        XCTAssertTrue(output.contains("File not found") || output.contains("VALIDATION FAILED"), "Output should indicate file not found")
    }

    // MARK: - JSON Errors

    func testInvalidJSON_ReturnsError() {
        let invalidJSON = "{ invalid json }"

        let filePath = tempDir.appendingPathComponent("invalid.json")
        try? invalidJSON.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Invalid JSON should fail validation")
        XCTAssertTrue(output.contains("Invalid JSON") || output.contains("VALIDATION FAILED"), "Output should indicate JSON error")
    }

    // MARK: - Required Fields

    func testEmptyId_ReturnsError() {
        let ruleWithEmptyId = """
        {
            "id": "",
            "pattern": "test",
            "description": "Test description for validation purposes",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "error",
            "testCases": {
                "positive": ["test1", "test2"],
                "negative": ["neg1", "neg2"]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("empty-id.json")
        try? ruleWithEmptyId.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Empty id should fail validation")
        XCTAssertTrue(output.contains("Field cannot be empty: id") || output.contains("empty: id"), "Output should indicate empty id error")
    }

    func testEmptyPattern_ReturnsError() {
        let ruleWithEmptyPattern = """
        {
            "id": "test-rule",
            "pattern": "",
            "description": "Test description for validation purposes",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "error",
            "testCases": {
                "positive": ["test1", "test2"],
                "negative": ["neg1", "neg2"]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("empty-pattern.json")
        try? ruleWithEmptyPattern.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Empty pattern should fail validation")
        XCTAssertTrue(output.contains("Field cannot be empty: pattern") || output.contains("empty: pattern"), "Output should indicate empty pattern error")
    }

    func testEmptyDescription_ReturnsError() {
        let ruleWithEmptyDescription = """
        {
            "id": "test-rule",
            "pattern": "test",
            "description": "",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "error",
            "testCases": {
                "positive": ["test1", "test2"],
                "negative": ["neg1", "neg2"]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("empty-description.json")
        try? ruleWithEmptyDescription.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Empty description should fail validation")
        XCTAssertTrue(output.contains("Field cannot be empty: description") || output.contains("empty: description"), "Output should indicate empty description error")
    }

    // MARK: - Pattern Validation

    func testInvalidRegex_ReturnsError() {
        let ruleWithInvalidRegex = """
        {
            "id": "test-rule",
            "pattern": "[invalid(regex",
            "description": "Test description with invalid regex pattern for validation purposes",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "error",
            "testCases": {
                "positive": ["test1", "test2"],
                "negative": ["neg1", "neg2"]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("invalid-regex.json")
        try? ruleWithInvalidRegex.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Invalid regex should fail validation")
        XCTAssertTrue(output.contains("Invalid regex pattern") || output.contains("regex"), "Output should indicate regex error")
    }

    // MARK: - Severity Validation

    func testInvalidSeverity_ReturnsError() {
        let ruleWithInvalidSeverity = """
        {
            "id": "test-rule",
            "pattern": "test",
            "description": "Test description for validation purposes",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "invalid-severity",
            "testCases": {
                "positive": ["test1", "test2"],
                "negative": ["neg1", "neg2"]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("invalid-severity.json")
        try? ruleWithInvalidSeverity.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Invalid severity should fail validation")
        XCTAssertTrue(output.contains("Invalid severity") || output.contains("severity"), "Output should indicate severity error")
    }

    func testValidSeverities_Pass() {
        let severities = ["critical", "error", "warning"]

        for severity in severities {
            let rule = """
            {
                "id": "test-\(severity)",
                "pattern": "test",
                "description": "Test description for validation purposes with adequate length",
                "correctionId": "service-layer-no-hummingbird",
                "severity": "\(severity)",
                "testCases": {
                    "positive": ["test1", "test2"],
                    "negative": ["neg1", "neg2"]
                }
            }
            """

            let filePath = tempDir.appendingPathComponent("severity-\(severity).json")
            try? rule.write(to: filePath, atomically: true, encoding: .utf8)

            let (exitCode, output) = runValidator(on: filePath.path)

            XCTAssertEqual(exitCode, 0, "Severity '\(severity)' should be valid")
            XCTAssertTrue(output.contains("VALIDATION PASSED"), "Output should indicate success for severity \(severity)")
        }
    }

    // MARK: - Test Cases Validation

    func testInsufficientPositiveTestCases_ReturnsError() {
        let ruleWithOnePositiveCase = """
        {
            "id": "test-rule",
            "pattern": "test",
            "description": "Test description for validation purposes",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "error",
            "testCases": {
                "positive": ["test1"],
                "negative": ["neg1", "neg2"]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("insufficient-positive.json")
        try? ruleWithOnePositiveCase.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Insufficient positive test cases should fail")
        XCTAssertTrue(output.contains("Insufficient positive test cases") || output.contains("positive"), "Output should indicate insufficient positive cases")
    }

    func testInsufficientNegativeTestCases_ReturnsError() {
        let ruleWithOneNegativeCase = """
        {
            "id": "test-rule",
            "pattern": "test",
            "description": "Test description for validation purposes",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "error",
            "testCases": {
                "positive": ["test1", "test2"],
                "negative": ["neg1"]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("insufficient-negative.json")
        try? ruleWithOneNegativeCase.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Insufficient negative test cases should fail")
        XCTAssertTrue(output.contains("Insufficient negative test cases") || output.contains("negative"), "Output should indicate insufficient negative cases")
    }

    func testPositiveTestCaseDoesNotMatch_ReturnsError() {
        let ruleWithFailingPositiveCase = """
        {
            "id": "test-rule",
            "pattern": "^exact-match$",
            "description": "Test description for validation purposes",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "error",
            "testCases": {
                "positive": ["exact-match", "wrong-text"],
                "negative": ["neg1", "neg2"]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("failing-positive.json")
        try? ruleWithFailingPositiveCase.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Positive test case that doesn't match should fail")
        XCTAssertTrue(output.contains("Positive test case") || output.contains("did not match"), "Output should indicate positive case failure")
    }

    func testNegativeTestCaseMatches_ReturnsError() {
        let ruleWithFailingNegativeCase = """
        {
            "id": "test-rule",
            "pattern": "match-this",
            "description": "Test description for validation purposes",
            "correctionId": "service-layer-no-hummingbird",
            "severity": "error",
            "testCases": {
                "positive": ["match-this", "also match-this"],
                "negative": ["no-match", "contains match-this here"]
            }
        }
        """

        let filePath = tempDir.appendingPathComponent("failing-negative.json")
        try? ruleWithFailingNegativeCase.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Negative test case that matches should fail")
        XCTAssertTrue(output.contains("Negative test case") || output.contains("matched pattern but should not"), "Output should indicate negative case failure")
    }

    // MARK: - Help Text

    func testHelpFlag_ShowsUsage() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [scriptPath, "--help"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            XCTAssertEqual(process.terminationStatus, 0, "--help should exit successfully")
            XCTAssertTrue(output.contains("USAGE:"), "Help output should contain usage information")
            XCTAssertTrue(output.contains("VALIDATION CHECKS:"), "Help output should list validation checks")
        } catch {
            XCTFail("Failed to run validation script with --help: \(error)")
        }
    }
}
