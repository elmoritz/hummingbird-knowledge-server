// Tests/HummingbirdKnowledgeServerTests/Integration/ContributionWorkflowTests.swift
//
// Integration tests for the complete contribution workflow.
// Validates the end-to-end process of submitting violation rules and knowledge
// entries, including validation, duplicate detection, and test case enforcement.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class ContributionWorkflowTests: XCTestCase {

    var tempDir: URL!
    let violationValidatorPath = "./scripts/validate-violation-rule.swift"
    let knowledgeValidatorPath = "./scripts/validate-knowledge-entry.swift"
    let checklistGeneratorPath = "./scripts/generate-pr-checklist.swift"

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContributionWorkflowTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func runScript(scriptPath: String, arguments: [String] = []) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [scriptPath] + arguments

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
            XCTFail("Failed to run script: \(error)")
            return (1, "")
        }
    }

    private func writeFile(content: String, filename: String) -> String {
        let filePath = tempDir.appendingPathComponent(filename)
        try? content.write(to: filePath, atomically: true, encoding: .utf8)
        return filePath.path
    }

    // MARK: - Violation Rule Workflow Tests

    func testValidViolationRuleContribution_PassesWorkflow() {
        // Simulate a contributor submitting a valid violation rule
        let contributionJSON = """
        {
            "id": "test-valid-contribution",
            "pattern": "router\\\\.(get|post).*\\\\{[^}]*directDBCall",
            "description": "Detects direct database calls in route handlers, which violates separation of concerns by mixing transport and data access layers.",
            "correctionId": "route-handler-dispatcher-only",
            "severity": "critical",
            "testCases": {
                "positive": [
                    "router.get(\\"/data\\") { req, ctx in let result = try await directDBCall() }",
                    "router.post(\\"/items\\") { req, ctx in return try await directDBCall(id) }"
                ],
                "negative": [
                    "router.get(\\"/data\\") { req, ctx in let service = ctx.dependencies.dataService }",
                    "router.post(\\"/items\\") { req, ctx in return try await service.create(item) }"
                ]
            }
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "valid-violation.json")

        // Step 1: Validate the contribution
        let (exitCode, output) = runScript(scriptPath: violationValidatorPath, arguments: [filePath])

        XCTAssertEqual(exitCode, 0, "Valid violation rule should pass validation")
        XCTAssertTrue(output.contains("VALIDATION PASSED"), "Output should indicate success: \(output)")

        // Step 2: Generate PR checklist
        let (checklistExitCode, checklistOutput) = runScript(
            scriptPath: checklistGeneratorPath,
            arguments: ["--type", "violation"]
        )

        XCTAssertEqual(checklistExitCode, 0, "Checklist generation should succeed")
        XCTAssertTrue(checklistOutput.contains("Review Checklist"), "Checklist should be generated")
    }

    func testInvalidViolationRuleContribution_FailsWorkflow() {
        // Simulate a contributor submitting an invalid violation rule (missing required fields)
        let contributionJSON = """
        {
            "id": "test-invalid-contribution",
            "pattern": "somePattern",
            "description": "Missing severity, correctionId, and insufficient test cases"
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "invalid-violation.json")

        // Step 1: Validate the contribution
        let (exitCode, output) = runScript(scriptPath: violationValidatorPath, arguments: [filePath])

        XCTAssertNotEqual(exitCode, 0, "Invalid violation rule should fail validation")
        XCTAssertTrue(output.contains("VALIDATION FAILED"), "Output should indicate failure: \(output)")
        XCTAssertTrue(
            output.contains("Invalid JSON") || output.contains("missing"),
            "Output should indicate JSON parsing error: \(output)"
        )
    }

    func testViolationRuleWithInvalidRegex_FailsWorkflow() {
        // Test that invalid regex patterns are caught
        let contributionJSON = """
        {
            "id": "test-invalid-regex",
            "pattern": "[invalid(regex",
            "description": "This rule has an invalid regex pattern that won't compile.",
            "correctionId": "route-handler-dispatcher-only",
            "severity": "error",
            "testCases": {
                "positive": ["test1", "test2"],
                "negative": ["test3", "test4"]
            }
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "invalid-regex.json")
        let (exitCode, output) = runScript(scriptPath: violationValidatorPath, arguments: [filePath])

        XCTAssertNotEqual(exitCode, 0, "Invalid regex should fail validation")
        XCTAssertTrue(
            output.contains("Invalid regex pattern") || output.contains("regex"),
            "Output should indicate regex error: \(output)"
        )
    }

    func testViolationRuleWithInsufficientTestCases_FailsWorkflow() {
        // Test that insufficient test cases are caught (need 2+ positive and 2+ negative)
        let contributionJSON = """
        {
            "id": "test-insufficient-tests",
            "pattern": "testPattern",
            "description": "This rule doesn't have enough test cases to verify pattern accuracy.",
            "correctionId": "route-handler-dispatcher-only",
            "severity": "warning",
            "testCases": {
                "positive": ["test1"],
                "negative": ["test2"]
            }
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "insufficient-tests.json")
        let (exitCode, output) = runScript(scriptPath: violationValidatorPath, arguments: [filePath])

        XCTAssertNotEqual(exitCode, 0, "Insufficient test cases should fail validation")
        XCTAssertTrue(
            output.contains("Insufficient") || output.contains("at least 2"),
            "Output should indicate insufficient test cases: \(output)"
        )
    }

    func testViolationRuleWithInvalidSeverity_FailsWorkflow() {
        // Test that invalid severity values are caught
        let contributionJSON = """
        {
            "id": "test-invalid-severity",
            "pattern": "testPattern",
            "description": "This rule has an invalid severity value that's not critical, error, or warning.",
            "correctionId": "route-handler-dispatcher-only",
            "severity": "medium",
            "testCases": {
                "positive": ["test1", "test2"],
                "negative": ["test3", "test4"]
            }
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "invalid-severity.json")
        let (exitCode, output) = runScript(scriptPath: violationValidatorPath, arguments: [filePath])

        XCTAssertNotEqual(exitCode, 0, "Invalid severity should fail validation")
        XCTAssertTrue(
            output.contains("Invalid severity") || output.contains("critical, error, warning"),
            "Output should indicate invalid severity: \(output)"
        )
    }

    // MARK: - Knowledge Entry Workflow Tests

    func testValidKnowledgeEntryContribution_PassesWorkflow() {
        // Simulate a contributor submitting a valid knowledge entry
        let contributionJSON = """
        {
            "id": "test-valid-knowledge-contribution",
            "title": "Proper Service Layer Pattern in Hummingbird",
            "content": "Services should be injected via dependency container, not constructed in route handlers.\\n\\n✅ Correct — inject service via container:\\n```swift\\nstruct AppDependencies {\\n    let userService: UserService\\n}\\n```\\n\\n❌ Wrong — constructing service in handler:\\n```swift\\nrouter.get(\\"/users\\") { req, ctx in\\n    let service = UserService()\\n}\\n```",
            "layer": "service",
            "patternIds": ["dependency-injection"],
            "violationIds": ["service-construction-in-handler"],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.95,
            "source": "contribution-test",
            "lastVerifiedAt": "2026-03-01T00:00:00Z"
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "valid-knowledge.json")

        // Step 1: Validate the contribution (skip compilation for speed in tests)
        let (exitCode, output) = runScript(
            scriptPath: knowledgeValidatorPath,
            arguments: [filePath, "--skip-compile"]
        )

        XCTAssertEqual(exitCode, 0, "Valid knowledge entry should pass validation")
        XCTAssertTrue(output.contains("VALIDATION PASSED"), "Output should indicate success: \(output)")

        // Step 2: Generate PR checklist
        let (checklistExitCode, checklistOutput) = runScript(
            scriptPath: checklistGeneratorPath,
            arguments: ["--type", "knowledge"]
        )

        XCTAssertEqual(checklistExitCode, 0, "Checklist generation should succeed")
        XCTAssertTrue(checklistOutput.contains("Review Checklist"), "Checklist should be generated")
    }

    func testInvalidKnowledgeEntryContribution_FailsWorkflow() {
        // Simulate a contributor submitting an invalid knowledge entry (missing required fields)
        let contributionJSON = """
        {
            "id": "test-invalid-knowledge",
            "title": "Invalid Entry",
            "content": "This entry is missing source field and has invalid confidence"
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "invalid-knowledge.json")

        // Step 1: Validate the contribution
        let (exitCode, output) = runScript(
            scriptPath: knowledgeValidatorPath,
            arguments: [filePath, "--skip-compile"]
        )

        XCTAssertNotEqual(exitCode, 0, "Invalid knowledge entry should fail validation")
        XCTAssertTrue(output.contains("VALIDATION FAILED"), "Output should indicate failure: \(output)")
        XCTAssertTrue(
            output.contains("Invalid JSON") || output.contains("missing"),
            "Output should indicate JSON parsing error: \(output)"
        )
    }

    func testKnowledgeEntryWithInvalidLayer_FailsWorkflow() {
        // Test that invalid layer values are caught
        let contributionJSON = """
        {
            "id": "test-invalid-layer",
            "title": "Test Entry",
            "content": "Test content with invalid layer value",
            "layer": "invalid-layer",
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.8,
            "source": "test"
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "invalid-layer.json")
        let (exitCode, output) = runScript(
            scriptPath: knowledgeValidatorPath,
            arguments: [filePath, "--skip-compile"]
        )

        XCTAssertNotEqual(exitCode, 0, "Invalid layer should fail validation")
        XCTAssertTrue(
            output.contains("Invalid layer") || output.contains("controller, service"),
            "Output should indicate invalid layer: \(output)"
        )
    }

    func testKnowledgeEntryWithInvalidConfidence_FailsWorkflow() {
        // Test that confidence values outside 0.0-1.0 are caught
        let contributionJSON = """
        {
            "id": "test-invalid-confidence",
            "title": "Test Entry",
            "content": "Test content with invalid confidence value",
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 1.5,
            "source": "test"
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "invalid-confidence.json")
        let (exitCode, output) = runScript(
            scriptPath: knowledgeValidatorPath,
            arguments: [filePath, "--skip-compile"]
        )

        XCTAssertNotEqual(exitCode, 0, "Invalid confidence value should fail validation")
        XCTAssertTrue(
            output.contains("confidence") && (output.contains("0.0") || output.contains("1.0")),
            "Output should indicate invalid confidence range: \(output)"
        )
    }

    func testKnowledgeEntryWithInvalidVersionRange_FailsWorkflow() {
        // Test that invalid version ranges are caught
        let contributionJSON = """
        {
            "id": "test-invalid-version",
            "title": "Test Entry",
            "content": "Test content with invalid version range format",
            "hummingbirdVersionRange": "not-a-version",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.9,
            "source": "test"
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "invalid-version.json")
        let (exitCode, output) = runScript(
            scriptPath: knowledgeValidatorPath,
            arguments: [filePath, "--skip-compile"]
        )

        XCTAssertNotEqual(exitCode, 0, "Invalid version range should fail validation")
        XCTAssertTrue(
            output.contains("Invalid version range") || output.contains("semver"),
            "Output should indicate invalid version range: \(output)"
        )
    }

    func testTutorialPatternWithoutCorrectionId_FailsWorkflow() {
        // Test that tutorial patterns require a correctionId
        let contributionJSON = """
        {
            "id": "test-tutorial-no-correction",
            "title": "Tutorial Pattern",
            "content": "This is a tutorial pattern but missing correctionId",
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": true,
            "correctionId": null,
            "confidence": 0.9,
            "source": "test"
        }
        """

        let filePath = writeFile(content: contributionJSON, filename: "tutorial-no-correction.json")
        let (exitCode, output) = runScript(
            scriptPath: knowledgeValidatorPath,
            arguments: [filePath, "--skip-compile"]
        )

        XCTAssertNotEqual(exitCode, 0, "Tutorial pattern without correctionId should fail validation")
        XCTAssertTrue(
            output.contains("correctionId is required") || output.contains("tutorial"),
            "Output should indicate missing correctionId: \(output)"
        )
    }

    // MARK: - Complete Workflow Integration Tests

    func testCompleteViolationRuleWorkflow_WithFixtures() {
        // Test using the actual fixture files
        let validFixturePath = "./Tests/HummingbirdKnowledgeServerTests/Fixtures/valid-violation-rule.json"
        let invalidFixturePath = "./Tests/HummingbirdKnowledgeServerTests/Fixtures/invalid-violation-rule.json"

        // Valid fixture should pass
        let (validExitCode, validOutput) = runScript(
            scriptPath: violationValidatorPath,
            arguments: [validFixturePath]
        )
        XCTAssertEqual(validExitCode, 0, "Valid fixture should pass validation")
        XCTAssertTrue(validOutput.contains("VALIDATION PASSED"), "Valid fixture output: \(validOutput)")

        // Invalid fixture should fail
        let (invalidExitCode, invalidOutput) = runScript(
            scriptPath: violationValidatorPath,
            arguments: [invalidFixturePath]
        )
        XCTAssertNotEqual(invalidExitCode, 0, "Invalid fixture should fail validation")
        XCTAssertTrue(invalidOutput.contains("VALIDATION FAILED"), "Invalid fixture output: \(invalidOutput)")
    }

    func testCompleteKnowledgeEntryWorkflow_WithFixtures() {
        // Test using the actual fixture files
        let validFixturePath = "./Tests/HummingbirdKnowledgeServerTests/Fixtures/valid-knowledge-entry.json"
        let invalidFixturePath = "./Tests/HummingbirdKnowledgeServerTests/Fixtures/invalid-knowledge-entry.json"

        // Valid fixture should pass (skip compilation for speed)
        let (validExitCode, validOutput) = runScript(
            scriptPath: knowledgeValidatorPath,
            arguments: [validFixturePath, "--skip-compile"]
        )
        XCTAssertEqual(validExitCode, 0, "Valid fixture should pass validation")
        XCTAssertTrue(validOutput.contains("VALIDATION PASSED"), "Valid fixture output: \(validOutput)")

        // Invalid fixture should fail
        let (invalidExitCode, invalidOutput) = runScript(
            scriptPath: knowledgeValidatorPath,
            arguments: [invalidFixturePath, "--skip-compile"]
        )
        XCTAssertNotEqual(invalidExitCode, 0, "Invalid fixture should fail validation")
        XCTAssertTrue(invalidOutput.contains("VALIDATION FAILED"), "Invalid fixture output: \(invalidOutput)")
    }

    func testPRChecklistGeneration_ForBothTypes() {
        // Test that PR checklists can be generated for both contribution types

        // Generate violation checklist
        let (violationExitCode, violationOutput) = runScript(
            scriptPath: checklistGeneratorPath,
            arguments: ["--type", "violation"]
        )
        XCTAssertEqual(violationExitCode, 0, "Violation checklist should generate successfully")
        XCTAssertTrue(violationOutput.contains("Review Checklist"), "Should contain checklist header")
        XCTAssertTrue(violationOutput.contains("- [ ]"), "Should contain checkbox items")
        XCTAssertTrue(
            violationOutput.contains("regex") || violationOutput.contains("pattern"),
            "Should contain violation-specific checks"
        )

        // Generate knowledge checklist
        let (knowledgeExitCode, knowledgeOutput) = runScript(
            scriptPath: checklistGeneratorPath,
            arguments: ["--type", "knowledge"]
        )
        XCTAssertEqual(knowledgeExitCode, 0, "Knowledge checklist should generate successfully")
        XCTAssertTrue(knowledgeOutput.contains("Review Checklist"), "Should contain checklist header")
        XCTAssertTrue(knowledgeOutput.contains("- [ ]"), "Should contain checkbox items")
        XCTAssertTrue(
            knowledgeOutput.contains("code") || knowledgeOutput.contains("example"),
            "Should contain knowledge-specific checks"
        )
    }

    func testValidationScripts_ProvideHelpfulErrorMessages() {
        // Test that validation scripts provide helpful error messages

        // Create a rule with multiple errors
        let multiErrorJSON = """
        {
            "id": "INVALID_ID_FORMAT",
            "pattern": "[invalid(regex",
            "description": "Short",
            "correctionId": "nonexistent-correction",
            "severity": "invalid-severity",
            "testCases": {
                "positive": ["test1"],
                "negative": []
            }
        }
        """

        let filePath = writeFile(content: multiErrorJSON, filename: "multi-error.json")
        let (exitCode, output) = runScript(scriptPath: violationValidatorPath, arguments: [filePath])

        XCTAssertNotEqual(exitCode, 0, "Multiple errors should fail validation")

        // Check that output contains helpful information about multiple errors
        XCTAssertTrue(output.contains("VALIDATION FAILED"), "Should indicate failure")

        // The output should mention at least some of the errors
        let errorIndicators = [
            output.contains("regex"),
            output.contains("severity"),
            output.contains("test"),
            output.contains("correction")
        ]
        let errorCount = errorIndicators.filter { $0 }.count
        XCTAssertGreaterThan(errorCount, 1, "Should report multiple error types: \(output)")
    }

    func testEndToEndWorkflow_SimulatesContributorExperience() {
        // Simulate the complete workflow a contributor would experience:
        // 1. Write contribution JSON
        // 2. Run local validation
        // 3. Receive feedback
        // 4. Fix issues
        // 5. Validation passes

        // Step 1: Initial contribution with an error (missing test case)
        let initialContribution = """
        {
            "id": "contributor-test-rule",
            "pattern": "badPattern",
            "description": "A rule submitted by a contributor learning the process.",
            "correctionId": "route-handler-dispatcher-only",
            "severity": "error",
            "testCases": {
                "positive": ["code with badPattern in it"],
                "negative": ["code with goodPattern in it", "completely different code"]
            }
        }
        """

        let filePath = writeFile(content: initialContribution, filename: "contributor-rule.json")

        // Step 2: Run validation - should fail
        let (firstExitCode, firstOutput) = runScript(scriptPath: violationValidatorPath, arguments: [filePath])
        XCTAssertNotEqual(firstExitCode, 0, "Initial contribution should fail due to insufficient positive test cases")
        XCTAssertTrue(
            firstOutput.contains("positive") || firstOutput.contains("at least 2"),
            "Should provide feedback about test cases"
        )

        // Step 3: Fix the issue (add another positive test case)
        let fixedContribution = """
        {
            "id": "contributor-test-rule",
            "pattern": "badPattern",
            "description": "A rule submitted by a contributor learning the process, now with proper test coverage.",
            "correctionId": "route-handler-dispatcher-only",
            "severity": "error",
            "testCases": {
                "positive": ["code with badPattern in it", "another badPattern example"],
                "negative": ["code with goodPattern in it", "completely different code"]
            }
        }
        """

        try? fixedContribution.write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)

        // Step 4: Run validation again - should pass
        let (secondExitCode, secondOutput) = runScript(scriptPath: violationValidatorPath, arguments: [filePath])
        XCTAssertEqual(secondExitCode, 0, "Fixed contribution should pass validation")
        XCTAssertTrue(secondOutput.contains("VALIDATION PASSED"), "Should indicate success after fix")
    }
}
