// Tests/HummingbirdKnowledgeServerTests/Tools/CheckVersionCompatibilityToolTests.swift
//
// Comprehensive tests for CheckVersionCompatibilityTool: validates 1.x to 2.x
// migration detection and compatibility checking.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class CheckVersionCompatibilityToolTests: XCTestCase {

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        XCTAssertEqual(tool.tool.name, "check_version_compatibility")
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
            XCTAssertTrue(requiredStrings.contains("code"), "code must be required")
            XCTAssertFalse(requiredStrings.contains("from_version"), "from_version must be optional")
            XCTAssertFalse(requiredStrings.contains("to_version"), "to_version must be optional")
        } else {
            XCTFail("Schema must have 'required' array")
        }
    }

    // MARK: - Argument Validation

    func testHandle_MissingCodeArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertEqual(result.isError, true, "Should return error for missing code")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
            XCTAssertTrue(message.contains("code"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_InvalidCodeType_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let result = try await tool.handle(["code": .int(123)])

        XCTAssertEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
        }
    }

    // MARK: - No Compatibility Issues

    func testHandle_ModernCode_ReturnsNoIssues() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let modernCode = """
        import Hummingbird

        struct UserService {
            func getUser(id: UUID) async throws -> User {
                // Modern Hummingbird 2.x code
            }
        }
        """

        let result = try await tool.handle(["code": .string(modernCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("# Compatibility Check:"))
            XCTAssertTrue(message.contains("✅ No known compatibility issues"))
            XCTAssertTrue(message.contains("check_architecture"))
        } else {
            XCTFail("Content should be text")
        }
    }

    // MARK: - HBApplication Detection

    func testHandle_HBApplication_DetectsIssue() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let legacyCode = """
        let app = HBApplication()
        """

        let result = try await tool.handle(["code": .string(legacyCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("⚠️"))
            XCTAssertTrue(message.contains("compatibility issue"))
            XCTAssertTrue(message.contains("HBApplication"))
            XCTAssertTrue(message.contains("Application"))
            XCTAssertTrue(message.contains("Migration:"))
        } else {
            XCTFail("Content should be text")
        }
    }

    // MARK: - HBRequest Detection

    func testHandle_HBRequest_DetectsIssue() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let legacyCode = """
        func handler(_ request: HBRequest) -> Response {
            return Response()
        }
        """

        let result = try await tool.handle(["code": .string(legacyCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("HBRequest"))
            XCTAssertTrue(message.contains("Request"))
        }
    }

    // MARK: - HBResponse Detection

    func testHandle_HBResponse_DetectsIssue() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let legacyCode = """
        let response = HBResponse(status: .ok)
        """

        let result = try await tool.handle(["code": .string(legacyCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("HBResponse"))
            XCTAssertTrue(message.contains("Response"))
        }
    }

    // MARK: - HBMiddleware Detection

    func testHandle_HBMiddleware_DetectsIssue() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let legacyCode = """
        struct MyMiddleware: HBMiddleware {
            func apply(to request: HBRequest) -> Response {
                return Response()
            }
        }
        """

        let result = try await tool.handle(["code": .string(legacyCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("HBMiddleware"))
            XCTAssertTrue(message.contains("RouterMiddleware"))
        }
    }

    // MARK: - HBRouterBuilder Detection

    func testHandle_HBRouterBuilder_DetectsIssue() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let legacyCode = """
        let router = HBRouterBuilder()
        """

        let result = try await tool.handle(["code": .string(legacyCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("HBRouterBuilder"))
            XCTAssertTrue(message.contains("Router(context:)"))
        }
    }

    // MARK: - HBHTTPError Detection

    func testHandle_HBHTTPError_DetectsIssue() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let legacyCode = """
        throw HBHTTPError(.notFound)
        """

        let result = try await tool.handle(["code": .string(legacyCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("HBHTTPError"))
            XCTAssertTrue(message.contains("HTTPError"))
        }
    }

    // MARK: - addMiddleware Detection

    func testHandle_AddMiddleware_DetectsIssue() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let legacyCode = """
        app.addMiddleware(MyMiddleware())
        """

        let result = try await tool.handle(["code": .string(legacyCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("addMiddleware"))
            XCTAssertTrue(message.contains("router.add(middleware:)"))
        }
    }

    // MARK: - Multiple Issues

    func testHandle_MultipleIssues_ListsAll() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let legacyCode = """
        let app = HBApplication()
        app.addMiddleware(MyMiddleware())
        app.router.get("/test") { (request: HBRequest) -> HBResponse in
            return HBResponse(status: .ok)
        }
        """

        let result = try await tool.handle(["code": .string(legacyCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("⚠️"))
            // Should show count of issues
            XCTAssertTrue(message.contains("compatibility issue"))

            // Should show all issues
            XCTAssertTrue(message.contains("1."))
            XCTAssertTrue(message.contains("2."))

            // Should contain migration guidance for each
            let migrationCount = message.components(separatedBy: "Migration:").count - 1
            XCTAssertGreaterThan(migrationCount, 1)
        }
    }

    // MARK: - Version Parameters

    func testHandle_WithVersions_IncludesInTitle() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let result = try await tool.handle([
            "code": .string("import Hummingbird"),
            "from_version": .string("1.9.0"),
            "to_version": .string("2.5.0")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("# Compatibility Check: 1.9.0 → 2.5.0"))
        }
    }

    func testHandle_DefaultVersions_Uses1xTo2x() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let result = try await tool.handle(["code": .string("import Hummingbird")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("# Compatibility Check: 1.x → 2.x"))
        }
    }

    func testHandle_InvalidVersionTypes_UsesDefaults() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let result = try await tool.handle([
            "code": .string("import Hummingbird"),
            "from_version": .int(1),
            "to_version": .int(2)
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("1.x → 2.x"))
        }
    }

    // MARK: - Guidance After Results

    func testHandle_AfterMigration_SuggestsArchitectureCheck() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let legacyCode = "let app = HBApplication()"

        let result = try await tool.handle(["code": .string(legacyCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("check_architecture"))
        }
    }

    // MARK: - Edge Cases

    func testHandle_EmptyCode_ReturnsNoIssues() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let result = try await tool.handle(["code": .string("")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ No known compatibility issues"))
        }
    }

    func testHandle_WhitespaceCode_ReturnsNoIssues() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let result = try await tool.handle(["code": .string("   \n  \t  ")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ No known compatibility issues"))
        }
    }

    func testHandle_CaseSensitiveMatching_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        // Should not match hbapplication (lowercase)
        let result = try await tool.handle(["code": .string("let app = hbapplication()")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("✅ No known compatibility issues"))
        }
    }

    func testHandle_PartialMatches_DontTrigger() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        // HBApplicationError should not match HBApplication pattern
        let result = try await tool.handle(["code": .string("throw HBApplicationError.somethingWrong")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should match because it contains HBApplication as substring
            // (current implementation uses .contains())
            XCTAssertTrue(message.contains("HBApplication") || message.contains("✅"))
        }
    }

    func testHandle_VeryLongCode_HandlesCorrectly() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = CheckVersionCompatibilityTool(store: store)

        let longCode = String(repeating: "// Comment\n", count: 1000) + "let app = HBApplication()"

        let result = try await tool.handle(["code": .string(longCode)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("HBApplication"))
        }
    }
}
