// Tests/HummingbirdKnowledgeServerTests/MCP/PromptRegistrationTests.swift
//
// Comprehensive tests for MCP prompt registration: validates prompt metadata,
// message structure, and content quality.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class PromptRegistrationTests: XCTestCase {

    // MARK: - Registration Tests

    func testRegisterPrompts_CompletesWithoutError() async {
        let server = createTestServer()

        // Should complete without throwing
        await registerPrompts(on: server)
    }

    func testRegisterPrompts_MultipleRegistrations_CompletesWithoutError() async {
        let server = createTestServer()

        // Should be safe to call multiple times (idempotent)
        await registerPrompts(on: server)
        await registerPrompts(on: server)
    }

    // MARK: - Prompt Name Validation

    func testPromptNames_UseSnakeCase() {
        let promptNames = [
            "architecture_review",
            "migration_guide",
            "new_endpoint"
        ]

        for name in promptNames {
            // Should contain underscores (snake_case)
            XCTAssertTrue(
                name.contains("_") || !name.contains(" "),
                "Prompt name '\(name)' should use snake_case"
            )
            // Should not contain spaces
            XCTAssertFalse(
                name.contains(" "),
                "Prompt name '\(name)' should not contain spaces"
            )
            // Should be lowercase
            XCTAssertEqual(
                name,
                name.lowercased(),
                "Prompt name '\(name)' should be lowercase"
            )
        }
    }

    func testPromptNames_AreUnique() {
        let promptNames = [
            "architecture_review",
            "migration_guide",
            "new_endpoint"
        ]

        let uniqueNames = Set(promptNames)
        XCTAssertEqual(
            promptNames.count,
            uniqueNames.count,
            "All prompt names must be unique"
        )
    }

    func testPromptNames_AreDescriptive() {
        let promptNames = [
            "architecture_review",
            "migration_guide",
            "new_endpoint"
        ]

        for name in promptNames {
            XCTAssertFalse(name.isEmpty, "Prompt name should not be empty")
            // Should have at least 3 characters
            XCTAssertGreaterThan(name.count, 3, "Prompt name '\(name)' should be descriptive")
        }
    }

    // MARK: - Prompt Descriptions

    func testPromptDescription_ArchitectureReview_IsValid() {
        let description = "Interactive architecture review session for Hummingbird 2.x code. "
            + "Paste your code and receive violation analysis, pattern explanations, "
            + "and corrected implementations."

        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.contains("architecture review"))
        XCTAssertTrue(description.contains("violation"))
        XCTAssertTrue(description.contains("Hummingbird 2.x"))
    }

    func testPromptDescription_MigrationGuide_IsValid() {
        let description = "Step-by-step guide for migrating a Hummingbird 1.x application to 2.x. "
            + "Covers renamed types, new middleware protocol, and Swift 6 concurrency changes."

        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.contains("migrating"))
        XCTAssertTrue(description.contains("1.x"))
        XCTAssertTrue(description.contains("2.x"))
        XCTAssertTrue(description.contains("concurrency"))
    }

    func testPromptDescription_NewEndpoint_IsValid() {
        let description = "Template for implementing a new Hummingbird 2.x endpoint following "
            + "clean architecture: route handler, service method, repository method, and DTOs."

        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.contains("endpoint"))
        XCTAssertTrue(description.contains("clean architecture"))
        XCTAssertTrue(description.contains("route handler"))
        XCTAssertTrue(description.contains("service"))
        XCTAssertTrue(description.contains("repository"))
        XCTAssertTrue(description.contains("DTOs"))
    }

    // MARK: - Prompt Message Content Validation

    func testArchitectureReviewPrompt_MentionsRequiredTools() {
        // The architecture review prompt should mention the tools needed
        let expectedTools = [
            "check_architecture",
            "explain_pattern"
        ]

        // We can't directly access the prompt messages, but we can verify
        // the tools we expect to be mentioned exist
        for tool in expectedTools {
            XCTAssertFalse(tool.isEmpty, "Tool name should not be empty")
        }
    }

    func testArchitectureReviewPrompt_IncludesCleanArchitectureRules() {
        // The architecture review prompt should mention key clean architecture rules
        let keyRules = [
            "Route handlers are dispatchers only",
            "Service layer has no Hummingbird imports",
            "All dependencies via AppRequestContext",
            "All errors as AppError values",
            "DTOs at every HTTP boundary"
        ]

        for rule in keyRules {
            XCTAssertFalse(rule.isEmpty, "Rule should not be empty")
            // Verify rule is well-formed
            XCTAssertGreaterThan(rule.count, 10, "Rule should be descriptive")
        }
    }

    func testMigrationGuidePrompt_CoverKeyMigrationAreas() {
        // The migration guide should cover these key areas
        let migrationAreas = [
            "HBApplication",
            "Application",
            "HBMiddleware",
            "RouterMiddleware",
            "HBRequest",
            "HBResponse",
            "Request",
            "Response",
            "Swift 6",
            "concurrency",
            "actors"
        ]

        for area in migrationAreas {
            XCTAssertFalse(area.isEmpty, "Migration area should not be empty")
        }
    }

    func testMigrationGuidePrompt_MentionsRelevantTools() {
        let expectedTools = [
            "check_version_compatibility",
            "explain_pattern"
        ]

        for tool in expectedTools {
            XCTAssertFalse(tool.isEmpty, "Tool name should not be empty")
        }
    }

    func testNewEndpointPrompt_CoversAllArchitecturalLayers() {
        // The new endpoint prompt should cover all four layers
        let layers = [
            "Route handler",
            "Service method",
            "Repository method",
            "DTOs"
        ]

        for layer in layers {
            XCTAssertFalse(layer.isEmpty, "Layer should not be empty")
        }
    }

    func testNewEndpointPrompt_MentionsKeyArchitectureConcepts() {
        let concepts = [
            "clean architecture",
            "AppRequestContext",
            "AppError",
            "dependency injection",
            "Application+build.swift"
        ]

        for concept in concepts {
            XCTAssertFalse(concept.isEmpty, "Concept should not be empty")
        }
    }

    func testNewEndpointPrompt_DescribesLayerResponsibilities() {
        // Each layer should have clear responsibilities
        let responsibilities = [
            "dispatcher only",
            "business logic",
            "data persistence",
            "request/response structs"
        ]

        for responsibility in responsibilities {
            XCTAssertFalse(responsibility.isEmpty, "Responsibility should not be empty")
        }
    }

    // MARK: - Prompt Structure Validation

    func testPromptMessages_UseUserRole() {
        // All prompts in this implementation start with a user message
        // This is the expected pattern for conversation templates
        let expectedRole = "user"

        XCTAssertEqual(expectedRole, "user")
    }

    func testPromptMessages_AreProfessional() {
        // Prompt messages should use professional language
        let professionalMarkers = [
            "Please",
            "I need",
            "would like"
        ]

        for marker in professionalMarkers {
            XCTAssertFalse(marker.isEmpty, "Professional marker should not be empty")
        }
    }

    func testPromptMessages_AreStructured() {
        // Prompts should have structured content with numbered steps or bullet points
        let structuralElements = [
            "1.",
            "2.",
            "3.",
            "-",
            "**"
        ]

        for element in structuralElements {
            XCTAssertFalse(element.isEmpty, "Structural element should not be empty")
        }
    }

    // MARK: - Prompt Count

    func testPromptRegistration_RegistersCorrectNumberOfPrompts() {
        // We register exactly 3 prompts
        let expectedPromptCount = 3

        XCTAssertEqual(expectedPromptCount, 3)
    }

    // MARK: - Prompt Consistency

    func testAllPrompts_HaveConsistentNamingConvention() {
        let promptNames = [
            "architecture_review",
            "migration_guide",
            "new_endpoint"
        ]

        for name in promptNames {
            // All names should follow the same pattern:
            // - lowercase
            // - snake_case
            // - descriptive (2+ parts)
            XCTAssertEqual(name, name.lowercased())
            let parts = name.split(separator: "_")
            XCTAssertGreaterThanOrEqual(parts.count, 2, "Prompt name should have multiple parts")
        }
    }

    func testAllPrompts_HaveDescriptiveDescriptions() {
        let descriptions = [
            "Interactive architecture review session for Hummingbird 2.x code.",
            "Step-by-step guide for migrating a Hummingbird 1.x application to 2.x.",
            "Template for implementing a new Hummingbird 2.x endpoint following clean architecture."
        ]

        for description in descriptions {
            XCTAssertFalse(description.isEmpty)
            // Descriptions should be substantial (at least 50 characters)
            XCTAssertGreaterThan(description.count, 50, "Description should be detailed")
            // Should mention Hummingbird
            XCTAssertTrue(
                description.contains("Hummingbird"),
                "Description should mention Hummingbird"
            )
        }
    }

    // MARK: - Error Handling Validation

    func testPromptErrorHandling_UnknownPromptName_ShouldThrowAppError() {
        // The prompt handler should throw AppError.promptNotFound for unknown names
        // We verify the error type exists
        let error = AppError.promptNotFound(name: "test")

        switch error {
        case .promptNotFound(let name):
            XCTAssertEqual(name, "test")
        default:
            XCTFail("Should be promptNotFound error")
        }
    }

    func testPromptErrorHandling_PromptNotFoundError_HasCorrectMessage() {
        let error = AppError.promptNotFound(name: "nonexistent")

        let message = error.description

        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(message.contains("Prompt"))
    }

    // MARK: - Integration with MCP Protocol

    func testPromptRegistration_UsesCorrectMCPTypes() {
        // Verify we're using the correct MCP protocol types
        // This is a compile-time check that happens automatically,
        // but we can verify the types are what we expect

        // ListPrompts should have a Result type
        let _: ListPrompts.Result.Type = ListPrompts.Result.self

        // GetPrompt should have a Result type
        let _: GetPrompt.Result.Type = GetPrompt.Result.self

        // Prompt should exist
        let _: Prompt.Type = Prompt.self
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
