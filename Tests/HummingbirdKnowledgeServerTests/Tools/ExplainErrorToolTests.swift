// Tests/HummingbirdKnowledgeServerTests/Tools/ExplainErrorToolTests.swift
//
// Comprehensive tests for ExplainErrorTool: validates error diagnosis,
// context handling, and knowledge base matching.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class ExplainErrorToolTests: XCTestCase {

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        XCTAssertEqual(tool.tool.name, "explain_error")
        XCTAssertNotNil(tool.tool.description)
        XCTAssertFalse(tool.tool.description?.isEmpty ?? true)

        // Verify input schema structure
        guard case .object(let schema) = tool.tool.inputSchema else {
            XCTFail("Input schema must be an object")
            return
        }

        // Verify required fields
        if case .array(let requiredArray) = schema["required"] {
            let requiredStrings = requiredArray.compactMap { value -> String? in
                if case .string(let s) = value { return s }
                return nil
            }
            XCTAssertTrue(requiredStrings.contains("error_message"), "error_message must be required")
            XCTAssertFalse(requiredStrings.contains("context"), "context must be optional")
            XCTAssertFalse(requiredStrings.contains("hummingbird_version"), "hummingbird_version must be optional")
        } else {
            XCTFail("Schema must have 'required' array")
        }
    }

    // MARK: - Argument Validation

    func testHandle_MissingErrorMessageArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertEqual(result.isError, true, "Should return error for missing error_message")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
            XCTAssertTrue(message.contains("error_message"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_InvalidErrorMessageType_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle(["error_message": .int(123)])

        XCTAssertEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
        }
    }

    // MARK: - Error Diagnosis with Matches

    func testHandle_ErrorWithMatches_ReturnsRelevantEntries() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "connection-error",
            title: "Database Connection Errors",
            content: "Connection refused errors typically occur when PostgresNIO cannot reach the database server. Check your connection string and ensure the database is running."
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("Connection refused to PostgreSQL database")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Error Diagnosis"))
            XCTAssertTrue(message.contains("**Error:** Connection refused"))
            XCTAssertTrue(message.contains("**Relevant knowledge entries:**"))
            XCTAssertTrue(message.contains("### Database Connection Errors"))
            XCTAssertTrue(message.contains("PostgresNIO"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_ErrorWithContext_IncludesContext() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("Type mismatch error"),
            "context": .string("Trying to decode JSON response from API")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("**Context:** Trying to decode JSON"))
        }
    }

    func testHandle_ErrorNoContext_OmitsContextSection() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("Some error")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertFalse(message.contains("**Context:**"))
        }
    }

    // MARK: - Error Diagnosis without Matches

    func testHandle_ErrorNoMatches_ProvidesSuggestions() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("ZXY123 Unknown error code from system")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No matching knowledge base entries"))
            XCTAssertTrue(message.contains("**Suggestions:**"))
            XCTAssertTrue(message.contains("check_architecture"))
            XCTAssertTrue(message.contains("report_issue"))
        }
    }

    // MARK: - Word-Based Matching

    func testHandle_WordBasedMatching_FindsRelevantEntries() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "middleware-error",
            title: "Middleware Ordering Issues",
            content: "Middleware must be registered in the correct order. DependencyInjectionMiddleware must come first."
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("Fatal error: middleware dependency not found")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Middleware Ordering Issues"))
        }
    }

    // MARK: - Multiple Matches

    func testHandle_MultipleMatches_LimitsToThree() async throws {
        let entries = (1...10).map { i in
            createMinimalKnowledgeEntry(
                id: "error-\(i)",
                title: "Database Error Pattern \(i)",
                content: "Database connection and query error information \(i)"
            )
        }
        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("Database connection error")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Count how many "###" headers appear
            let headerCount = message.components(separatedBy: "\n### ").count - 1
            XCTAssertLessThanOrEqual(headerCount, 3, "Should limit to 3 results")
        }
    }

    // MARK: - Confidence Sorting

    func testHandle_SortsByConfidence() async throws {
        let lowEntry = KnowledgeEntry(
            id: "low",
            title: "Low Confidence Error",
            content: "Error information with low confidence",
            layer: .service,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.3,
            source: "test",
            lastVerifiedAt: Date()
        )

        let highEntry = KnowledgeEntry(
            id: "high",
            title: "High Confidence Error",
            content: "Error information with high confidence",
            layer: .service,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.95,
            source: "test",
            lastVerifiedAt: Date()
        )

        let store = KnowledgeStore.forTesting(seedEntries: [lowEntry, highEntry])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("Error information")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // High confidence should appear before low confidence
            let highPos = message.range(of: "High Confidence")
            let lowPos = message.range(of: "Low Confidence")

            if let highPos = highPos, let lowPos = lowPos {
                XCTAssertLessThan(highPos.lowerBound, lowPos.lowerBound)
            }
        }
    }

    // MARK: - Case Insensitivity

    func testHandle_CaseInsensitiveMatching_Works() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test",
            title: "AppError Handling",
            content: "How to handle AppError correctly"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("APPERROR TYPE MISMATCH")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("AppError Handling"))
        }
    }

    // MARK: - Optional Arguments

    func testHandle_WithHummingbirdVersion_IgnoresIt() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        // hummingbird_version is optional and currently not used in the implementation
        let result = try await tool.handle([
            "error_message": .string("Some error"),
            "hummingbird_version": .string("2.5.0")
        ])

        XCTAssertNotEqual(result.isError, true)
    }

    func testHandle_InvalidContextType_IgnoresIt() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("Error"),
            "context": .int(123)
        ])

        XCTAssertNotEqual(result.isError, true)
    }

    // MARK: - Edge Cases

    func testHandle_EmptyErrorMessage_ReturnsNoMatches() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle(["error_message": .string("")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No matching knowledge base entries"))
        }
    }

    func testHandle_WhitespaceErrorMessage_ReturnsNoMatches() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle(["error_message": .string("   \n  \t  ")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No matching knowledge base entries"))
        }
    }

    func testHandle_VeryLongError_HandlesCorrectly() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test",
            title: "Error Pattern",
            content: "Error handling information"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = ExplainErrorTool(store: store)

        let longError = String(repeating: "Error occurred in system. ", count: 500) + " error handling"

        let result = try await tool.handle(["error_message": .string(longError)])

        XCTAssertNotEqual(result.isError, true)
    }

    func testHandle_SpecialCharacters_HandlesCorrectly() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainErrorTool(store: store)

        let result = try await tool.handle([
            "error_message": .string("Error: @#$% special ~`!@#$%^&*()_+ chars")
        ])

        XCTAssertNotEqual(result.isError, true)
    }
}
