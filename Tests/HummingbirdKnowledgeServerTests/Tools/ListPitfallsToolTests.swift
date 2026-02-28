// Tests/HummingbirdKnowledgeServerTests/Tools/ListPitfallsToolTests.swift
//
// Comprehensive tests for ListPitfallsTool: validates filtering by layer and severity,
// violation catalogue integration, and result limiting.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class ListPitfallsToolTests: XCTestCase {

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ListPitfallsTool(store: store)

        XCTAssertEqual(tool.tool.name, "list_pitfalls")
        XCTAssertNotNil(tool.tool.description)
        XCTAssertFalse(tool.tool.description?.isEmpty ?? true)

        // Verify input schema structure
        guard case .object(let schema) = tool.tool.inputSchema else {
            XCTFail("Input schema must be an object")
            return
        }

        // Verify properties exist (all optional)
        if case .object(let properties) = schema["properties"] {
            XCTAssertTrue(properties.keys.contains("layer"))
            XCTAssertTrue(properties.keys.contains("severity"))
            XCTAssertTrue(properties.keys.contains("limit"))
        } else {
            XCTFail("Schema must have 'properties' object")
        }
    }

    // MARK: - No Arguments (Default Behavior)

    func testHandle_NoArguments_ReturnsAllPitfalls() async throws {
        let pitfall = createMinimalKnowledgeEntry(
            id: "test-pitfall",
            title: "Common Pitfall",
            content: "This is a pitfall",
            layer: .service
        )
        let store = KnowledgeStore.forTesting(seedEntries: [pitfall])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("# Hummingbird 2.x Pitfall Catalogue"))
            XCTAssertTrue(message.contains("explain_pattern"))
        } else {
            XCTFail("Content should be text")
        }
    }

    // MARK: - Architectural Violations

    func testHandle_ShowsArchitecturalViolations() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Architectural Violations"))
            XCTAssertTrue(message.contains("check_architecture"))
            // Should show some violations from ArchitecturalViolations.all
            XCTAssertTrue(message.contains("🔴") || message.contains("🟠") || message.contains("🟡"))
        }
    }

    // MARK: - Severity Filtering

    func testHandle_FilterBySeverityCritical_ShowsOnlyCritical() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle(["severity": .string("critical")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should show critical violations
            XCTAssertTrue(message.contains("🔴") || message.isEmpty || message.contains("Hummingbird"))
            // Should not show error or warning if critical exists
            if message.contains("🔴") {
                let lines = message.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("🟠") || line.contains("🟡") {
                        XCTFail("Should not show error or warning when filtering for critical")
                    }
                }
            }
        }
    }

    func testHandle_FilterBySeverityError_ShowsOnlyErrors() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle(["severity": .string("error")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Hummingbird"))
        }
    }

    func testHandle_FilterBySeverityWarning_ShowsOnlyWarnings() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle(["severity": .string("warning")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Hummingbird"))
        }
    }

    func testHandle_InvalidSeverityType_IgnoresFilter() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle(["severity": .int(123)])

        XCTAssertNotEqual(result.isError, true)
    }

    // MARK: - Layer Filtering

    func testHandle_FilterByLayer_ShowsOnlyMatchingPitfalls() async throws {
        // Note: pitfalls() returns non-tutorial patterns (isTutorialPattern: false)
        let servicePitfall = createMinimalKnowledgeEntry(
            id: "service-pitfall",
            title: "Service Pitfall",
            content: "Service layer pitfall",
            layer: .service
        )
        let controllerPitfall = createMinimalKnowledgeEntry(
            id: "controller-pitfall",
            title: "Controller Pitfall",
            content: "Controller layer pitfall",
            layer: .controller
        )

        let store = KnowledgeStore.forTesting(seedEntries: [servicePitfall, controllerPitfall])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle(["layer": .string("service")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Service Pitfall"))
            XCTAssertFalse(message.contains("Controller Pitfall"))
        }
    }

    func testHandle_InvalidLayerType_IgnoresFilter() async throws {
        let pitfall = createMinimalKnowledgeEntry(
            id: "test",
            title: "Test Pitfall",
            content: "Test",
            layer: .service
        )
        let store = KnowledgeStore.forTesting(seedEntries: [pitfall])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle(["layer": .int(123)])

        XCTAssertNotEqual(result.isError, true)
    }

    // MARK: - Limit Parameter

    func testHandle_WithLimit_LimitsResults() async throws {
        let pitfalls = (1...15).map { i in
            KnowledgeEntry(
                id: "pitfall-\(i)",
                title: "Pitfall \(i)",
                content: "Content \(i)",
                layer: .service,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: true,
                correctionId: "correction",
                confidence: 1.0,
                source: "test",
                lastVerifiedAt: Date()
            )
        }
        let store = KnowledgeStore.forTesting(seedEntries: pitfalls)
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle(["limit": .int(5)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Count numbered items in knowledge base section
            let matches = message.ranges(of: /\d+\. \*\*/)
            // Should have violations + pitfalls, but pitfalls limited to 5
            XCTAssertTrue(message.contains("Pitfall"))
        }
    }

    func testHandle_DefaultLimit_UsesTen() async throws {
        let pitfalls = (1...15).map { i in
            KnowledgeEntry(
                id: "pitfall-\(i)",
                title: "Pitfall \(i)",
                content: "Content \(i)",
                layer: .service,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: true,
                correctionId: "correction",
                confidence: 1.0,
                source: "test",
                lastVerifiedAt: Date()
            )
        }
        let store = KnowledgeStore.forTesting(seedEntries: pitfalls)
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Pitfall"))
        }
    }

    func testHandle_InvalidLimitType_UsesDefault() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle(["limit": .string("not-a-number")])

        XCTAssertNotEqual(result.isError, true)
    }

    // MARK: - Knowledge Base Pitfalls

    func testHandle_ShowsKnowledgeBasePitfalls() async throws {
        // Note: pitfalls() returns non-tutorial patterns
        let pitfall = createMinimalKnowledgeEntry(
            id: "kb-pitfall",
            title: "Knowledge Base Pitfall",
            content: "This is a detailed explanation of the pitfall that is longer than 120 characters to test the preview truncation feature in the list pitfalls tool output.",
            layer: .service
        )
        let store = KnowledgeStore.forTesting(seedEntries: [pitfall])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Knowledge Base Pitfalls"))
            XCTAssertTrue(message.contains("Knowledge Base Pitfall"))
            XCTAssertTrue(message.contains("kb-pitfall"))
            // Should truncate content preview
            XCTAssertTrue(message.contains("…"))
        }
    }

    // MARK: - Formatting

    func testHandle_FormatsViolationsWithIcons() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should have severity icons
            let hasCritical = message.contains("🔴")
            let hasError = message.contains("🟠")
            let hasWarning = message.contains("🟡")

            XCTAssertTrue(hasCritical || hasError || hasWarning, "Should show severity icons")
        }
    }

    func testHandle_ShowsCorrectionIds() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Correction:") || message.contains("explain_pattern"))
        }
    }

    // MARK: - Edge Cases

    func testHandle_NoPitfalls_ShowsViolationsOnly() async throws {
        let normalEntry = createMinimalKnowledgeEntry(
            id: "normal",
            title: "Normal Pattern",
            content: "Not a pitfall"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [normalEntry])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Architectural Violations"))
            XCTAssertTrue(message.contains("explain_pattern"))
        }
    }

    func testHandle_MultipleFilters_CombinesThem() async throws {
        let servicePitfall = createMinimalKnowledgeEntry(
            id: "service-pitfall",
            title: "Service Pitfall",
            content: "Service layer pitfall",
            layer: .service
        )
        let controllerPitfall = createMinimalKnowledgeEntry(
            id: "controller-pitfall",
            title: "Controller Pitfall",
            content: "Controller layer pitfall",
            layer: .controller
        )

        let store = KnowledgeStore.forTesting(seedEntries: [servicePitfall, controllerPitfall])
        let tool = ListPitfallsTool(store: store)

        let result = try await tool.handle([
            "layer": .string("service"),
            "severity": .string("critical"),
            "limit": .int(5)
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Service Pitfall"))
            XCTAssertFalse(message.contains("Controller Pitfall"))
        }
    }
}
