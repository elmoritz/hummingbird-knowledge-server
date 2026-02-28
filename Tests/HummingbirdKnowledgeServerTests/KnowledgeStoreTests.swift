// Tests/HummingbirdKnowledgeServerTests/KnowledgeStoreTests.swift
//
// Comprehensive tests for KnowledgeStore actor: initialization, queries,
// filtering, violation detection, upserts, and formatted output.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class KnowledgeStoreTests: XCTestCase {

    // MARK: - Initialization

    func testInitWithSeedEntries() async {
        let entries = [
            createMinimalKnowledgeEntry(id: "entry-1", title: "Entry 1"),
            createMinimalKnowledgeEntry(id: "entry-2", title: "Entry 2")
        ]

        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let count = await store.count

        XCTAssertEqual(count, 2, "Store should contain exactly 2 entries")
    }

    func testInitWithEmptySeedEntries() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let count = await store.count

        XCTAssertEqual(count, 0, "Store initialized with empty array should have zero entries")
    }

    // MARK: - Basic Queries

    func testCountReflectsActualEntryCount() async {
        let entries = [
            createMinimalKnowledgeEntry(id: "entry-1"),
            createMinimalKnowledgeEntry(id: "entry-2"),
            createMinimalKnowledgeEntry(id: "entry-3")
        ]

        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let count = await store.count

        XCTAssertEqual(count, 3)
    }

    func testEntryForIdReturnsCorrectEntry() async {
        let entry1 = createMinimalKnowledgeEntry(id: "entry-1", title: "First Entry")
        let entry2 = createMinimalKnowledgeEntry(id: "entry-2", title: "Second Entry")

        let store = KnowledgeStore.forTesting(seedEntries: [entry1, entry2])
        let retrieved = await store.entry(for: "entry-1")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "entry-1")
        XCTAssertEqual(retrieved?.title, "First Entry")
    }

    func testEntryForIdReturnsNilForMissingEntry() async {
        let store = KnowledgeStore.forTesting(seedEntries: [createMinimalKnowledgeEntry(id: "entry-1")])
        let retrieved = await store.entry(for: "nonexistent-id")

        XCTAssertNil(retrieved, "Should return nil for missing entry ID")
    }

    func testAllEntriesReturnsAllStoredEntries() async {
        let entries = [
            createMinimalKnowledgeEntry(id: "entry-1"),
            createMinimalKnowledgeEntry(id: "entry-2"),
            createMinimalKnowledgeEntry(id: "entry-3")
        ]

        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let allEntries = await store.allEntries()

        XCTAssertEqual(allEntries.count, 3)
        XCTAssertTrue(allEntries.contains(where: { $0.id == "entry-1" }))
        XCTAssertTrue(allEntries.contains(where: { $0.id == "entry-2" }))
        XCTAssertTrue(allEntries.contains(where: { $0.id == "entry-3" }))
    }

    // MARK: - Layer-Based Filtering

    func testEntriesForLayerReturnsOnlyMatchingLayer() async {
        let serviceEntry = createMinimalKnowledgeEntry(id: "service-1", layer: .service)
        let controllerEntry = createMinimalKnowledgeEntry(id: "controller-1", layer: .controller)
        let repositoryEntry = createMinimalKnowledgeEntry(id: "repo-1", layer: .repository)

        let store = KnowledgeStore.forTesting(seedEntries: [serviceEntry, controllerEntry, repositoryEntry])
        let serviceEntries = await store.entries(for: .service)

        XCTAssertEqual(serviceEntries.count, 1)
        XCTAssertEqual(serviceEntries.first?.id, "service-1")
    }

    func testEntriesForLayerReturnsEmptyArrayWhenNoMatches() async {
        let entry = createMinimalKnowledgeEntry(id: "entry-1", layer: .service)
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let middlewareEntries = await store.entries(for: .middleware)

        XCTAssertEqual(middlewareEntries.count, 0)
    }

    func testEntriesForLayerReturnsMultipleMatchingEntries() async {
        let service1 = createMinimalKnowledgeEntry(id: "service-1", layer: .service)
        let service2 = createMinimalKnowledgeEntry(id: "service-2", layer: .service)
        let controller = createMinimalKnowledgeEntry(id: "controller-1", layer: .controller)

        let store = KnowledgeStore.forTesting(seedEntries: [service1, service2, controller])
        let serviceEntries = await store.entries(for: .service)

        XCTAssertEqual(serviceEntries.count, 2)
        XCTAssertTrue(serviceEntries.contains(where: { $0.id == "service-1" }))
        XCTAssertTrue(serviceEntries.contains(where: { $0.id == "service-2" }))
    }

    // MARK: - Pitfalls

    func testPitfallsExcludesTutorialPatterns() async {
        let regularEntry = KnowledgeEntry(
            id: "regular-1",
            title: "Regular Pattern",
            content: "Regular content",
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

        let tutorialEntry = KnowledgeEntry(
            id: "tutorial-1",
            title: "Anti-Pattern Example",
            content: "Tutorial content",
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

        let store = KnowledgeStore.forTesting(seedEntries: [regularEntry, tutorialEntry])
        let pitfalls = await store.pitfalls()

        XCTAssertEqual(pitfalls.count, 1)
        XCTAssertEqual(pitfalls.first?.id, "regular-1")
        XCTAssertFalse(pitfalls.first?.isTutorialPattern ?? true)
    }

    func testPitfallsSortedByConfidenceDescending() async {
        let lowConfidence = KnowledgeEntry(
            id: "low-conf",
            title: "Low Confidence",
            content: "Content",
            layer: .service,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.3,
            source: "test",
            lastVerifiedAt: nil
        )

        let highConfidence = KnowledgeEntry(
            id: "high-conf",
            title: "High Confidence",
            content: "Content",
            layer: .service,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.9,
            source: "test",
            lastVerifiedAt: nil
        )

        let mediumConfidence = KnowledgeEntry(
            id: "med-conf",
            title: "Medium Confidence",
            content: "Content",
            layer: .service,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.6,
            source: "test",
            lastVerifiedAt: nil
        )

        let store = KnowledgeStore.forTesting(seedEntries: [lowConfidence, highConfidence, mediumConfidence])
        let pitfalls = await store.pitfalls()

        XCTAssertEqual(pitfalls.count, 3)
        XCTAssertEqual(pitfalls[0].id, "high-conf", "First entry should be highest confidence")
        XCTAssertEqual(pitfalls[1].id, "med-conf", "Second entry should be medium confidence")
        XCTAssertEqual(pitfalls[2].id, "low-conf", "Third entry should be lowest confidence")
    }

    // MARK: - Anti-Pattern Entries

    func testAntiPatternEntriesReturnsOnlyTutorialPatterns() async {
        let regularEntry = KnowledgeEntry(
            id: "regular-1",
            title: "Regular Pattern",
            content: "Regular content",
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

        let antiPattern1 = KnowledgeEntry(
            id: "anti-1",
            title: "Anti-Pattern 1",
            content: "Content",
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

        let antiPattern2 = KnowledgeEntry(
            id: "anti-2",
            title: "Anti-Pattern 2",
            content: "Content",
            layer: .service,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: true,
            correctionId: "correction-2",
            confidence: 0.8,
            source: "test",
            lastVerifiedAt: nil
        )

        let store = KnowledgeStore.forTesting(seedEntries: [regularEntry, antiPattern1, antiPattern2])
        let antiPatterns = await store.antiPatternEntries()

        XCTAssertEqual(antiPatterns.count, 2)
        XCTAssertTrue(antiPatterns.allSatisfy { $0.isTutorialPattern })
        XCTAssertTrue(antiPatterns.contains(where: { $0.id == "anti-1" }))
        XCTAssertTrue(antiPatterns.contains(where: { $0.id == "anti-2" }))
    }

    func testAntiPatternEntriesReturnsEmptyArrayWhenNone() async {
        let entry = createMinimalKnowledgeEntry(id: "regular-1")
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let antiPatterns = await store.antiPatternEntries()

        XCTAssertEqual(antiPatterns.count, 0)
    }

    // MARK: - Violation Detection

    func testDetectViolationsFindsInlineDatabaseCall() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])

        let code = """
        router.get("/users") { request, context in
            let users = try await context.db.query("SELECT * FROM users")
            return users
        }
        """

        let violations = await store.detectViolations(in: code)

        XCTAssertGreaterThan(violations.count, 0, "Should detect inline database call violation")
        XCTAssertTrue(
            violations.contains(where: { $0.id == "inline-db-in-handler" }),
            "Should detect the inline-db-in-handler violation"
        )
    }

    func testDetectViolationsFindsServiceConstructionInHandler() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])

        let code = """
        router.post("/items") { request, context in
            let service = ItemService(context: context)
            return try await service.create(request)
        }
        """

        let violations = await store.detectViolations(in: code)

        XCTAssertTrue(
            violations.contains(where: { $0.id == "service-construction-in-handler" }),
            "Should detect service construction in handler"
        )
    }

    func testDetectViolationsSortedBySeverity() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])

        // Code that triggers both critical and warning violations
        let code = """
        router.get("/test") { request, context in
            let db = context.pool.query("SELECT * FROM test")
            return db
        }
        var globalCache: [String] = []
        """

        let violations = await store.detectViolations(in: code)

        guard violations.count >= 2 else {
            XCTFail("Expected at least 2 violations")
            return
        }

        // Critical violations should come before warnings
        let firstViolationIsCritical = violations.first?.severity == .critical

        XCTAssertTrue(
            firstViolationIsCritical || violations.allSatisfy({ $0.severity == .critical }),
            "Critical violations should be sorted first"
        )
    }

    func testDetectViolationsReturnsEmptyArrayForCleanCode() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])

        let cleanCode = """
        struct UserDTO: Codable {
            let id: UUID
            let name: String
        }
        """

        let violations = await store.detectViolations(in: cleanCode)

        XCTAssertEqual(violations.count, 0, "Clean code should have no violations")
    }

    // MARK: - Upsert Operations

    func testUpsertAddsNewEntry() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])

        let initialCount = await store.count
        XCTAssertEqual(initialCount, 0)

        let newEntry = createMinimalKnowledgeEntry(id: "new-entry-1", title: "New Entry")
        await store.upsert(newEntry)

        let finalCount = await store.count
        let retrieved = await store.entry(for: "new-entry-1")

        XCTAssertEqual(finalCount, 1)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.title, "New Entry")
    }

    func testUpsertUpdatesExistingEntry() async {
        let originalEntry = createMinimalKnowledgeEntry(id: "entry-1", title: "Original Title")
        let store = KnowledgeStore.forTesting(seedEntries: [originalEntry])

        let updatedEntry = createMinimalKnowledgeEntry(id: "entry-1", title: "Updated Title")
        await store.upsert(updatedEntry)

        let count = await store.count
        let retrieved = await store.entry(for: "entry-1")

        XCTAssertEqual(count, 1, "Count should remain 1 after update")
        XCTAssertEqual(retrieved?.title, "Updated Title")
    }

    func testUpsertAllAddsMultipleEntries() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])

        let newEntries = [
            createMinimalKnowledgeEntry(id: "entry-1", title: "Entry 1"),
            createMinimalKnowledgeEntry(id: "entry-2", title: "Entry 2"),
            createMinimalKnowledgeEntry(id: "entry-3", title: "Entry 3")
        ]

        await store.upsertAll(newEntries)

        let count = await store.count
        XCTAssertEqual(count, 3)
    }

    func testUpsertAllMixesUpdatesAndInserts() async {
        let existing = createMinimalKnowledgeEntry(id: "existing-1", title: "Original")
        let store = KnowledgeStore.forTesting(seedEntries: [existing])

        let batch = [
            createMinimalKnowledgeEntry(id: "existing-1", title: "Updated"),
            createMinimalKnowledgeEntry(id: "new-1", title: "New Entry")
        ]

        await store.upsertAll(batch)

        let count = await store.count
        let updatedEntry = await store.entry(for: "existing-1")
        let newEntry = await store.entry(for: "new-1")

        XCTAssertEqual(count, 2)
        XCTAssertEqual(updatedEntry?.title, "Updated")
        XCTAssertNotNil(newEntry)
    }

    func testUpsertAllWithEmptyArrayDoesNothing() async {
        let entry = createMinimalKnowledgeEntry(id: "entry-1")
        let store = KnowledgeStore.forTesting(seedEntries: [entry])

        await store.upsertAll([])

        let count = await store.count
        XCTAssertEqual(count, 1, "Count should remain unchanged")
    }

    // MARK: - Formatted Output

    func testPitfallCatalogueTextFormatsEntriesCorrectly() async {
        let entry1 = KnowledgeEntry(
            id: "pitfall-1",
            title: "First Pitfall",
            content: "This is the first pitfall.",
            layer: .service,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.9,
            source: "test",
            lastVerifiedAt: nil
        )

        let entry2 = KnowledgeEntry(
            id: "pitfall-2",
            title: "Second Pitfall",
            content: "This is the second pitfall.",
            layer: .controller,
            patternIds: [],
            violationIds: [],
            hummingbirdVersionRange: ">=2.0.0",
            swiftVersionRange: ">=6.0",
            isTutorialPattern: false,
            correctionId: nil,
            confidence: 0.7,
            source: "test",
            lastVerifiedAt: nil
        )

        let store = KnowledgeStore.forTesting(seedEntries: [entry1, entry2])
        let catalogueText = await store.pitfallCatalogueText()

        XCTAssertTrue(catalogueText.contains("## 1. First Pitfall"))
        XCTAssertTrue(catalogueText.contains("This is the first pitfall."))
        XCTAssertTrue(catalogueText.contains("## 2. Second Pitfall"))
        XCTAssertTrue(catalogueText.contains("This is the second pitfall."))
        XCTAssertTrue(catalogueText.contains("---"), "Should contain separator between entries")
    }

    func testPitfallCatalogueTextReturnsMessageForEmptyStore() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let catalogueText = await store.pitfallCatalogueText()

        XCTAssertEqual(catalogueText, "No pitfalls recorded yet.")
    }

    func testPitfallCatalogueTextExcludesTutorialPatterns() async {
        let pitfall = KnowledgeEntry(
            id: "pitfall-1",
            title: "Real Pitfall",
            content: "Avoid this pattern.",
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

        let tutorial = KnowledgeEntry(
            id: "tutorial-1",
            title: "Tutorial Example",
            content: "This is an anti-pattern example.",
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

        let store = KnowledgeStore.forTesting(seedEntries: [pitfall, tutorial])
        let catalogueText = await store.pitfallCatalogueText()

        XCTAssertTrue(catalogueText.contains("Real Pitfall"))
        XCTAssertFalse(catalogueText.contains("Tutorial Example"))
    }
}
