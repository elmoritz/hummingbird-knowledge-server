// Tests/HummingbirdKnowledgeServerTests/ArchitecturalViolationsTests.swift
//
// Comprehensive tests for ArchitecturalViolations: validates all 7 violation
// rules with known-good and known-bad code samples.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class ArchitecturalViolationsTests: XCTestCase {

    // MARK: - Critical Violations

    func testInlineDatabaseCallInHandler_DetectsViolation() {
        let violation = ArchitecturalViolations.all.first { $0.id == "inline-db-in-handler" }
        XCTAssertNotNil(violation, "inline-db-in-handler violation must exist")

        let badCode = """
        router.get("/users") { request, context in
            let users = try await context.db.query("SELECT * FROM users")
            return users
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(badCode.startIndex..., in: badCode)
        let match = regex.firstMatch(in: badCode, options: [], range: range)

        XCTAssertNotNil(match, "Should detect inline database call in handler")
        XCTAssertEqual(violation?.severity, .critical)
    }

    func testInlineDatabaseCallInHandler_AllowsCleanCode() {
        let violation = ArchitecturalViolations.all.first { $0.id == "inline-db-in-handler" }
        XCTAssertNotNil(violation)

        let goodCode = """
        router.get("/users") { request, context in
            let service = context.dependencies.userService
            return try await service.listUsers()
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(goodCode.startIndex..., in: goodCode)
        let match = regex.firstMatch(in: goodCode, options: [], range: range)

        XCTAssertNil(match, "Should not flag proper service-layer delegation")
    }

    func testInlineDatabaseCallInHandler_DetectsPoolQuery() {
        let violation = ArchitecturalViolations.all.first { $0.id == "inline-db-in-handler" }
        XCTAssertNotNil(violation)

        let badCode = """
        router.post("/items") { request, context in
            let result = try await pool.query("INSERT INTO items VALUES (?)", values: [item])
            return result
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(badCode.startIndex..., in: badCode)
        let match = regex.firstMatch(in: badCode, options: [], range: range)

        XCTAssertNotNil(match, "Should detect pool.query in handler")
    }

    func testServiceConstructionInHandler_DetectsViolation() {
        let violation = ArchitecturalViolations.all.first { $0.id == "service-construction-in-handler" }
        XCTAssertNotNil(violation, "service-construction-in-handler violation must exist")

        let badCode = """
        router.post("/items") { request, context in
            let service = ItemService(context: context)
            return try await service.create(request)
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(badCode.startIndex..., in: badCode)
        let match = regex.firstMatch(in: badCode, options: [], range: range)

        XCTAssertNotNil(match, "Should detect service construction in handler")
        XCTAssertEqual(violation?.severity, .critical)
    }

    func testServiceConstructionInHandler_AllowsInjectedService() {
        let violation = ArchitecturalViolations.all.first { $0.id == "service-construction-in-handler" }
        XCTAssertNotNil(violation)

        let goodCode = """
        router.post("/items") { request, context in
            let service = context.dependencies.itemService
            return try await service.create(request)
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(goodCode.startIndex..., in: goodCode)
        let match = regex.firstMatch(in: goodCode, options: [], range: range)

        XCTAssertNil(match, "Should not flag dependency-injected services")
    }

    // MARK: - Error-Level Violations

    func testHummingbirdImportInService_DetectsViolation() {
        let violation = ArchitecturalViolations.all.first { $0.id == "hummingbird-import-in-service" }
        XCTAssertNotNil(violation, "hummingbird-import-in-service violation must exist")

        let badCode = """
        import Hummingbird
        import Foundation

        struct UserService {
            func getUser(id: UUID) async throws -> User {
                // Service logic
            }
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [.anchorsMatchLines])
        let range = NSRange(badCode.startIndex..., in: badCode)
        let match = regex.firstMatch(in: badCode, options: [], range: range)

        XCTAssertNotNil(match, "Should detect Hummingbird import in service layer")
        XCTAssertEqual(violation?.severity, .error)
    }

    func testHummingbirdImportInService_AllowsInController() {
        let violation = ArchitecturalViolations.all.first { $0.id == "hummingbird-import-in-service" }
        XCTAssertNotNil(violation)

        // Note: This test verifies the pattern itself, not file location
        // The pattern only checks for the import statement existence
        let goodCode = """
        import Foundation

        struct UserService {
            func getUser(id: UUID) async throws -> User {
                // Service logic
            }
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [.anchorsMatchLines])
        let range = NSRange(goodCode.startIndex..., in: goodCode)
        let match = regex.firstMatch(in: goodCode, options: [], range: range)

        XCTAssertNil(match, "Should not flag service without Hummingbird import")
    }

    func testRawErrorThrownFromHandler_DetectsViolation() {
        let violation = ArchitecturalViolations.all.first { $0.id == "raw-error-thrown-from-handler" }
        XCTAssertNotNil(violation, "raw-error-thrown-from-handler violation must exist")

        let badCode = """
        router.get("/data") { request, context in
            guard let id = request.id else {
                throw ValidationError.missingParameter
            }
            return try await getData(id)
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(badCode.startIndex..., in: badCode)
        let match = regex.firstMatch(in: badCode, options: [], range: range)

        XCTAssertNotNil(match, "Should detect raw error thrown from handler")
        XCTAssertEqual(violation?.severity, .error)
    }

    func testRawErrorThrownFromHandler_AllowsAppError() {
        let violation = ArchitecturalViolations.all.first { $0.id == "raw-error-thrown-from-handler" }
        XCTAssertNotNil(violation)

        let goodCode = """
        router.get("/data") { request, context in
            guard let id = request.id else {
                throw AppError.validation(.missingParameter)
            }
            return try await getData(id)
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(goodCode.startIndex..., in: goodCode)
        let match = regex.firstMatch(in: goodCode, options: [], range: range)

        XCTAssertNil(match, "Should allow AppError to be thrown")
    }

    func testRawErrorThrownFromHandler_AllowsHTTPError() {
        let violation = ArchitecturalViolations.all.first { $0.id == "raw-error-thrown-from-handler" }
        XCTAssertNotNil(violation)

        let goodCode = """
        router.get("/data") { request, context in
            guard let id = request.id else {
                throw HTTPError(.badRequest)
            }
            return try await getData(id)
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(goodCode.startIndex..., in: goodCode)
        let match = regex.firstMatch(in: goodCode, options: [], range: range)

        XCTAssertNil(match, "Should allow HTTPError to be thrown")
    }

    func testDomainModelAcrossHTTPBoundary_DetectsViolation() {
        let violation = ArchitecturalViolations.all.first { $0.id == "domain-model-across-http-boundary" }
        XCTAssertNotNil(violation, "domain-model-across-http-boundary violation must exist")

        let badCode = """
        func getUser(request: Request) async throws -> UserModel {
            let user = try await userService.getUser(id: request.id)
            return user
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(badCode.startIndex..., in: badCode)
        let match = regex.firstMatch(in: badCode, options: [], range: range)

        XCTAssertNotNil(match, "Should detect domain model returned from handler")
        XCTAssertEqual(violation?.severity, .error)
    }

    func testDomainModelAcrossHTTPBoundary_AllowsResponse() {
        let violation = ArchitecturalViolations.all.first { $0.id == "domain-model-across-http-boundary" }
        XCTAssertNotNil(violation)

        let goodCode = """
        func getUser(request: Request) async throws -> Response {
            let user = try await userService.getUser(id: request.id)
            let dto = UserDTO(from: user)
            return Response(status: .ok, body: dto)
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(goodCode.startIndex..., in: goodCode)
        let match = regex.firstMatch(in: goodCode, options: [], range: range)

        XCTAssertNil(match, "Should allow Response type")
    }

    func testDomainModelAcrossHTTPBoundary_AllowsResponseGenerator() {
        let violation = ArchitecturalViolations.all.first { $0.id == "domain-model-across-http-boundary" }
        XCTAssertNotNil(violation)

        let goodCode = """
        func getUser(request: Request) async throws -> some ResponseGenerator {
            let user = try await userService.getUser(id: request.id)
            let dto = UserDTO(from: user)
            return dto
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(goodCode.startIndex..., in: goodCode)
        let match = regex.firstMatch(in: goodCode, options: [], range: range)

        XCTAssertNil(match, "Should allow some ResponseGenerator")
    }

    // MARK: - Warning-Level Violations

    func testSharedMutableStateWithoutActor_DetectsViolation() {
        let violation = ArchitecturalViolations.all.first { $0.id == "shared-mutable-state-without-actor" }
        XCTAssertNotNil(violation, "shared-mutable-state-without-actor violation must exist")

        let badCode = """
        var globalCache: [String: Data] = [:]

        func processData() {
            globalCache["key"] = data
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(badCode.startIndex..., in: badCode)
        let match = regex.firstMatch(in: badCode, options: [], range: range)

        XCTAssertNotNil(match, "Should detect shared mutable collection")
        XCTAssertEqual(violation?.severity, .warning)
    }

    func testSharedMutableStateWithoutActor_AllowsLetConstants() {
        let violation = ArchitecturalViolations.all.first { $0.id == "shared-mutable-state-without-actor" }
        XCTAssertNotNil(violation)

        let goodCode = """
        let globalCache: [String: Data] = [:]

        func processData() {
            let local = globalCache["key"]
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(goodCode.startIndex..., in: goodCode)
        let match = regex.firstMatch(in: goodCode, options: [], range: range)

        XCTAssertNil(match, "Should not flag immutable let collections")
    }

    func testNonisolatedContextAccess_DetectsViolation() {
        let violation = ArchitecturalViolations.all.first { $0.id == "nonisolated-context-access" }
        XCTAssertNotNil(violation, "nonisolated-context-access violation must exist")

        let badCode = """
        nonisolated func processRequest() { let user = context.currentUser
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(badCode.startIndex..., in: badCode)
        let match = regex.firstMatch(in: badCode, options: [], range: range)

        XCTAssertNotNil(match, "Should detect nonisolated context access")
        XCTAssertEqual(violation?.severity, .warning)
    }

    func testNonisolatedContextAccess_AllowsIsolatedAccess() {
        let violation = ArchitecturalViolations.all.first { $0.id == "nonisolated-context-access" }
        XCTAssertNotNil(violation)

        let goodCode = """
        func processRequest(context: AppRequestContext) {
            let user = context.currentUser
            performAction(user)
        }
        """

        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(goodCode.startIndex..., in: goodCode)
        let match = regex.firstMatch(in: goodCode, options: [], range: range)

        XCTAssertNil(match, "Should not flag regular context access")
    }

    // MARK: - Violation Catalogue Structure

    func testAllViolationsHaveRequiredFields() {
        XCTAssertEqual(ArchitecturalViolations.all.count, 38, "Should have exactly 38 violations")

        for violation in ArchitecturalViolations.all {
            XCTAssertFalse(violation.id.isEmpty, "Violation ID must not be empty")
            XCTAssertFalse(violation.pattern.isEmpty, "Violation pattern must not be empty")
            XCTAssertFalse(violation.description.isEmpty, "Violation description must not be empty")
            XCTAssertFalse(violation.correctionId.isEmpty, "Violation correctionId must not be empty")

            // Verify the regex pattern is valid
            XCTAssertNoThrow(
                try NSRegularExpression(pattern: violation.pattern, options: []),
                "Violation pattern must be valid regex: \(violation.id)"
            )
        }
    }

    func testViolationSeverityDistribution() {
        let criticalCount = ArchitecturalViolations.all.filter { $0.severity == .critical }.count
        let errorCount = ArchitecturalViolations.all.filter { $0.severity == .error }.count
        let warningCount = ArchitecturalViolations.all.filter { $0.severity == .warning }.count

        XCTAssertEqual(criticalCount, 2, "Should have 2 critical violations")
        XCTAssertEqual(errorCount, 33, "Should have 33 error violations")
        XCTAssertEqual(warningCount, 3, "Should have 3 warning violations")
    }

    func testAllViolationIDsAreUnique() {
        let ids = ArchitecturalViolations.all.map { $0.id }
        let uniqueIds = Set(ids)

        XCTAssertEqual(ids.count, uniqueIds.count, "All violation IDs must be unique")
    }

    // MARK: - Integration with KnowledgeStore

    func testDetectViolationsIntegration_FindsCriticalViolation() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])

        let codeWithViolation = """
        router.get("/users") { request, context in
            let users = try await context.db.query("SELECT * FROM users")
            return users
        }
        """

        let violations = await store.detectViolations(in: codeWithViolation)

        XCTAssertGreaterThan(violations.count, 0, "Should detect at least one violation")
        XCTAssertTrue(
            violations.contains(where: { $0.id == "inline-db-in-handler" }),
            "Should detect inline-db-in-handler violation"
        )
    }

    func testDetectViolationsIntegration_SortsViolationsBySeverity() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])

        // Code with multiple violations of different severities
        let codeWithMultipleViolations = """
        import Hummingbird

        var globalState: [String] = []

        router.get("/test") { request, context in
            let service = TestService(context: context)
            let result = try await context.pool.query("SELECT * FROM test")
            return result
        }
        """

        let violations = await store.detectViolations(in: codeWithMultipleViolations)

        XCTAssertGreaterThan(violations.count, 0, "Should detect multiple violations")

        // Verify critical violations come first
        if violations.count > 1 {
            let criticalViolations = violations.filter { $0.severity == .critical }

            if !criticalViolations.isEmpty {
                // If there are critical violations, they should appear before non-critical ones
                let nonCriticalAfterCritical = violations.dropFirst(criticalViolations.count).allSatisfy { $0.severity != .critical }
                XCTAssertTrue(
                    nonCriticalAfterCritical,
                    "Critical violations should be sorted first"
                )
            }
        }
    }

    // MARK: - Fix Suggestions

    func testAllViolationsHaveFixSuggestions() {
        XCTAssertEqual(ArchitecturalViolations.all.count, 38, "Should have exactly 38 violations")

        for violation in ArchitecturalViolations.all {
            XCTAssertNotNil(
                violation.fixSuggestion,
                "Violation '\(violation.id)' must have a fix suggestion"
            )
        }
    }

    func testFixSuggestionsHaveBeforeAfterCode() {
        for violation in ArchitecturalViolations.all {
            guard let fix = violation.fixSuggestion else {
                XCTFail("Violation '\(violation.id)' is missing a fix suggestion")
                continue
            }

            XCTAssertFalse(
                fix.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Violation '\(violation.id)' fix suggestion must have non-empty 'before' code"
            )

            XCTAssertFalse(
                fix.after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Violation '\(violation.id)' fix suggestion must have non-empty 'after' code"
            )

            XCTAssertFalse(
                fix.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Violation '\(violation.id)' fix suggestion must have non-empty 'explanation'"
            )

            // Verify before/after examples are different
            XCTAssertNotEqual(
                fix.before.trimmingCharacters(in: .whitespacesAndNewlines),
                fix.after.trimmingCharacters(in: .whitespacesAndNewlines),
                "Violation '\(violation.id)' fix suggestion 'before' and 'after' must be different"
            )

            // Verify examples contain actual code (basic sanity check)
            XCTAssertTrue(
                fix.before.contains("{") || fix.before.contains("(") || fix.before.contains("import"),
                "Violation '\(violation.id)' fix suggestion 'before' should look like code"
            )

            XCTAssertTrue(
                fix.after.contains("{") || fix.after.contains("(") || fix.after.contains("import"),
                "Violation '\(violation.id)' fix suggestion 'after' should look like code"
            )
        }
    }

    func testCheckArchitectureToolIncludesFixSuggestions() async {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let codeWithViolation = """
        router.post("/users") { request, context in
            let service = UserService(context: context)
            return try await service.create(request)
        }
        """

        let arguments: [String: Value] = [
            "code": .string(codeWithViolation)
        ]

        let result = try! await tool.handle(arguments)

        // Extract the text content from the result
        guard case .text(let resultText) = result.content.first else {
            XCTFail("Expected text content in result")
            return
        }

        // Should detect the violation
        XCTAssertTrue(
            resultText.contains("service-construction-in-handler"),
            "Tool should detect service-construction-in-handler violation"
        )

        // Should include fix information from the knowledge base entry
        XCTAssertTrue(
            resultText.contains("→ Fix:") || resultText.contains("Correction"),
            "Tool response should include fix guidance"
        )

        // Should indicate critical severity
        XCTAssertTrue(
            resultText.contains("CRITICAL") || resultText.contains("🔴"),
            "Tool should indicate critical severity"
        )
    }
}
