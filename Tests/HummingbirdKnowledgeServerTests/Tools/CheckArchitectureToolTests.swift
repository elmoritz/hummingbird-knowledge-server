// Tests/HummingbirdKnowledgeServerTests/Tools/CheckArchitectureToolTests.swift
//
// Comprehensive tests for CheckArchitectureTool: validates argument handling,
// violation detection, severity-based error reporting, and correction guidance.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class CheckArchitectureToolTests: XCTestCase {

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        XCTAssertEqual(tool.tool.name, "check_architecture")
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

        // Verify required fields
        if case .array(let requiredArray) = schema["required"] {
            let requiredStrings = requiredArray.compactMap { value -> String? in
                if case .string(let s) = value { return s }
                return nil
            }
            XCTAssertTrue(requiredStrings.contains("code"), "code must be required")
            XCTAssertFalse(requiredStrings.contains("file_path"), "file_path must be optional")
        } else {
            XCTFail("Schema must have 'required' array")
        }
    }

    // MARK: - Argument Validation

    func testHandle_MissingCodeArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        // Missing 'code' argument entirely
        let result = try await tool.handle([:])

        XCTAssertEqual(result.isError, true, "Should return error for missing code argument")
        XCTAssertEqual(result.content.count, 1)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("Missing required argument"),
                "Error message should mention missing argument"
            )
            XCTAssertTrue(
                message.contains("code"),
                "Error message should mention 'code' parameter"
            )
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_InvalidCodeArgumentType_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        // 'code' is a number instead of string
        let result = try await tool.handle(["code": .int(123)])

        XCTAssertEqual(result.isError, true, "Should return error for invalid code type")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("Missing required argument"),
                "Error message should indicate code is required as string"
            )
        }
    }

    // MARK: - Valid Code (No Violations)

    func testHandle_ValidCode_ReturnsSuccess() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let validCode = """
        import Foundation

        struct UserService: Sendable {
            func getUser(id: UUID) async throws -> User {
                // Service logic
            }
        }
        """

        let result = try await tool.handle(["code": .string(validCode)])

        XCTAssertNotEqual(result.isError, true, "Should not return error for valid code")
        XCTAssertEqual(result.content.count, 1)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("✅"),
                "Success message should contain success emoji"
            )
            XCTAssertTrue(
                message.contains("No architectural violations detected"),
                "Should indicate no violations found"
            )
            XCTAssertTrue(
                message.contains("Route handlers appear to be pure dispatchers"),
                "Should list passed checks"
            )
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_ValidCodeWithFilePath_IncludesFilePath() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let validCode = """
        import Foundation

        struct UserService: Sendable {
            func getUser(id: UUID) async throws -> User {
                // Service logic
            }
        }
        """

        let filePath = "Sources/App/Services/UserService.swift"
        let result = try await tool.handle([
            "code": .string(validCode),
            "file_path": .string(filePath)
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains(filePath),
                "Success message should include file path when provided"
            )
        }
    }

    func testHandle_EmptyCode_ReturnsSuccess() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let result = try await tool.handle(["code": .string("")])

        XCTAssertNotEqual(result.isError, true, "Empty code should not error")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("No architectural violations detected"),
                "Empty code should pass all checks"
            )
        }
    }

    // MARK: - Critical Violations

    func testHandle_CriticalViolation_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let codeWithCriticalViolation = """
        router.get("/users") { request, context in
            let users = try await context.db.query("SELECT * FROM users")
            return users
        }
        """

        let result = try await tool.handle(["code": .string(codeWithCriticalViolation)])

        XCTAssertEqual(result.isError, true, "Critical violations should set isError flag")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("🚫"),
                "Critical violation message should contain blocking emoji"
            )
            XCTAssertTrue(
                message.contains("CODE GENERATION BLOCKED"),
                "Should indicate code generation is blocked"
            )
            XCTAssertTrue(
                message.contains("🔴 CRITICAL"),
                "Should indicate critical severity"
            )
            XCTAssertTrue(
                message.contains("inline-db-in-handler"),
                "Should mention the violation ID"
            )
            XCTAssertTrue(
                message.contains("Correct all critical violations"),
                "Should instruct to fix critical violations"
            )
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_ServiceConstructionViolation_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let codeWithViolation = """
        router.post("/items") { request, context in
            let service = ItemService(context: context)
            return try await service.create(request)
        }
        """

        let result = try await tool.handle(["code": .string(codeWithViolation)])

        XCTAssertEqual(result.isError, true, "Critical violations should set isError flag")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("service-construction-in-handler"))
            XCTAssertTrue(message.contains("🔴 CRITICAL"))
        }
    }

    // MARK: - Error-Level Violations

    func testHandle_ErrorViolation_ReturnsWarningNotBlocked() async throws {
        let correctionEntry = createMinimalKnowledgeEntry(
            id: "service-layer-no-hummingbird",
            title: "Service Layer Must Be Framework-Agnostic",
            content: "Services should not import Hummingbird."
        )

        let store = KnowledgeStore.forTesting(seedEntries: [correctionEntry])
        let tool = CheckArchitectureTool(store: store)

        let codeWithErrorViolation = """
        import Hummingbird

        struct UserService {
            func getUser(id: UUID) async throws -> User {
                // Service logic
            }
        }
        """

        let result = try await tool.handle(["code": .string(codeWithErrorViolation)])

        XCTAssertNotEqual(result.isError, true, "Error-level violations should NOT block (isError=false)")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("⚠️"),
                "Non-critical violations should show warning emoji"
            )
            XCTAssertTrue(
                message.contains("Architectural violations detected"),
                "Should indicate violations were found"
            )
            XCTAssertTrue(
                message.contains("🟠 ERROR"),
                "Should indicate error severity"
            )
            XCTAssertTrue(
                message.contains("hummingbird-import-in-service"),
                "Should mention the violation ID"
            )
            XCTAssertFalse(
                message.contains("CODE GENERATION BLOCKED"),
                "Should not block code generation for error-level violations"
            )
        }
    }

    func testHandle_RawErrorViolation_ShowsCorrectionGuidance() async throws {
        let correctionEntry = createMinimalKnowledgeEntry(
            id: "typed-errors-app-error",
            title: "Use Typed Errors (AppError)",
            content: "All errors must be wrapped in AppError."
        )

        let store = KnowledgeStore.forTesting(seedEntries: [correctionEntry])
        let tool = CheckArchitectureTool(store: store)

        let codeWithViolation = """
        router.get("/data") { request, context in
            guard let id = request.id else {
                throw ValidationError.missingParameter
            }
            return try await getData(id)
        }
        """

        let result = try await tool.handle(["code": .string(codeWithViolation)])

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("raw-error-thrown-from-handler"))
            XCTAssertTrue(
                message.contains("→ Fix:"),
                "Should provide correction guidance"
            )
            XCTAssertTrue(
                message.contains("Use Typed Errors (AppError)"),
                "Should include correction entry title"
            )
            XCTAssertTrue(
                message.contains("pattern_id:"),
                "Should include correction ID reference"
            )
            XCTAssertTrue(
                message.contains("typed-errors-app-error"),
                "Should include the correction ID"
            )
        }
    }

    // MARK: - Warning-Level Violations

    func testHandle_WarningViolation_DoesNotBlock() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let codeWithWarning = """
        var globalCache: [String: Data] = [:]

        func processData() {
            globalCache["key"] = data
        }
        """

        let result = try await tool.handle(["code": .string(codeWithWarning)])

        XCTAssertNotEqual(result.isError, true, "Warnings should not block")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("⚠️"))
            XCTAssertTrue(message.contains("🟡 WARNING"))
            XCTAssertTrue(message.contains("shared-mutable-state-without-actor"))
            XCTAssertFalse(message.contains("CODE GENERATION BLOCKED"))
        }
    }

    func testHandle_NonisolatedContextWarning_DetectsViolation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        // Pattern requires nonisolated and context access on same line
        let codeWithWarning = """
        nonisolated func processRequest() { let user = context.currentUser
        """

        let result = try await tool.handle(["code": .string(codeWithWarning)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("nonisolated-context-access"))
            XCTAssertTrue(message.contains("🟡 WARNING"))
        }
    }

    // MARK: - Multiple Violations

    func testHandle_MultipleViolations_SortsBySeverity() async throws {
        let correctionEntry1 = createMinimalKnowledgeEntry(
            id: "route-handler-dispatcher-only",
            title: "Route Handlers as Pure Dispatchers",
            content: "Keep handlers thin."
        )

        let correctionEntry2 = createMinimalKnowledgeEntry(
            id: "service-layer-no-hummingbird",
            title: "Framework-Agnostic Services",
            content: "Don't import Hummingbird in services."
        )

        let store = KnowledgeStore.forTesting(seedEntries: [correctionEntry1, correctionEntry2])
        let tool = CheckArchitectureTool(store: store)

        // Code with critical, error, and warning violations
        let codeWithMultipleViolations = """
        import Hummingbird

        var globalState: [String] = []

        router.get("/test") { request, context in
            let service = TestService(context: context)
            let result = try await context.pool.query("SELECT * FROM test")
            return result
        }
        """

        let result = try await tool.handle(["code": .string(codeWithMultipleViolations)])

        XCTAssertEqual(result.isError, true, "Should error if any critical violation exists")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("🚫"))
            XCTAssertTrue(message.contains("CODE GENERATION BLOCKED"))

            // Verify multiple violations are listed
            let criticalMatches = message.ranges(of: "🔴 CRITICAL")
            let errorMatches = message.ranges(of: "🟠 ERROR")
            let warningMatches = message.ranges(of: "🟡 WARNING")

            XCTAssertGreaterThan(
                criticalMatches.count + errorMatches.count + warningMatches.count,
                1,
                "Should detect multiple violations"
            )

            // Verify numbering (1., 2., 3., etc.)
            XCTAssertTrue(message.contains("1. ["))
            XCTAssertTrue(message.contains("2. ["))
        }
    }

    func testHandle_MultipleSameSeverity_ListsAll() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        // Code with two critical violations
        let codeWithMultipleCritical = """
        router.post("/items") { request, context in
            let service = ItemService(db: context.db)
            let items = try await context.pool.query("SELECT * FROM items")
            return items
        }
        """

        let result = try await tool.handle(["code": .string(codeWithMultipleCritical)])

        XCTAssertEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should list both violations
            XCTAssertTrue(message.contains("1. ["))
            XCTAssertTrue(message.contains("2. ["))

            // Both should be critical
            let criticalCount = message.ranges(of: "🔴 CRITICAL").count
            XCTAssertGreaterThanOrEqual(criticalCount, 2)
        }
    }

    // MARK: - Correction Guidance

    func testHandle_ViolationWithCorrection_ShowsCorrectionDetails() async throws {
        let correctionEntry = createMinimalKnowledgeEntry(
            id: "dependency-injection-via-context",
            title: "Dependency Injection via Context",
            content: "Services must be injected, not constructed inline."
        )

        let store = KnowledgeStore.forTesting(seedEntries: [correctionEntry])
        let tool = CheckArchitectureTool(store: store)

        let codeWithViolation = """
        router.post("/items") { request, context in
            let service = ItemService(context: context)
            return try await service.create(request)
        }
        """

        let result = try await tool.handle(["code": .string(codeWithViolation)])

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("→ Fix:"),
                "Should show correction guidance"
            )
            XCTAssertTrue(
                message.contains("Dependency Injection via Context"),
                "Should show correction entry title"
            )
            XCTAssertTrue(
                message.contains("Services must be injected, not constructed inline."),
                "Should show correction entry content"
            )
            XCTAssertTrue(
                message.contains("pattern_id:"),
                "Should show pattern ID label"
            )
            XCTAssertTrue(
                message.contains("dependency-injection-via-context"),
                "Should show correction ID"
            )
        }
    }

    func testHandle_ViolationWithoutCorrectionInStore_ShowsCorrectionID() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let codeWithViolation = """
        router.get("/users") { request, context in
            let users = try await context.db.query("SELECT * FROM users")
            return users
        }
        """

        let result = try await tool.handle(["code": .string(codeWithViolation)])

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(
                message.contains("→ Correction ID:"),
                "Should show correction ID when entry not in store"
            )
            XCTAssertTrue(
                message.contains("route-handler-dispatcher-only"),
                "Should include the correction ID"
            )
        }
    }

    // MARK: - Edge Cases

    func testHandle_WhitespaceCode_ReturnsSuccess() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let result = try await tool.handle(["code": .string("   \n\n   \t  \n  ")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No architectural violations detected"))
        }
    }

    func testHandle_VeryLongCode_HandlesCorrectly() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        // Generate a large code string with a violation
        let longCode = String(repeating: "// Comment line\n", count: 1000) + """
        router.get("/test") { request, context in
            let result = try await context.db.query("SELECT * FROM test")
            return result
        }
        """

        let result = try await tool.handle(["code": .string(longCode)])

        XCTAssertEqual(result.isError, true, "Should detect violation even in long code")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("inline-db-in-handler"))
        }
    }

    func testHandle_CodeWithSpecialCharacters_HandlesCorrectly() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let codeWithSpecialChars = """
        import Foundation

        struct UserService: Sendable {
            func getUser(name: String) -> String {
                return "Hello, \\(name)! 你好 🎉"
            }
        }
        """

        let result = try await tool.handle(["code": .string(codeWithSpecialChars)])

        XCTAssertNotEqual(result.isError, true)
        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No architectural violations detected"))
        }
    }

    func testHandle_InvalidFilePathType_IgnoresFilePath() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckArchitectureTool(store: store)

        let validCode = "import Foundation"

        // file_path is a number instead of string - should be ignored
        let result = try await tool.handle([
            "code": .string(validCode),
            "file_path": .int(123)
        ])

        XCTAssertNotEqual(result.isError, true, "Invalid file_path type should be gracefully ignored")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No architectural violations detected"))
            XCTAssertFalse(message.contains("123"), "Should not include invalid file_path")
        }
    }
}
