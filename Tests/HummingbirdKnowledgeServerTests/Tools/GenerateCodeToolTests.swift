// Tests/HummingbirdKnowledgeServerTests/Tools/GenerateCodeToolTests.swift
//
// Comprehensive tests for GenerateCodeTool: validates code generation with layer context,
// violation detection in existing code, and scaffolding guidance.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class GenerateCodeToolTests: XCTestCase {

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        XCTAssertEqual(tool.tool.name, "generate_code")
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
            XCTAssertTrue(requiredStrings.contains("description"), "description must be required")
            XCTAssertTrue(requiredStrings.contains("layer"), "layer must be required")
            XCTAssertFalse(requiredStrings.contains("existing_code"), "existing_code must be optional")
        } else {
            XCTFail("Schema must have 'required' array")
        }
    }

    // MARK: - Argument Validation

    func testHandle_MissingDescriptionArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle(["layer": .string("service")])

        XCTAssertEqual(result.isError, true, "Should return error for missing description")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
            XCTAssertTrue(message.contains("description"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_MissingLayerArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle(["description": .string("Create a user service")])

        XCTAssertEqual(result.isError, true, "Should return error for missing layer")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing or invalid"))
            XCTAssertTrue(message.contains("layer"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_InvalidLayerValue_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create a service"),
            "layer": .string("invalid-layer")
        ])

        XCTAssertEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing or invalid"))
            XCTAssertTrue(message.contains("layer"))
            // Should list valid layers
            XCTAssertTrue(message.contains("controller") || message.contains("service"))
        }
    }

    func testHandle_InvalidDescriptionType_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .int(123),
            "layer": .string("service")
        ])

        XCTAssertEqual(result.isError, true)
    }

    // MARK: - Valid Generation

    func testHandle_ValidArguments_ReturnsScaffolding() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "service-pattern",
            title: "Service Layer Pattern",
            content: "How to structure services",
            layer: .service
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create a user management service"),
            "layer": .string("service")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Generated Code:"))
            XCTAssertTrue(message.contains("Create a user management service"))
            XCTAssertTrue(message.contains("**Layer:** service"))
            XCTAssertTrue(message.contains("**Relevant patterns:**"))
            XCTAssertTrue(message.contains("Service Layer Pattern"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_NoRelevantPatterns_ShowsMessage() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create something"),
            "layer": .string("middleware")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No specific patterns found"))
            XCTAssertTrue(message.contains("middleware layer"))
        }
    }

    func testHandle_MultipleRelevantPatterns_LimitsToTwo() async throws {
        let entries = (1...5).map { i in
            createMinimalKnowledgeEntry(
                id: "pattern-\(i)",
                title: "Service Pattern \(i)",
                content: "Content \(i)",
                layer: .service
            )
        }
        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create a service"),
            "layer": .string("service")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Count bullet points in relevant patterns section
            let bulletCount = message.components(separatedBy: "• ").count - 1
            XCTAssertLessThanOrEqual(bulletCount, 2, "Should limit to 2 patterns")
        }
    }

    // MARK: - Existing Code Validation

    func testHandle_ExistingCodeWithCriticalViolation_BlocksGeneration() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let codeWithViolation = """
        router.get("/users") { request, context in
            let users = try await context.db.query("SELECT * FROM users")
            return users
        }
        """

        let result = try await tool.handle([
            "description": .string("Extend user endpoint"),
            "layer": .string("controller"),
            "existing_code": .string(codeWithViolation)
        ])

        XCTAssertEqual(result.isError, true, "Should block generation for critical violations")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("🚫"))
            XCTAssertTrue(message.contains("Generation blocked"))
            XCTAssertTrue(message.contains("critical violations"))
            XCTAssertTrue(message.contains("check_architecture"))
            XCTAssertTrue(message.contains("explain_pattern"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_ExistingCodeWithNonCriticalViolation_AllowsGeneration() async throws {
        let correctionEntry = createMinimalKnowledgeEntry(
            id: "service-layer-no-hummingbird",
            title: "Service Layer Must Be Framework-Agnostic",
            content: "Services should not import Hummingbird."
        )
        let store = KnowledgeStore.forTesting(seedEntries: [correctionEntry])
        let tool = GenerateCodeTool(store: store)

        let codeWithWarning = """
        import Hummingbird

        struct UserService {
            func getUser(id: UUID) async throws -> User {
                // Service logic
            }
        }
        """

        let result = try await tool.handle([
            "description": .string("Extend service"),
            "layer": .string("service"),
            "existing_code": .string(codeWithWarning)
        ])

        // Non-critical violations should not block
        XCTAssertNotEqual(result.isError, true)
    }

    func testHandle_ExistingCodeValid_AllowsGeneration() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let validCode = """
        import Foundation

        struct UserService {
            func getUser(id: UUID) async throws -> User {
                // Service logic
            }
        }
        """

        let result = try await tool.handle([
            "description": .string("Add new method"),
            "layer": .string("service"),
            "existing_code": .string(validCode)
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Generated Code:"))
        }
    }

    func testHandle_InvalidExistingCodeType_IgnoresIt() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create service"),
            "layer": .string("service"),
            "existing_code": .int(123)
        ])

        XCTAssertNotEqual(result.isError, true)
    }

    // MARK: - Next Steps Guidance

    func testHandle_IncludesNextStepsGuidance() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create service"),
            "layer": .string("service")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("### Next steps"))
            XCTAssertTrue(message.contains("explain_pattern"))
            XCTAssertTrue(message.contains("check_architecture"))
            XCTAssertTrue(message.contains("get_best_practice"))
        }
    }

    // MARK: - All Layers

    func testHandle_ControllerLayer_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create endpoint"),
            "layer": .string("controller")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("**Layer:** controller"))
        }
    }

    func testHandle_RepositoryLayer_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create repository"),
            "layer": .string("repository")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("**Layer:** repository"))
        }
    }

    func testHandle_ModelLayer_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create model"),
            "layer": .string("model")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("**Layer:** model"))
        }
    }

    func testHandle_MiddlewareLayer_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create middleware"),
            "layer": .string("middleware")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("**Layer:** middleware"))
        }
    }

    func testHandle_ConfigurationLayer_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string("Create configuration"),
            "layer": .string("configuration")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("**Layer:** configuration"))
        }
    }

    // MARK: - Edge Cases

    func testHandle_EmptyDescription_StillWorks() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let result = try await tool.handle([
            "description": .string(""),
            "layer": .string("service")
        ])

        XCTAssertNotEqual(result.isError, true)
    }

    func testHandle_VeryLongDescription_HandlesCorrectly() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = GenerateCodeTool(store: store)

        let longDescription = String(repeating: "Create a service that does many things. ", count: 100)

        let result = try await tool.handle([
            "description": .string(longDescription),
            "layer": .string("service")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Generated Code:"))
        }
    }
}
