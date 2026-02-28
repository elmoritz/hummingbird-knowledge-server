// Tests/HummingbirdKnowledgeServerTests/Tools/GetBestPracticeToolTests.swift
//
// Comprehensive tests for GetBestPracticeTool: validates topic search,
// layer filtering, and anti-pattern exclusion.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class GetBestPracticeToolTests: XCTestCase {

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GetBestPracticeTool(store: store)

        XCTAssertEqual(tool.tool.name, "get_best_practice")
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
            XCTAssertTrue(requiredStrings.contains("topic"), "topic must be required")
            XCTAssertFalse(requiredStrings.contains("layer"), "layer must be optional")
        } else {
            XCTFail("Schema must have 'required' array")
        }
    }

    // MARK: - Argument Validation

    func testHandle_MissingTopicArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertEqual(result.isError, true, "Should return error for missing topic argument")
        XCTAssertEqual(result.content.count, 1)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
            XCTAssertTrue(message.contains("topic"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_InvalidTopicType_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .int(123)])

        XCTAssertEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
        }
    }

    // MARK: - Topic Search

    func testHandle_ValidTopic_ReturnsMatches() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "error-handling",
            title: "Error Handling Best Practice",
            content: "Always use AppError for typed errors in Hummingbird 2.x"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .string("error handling")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("# Best Practice: error handling"))
            XCTAssertTrue(message.contains("## Error Handling Best Practice"))
            XCTAssertTrue(message.contains("Always use AppError"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_TopicCaseInsensitive_FindsMatches() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test",
            title: "Dependency Injection",
            content: "Use DI for services"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .string("DEPENDENCY")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Dependency Injection"))
        }
    }

    func testHandle_TopicNotFound_ReturnsGuidance() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .string("nonexistent topic")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No best practice found"))
            XCTAssertTrue(message.contains("list_pitfalls"))
        }
    }

    // MARK: - Layer Filtering

    func testHandle_WithLayerFilter_ReturnsOnlyMatchingLayer() async throws {
        let serviceEntry = createMinimalKnowledgeEntry(
            id: "service-pattern",
            title: "Service Layer Pattern",
            content: "Service layer best practices",
            layer: .service
        )
        let controllerEntry = createMinimalKnowledgeEntry(
            id: "controller-pattern",
            title: "Controller Pattern",
            content: "Controller layer best practices",
            layer: .controller
        )
        let store = KnowledgeStore.forTesting(seedEntries: [serviceEntry, controllerEntry])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle([
            "topic": .string("pattern"),
            "layer": .string("service")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("**Layer:** service"))
            XCTAssertTrue(message.contains("Service Layer Pattern"))
            XCTAssertFalse(message.contains("Controller Pattern"))
        }
    }

    func testHandle_InvalidLayerType_IgnoresFilter() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test",
            title: "Test Pattern",
            content: "Test content"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = GetBestPracticeTool(store: store)

        // Invalid layer type - should ignore filter
        let result = try await tool.handle([
            "topic": .string("test"),
            "layer": .int(123)
        ])

        XCTAssertNotEqual(result.isError, true)
    }

    func testHandle_InvalidLayerValue_IgnoresFilter() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test",
            title: "Test Pattern",
            content: "Test content"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = GetBestPracticeTool(store: store)

        // Invalid layer value - should ignore filter
        let result = try await tool.handle([
            "topic": .string("test"),
            "layer": .string("invalid-layer")
        ])

        XCTAssertNotEqual(result.isError, true)
    }

    func testHandle_LayerFilterNoMatches_ReturnsGuidance() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "test",
            title: "Error Handling",
            content: "Use AppError",
            layer: .service
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle([
            "topic": .string("error"),
            "layer": .string("middleware")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No best practice found"))
            XCTAssertTrue(message.contains("middleware layer"))
        }
    }

    // MARK: - Anti-Pattern Exclusion

    func testHandle_ExcludesAntiPatterns() async throws {
        let goodPattern = createMinimalKnowledgeEntry(
            id: "good",
            title: "Good Pattern",
            content: "This is correct"
        )
        let antiPattern = KnowledgeEntry(
            id: "bad",
            title: "Bad Pattern",
            content: "This is incorrect",
            layer: .service,
            patternIds: ["bad"],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: true,
            correctionId: "good",
            confidence: 1.0,
            source: "test",
            lastVerifiedAt: Date()
        )

        let store = KnowledgeStore.forTesting(seedEntries: [goodPattern, antiPattern])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .string("pattern")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Good Pattern"))
            XCTAssertFalse(message.contains("Bad Pattern"))
        }
    }

    // MARK: - Pattern ID Matching

    func testHandle_SearchByPatternId_FindsMatches() async throws {
        let entry = KnowledgeEntry(
            id: "test",
            title: "Test Pattern",
            content: "Test content",
            layer: .service,
            patternIds: ["dependency-injection", "service-pattern"],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 1.0,
            source: "test",
            lastVerifiedAt: Date()
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .string("dependency")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Test Pattern"))
        }
    }

    // MARK: - Multiple Results

    func testHandle_MultipleMatches_LimitsToThree() async throws {
        let entries = (1...5).map { i in
            createMinimalKnowledgeEntry(
                id: "pattern-\(i)",
                title: "Error Pattern \(i)",
                content: "Error handling content \(i)"
            )
        }
        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .string("error")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Count how many "##" headers (excluding the main title)
            let headerCount = message.components(separatedBy: "\n## ").count - 1
            XCTAssertLessThanOrEqual(headerCount, 3, "Should limit to 3 results")
        }
    }

    // MARK: - Confidence Sorting

    func testHandle_SortsByConfidence() async throws {
        let lowEntry = KnowledgeEntry(
            id: "low",
            title: "Low Confidence Error Pattern",
            content: "Low confidence",
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
            title: "High Confidence Error Pattern",
            content: "High confidence",
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
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .string("error")])

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

    // MARK: - Edge Cases

    func testHandle_EmptyTopic_ReturnsNoMatches() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .string("")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No best practice found"))
        }
    }

    func testHandle_WhitespaceTopic_ReturnsNoMatches() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GetBestPracticeTool(store: store)

        let result = try await tool.handle(["topic": .string("   \n  \t  ")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No best practice found"))
        }
    }
}
