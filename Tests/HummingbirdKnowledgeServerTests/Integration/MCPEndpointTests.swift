// Tests/HummingbirdKnowledgeServerTests/Integration/MCPEndpointTests.swift
//
// Integration tests for MCP endpoint (/mcp).
// Tests the SSE streaming transport (GET) and JSON-RPC message handling (POST).
//
// MCP protocol flow:
//   1. Client opens GET /mcp → establishes SSE stream
//   2. Client sends POST /mcp with JSON-RPC message → returns 202 Accepted
//   3. Server processes message and sends response via SSE stream
//
// These tests verify HTTP-level behavior, not full JSON-RPC protocol semantics.

import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

@testable import HummingbirdKnowledgeServer

final class MCPEndpointTests: XCTestCase {

    // MARK: - GET /mcp (SSE Stream) Tests
    //
    // NOTE: GET /mcp opens a persistent SSE stream that never closes naturally.
    // The HummingbirdTesting framework's client.execute() waits for response completion,
    // which causes tests to hang indefinitely. SSE stream testing requires a different
    // approach (e.g., URLSession with timeout, or testing the transport layer directly).
    //
    // The GET endpoint functionality is implicitly tested through:
    // 1. MCPServerService tests (if they exist)
    // 2. Manual integration testing with real MCP clients
    // 3. The transport layer unit tests
    //
    // For now, we focus on testing the POST endpoint which can be tested reliably.

    // MARK: - POST /mcp (Message Handler) Tests

    func testMCPPostEndpoint_ReturnsAccepted() async throws {
        let app = try await buildTestApplication()

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
                "POST /mcp should return 202 Accepted immediately"
            )
        }
    }

    func testMCPPostEndpoint_RejectsEmptyBody() async throws {
        let app = try await buildTestApplication()

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
                "POST /mcp should return 400 Bad Request for empty body"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("must not be empty"),
                "Error message should indicate body must not be empty"
            )
        }
    }

    func testMCPPostEndpoint_AcceptsValidJSONRPC() async throws {
        let app = try await buildTestApplication()

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
                "POST /mcp should accept valid JSON-RPC initialize request"
            )
        }
    }

    func testMCPPostEndpoint_AcceptsToolsListRequest() async throws {
        let app = try await buildTestApplication()

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
                "POST /mcp should accept tools/list request"
            )
        }
    }

    func testMCPPostEndpoint_AcceptsResourcesListRequest() async throws {
        let app = try await buildTestApplication()

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
                "POST /mcp should accept resources/list request"
            )
        }
    }

    func testMCPPostEndpoint_AcceptsPromptsListRequest() async throws {
        let app = try await buildTestApplication()

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
                "POST /mcp should accept prompts/list request"
            )
        }
    }

    func testMCPPostEndpoint_RequiresAuthenticationWhenEnabled() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 1
        }
        """

        try await app.test(.router) { client in
            // Should reject requests without auth when auth is enabled
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "POST /mcp should require authentication when auth is enabled"
            )
        }
    }

    func testMCPPostEndpoint_WorksWithAuthentication() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 1
        }
        """

        try await app.test(.router) { client in
            // Should work with valid auth token when auth is enabled
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer test-token"
                ],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp should work with valid authentication"
            )
        }
    }

    func testMCPPostEndpoint_WorksInLocalMode() async throws {
        let app = try await buildTestApplication(enableAuth: false)

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 1
        }
        """

        try await app.test(.router) { client in
            // Should work without auth when in local mode (auth disabled)
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp should work without auth in local mode"
            )
        }
    }

    func testMCPPostEndpoint_HandlesMultipleRequests() async throws {
        let app = try await buildTestApplication()

        let jsonBody1 = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 1
        }
        """

        let jsonBody2 = """
        {
            "jsonrpc": "2.0",
            "method": "resources/list",
            "id": 2
        }
        """

        try await app.test(.router) { client in
            // Send multiple requests sequentially
            let response1 = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody1)
            )

            let response2 = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody2)
            )

            XCTAssertEqual(response1.status, .accepted, "First request should be accepted")
            XCTAssertEqual(response2.status, .accepted, "Second request should be accepted")
        }
    }

    func testMCPPostEndpoint_HandlesLargePayload() async throws {
        let app = try await buildTestApplication()

        // Create a large but valid JSON-RPC request
        let largeParams = String(repeating: "a", count: 10_000)
        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "check_architecture",
                "arguments": {
                    "code": "\(largeParams)"
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

            // Should accept large payloads (up to 1MB per controller implementation)
            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp should accept large payloads under 1MB"
            )
        }
    }

    // MARK: - HTTP Method Tests

    func testMCPEndpoint_SupportsPOST() async throws {
        let app = try await buildTestApplication()

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
                "POST /mcp should be supported"
            )
        }
    }

    func testMCPEndpoint_RejectsPUT() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .put,
                headers: [:]
            )

            // PUT should not be supported
            XCTAssertNotEqual(
                response.status,
                .ok,
                "PUT /mcp should not return 200"
            )
            XCTAssertNotEqual(
                response.status,
                .accepted,
                "PUT /mcp should not return 202"
            )
        }
    }

    func testMCPEndpoint_RejectsDELETE() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .delete,
                headers: [:]
            )

            // DELETE should not be supported
            XCTAssertNotEqual(
                response.status,
                .ok,
                "DELETE /mcp should not return 200"
            )
            XCTAssertNotEqual(
                response.status,
                .accepted,
                "DELETE /mcp should not return 202"
            )
        }
    }

    // MARK: - Integration with Middleware Stack

    func testMCPEndpoint_WorksWithRateLimiting() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 1
        }
        """

        try await app.test(.router) { client in
            // MCP endpoint should work even with rate limiting enabled
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp should work with rate limiting enabled"
            )
        }
    }

    func testMCPEndpoint_WorksWithAllMiddlewareEnabled() async throws {
        let app = try await buildTestApplication(
            enableAuth: true,
            enableRateLimit: true
        )

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 1
        }
        """

        try await app.test(.router) { client in
            // MCP endpoint should work with all middleware enabled and valid auth
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .contentType: "application/json",
                    .authorization: "Bearer test-token"
                ],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp should work with all middleware enabled and valid auth"
            )
        }
    }

    // MARK: - Error Handling Tests

    func testMCPPostEndpoint_RejectsNullBody() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"]
            )

            XCTAssertEqual(
                response.status,
                .badRequest,
                "POST /mcp should reject requests with no body"
            )
        }
    }

    func testMCPPostEndpoint_ToleratesInvalidJSON() async throws {
        let app = try await buildTestApplication()

        // Send invalid JSON - the controller should accept it and let MCP SDK handle validation
        let invalidJson = "{ invalid json }"

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: invalidJson)
            )

            // Controller accepts anything non-empty; validation happens in MCP SDK
            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp accepts all non-empty bodies (MCP SDK validates protocol)"
            )
        }
    }

    // MARK: - Content Negotiation Tests

    func testMCPPostEndpoint_WorksWithoutContentType() async throws {
        let app = try await buildTestApplication()

        let jsonBody = """
        {
            "jsonrpc": "2.0",
            "method": "tools/list",
            "id": 1
        }
        """

        try await app.test(.router) { client in
            // Should work even without Content-Type header
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [:],
                body: ByteBuffer(string: jsonBody)
            )

            XCTAssertEqual(
                response.status,
                .accepted,
                "POST /mcp should work without Content-Type header"
            )
        }
    }

    func testMCPPostEndpoint_WorksWithJSONContentType() async throws {
        let app = try await buildTestApplication()

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
                "POST /mcp should work with application/json Content-Type"
            )
        }
    }
}
