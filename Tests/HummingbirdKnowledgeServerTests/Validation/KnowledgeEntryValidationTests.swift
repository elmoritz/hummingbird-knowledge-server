// Tests/HummingbirdKnowledgeServerTests/Validation/KnowledgeEntryValidationTests.swift
//
// Comprehensive tests for knowledge entry validation script.
// Validates: required fields, layer values, version ranges, confidence values,
// correctionId logic, code compilation, and quality checks.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class KnowledgeEntryValidationTests: XCTestCase {

    var tempDir: URL!
    let scriptPath = "./scripts/validate-knowledge-entry.swift"

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowledgeEntryValidationTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func runValidator(on filePath: String, skipCompile: Bool = true) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")

        var args = [scriptPath, filePath]
        if skipCompile {
            args.append("--skip-compile")
        }
        process.arguments = args

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

    func testValidKnowledgeEntry_Passes() {
        let validEntry = """
        {
            "id": "test-knowledge-entry",
            "title": "Test Knowledge Entry Title",
            "content": "This is a comprehensive test knowledge entry that provides detailed information about a specific pattern or practice in Hummingbird development. It includes sufficient context and explanation.",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.95,
            "source": "community-contribution",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("valid-entry.json")
        try? validEntry.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertEqual(exitCode, 0, "Valid knowledge entry should pass validation")
        XCTAssertTrue(output.contains("VALIDATION PASSED"), "Output should indicate success")
    }

    func testValidEntryWithTutorialPattern_Passes() {
        let validTutorialEntry = """
        {
            "id": "test-tutorial-pattern",
            "title": "Test Tutorial Pattern Entry",
            "content": "This is a comprehensive tutorial pattern entry that provides detailed guidance on implementing a specific pattern correctly. It includes examples and best practices for developers.",
            "layer": "controller",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": true,
            "correctionId": "service-layer-no-hummingbird",
            "confidence": 0.98,
            "source": "community-contribution",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("valid-tutorial.json")
        try? validTutorialEntry.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertEqual(exitCode, 0, "Valid tutorial pattern entry should pass")
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
        let entryWithEmptyId = """
        {
            "id": "",
            "title": "Test Entry Title",
            "content": "This is test content with adequate length to pass validation checks",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.95,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("empty-id.json")
        try? entryWithEmptyId.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Empty id should fail validation")
        XCTAssertTrue(output.contains("Field cannot be empty: id") || output.contains("empty: id"), "Output should indicate empty id error")
    }

    func testEmptyTitle_ReturnsError() {
        let entryWithEmptyTitle = """
        {
            "id": "test-entry",
            "title": "",
            "content": "This is test content with adequate length to pass validation checks",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.95,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("empty-title.json")
        try? entryWithEmptyTitle.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Empty title should fail validation")
        XCTAssertTrue(output.contains("Field cannot be empty: title") || output.contains("empty: title"), "Output should indicate empty title error")
    }

    func testEmptyContent_ReturnsError() {
        let entryWithEmptyContent = """
        {
            "id": "test-entry",
            "title": "Test Entry Title",
            "content": "",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.95,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("empty-content.json")
        try? entryWithEmptyContent.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Empty content should fail validation")
        XCTAssertTrue(output.contains("Content field cannot be empty") || output.contains("empty"), "Output should indicate empty content error")
    }

    // MARK: - Layer Validation

    func testInvalidLayer_ReturnsError() {
        let entryWithInvalidLayer = """
        {
            "id": "test-entry",
            "title": "Test Entry Title",
            "content": "This is test content with adequate length to pass validation checks",
            "layer": "invalid-layer",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.95,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("invalid-layer.json")
        try? entryWithInvalidLayer.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Invalid layer should fail validation")
        XCTAssertTrue(output.contains("Invalid layer") || output.contains("layer"), "Output should indicate layer error")
    }

    func testValidLayers_Pass() {
        let validLayers = ["controller", "service", "repository", "model"]

        for layer in validLayers {
            let entry = """
            {
                "id": "test-\(layer)",
                "title": "Test \(layer.capitalized) Entry",
                "content": "This is comprehensive test content with adequate length to pass validation checks for layer testing",
                "layer": "\(layer)",
                "patternIds": [],
                "violationIds": [],
                "hummingbirdVersionRange": ">=2.0.0",
                "swiftVersionRange": ">=6.0",
                "isTutorialPattern": false,
                "correctionId": null,
                "confidence": 0.95,
                "source": "test",
                "lastVerifiedAt": null
            }
            """

            let filePath = tempDir.appendingPathComponent("layer-\(layer).json")
            try? entry.write(to: filePath, atomically: true, encoding: .utf8)

            let (exitCode, output) = runValidator(on: filePath.path)

            XCTAssertEqual(exitCode, 0, "Layer '\(layer)' should be valid")
            XCTAssertTrue(output.contains("VALIDATION PASSED"), "Output should indicate success for layer \(layer)")
        }
    }

    // MARK: - Version Range Validation

    func testInvalidHummingbirdVersionRange_ReturnsError() {
        let entryWithInvalidVersion = """
        {
            "id": "test-entry",
            "title": "Test Entry Title",
            "content": "This is test content with adequate length to pass validation checks",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": "invalid-version",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.95,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("invalid-hb-version.json")
        try? entryWithInvalidVersion.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Invalid version range should fail")
        XCTAssertTrue(output.contains("Invalid version range") || output.contains("version"), "Output should indicate version error")
    }

    func testInvalidSwiftVersionRange_ReturnsError() {
        let entryWithInvalidVersion = """
        {
            "id": "test-entry",
            "title": "Test Entry Title",
            "content": "This is test content with adequate length to pass validation checks",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": "invalid",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.95,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("invalid-swift-version.json")
        try? entryWithInvalidVersion.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Invalid version range should fail")
        XCTAssertTrue(output.contains("Invalid version range") || output.contains("version"), "Output should indicate version error")
    }

    // MARK: - Confidence Validation

    func testInvalidConfidence_TooLow_ReturnsError() {
        let entryWithLowConfidence = """
        {
            "id": "test-entry",
            "title": "Test Entry Title",
            "content": "This is test content with adequate length to pass validation checks",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": -0.1,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("low-confidence.json")
        try? entryWithLowConfidence.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Confidence below 0.0 should fail")
        XCTAssertTrue(output.contains("Invalid confidence") || output.contains("confidence"), "Output should indicate confidence error")
    }

    func testInvalidConfidence_TooHigh_ReturnsError() {
        let entryWithHighConfidence = """
        {
            "id": "test-entry",
            "title": "Test Entry Title",
            "content": "This is test content with adequate length to pass validation checks",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 1.5,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("high-confidence.json")
        try? entryWithHighConfidence.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Confidence above 1.0 should fail")
        XCTAssertTrue(output.contains("Invalid confidence") || output.contains("confidence"), "Output should indicate confidence error")
    }

    // MARK: - CorrectionId Logic Validation

    func testTutorialPattern_MissingCorrectionId_ReturnsError() {
        let tutorialWithoutCorrectionId = """
        {
            "id": "test-entry",
            "title": "Test Tutorial Entry",
            "content": "This is comprehensive test content with adequate length to pass validation checks",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": true,
            "correctionId": null,
            "confidence": 0.95,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("tutorial-no-correction.json")
        try? tutorialWithoutCorrectionId.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Tutorial pattern without correctionId should fail")
        XCTAssertTrue(output.contains("correctionId is required") || output.contains("correctionId"), "Output should indicate missing correctionId")
    }

    func testNonTutorialPattern_WithCorrectionId_ReturnsError() {
        let nonTutorialWithCorrectionId = """
        {
            "id": "test-entry",
            "title": "Test Non-Tutorial Entry",
            "content": "This is comprehensive test content with adequate length to pass validation checks",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": "some-correction-id",
            "confidence": 0.95,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("non-tutorial-with-correction.json")
        try? nonTutorialWithCorrectionId.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path)

        XCTAssertNotEqual(exitCode, 0, "Non-tutorial pattern with correctionId should fail")
        XCTAssertTrue(output.contains("correctionId should be null") || output.contains("correctionId"), "Output should indicate unnecessary correctionId")
    }

    // MARK: - Skip Compilation Flag

    func testSkipCompilation_Flag() {
        let entryWithCode = """
        {
            "id": "test-entry",
            "title": "Test Entry With Code",
            "content": "Example with potentially invalid code that we skip compiling",
            "layer": "service",
            "patternIds": [],
            "violationIds": [],
            "hummingbirdVersionRange": ">=2.0.0",
            "swiftVersionRange": ">=6.0",
            "isTutorialPattern": false,
            "correctionId": null,
            "confidence": 0.95,
            "source": "test",
            "lastVerifiedAt": null
        }
        """

        let filePath = tempDir.appendingPathComponent("entry-with-code.json")
        try? entryWithCode.write(to: filePath, atomically: true, encoding: .utf8)

        let (exitCode, output) = runValidator(on: filePath.path, skipCompile: true)

        // With skipCompilation, should focus on format validation only
        XCTAssertEqual(exitCode, 0, "Should pass when compilation is skipped")
        XCTAssertTrue(output.contains("VALIDATION PASSED"), "Output should indicate success")
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
            XCTAssertTrue(output.contains("--skip-compile"), "Help output should mention --skip-compile option")
        } catch {
            XCTFail("Failed to run validation script with --help: \(error)")
        }
    }
}
