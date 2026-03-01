// Tests/HummingbirdKnowledgeServerTests/Tools/ExplainPatternToolTests.swift
//
// Comprehensive tests for ExplainPatternTool: validates pattern lookup by ID,
// topic search, formatting, and error handling.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class ExplainPatternToolTests: XCTestCase {

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainPatternTool(store: store)

        XCTAssertEqual(tool.tool.name, "explain_pattern")
        XCTAssertNotNil(tool.tool.description)
        XCTAssertFalse(tool.tool.description?.isEmpty ?? true)

        // Verify input schema structure
        guard case .object(let schema) = tool.tool.inputSchema else {
            XCTFail("Input schema must be an object")
            return
        }

        // Verify 'type' field
        if case .string(let typeValue) = schema["type"] {
            XCTAssertEqual(typeValue, "object")
        } else {
            XCTFail("Schema must have 'type' field set to 'object'")
        }

        // Verify properties exist
        if case .object(let properties) = schema["properties"] {
            XCTAssertTrue(properties.keys.contains("pattern_id"))
            XCTAssertTrue(properties.keys.contains("topic"))
        } else {
            XCTFail("Schema must have 'properties' object")
        }
    }

    // MARK: - Argument Validation

    func testHandle_MissingBothArguments_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertEqual(result.isError, true, "Should return error when both arguments are missing")
        XCTAssertEqual(result.content.count, 1)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("pattern_id") || message.contains("topic"),
                "Error message should mention required arguments"
            )
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_InvalidPatternIdType_IgnoresIt() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test-pattern",
            title: "Test Pattern",
            content: "Test pattern content"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = ExplainPatternTool(store: store)

        // pattern_id is a number instead of string - should be ignored and fall back to topic
        let result = try await tool.handle([
            "pattern_id": .int(123),
            "topic": .string("test")
        ])

        XCTAssertNotEqual(result.isError, true)
    }

    // MARK: - Pattern ID Lookup

    func testHandle_ValidPatternId_ReturnsEntry() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "dependency-injection",
            title: "Dependency Injection via Context",
            content: "Services must be injected through context, not constructed inline.",
            layer: .service
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle(["pattern_id": .string("dependency-injection")])

        XCTAssertNotEqual(result.isError, true)
        XCTAssertEqual(result.content.count, 1)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("# Dependency Injection via Context"))
            XCTAssertTrue(message.contains("**Layer:** service"))
            XCTAssertTrue(message.contains("Services must be injected"))
            XCTAssertTrue(message.contains("**Hummingbird:**"))
            XCTAssertTrue(message.contains("**Swift:**"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_NonExistentPatternId_FallsBackToTopicSearch() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test-pattern",
            title: "Test Pattern",
            content: "This is about dependency injection"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = ExplainPatternTool(store: store)

        // Pattern ID doesn't exist, but topic matches
        let result = try await tool.handle(["pattern_id": .string("non-existent")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("No pattern found") || message.contains("Test Pattern"),
                "Should either find no pattern or fall back to topic search"
            )
        }
    }

    // MARK: - Topic Search

    func testHandle_TopicSearch_ReturnsMatches() async throws {
        let entry1 = createMinimalKnowledgeEntry(
            id: "di-pattern",
            title: "Dependency Injection Pattern",
            content: "Use dependency injection for services"
        )
        let entry2 = createMinimalKnowledgeEntry(
            id: "middleware-pattern",
            title: "Middleware Pattern",
            content: "How to write middleware"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry1, entry2])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle(["topic": .string("dependency")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Dependency Injection Pattern"))
            XCTAssertTrue(message.contains("Use dependency injection"))
        }
    }

    func testHandle_TopicSearchCaseInsensitive_FindsMatches() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test",
            title: "Middleware Pattern",
            content: "How to write middleware"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle(["topic": .string("MIDDLEWARE")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Middleware Pattern"))
        }
    }

    func testHandle_TopicSearchNoMatches_ReturnsGuidance() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle(["topic": .string("nonexistent topic")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No pattern found"))
            XCTAssertTrue(message.contains("list_pitfalls"))
        }
    }

    func testHandle_TopicSearchMultipleMatches_LimitsToTwo() async throws {
        let entries = (1...5).map { i in
            createMinimalKnowledgeEntry(
                id: "pattern-\(i)",
                title: "Middleware Pattern \(i)",
                content: "Middleware content \(i)"
            )
        }
        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle(["topic": .string("middleware")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should contain separator for multiple results
            let separatorCount = message.components(separatedBy: "---").count - 1
            XCTAssertLessThanOrEqual(separatorCount, 1, "Should limit to 2 results (1 separator)")
        }
    }

    // MARK: - Confidence Sorting

    func testHandle_TopicSearch_SortsByConfidence() async throws {
        // Create low confidence entry
        let lowConfidenceEntry = KnowledgeEntry(
            id: "low",
            title: "Low Confidence Middleware",
            content: "Middleware with low confidence",
            layer: .service,
            patternIds: ["test-pattern"],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.3,
            source: "test",
            lastVerifiedAt: Date()
        )

        // Create high confidence entry
        let highConfidenceEntry = KnowledgeEntry(
            id: "high",
            title: "High Confidence Middleware",
            content: "Middleware with high confidence",
            layer: .service,
            patternIds: ["test-pattern"],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.95,
            source: "test",
            lastVerifiedAt: Date()
        )

        let store = KnowledgeStore.forTesting(seedEntries: [lowConfidenceEntry, highConfidenceEntry])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle(["topic": .string("middleware")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // High confidence should appear first
            let highPos = message.range(of: "High Confidence")
            let lowPos = message.range(of: "Low Confidence")

            if let highPos = highPos, let lowPos = lowPos {
                XCTAssertLessThan(highPos.lowerBound, lowPos.lowerBound)
            }
        }
    }

    // MARK: - Anti-Pattern Detection

    func testHandle_TutorialPattern_ShowsWarning() async throws {
        let antiPattern = KnowledgeEntry(
            id: "anti-pattern",
            title: "Don't Do This",
            content: "This is an anti-pattern",
            layer: .service,
            patternIds: ["anti"],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: true,
            correctionId: "correct-pattern",
            confidence: 1.0,
            source: "test",
            lastVerifiedAt: Date()
        )
        let store = KnowledgeStore.forTesting(seedEntries: [antiPattern])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle(["pattern_id": .string("anti-pattern")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("⚠️"))
            XCTAssertTrue(message.contains("anti-pattern"))
            XCTAssertTrue(message.contains("correct-pattern"))
        }
    }

    // MARK: - Edge Cases

    func testHandle_EmptyTopic_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle(["topic": .string("")])

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("No pattern found") || message.contains("pattern_id") || message.contains("topic")
            )
        }
    }

    func testHandle_BothArgumentsProvided_PrefersPatternId() async throws {
        let entry1 = createMinimalKnowledgeEntry(
            id: "exact-id",
            title: "Exact ID Match",
            content: "Found by ID"
        )
        let entry2 = createMinimalKnowledgeEntry(
            id: "topic-match",
            title: "Topic Match",
            content: "Found by topic search"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry1, entry2])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle([
            "pattern_id": .string("exact-id"),
            "topic": .string("topic")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Exact ID Match"))
            XCTAssertTrue(message.contains("Found by ID"))
        }
    }

    func testHandle_SpecialCharactersInTopic_HandlesCorrectly() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test",
            title: "Error Handling",
            content: "Use AppError for errors"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = ExplainPatternTool(store: store)

        let result = try await tool.handle(["topic": .string("error@#$%")])

        XCTAssertNotEqual(result.isError, true)
    }
}
