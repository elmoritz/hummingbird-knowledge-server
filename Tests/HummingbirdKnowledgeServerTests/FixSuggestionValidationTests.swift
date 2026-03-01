// Tests/HummingbirdKnowledgeServerTests/FixSuggestionValidationTests.swift
//
// Validates fix suggestions against real anti-pattern code samples.
// Each test applies a fix suggestion to a real anti-pattern and verifies
// the suggestion is contextual, applicable, and follows project patterns.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class FixSuggestionValidationTests: XCTestCase {

    // MARK: - Critical Violation Fix Validation

    func testInlineDatabaseInHandler_FixSuggestionApplicable() {
        let violation = ArchitecturalViolations.all.first { $0.id == "inline-db-in-handler" }
        XCTAssertNotNil(violation, "inline-db-in-handler violation must exist")

        let antiPattern = """
        router.post("/users") { request, context in
            let users = try await context.db.query("SELECT * FROM users")
            return users
        }
        """

        // 1. Verify violation is detected
        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(antiPattern.startIndex..., in: antiPattern)
        let match = regex.firstMatch(in: antiPattern, options: [], range: range)
        XCTAssertNotNil(match, "Anti-pattern should be detected")

        // 2. Verify fix suggestion exists
        XCTAssertNotNil(violation?.fixSuggestion, "Fix suggestion must exist")
        let fix = violation!.fixSuggestion!

        // 3. Verify fix suggestion has all required fields
        XCTAssertFalse(fix.before.isEmpty, "Fix must have before example")
        XCTAssertFalse(fix.after.isEmpty, "Fix must have after example")
        XCTAssertFalse(fix.explanation.isEmpty, "Fix must have explanation")

        // 4. Verify before example shows the anti-pattern
        XCTAssertTrue(fix.before.contains("db.") || fix.before.contains(".query") || fix.before.contains("pool."),
                      "Before example should show database call")
        XCTAssertTrue(fix.before.contains("router."), "Before example should show route handler context")

        // 5. Verify after example shows the correct pattern
        XCTAssertTrue(fix.after.contains("context.dependencies"), "After example should use dependency injection")
        XCTAssertTrue(fix.after.contains("Service") || fix.after.contains("service"), "After example should delegate to service layer")
        XCTAssertFalse(fix.after.contains(".query(") || fix.after.contains("pool.query") || fix.after.contains("db.query"),
                       "After example should not contain direct database queries")

        // 6. Verify explanation is contextual and references architecture
        XCTAssertTrue(fix.explanation.contains("service") || fix.explanation.contains("repository") || fix.explanation.contains("layer"),
                      "Explanation should reference architectural layers")
        XCTAssertTrue(fix.explanation.lowercased().contains("handler") || fix.explanation.lowercased().contains("dispatcher"),
                      "Explanation should explain handler role")
    }

    func testServiceConstructionInHandler_FixSuggestionApplicable() {
        let violation = ArchitecturalViolations.all.first { $0.id == "service-construction-in-handler" }
        XCTAssertNotNil(violation, "service-construction-in-handler violation must exist")

        let antiPattern = """
        router.post("/items") { request, context in
            let service = ItemService(context: context)
            let dto = try await request.decode(as: CreateItemRequest.self, context: context)
            return try await service.create(dto)
        }
        """

        // 1. Verify violation is detected
        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(antiPattern.startIndex..., in: antiPattern)
        let match = regex.firstMatch(in: antiPattern, options: [], range: range)
        XCTAssertNotNil(match, "Anti-pattern should be detected")

        // 2. Verify fix suggestion exists and has content
        XCTAssertNotNil(violation?.fixSuggestion, "Fix suggestion must exist")
        let fix = violation!.fixSuggestion!
        XCTAssertFalse(fix.before.isEmpty, "Fix must have before example")
        XCTAssertFalse(fix.after.isEmpty, "Fix must have after example")
        XCTAssertFalse(fix.explanation.isEmpty, "Fix must have explanation")

        // 3. Verify before example shows service construction
        XCTAssertTrue(fix.before.contains("Service("), "Before example should show service construction")
        XCTAssertTrue(fix.before.contains("router."), "Before example should show route handler context")

        // 4. Verify after example uses dependency injection
        XCTAssertTrue(fix.after.contains("context.dependencies"), "After example should use dependency injection")
        XCTAssertFalse(fix.after.contains("Service("), "After example should not construct services")

        // 5. Verify explanation covers dependency injection pattern
        XCTAssertTrue(fix.explanation.contains("inject") || fix.explanation.contains("dependencies") || fix.explanation.contains("AppRequestContext"),
                      "Explanation should cover dependency injection")
        XCTAssertTrue(fix.explanation.lowercased().contains("testable") || fix.explanation.lowercased().contains("singleton") || fix.explanation.lowercased().contains("reuse"),
                      "Explanation should explain benefits of DI")
    }

    // MARK: - Boundary Violation Fix Validation

    func testDomainModelAcrossHTTPBoundary_FixSuggestionApplicable() {
        let violation = ArchitecturalViolations.all.first { $0.id == "domain-model-across-http-boundary" }
        XCTAssertNotNil(violation, "domain-model-across-http-boundary violation must exist")

        let antiPattern = """
        func getUser(id: String) async throws -> UserModel {
            return try await userService.find(id: id)
        }
        """

        // 1. Verify violation is detected
        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(antiPattern.startIndex..., in: antiPattern)
        let match = regex.firstMatch(in: antiPattern, options: [], range: range)
        XCTAssertNotNil(match, "Anti-pattern should be detected")

        // 2. Verify fix suggestion exists
        XCTAssertNotNil(violation?.fixSuggestion, "Fix suggestion must exist")
        let fix = violation!.fixSuggestion!
        XCTAssertFalse(fix.before.isEmpty, "Fix must have before example")
        XCTAssertFalse(fix.after.isEmpty, "Fix must have after example")
        XCTAssertFalse(fix.explanation.isEmpty, "Fix must have explanation")

        // 3. Verify before example shows domain model being returned
        XCTAssertTrue(fix.before.contains("Model") || fix.before.contains("Entity") || fix.before.contains("return user"),
                      "Before example should show domain model return")

        // 4. Verify after example uses DTO
        XCTAssertTrue(fix.after.contains("Response") || fix.after.contains("DTO") || fix.after.contains("struct"),
                      "After example should introduce DTO/Response type")
        XCTAssertTrue(fix.after.contains("Codable") || fix.after.contains("ResponseCodable"),
                      "After example should show DTO is Codable")
        XCTAssertTrue(fix.after.contains("init("), "After example should show DTO initialization from domain model")

        // 5. Verify explanation covers boundary pattern
        XCTAssertTrue(fix.explanation.contains("DTO") || fix.explanation.contains("boundary") || fix.explanation.contains("contract"),
                      "Explanation should explain DTO/boundary concept")
        XCTAssertTrue(fix.explanation.lowercased().contains("model") && (fix.explanation.lowercased().contains("internal") || fix.explanation.lowercased().contains("domain")),
                      "Explanation should explain domain model concerns")
    }

    // MARK: - Error Handling Fix Validation

    func testRawErrorThrownFromHandler_FixSuggestionApplicable() {
        let violation = ArchitecturalViolations.all.first { $0.id == "raw-error-thrown-from-handler" }
        XCTAssertNotNil(violation, "raw-error-thrown-from-handler violation must exist")

        let antiPattern = """
        router.get("/data") { request, context in
            guard let id = request.uri.queryParameters.get("id") else {
                throw ValidationError.missingParameter
            }
            return try await getData(id)
        }
        """

        // 1. Verify violation is detected
        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(antiPattern.startIndex..., in: antiPattern)
        let match = regex.firstMatch(in: antiPattern, options: [], range: range)
        XCTAssertNotNil(match, "Anti-pattern should be detected")

        // 2. Verify fix suggestion exists
        XCTAssertNotNil(violation?.fixSuggestion, "Fix suggestion must exist")
        let fix = violation!.fixSuggestion!
        XCTAssertFalse(fix.before.isEmpty, "Fix must have before example")
        XCTAssertFalse(fix.after.isEmpty, "Fix must have after example")
        XCTAssertFalse(fix.explanation.isEmpty, "Fix must have explanation")

        // 3. Verify before example shows raw error
        XCTAssertTrue(fix.before.contains("throw") && !fix.before.contains("throw AppError") && !fix.before.contains("throw HTTPError"),
                      "Before example should show raw error throw")

        // 4. Verify after example uses typed error
        XCTAssertTrue(fix.after.contains("AppError") || fix.after.contains("HTTPError"),
                      "After example should use typed error (AppError or HTTPError)")

        // 5. Verify explanation covers error handling pattern
        XCTAssertTrue(fix.explanation.contains("AppError") || fix.explanation.contains("typed") || fix.explanation.contains("HTTP"),
                      "Explanation should reference typed error system")
        XCTAssertTrue(fix.explanation.lowercased().contains("status") || fix.explanation.lowercased().contains("code") || fix.explanation.lowercased().contains("client"),
                      "Explanation should explain HTTP response mapping")
    }

    // MARK: - Concurrency Fix Validation

    func testBlockingSleepInAsync_FixSuggestionApplicable() {
        let violation = ArchitecturalViolations.all.first { $0.id == "blocking-sleep-in-async" }
        XCTAssertNotNil(violation, "blocking-sleep-in-async violation must exist")

        let antiPattern = """
        async func retryRequest() -> Response { sleep(5) }
        """

        // 1. Verify violation is detected
        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(antiPattern.startIndex..., in: antiPattern)
        let match = regex.firstMatch(in: antiPattern, options: [], range: range)
        XCTAssertNotNil(match, "Anti-pattern should be detected")

        // 2. Verify fix suggestion exists
        XCTAssertNotNil(violation?.fixSuggestion, "Fix suggestion must exist")
        let fix = violation!.fixSuggestion!
        XCTAssertFalse(fix.before.isEmpty, "Fix must have before example")
        XCTAssertFalse(fix.after.isEmpty, "Fix must have after example")
        XCTAssertFalse(fix.explanation.isEmpty, "Fix must have explanation")

        // 3. Verify before example shows blocking sleep
        XCTAssertTrue(fix.before.contains("sleep(") || fix.before.contains("Thread.sleep") || fix.before.contains("usleep"),
                      "Before example should show blocking sleep")
        XCTAssertTrue(fix.before.contains("async"), "Before example should be in async context")

        // 4. Verify after example uses Task.sleep
        XCTAssertTrue(fix.after.contains("Task.sleep"), "After example should use Task.sleep")
        XCTAssertTrue(fix.after.contains("await"), "After example should await Task.sleep")
        XCTAssertFalse(fix.after.contains("sleep(") && !fix.after.contains("Task.sleep"),
                       "After example should not have blocking sleep")

        // 5. Verify explanation covers concurrency
        XCTAssertTrue(fix.explanation.contains("Task.sleep") || fix.explanation.contains("cooperative") || fix.explanation.contains("yield"),
                      "Explanation should explain cooperative concurrency")
        XCTAssertTrue(fix.explanation.lowercased().contains("block") || fix.explanation.lowercased().contains("thread"),
                      "Explanation should explain why blocking is bad")
    }

    // MARK: - Additional Violation Fix Validation

    func testHummingbirdImportInService_FixSuggestionApplicable() {
        let violation = ArchitecturalViolations.all.first { $0.id == "hummingbird-import-in-service" }
        XCTAssertNotNil(violation, "hummingbird-import-in-service violation must exist")

        let antiPattern = """
        import Hummingbird
        import Foundation

        struct UserService {
            func getUser(id: UUID) async throws -> User {
                // Service logic
            }
        }
        """

        // 1. Verify violation is detected
        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [.anchorsMatchLines])
        let range = NSRange(antiPattern.startIndex..., in: antiPattern)
        let match = regex.firstMatch(in: antiPattern, options: [], range: range)
        XCTAssertNotNil(match, "Anti-pattern should be detected")

        // 2. Verify fix suggestion exists
        XCTAssertNotNil(violation?.fixSuggestion, "Fix suggestion must exist")
        let fix = violation!.fixSuggestion!
        XCTAssertFalse(fix.before.isEmpty, "Fix must have before example")
        XCTAssertFalse(fix.after.isEmpty, "Fix must have after example")
        XCTAssertFalse(fix.explanation.isEmpty, "Fix must have explanation")

        // 3. Verify before example shows Hummingbird import
        XCTAssertTrue(fix.before.contains("import Hummingbird"), "Before example should show Hummingbird import")

        // 4. Verify after example removes Hummingbird import
        XCTAssertFalse(fix.after.contains("import Hummingbird"), "After example should not import Hummingbird")
        XCTAssertTrue(fix.after.contains("import Foundation") || fix.after.contains("struct") || fix.after.contains("class"),
                      "After example should show service layer code")

        // 5. Verify explanation covers layer separation
        XCTAssertTrue(fix.explanation.contains("layer") || fix.explanation.contains("service") || fix.explanation.contains("framework"),
                      "Explanation should explain layer separation")
        XCTAssertTrue(fix.explanation.lowercased().contains("coupling") || fix.explanation.lowercased().contains("independent") || fix.explanation.lowercased().contains("agnostic"),
                      "Explanation should explain decoupling benefits")
    }

    func testSynchronousDatabaseCallInAsync_FixSuggestionApplicable() {
        let violation = ArchitecturalViolations.all.first { $0.id == "synchronous-database-call-in-async" }
        XCTAssertNotNil(violation, "synchronous-database-call-in-async violation must exist")

        let antiPattern = """
        async func getUsers() { let result = db.query("SELECT * FROM users") }
        """

        // 1. Verify violation is detected
        let regex = try! NSRegularExpression(pattern: violation!.pattern, options: [])
        let range = NSRange(antiPattern.startIndex..., in: antiPattern)
        let match = regex.firstMatch(in: antiPattern, options: [], range: range)
        XCTAssertNotNil(match, "Anti-pattern should be detected")

        // 2. Verify fix suggestion exists
        XCTAssertNotNil(violation?.fixSuggestion, "Fix suggestion must exist")
        let fix = violation!.fixSuggestion!
        XCTAssertFalse(fix.before.isEmpty, "Fix must have before example")
        XCTAssertFalse(fix.after.isEmpty, "Fix must have after example")
        XCTAssertFalse(fix.explanation.isEmpty, "Fix must have explanation")

        // 3. Verify before example shows synchronous database call in async context
        XCTAssertTrue(fix.before.contains("async"), "Before example should be async")
        XCTAssertTrue(fix.before.contains(".query") || fix.before.contains(".execute") || fix.before.contains("database"),
                      "Before example should show database operation")

        // 4. Verify after example uses await
        XCTAssertTrue(fix.after.contains("await"), "After example should await database call")

        // 5. Verify explanation covers async/await pattern
        XCTAssertTrue(fix.explanation.contains("async") || fix.explanation.contains("await") || fix.explanation.contains("concurrency"),
                      "Explanation should reference async/await")
        XCTAssertTrue(fix.explanation.lowercased().contains("block") || fix.explanation.lowercased().contains("thread") || fix.explanation.lowercased().contains("await"),
                      "Explanation should explain async database access")
    }

    // MARK: - Comprehensive Fix Quality Tests

    func testAllCriticalViolationsHaveRobustFixSuggestions() {
        let criticalViolations = ArchitecturalViolations.all.filter { $0.severity == .critical }

        XCTAssertFalse(criticalViolations.isEmpty, "Should have critical violations")

        for violation in criticalViolations {
            // Critical violations must have fix suggestions
            XCTAssertNotNil(violation.fixSuggestion, "Critical violation '\(violation.id)' must have fix suggestion")

            guard let fix = violation.fixSuggestion else { continue }

            // Verify fix quality
            XCTAssertGreaterThan(fix.before.count, 50, "Fix suggestion for '\(violation.id)' should have substantial before example")
            XCTAssertGreaterThan(fix.after.count, 50, "Fix suggestion for '\(violation.id)' should have substantial after example")
            XCTAssertGreaterThan(fix.explanation.count, 100, "Fix suggestion for '\(violation.id)' should have detailed explanation")

            // Verify before example has context markers
            XCTAssertTrue(fix.before.contains("❌") || fix.before.contains("Wrong") || fix.before.contains("Bad"),
                          "Before example for '\(violation.id)' should be marked as incorrect")

            // Verify after example has context markers
            XCTAssertTrue(fix.after.contains("✅") || fix.after.contains("Correct") || fix.after.contains("Good"),
                          "After example for '\(violation.id)' should be marked as correct")

            // Verify explanation is educational, not just prescriptive
            let lowercaseExplanation = fix.explanation.lowercased()
            let hasRationale = lowercaseExplanation.contains("because") ||
                              lowercaseExplanation.contains("this") ||
                              lowercaseExplanation.contains("ensures") ||
                              lowercaseExplanation.contains("prevents") ||
                              lowercaseExplanation.contains("allows")
            XCTAssertTrue(hasRationale, "Explanation for '\(violation.id)' should provide rationale, not just instructions")
        }
    }

    func testFixSuggestionsFollowProjectArchitecturalPatterns() {
        let violations = ArchitecturalViolations.all.filter { $0.fixSuggestion != nil }

        XCTAssertFalse(violations.isEmpty, "Should have violations with fix suggestions")

        var usesServiceLayer = 0
        var usesDependencyInjection = 0
        var usesTypedErrors = 0
        var usesDTOs = 0

        for violation in violations {
            guard let fix = violation.fixSuggestion else { continue }

            let afterLower = fix.after.lowercased()
            let explanation = fix.explanation.lowercased()

            // Count pattern usage across all fixes
            if afterLower.contains("service") || explanation.contains("service") {
                usesServiceLayer += 1
            }
            if afterLower.contains("context.dependencies") || explanation.contains("inject") || explanation.contains("dependencies") {
                usesDependencyInjection += 1
            }
            if afterLower.contains("apperror") || afterLower.contains("httperror") || explanation.contains("typed error") {
                usesTypedErrors += 1
            }
            if afterLower.contains("response") || afterLower.contains("dto") || explanation.contains("boundary") {
                usesDTOs += 1
            }
        }

        // Verify project patterns are represented across fix suggestions
        XCTAssertGreaterThan(usesServiceLayer, 5, "Fix suggestions should demonstrate service layer pattern")
        XCTAssertGreaterThan(usesDependencyInjection, 3, "Fix suggestions should demonstrate dependency injection")
        XCTAssertGreaterThan(usesTypedErrors, 2, "Fix suggestions should demonstrate typed error handling")
        XCTAssertGreaterThan(usesDTOs, 2, "Fix suggestions should demonstrate DTO pattern")
    }
}
