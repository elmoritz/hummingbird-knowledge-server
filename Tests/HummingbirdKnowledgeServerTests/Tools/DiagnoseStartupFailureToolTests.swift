// Tests/HummingbirdKnowledgeServerTests/Tools/DiagnoseStartupFailureToolTests.swift
//
// Comprehensive tests for DiagnoseStartupFailureTool: validates pattern matching
// for common startup failures and diagnostic guidance.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class DiagnoseStartupFailureToolTests: XCTestCase {

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        XCTAssertEqual(tool.tool.name, "diagnose_startup_failure")
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
            XCTAssertTrue(requiredStrings.contains("error_output"), "error_output must be required")
            XCTAssertFalse(requiredStrings.contains("configuration"), "configuration must be optional")
        } else {
            XCTFail("Schema must have 'required' array")
        }
    }

    // MARK: - Argument Validation

    func testHandle_MissingErrorOutputArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertEqual(result.isError, true, "Should return error for missing error_output")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
            XCTAssertTrue(message.contains("error_output"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_InvalidErrorOutputType_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle(["error_output": .int(123)])

        XCTAssertEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
        }
    }

    // MARK: - Port Already In Use

    func testHandle_PortInUseError_ReturnsDiagnosis() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("Error: address already in use (bind failed)")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Diagnosis: Port Already In Use"))
            XCTAssertTrue(message.contains("lsof -i"))
            XCTAssertTrue(message.contains("PORT="))
            XCTAssertTrue(message.contains("**Fixes:**"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_EADDRINUSEError_ReturnsDiagnosis() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("Fatal error: EADDRINUSE on port 8080")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Diagnosis: Port Already In Use"))
        }
    }

    // MARK: - Dependency Injection Middleware Missing

    func testHandle_DependencyInjectionError_ReturnsDiagnosis() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("preconditionFailure: AppDependencies.placeholder accessed")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Diagnosis: DependencyInjectionMiddleware Not Registered"))
            XCTAssertTrue(message.contains("DependencyInjectionMiddleware"))
            XCTAssertTrue(message.contains("MUST be first"))
            XCTAssertTrue(message.contains("router.add(middleware:"))
        } else {
            XCTFail("Content should be text")
        }
    }

    // MARK: - Missing Module or Type

    func testHandle_CannotFindTypeError_ReturnsDiagnosis() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("error: cannot find type 'MCPServer' in scope")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Diagnosis: Missing Module or Type"))
            XCTAssertTrue(message.contains("Package.swift"))
            XCTAssertTrue(message.contains("swift package resolve"))
            XCTAssertTrue(message.contains("**Steps:**"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_NoSuchModuleError_ReturnsDiagnosis() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("error: no such module 'Hummingbird'")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Diagnosis: Missing Module or Type"))
            XCTAssertTrue(message.contains("swift package clean"))
        }
    }

    // MARK: - Task Cancelled

    func testHandle_TaskCancelledError_ReturnsDiagnosis() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("Fatal: task cancelled during startup")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Diagnosis: Task Cancelled at Startup"))
            XCTAssertTrue(message.contains("**Common causes:**"))
            XCTAssertTrue(message.contains("server.start"))
            XCTAssertTrue(message.contains("KnowledgeStore"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_CancelErrorError_ReturnsDiagnosis() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("Error: CancelError thrown during initialization")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Diagnosis: Task Cancelled at Startup"))
        }
    }

    // MARK: - General Diagnosis

    func testHandle_UnknownError_ReturnsGeneralGuidance() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("Unknown error: XYZ123 system failure")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Startup Failure Diagnosis"))
            XCTAssertTrue(message.contains("**General checklist:**"))
            XCTAssertTrue(message.contains("swift build"))
            XCTAssertTrue(message.contains("knowledge.json"))
            XCTAssertTrue(message.contains("LOG_LEVEL=debug"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_GeneralErrorWithRelevantEntries_IncludesThem() async throws {
        let entry = createMinimalKnowledgeEntry(
            id: "middleware-pattern",
            title: "Middleware Configuration",
            content: "How to configure middleware"
        )
        let store = KnowledgeStore.forTesting(seedEntries: [entry])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("Middleware error occurred during startup")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("**Potentially relevant patterns:**"))
            XCTAssertTrue(message.contains("Middleware Configuration"))
        }
    }

    // MARK: - Case Insensitivity

    func testHandle_CaseInsensitiveMatching_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("ERROR: ADDRESS ALREADY IN USE")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Diagnosis: Port Already In Use"))
        }
    }

    // MARK: - Error Truncation

    func testHandle_VeryLongError_TruncatesInGeneralDiagnosis() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let longError = String(repeating: "Error details here. ", count: 100)

        let result = try await tool.handle(["error_output": .string(longError)])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should contain truncated error (prefix 500)
            XCTAssertTrue(message.contains("**Error:**"))
            // The displayed error should be truncated
            let errorSection = message.components(separatedBy: "**Error:**")[1]
            XCTAssertLessThan(errorSection.count, longError.count)
        }
    }

    // MARK: - Optional Configuration Argument

    func testHandle_WithConfiguration_IgnoresIt() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        // configuration is optional and currently not used in the implementation
        let result = try await tool.handle([
            "error_output": .string("Some error"),
            "configuration": .string("PORT=8080\nENV=production")
        ])

        XCTAssertNotEqual(result.isError, true)
    }

    func testHandle_InvalidConfigurationType_IgnoresIt() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle([
            "error_output": .string("Error"),
            "configuration": .int(123)
        ])

        XCTAssertNotEqual(result.isError, true)
    }

    // MARK: - Edge Cases

    func testHandle_EmptyErrorOutput_ReturnsGeneralGuidance() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle(["error_output": .string("")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Startup Failure Diagnosis"))
            XCTAssertTrue(message.contains("**General checklist:**"))
        }
    }

    func testHandle_WhitespaceErrorOutput_ReturnsGeneralGuidance() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        let result = try await tool.handle(["error_output": .string("   \n  \t  ")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("## Startup Failure Diagnosis"))
        }
    }

    // MARK: - Multiple Pattern Matches

    func testHandle_MultiplePatterns_MatchesFirst() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let tool = DiagnoseStartupFailureTool(store: store)

        // This error contains both "address already in use" and "task cancelled"
        let result = try await tool.handle([
            "error_output": .string("address already in use, then task cancelled")
        ])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should match the first pattern (port in use)
            XCTAssertTrue(message.contains("## Diagnosis: Port Already In Use"))
        }
    }
}
