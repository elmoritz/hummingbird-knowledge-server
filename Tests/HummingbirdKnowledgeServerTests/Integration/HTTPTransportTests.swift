// Tests/HummingbirdKnowledgeServerTests/Integration/HTTPTransportTests.swift
//
// Integration tests for HTTP transport with MCP endpoint (/mcp).
// Tests the synchronous HTTP request/response transport.
//
// HTTP transport flow:
//   1. Client sends POST /mcp with JSON-RPC message
//   2. Server processes message via HTTP transport
//   3. Response is returned (current implementation returns 202 Accepted)
//
// These tests verify HTTP transport integration, not full JSON-RPC protocol semantics.

import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class HTTPTransportTests: XCTestCase {

    // MARK: - POST /mcp (HTTP Transport) Tests

    func testHTTPTransportPostEndpoint_ReturnsAccepted() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        // Valid JSON-RPC 2.0 request
        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 1
        }
        """

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp with HTTP transport should return 202 Accepted"
            )
        }
    }

    func testHTTPTransportPostEndpoint_RejectsEmptyBody() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "")
            )

            XCTAssertEqual(
                response.status,
                .badRequest,
                "POST /mcp with HTTP transport should return 400 Bad Request for empty body"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("must not be empty"),
                "Error message should indicate body must not be empty"
            )
        }
    }

    func testHTTPTransportPostEndpoint_AcceptsValidJSONRPC() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {
                    "name": "test-client",
                    "version": "1.0.0"
                }
            },
            "id": 1
        }
        """

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp with HTTP transport should accept valid JSON-RPC initialize request"
            )
        }
    }

    func testHTTPTransportPostEndpoint_AcceptsToolsListRequest() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 2
        }
        """

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp with HTTP transport should accept tools/list request"
            )
        }
    }

    func testHTTPTransportPostEndpoint_AcceptsResourcesListRequest() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "resources/list",
            "id": 3
        }
        """

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp with HTTP transport should accept resources/list request"
            )
        }
    }

    func testHTTPTransportPostEndpoint_AcceptsPromptsListRequest() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "prompts/list",
            "id": 4
        }
        """

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp with HTTP transport should accept prompts/list request"
            )
        }
    }

    func testHTTPTransportPostEndpoint_AcceptsNotificationRequest() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        // JSON-RPC notification (no id field)
        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        }
        """

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp with HTTP transport should accept notification (no response expected)"
            )
        }
    }

    func testHTTPTransportPostEndpoint_RejectsInvalidJSON() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        let invalidJSON = "{ this is not valid JSON }"

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: invalidJSON)
            )

            // The endpoint accepts any non-empty body and feeds it to the transport.
            // The MCP SDK will handle JSON validation.
            // So we expect 202 Accepted even for invalid JSON at the HTTP level.
            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp accepts raw body; JSON validation happens in MCP layer"
            )
        }
    }

    func testHTTPTransportPostEndpoint_HandlesConcurrentRequests() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 100
        }
        """

        try await app.test(.router) { client in
            // Send 5 concurrent requests
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<5 {
                    group.addTask {
                        do {
                            let response = try await client.execute(
                                uri: "/mcp",
                                method: .post,
                                headers: [.contentType: "application/json"],
                                body: ByteBuffer(string: jsonBody)
                            )

                            XCTAssertEqual(
                                response.status,
                                .accepted,
                                "Concurrent request \(i) should succeed"
                            )
                        } catch {
                            XCTFail("Concurrent request \(i) failed: \(error)")
                        }
                    }
                }
            }
        }
    }

    func testHTTPTransportPostEndpoint_HandlesLargePayload() async throws {
        let app = try await buildTestApplicationWithHTTPTransport()

        // Create a large but valid JSON-RPC request
        let largeContent = String(repeating: "a", count: 10_000)
        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "test-tool",
                "arguments": {
                    "data": "\(largeContent)"
                }
            },
            "id": 5
        }
        """

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp with HTTP transport should handle large payloads"
            )
        }
    }
}

// MARK: - Test Helpers

extension HTTPTransportTests {

    /// Builds a test application configured with HTTP transport instead of SSE transport.
    /// This allows testing the HTTP transport integration with the MCP endpoint.
    func buildTestApplicationWithHTTPTransport(
        knowledgeEntries: [KnowledgeEntry]? = nil,
        enableAuth: Bool = false,
        enableRateLimit: Bool = false
    ) async throws -> some ApplicationProtocol {

        _ = Logger(label: "com.hummingbird-knowledge-server.test-http")

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
            name: "hummingbird-knowledge-server-test-http",
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

        // ── Test HTTP Transport ───────────────────────────────────────────────────
        let transport = HummingbirdHTTPTransport(
            logger: Logger(label: "com.hummingbird-knowledge-server.test.transport.http")
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
                serverName: "hummingbird-knowledge-server-test-http/0.1.0"
            )
        )
    }
}
