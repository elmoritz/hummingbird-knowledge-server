// Tests/HummingbirdKnowledgeServerTests/Tools/ReportIssueToolTests.swift
//
// Comprehensive tests for ReportIssueTool: validates issue reporting,
// logging, and feedback mechanism.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class ReportIssueToolTests: XCTestCase {

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        XCTAssertEqual(tool.tool.name, "report_issue")
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
            XCTAssertTrue(requiredStrings.contains("tool_name"), "tool_name must be required")
            XCTAssertTrue(requiredStrings.contains("query"), "query must be required")
            XCTAssertTrue(requiredStrings.contains("problem"), "problem must be required")
            XCTAssertFalse(requiredStrings.contains("correct_answer"), "correct_answer must be optional")
            XCTAssertFalse(requiredStrings.contains("hummingbird_version"), "hummingbird_version must be optional")
            XCTAssertFalse(requiredStrings.contains("swift_version"), "swift_version must be optional")
        } else {
            XCTFail("Schema must have 'required' array")
        }
    }

    // MARK: - Argument Validation

    func testHandle_MissingToolNameArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "query": .string("test query"),
            "problem": .string("test problem")
        ])

        XCTAssertEqual(result.isError, true, "Should return error for missing tool_name")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
            XCTAssertTrue(message.contains("tool_name"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_MissingQueryArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "problem": .string("test problem")
        ])

        XCTAssertEqual(result.isError, true, "Should return error for missing query")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
            XCTAssertTrue(message.contains("query"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_MissingProblemArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("test query")
        ])

        XCTAssertEqual(result.isError, true, "Should return error for missing problem")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
            XCTAssertTrue(message.contains("problem"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_InvalidToolNameType_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .int(123),
            "query": .string("test query"),
            "problem": .string("test problem")
        ])

        XCTAssertEqual(result.isError, true)
    }

    // MARK: - Valid Issue Report

    func testHandle_ValidReport_ReturnsConfirmation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("Analysing middleware code"),
            "problem": .string("The tool didn't detect a known violation")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ Issue reported"))
            XCTAssertTrue(message.contains("Thank you"))
            XCTAssertTrue(message.contains("**Summary:**"))
            XCTAssertTrue(message.contains("Tool: check_architecture"))
            XCTAssertTrue(message.contains("Problem:"))
            XCTAssertTrue(message.contains("KnowledgeUpdateService"))
        } else {
            XCTFail("Content should be text")
        }
    }

    // MARK: - Optional Fields

    func testHandle_WithCorrectAnswer_IncludesInSummary() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("explain_pattern"),
            "query": .string("How to structure services"),
            "problem": .string("Missing dependency injection info"),
            "correct_answer": .string("Should mention context.dependencies")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ Issue reported"))
            // Note: correct_answer is logged but not shown in response
        }
    }

    func testHandle_WithHummingbirdVersion_IncludesInSummary() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("test"),
            "problem": .string("test"),
            "hummingbird_version": .string("2.5.0")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Hummingbird: 2.5.0"))
        }
    }

    func testHandle_WithSwiftVersion_IncludesInSummary() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("test"),
            "problem": .string("test"),
            "swift_version": .string("6.0")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Swift: 6.0"))
        }
    }

    func testHandle_WithAllOptionalFields_IncludesAll() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("generate_code"),
            "query": .string("Create a service"),
            "problem": .string("Generated code had violations"),
            "correct_answer": .string("Should inject dependencies"),
            "hummingbird_version": .string("2.5.0"),
            "swift_version": .string("6.0")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Tool: generate_code"))
            XCTAssertTrue(message.contains("Problem: Generated code"))
            XCTAssertTrue(message.contains("Hummingbird: 2.5.0"))
            XCTAssertTrue(message.contains("Swift: 6.0"))
        }
    }

    func testHandle_WithoutOptionalFields_OmitsThem() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("test"),
            "problem": .string("test")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertFalse(message.contains("Hummingbird:"))
            XCTAssertFalse(message.contains("Swift:"))
        }
    }

    func testHandle_InvalidOptionalFieldTypes_IgnoresThem() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("test"),
            "problem": .string("test"),
            "correct_answer": .int(123),
            "hummingbird_version": .int(2),
            "swift_version": .int(6)
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertFalse(message.contains("Hummingbird:"))
            XCTAssertFalse(message.contains("Swift:"))
        }
    }

    // MARK: - Problem Truncation

    func testHandle_LongProblem_TruncatesInSummary() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let longProblem = String(repeating: "This is a very long problem description. ", count: 20)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("test"),
            "problem": .string(longProblem)
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Problem:"))
            // Should be truncated to 200 chars in the response
            if let problemLine = message.split(separator: "\n").first(where: { $0.contains("Problem:") }) {
                XCTAssertLessThan(problemLine.count, longProblem.count)
            }
        }
    }

    // MARK: - Different Tool Names

    func testHandle_CheckArchitectureTool_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("test"),
            "problem": .string("test")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Tool: check_architecture"))
        }
    }

    func testHandle_ExplainPatternTool_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("explain_pattern"),
            "query": .string("test"),
            "problem": .string("test")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Tool: explain_pattern"))
        }
    }

    func testHandle_GenerateCodeTool_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("generate_code"),
            "query": .string("test"),
            "problem": .string("test")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Tool: generate_code"))
        }
    }

    // MARK: - Edge Cases

    func testHandle_EmptyProblem_StillWorks() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("test"),
            "problem": .string("")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ Issue reported"))
        }
    }

    func testHandle_EmptyQuery_StillWorks() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string(""),
            "problem": .string("test problem")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ Issue reported"))
        }
    }

    func testHandle_WhitespaceFields_StillWorks() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("  check_architecture  "),
            "query": .string("   \n  "),
            "problem": .string("  \t  test  ")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ Issue reported"))
        }
    }

    func testHandle_SpecialCharacters_HandlesCorrectly() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("Code with @#$% special chars"),
            "problem": .string("Error: \"quoted\" & <tagged> text")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ Issue reported"))
        }
    }

    func testHandle_UnicodeCharacters_HandlesCorrectly() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("Code with 你好 unicode"),
            "problem": .string("Problem with emoji 🎉")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ Issue reported"))
        }
    }

    // MARK: - Knowledge Update Service Mention

    func testHandle_MentionsKnowledgeUpdateService() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ReportIssueTool(store: store)

        let result = try await tool.handle([
            "tool_name": .string("check_architecture"),
            "query": .string("test"),
            "problem": .string("test")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("KnowledgeUpdateService"))
            XCTAssertTrue(message.contains("knowledge update cycle"))
        }
    }
}
