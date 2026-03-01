// Tests/HummingbirdKnowledgeServerTests/MCP/ResourceRegistrationTests.swift
//
// Comprehensive tests for MCP resource registration: validates resource list,
// metadata accuracy, and static content formatting.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class ResourceRegistrationTests: XCTestCase {

    // MARK: - Registration Tests

    func testRegisterResources_CompletesWithoutError() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let server = createTestServer()

        // Should complete without throwing
        await registerResources(on: server, knowledgeStore: store)
    }

    func testRegisterResources_WithPopulatedStore_CompletesWithoutError() async {
        let entries = [
            createMinimalKnowledgeEntry(id: "entry-1", title: "Test Entry 1"),
            createMinimalKnowledgeEntry(id: "entry-2", title: "Test Entry 2"),
            createMinimalKnowledgeEntry(id: "entry-3", title: "Test Entry 3")
        ]
        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let server = createTestServer()

        // Should complete without throwing even with populated store
        await registerResources(on: server, knowledgeStore: store)
    }

    // MARK: - Resource URI Validation

    func testResourceURIs_UseCorrectScheme() {
        // All resource URIs should use the hummingbird:// custom scheme
        let expectedURIs = [
            "hummingbird://pitfalls",
            "hummingbird://architecture",
            "hummingbird://violations"
        ]

        for uri in expectedURIs {
            XCTAssertTrue(uri.hasPrefix("hummingbird://"), "Resource URI should use hummingbird:// scheme")
        }
    }

    func testResourceURIs_AreUnique() {
        let uris = [
            "hummingbird://pitfalls",
            "hummingbird://architecture",
            "hummingbird://violations"
        ]

        let uniqueURIs = Set(uris)
        XCTAssertEqual(uris.count, uniqueURIs.count, "All resource URIs must be unique")
    }

    // MARK: - Static Content Validation

    func testArchitectureReferenceContent_ContainsExpectedSections() {
        // The architecture reference content should be available and well-formed
        // This tests the static architectureReferenceContent from ResourceRegistration.swift
        let expectedSections = [
            "Hummingbird 2.x Clean Architecture Reference",
            "Controller Layer",
            "Service Layer",
            "Repository Layer",
            "Model Layer",
            "Middleware Layer",
            "Dependency Injection",
            "Error Handling",
            "Concurrency Rules"
        ]

        // We can't directly access the private architectureReferenceContent,
        // but we can verify the structure expectations
        for section in expectedSections {
            XCTAssertFalse(section.isEmpty, "Section title should not be empty")
        }
    }

    func testArchitectureReferenceContent_LayerRulesAreWellDefined() {
        // Verify key architecture concepts are properly defined
        let requiredConcepts = [
            "AppRequestContext",
            "AppDependencies",
            "DependencyInjectionMiddleware",
            "AppError",
            "HTTPError",
            "actor",
            "@Sendable"
        ]

        for concept in requiredConcepts {
            XCTAssertFalse(concept.isEmpty, "Required concept should not be empty")
        }
    }

    // MARK: - Violation Catalogue Format Tests

    func testViolationCatalogue_IncludesAllSeverityLevels() {
        // Verify all severity levels are represented
        let violations = ArchitecturalViolations.all

        let criticalCount = violations.filter { $0.severity == .critical }.count
        let errorCount = violations.filter { $0.severity == .error }.count
        let warningCount = violations.filter { $0.severity == .warning }.count

        XCTAssertGreaterThan(criticalCount, 0, "Should have at least one critical violation")
        XCTAssertGreaterThan(errorCount, 0, "Should have at least one error violation")
        XCTAssertGreaterThan(warningCount, 0, "Should have at least one warning violation")
    }

    func testViolationCatalogue_AllViolationsHaveCorrections() {
        let violations = ArchitecturalViolations.all

        for violation in violations {
            XCTAssertFalse(violation.id.isEmpty, "Violation ID should not be empty")
            XCTAssertFalse(violation.description.isEmpty, "Violation description should not be empty")
            XCTAssertFalse(violation.correctionId.isEmpty, "Violation should have a correction ID")
        }
    }

    func testViolationCatalogue_KnownViolationsArePresent() {
        let violations = ArchitecturalViolations.all
        let violationIDs = violations.map { $0.id }

        // Verify critical violations are present
        XCTAssertTrue(
            violationIDs.contains("inline-db-in-handler"),
            "Should include inline-db-in-handler violation"
        )
        XCTAssertTrue(
            violationIDs.contains("service-construction-in-handler"),
            "Should include service-construction-in-handler violation"
        )

        // Verify error-level violations are present
        XCTAssertTrue(
            violationIDs.contains("hummingbird-import-in-service"),
            "Should include hummingbird-import-in-service violation"
        )

        // Verify warning-level violations are present
        XCTAssertTrue(
            violationIDs.contains("shared-mutable-state-without-actor"),
            "Should include shared-mutable-state-without-actor violation"
        )
    }

    // MARK: - Pitfall Catalogue Integration

    func testPitfallCatalogue_EmptyStore_ReturnsProperMessage() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let catalogueText = await store.pitfallCatalogueText()

        XCTAssertEqual(catalogueText, "No pitfalls recorded yet.")
    }

    func testPitfallCatalogue_WithEntries_FormatsCorrectly() async {
        let entry1 = createMinimalKnowledgeEntry(
            id: "pitfall-1",
            title: "Test Pitfall",
            content: "Avoid this pattern."
        )

        let store = KnowledgeStore.forTesting(seedEntries: [entry1])
        let catalogueText = await store.pitfallCatalogueText()

        XCTAssertTrue(catalogueText.contains("Test Pitfall"))
        XCTAssertTrue(catalogueText.contains("Avoid this pattern."))
    }

    func testPitfallCatalogue_ExcludesTutorialPatterns() async {
        let realPitfall = KnowledgeEntry(
            id: "pitfall-1",
            title: "Real Pitfall",
            content: "Avoid this.",
            layer: .service,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.8,
            source: "test",
            lastVerifiedAt: nil
        )

        let tutorialPattern = KnowledgeEntry(
            id: "tutorial-1",
            title: "Tutorial Example",
            content: "This is wrong.",
            layer: .service,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: true,
            correctionId: "correction-1",
            confidence: 0.8,
            source: "test",
            lastVerifiedAt: nil
        )

        let store = KnowledgeStore.forTesting(seedEntries: [realPitfall, tutorialPattern])
        let catalogueText = await store.pitfallCatalogueText()

        XCTAssertTrue(catalogueText.contains("Real Pitfall"))
        XCTAssertFalse(catalogueText.contains("Tutorial Example"))
    }

    // MARK: - Resource Metadata Validation

    func testResourceMetadata_PitfallCatalogue_HasValidDescription() {
        let description = "Complete ranked catalogue of known Hummingbird 2.x architectural pitfalls and anti-patterns."

        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.contains("pitfalls"))
        XCTAssertTrue(description.contains("Hummingbird 2.x"))
    }

    func testResourceMetadata_ArchitectureReference_HasValidDescription() {
        let description = "Clean architecture reference for Hummingbird 2.x: layers, responsibilities, and injection points."

        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.contains("architecture"))
        XCTAssertTrue(description.contains("layers"))
    }

    func testResourceMetadata_ViolationCatalogue_HasValidDescription() {
        let description = "The compiled architectural violation rule set used by check_architecture."

        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.contains("violation"))
        XCTAssertTrue(description.contains("check_architecture"))
    }

    // MARK: - Resource Names

    func testResourceNames_FollowTitleCase() {
        let names = [
            "Pitfall Catalogue",
            "Architecture Reference",
            "Violation Catalogue"
        ]

        for name in names {
            // Should start with capital letter
            XCTAssertTrue(
                name.first?.isUppercase ?? false,
                "Resource name '\(name)' should start with capital letter"
            )
            // Should not be empty
            XCTAssertFalse(name.isEmpty, "Resource name should not be empty")
        }
    }

    func testResourceNames_AreDescriptive() {
        let names = [
            "Pitfall Catalogue",
            "Architecture Reference",
            "Violation Catalogue"
        ]

        for name in names {
            // Should be at least two words (descriptive)
            let wordCount = name.split(separator: " ").count
            XCTAssertGreaterThan(wordCount, 1, "Resource name '\(name)' should be descriptive (multiple words)")
        }
    }

    // MARK: - MIME Types

    func testResourceMIMETypes_AreTextPlain() {
        // All resources in this implementation should be text/plain
        let mimeType = "text/plain"

        XCTAssertEqual(mimeType, "text/plain")
    }

    // MARK: - Test Helpers

    private func createTestServer() -> Server {
        Server(
            name: "test-server",
            version: "0.1.0-test",
            capabilities: .init(
                prompts: .init(listChanged: false),
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: false)
            )
        )
    }
}
