// Tests/HummingbirdKnowledgeServerTests/Helpers/TestHelpers.swift
//
// Shared test helpers for building test applications with fake dependencies.
// Following the HummingbirdTesting pattern: always use .router mode for speed.

import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

// MARK: - Test Application Builder

/// Builds a fully configured test application with test dependencies.
/// Uses the same dependency injection pattern as the production app,
/// but with in-memory test data instead of real resources.
///
/// - Parameters:
///   - knowledgeEntries: Test knowledge entries to seed the store with. Defaults to minimal fixture.
///   - enableAuth: If true, adds auth middleware with token "test-token". Defaults to false.
///   - enableRateLimit: If true, adds rate limit middleware. Defaults to false.
/// - Returns: An application instance configured for testing with `.router` mode
func buildTestApplication(
    knowledgeEntries: [KnowledgeEntry]? = nil,
    enableAuth: Bool = false,
    enableRateLimit: Bool = false
) async throws -> some ApplicationProtocol {

    _ = Logger(label: "com.hummingbird-knowledge-server.test")

    // ── Test Knowledge Store ──────────────────────────────────────────────────
    let seedEntries: [KnowledgeEntry]
    if let knowledgeEntries = knowledgeEntries {
        seedEntries = knowledgeEntries
    } else {
        seedEntries = try loadTestFixture()
    }
    let knowledgeStore = KnowledgeStore(seedEntries: seedEntries)

    // ── Test MCP Server ───────────────────────────────────────────────────────
    let mcpServer = Server(
        name: "hummingbird-knowledge-server-test",
        version: "0.1.0-test",
        capabilities: .init(
            prompts: .init(listChanged: false),
            resources: .init(subscribe: false, listChanged: true),
            tools: .init(listChanged: true)
        )
    )

    await registerTools(on: mcpServer, knowledgeStore: knowledgeStore)
    await registerResources(on: mcpServer, knowledgeStore: knowledgeStore)
    await registerPrompts(on: mcpServer)

    // ── Test Transport ────────────────────────────────────────────────────────
    let transport = HummingbirdSSETransport(
        logger: Logger(label: "com.hummingbird-knowledge-server.test.transport")
    )

    // ── Test Dependencies ─────────────────────────────────────────────────────
    let dependencies = AppDependencies(
        mcpServer: mcpServer,
        transport: transport,
        knowledgeStore: knowledgeStore
    )

    // ── Router ────────────────────────────────────────────────────────────────
    let router = Router(context: AppRequestContext.self)

    // Middleware — always inject dependencies first
    router.add(middleware: DependencyInjectionMiddleware(dependencies: dependencies))
    router.add(middleware: RequestLoggingMiddleware())

    // Optional test middleware
    if enableAuth {
        router.add(middleware: AuthMiddleware(token: "test-token"))
    }
    if enableRateLimit {
        router.add(middleware: RateLimitMiddleware(requestsPerMinute: 10))
    }

    // Infrastructure endpoints
    router.get("/health") { _, _ in
        ["status": "ok"]
    }
    router.get("/ready") { _, context in
        let count = await context.dependencies.knowledgeStore.count
        return ["status": "ok", "knowledgeEntries": "\(count)"]
    }

    // MCP endpoint
    MCPController().registerRoutes(on: router.group("/mcp"))

    return Application(
        router: router,
        configuration: .init(
            address: .hostname("127.0.0.1", port: 0), // Port 0 = system-assigned
            serverName: "hummingbird-knowledge-server-test/0.1.0"
        )
    )
}

// MARK: - Test Fixture Loading

/// Loads the minimal test fixture from `Fixtures/knowledge-test.json`.
/// Falls back to a hardcoded minimal entry if the fixture file is missing.
func loadTestFixture() throws -> [KnowledgeEntry] {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("knowledge-test.json")

    guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
        // Fallback: return minimal in-memory entry
        return [createMinimalKnowledgeEntry()]
    }

    let data = try Data(contentsOf: fixtureURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([KnowledgeEntry].self, from: data)
}

/// Creates a single minimal knowledge entry for tests that don't need fixtures.
func createMinimalKnowledgeEntry(
    id: String = "test-entry-1",
    title: String = "Test Pattern",
    content: String = "This is a test knowledge entry.",
    layer: ArchitecturalLayer = .service
) -> KnowledgeEntry {
    KnowledgeEntry(
        id: id,
        title: title,
        content: content,
        layer: layer,
        patternIds: ["test-pattern"],
        violationIds: [],
        hummingbirdVersionRange: ">=2.0.0",
        swiftVersionRange: ">=6.0",
        isTutorialPattern: false,
        correctionId: nil,
        confidence: 1.0,
        source: "test",
        lastVerifiedAt: Date()
    )
}

// MARK: - KnowledgeStore Test Extension

extension KnowledgeStore {
    /// Creates a test KnowledgeStore with the given seed entries.
    /// Exposed for testing only — production code uses `loadFromBundle()`.
    static func forTesting(seedEntries: [KnowledgeEntry] = []) -> KnowledgeStore {
        KnowledgeStore(seedEntries: seedEntries)
    }
}

// MARK: - XCTest Assertions

extension XCTestCase {

    /// Asserts that a response contains the expected JSON structure.
    /// Decodes the response body as JSON and validates it matches expectations.
    func assertJSONResponse<T: Decodable>(
        _ response: TestResponse,
        status expectedStatus: HTTPResponse.Status,
        type: T.Type,
        file: StaticString = #filePath,
        line: UInt = #line,
        validate: (T) throws -> Void = { _ in }
    ) throws {
        XCTAssertEqual(
            response.status,
            expectedStatus,
            "Response status mismatch",
            file: file,
            line: line
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(T.self, from: response.body)
        try validate(decoded)
    }

    /// Asserts that a response body contains the expected string content.
    func assertResponseContains(
        _ response: TestResponse,
        status expectedStatus: HTTPResponse.Status,
        substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            response.status,
            expectedStatus,
            "Response status mismatch",
            file: file,
            line: line
        )

        let bodyString = String(buffer: response.body)
        XCTAssertTrue(
            bodyString.contains(substring),
            "Response body does not contain '\(substring)'. Body: \(bodyString)",
            file: file,
            line: line
        )
    }
}
