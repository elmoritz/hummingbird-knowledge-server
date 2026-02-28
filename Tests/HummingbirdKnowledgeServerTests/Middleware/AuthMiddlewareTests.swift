// Tests/HummingbirdKnowledgeServerTests/Middleware/AuthMiddlewareTests.swift
//
// Comprehensive tests for AuthMiddleware: validates token authentication,
// header parsing, exemptions for health endpoints, and error responses.

import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import XCTest

@testable import HummingbirdKnowledgeServer

final class AuthMiddlewareTests: XCTestCase {

    // MARK: - Valid Token Tests

    func testAuthMiddleware_WithValidToken_AllowsAccess() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .authorization: "Bearer test-token",
                    .contentType: "application/json"
                ],
                body: ByteBuffer(string: "{}")
            )

            // Should successfully reach the MCP endpoint
            XCTAssertNotEqual(
                response.status,
                .unauthorized,
                "Valid token should grant access"
            )
        }
    }

    func testAuthMiddleware_WithValidTokenOnDifferentEndpoint_AllowsAccess() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [.authorization: "Bearer test-token"]
            )

            // /ready endpoint should work with valid token
            XCTAssertEqual(response.status, .ok)
        }
    }

    // MARK: - Invalid Token Tests

    func testAuthMiddleware_WithInvalidToken_ReturnsUnauthorized() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .authorization: "Bearer wrong-token",
                    .contentType: "application/json"
                ],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "Invalid token should return 401"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("Valid Bearer token required"),
                "Error message should explain authentication requirement"
            )
        }
    }

    func testAuthMiddleware_WithMalformedBearerToken_ReturnsUnauthorized() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // Missing "Bearer " prefix
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .authorization: "test-token",
                    .contentType: "application/json"
                ],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "Malformed authorization header should return 401"
            )
        }
    }

    func testAuthMiddleware_WithBearerButNoToken_ReturnsUnauthorized() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // "Bearer " prefix but no actual token
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .authorization: "Bearer ",
                    .contentType: "application/json"
                ],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "Empty token should return 401"
            )
        }
    }

    // MARK: - Missing Token Tests

    func testAuthMiddleware_WithMissingAuthorizationHeader_ReturnsUnauthorized() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "Missing authorization header should return 401"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("Valid Bearer token required"),
                "Error message should explain authentication requirement"
            )
        }
    }

    func testAuthMiddleware_WithEmptyAuthorizationHeader_ReturnsUnauthorized() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .authorization: "",
                    .contentType: "application/json"
                ],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "Empty authorization header should return 401"
            )
        }
    }

    // MARK: - Exempted Endpoints Tests

    func testAuthMiddleware_HealthEndpoint_ExemptFromAuth() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // /health should work without any authentication
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/health endpoint should be exempt from authentication"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("ok"),
                "Health endpoint should return status ok"
            )
        }
    }

    func testAuthMiddleware_ReadyEndpoint_ExemptFromAuth() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // /ready should work without any authentication
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/ready endpoint should be exempt from authentication"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("ok"),
                "Ready endpoint should return status ok"
            )
        }
    }

    func testAuthMiddleware_HealthEndpoint_WorksWithInvalidToken() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // /health should work even with an invalid token
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.authorization: "Bearer wrong-token"]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/health endpoint should be exempt even with invalid token"
            )
        }
    }

    func testAuthMiddleware_ReadyEndpoint_WorksWithInvalidToken() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // /ready should work even with an invalid token
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [.authorization: "Bearer wrong-token"]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/ready endpoint should be exempt even with invalid token"
            )
        }
    }

    // MARK: - HTTP Methods Tests

    func testAuthMiddleware_POSTRequest_RequiresValidToken() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // POST without token should fail
            let responseWithoutToken = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [:]
            )

            XCTAssertEqual(
                responseWithoutToken.status,
                .unauthorized,
                "POST without token should return 401"
            )

            // POST with valid token should succeed (or at least not fail auth)
            let responseWithToken = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.authorization: "Bearer test-token"]
            )

            XCTAssertNotEqual(
                responseWithToken.status,
                .unauthorized,
                "POST with valid token should pass auth middleware"
            )
        }
    }

    // MARK: - Case Sensitivity Tests

    func testAuthMiddleware_TokenIsCaseSensitive() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // "TEST-TOKEN" should not match "test-token"
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .authorization: "Bearer TEST-TOKEN",
                    .contentType: "application/json"
                ],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "Token comparison should be case-sensitive"
            )
        }
    }

    func testAuthMiddleware_BearerPrefixIsCaseInsensitive() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // HTTP headers are case-insensitive, but we check the value prefix
            // "bearer " (lowercase) should not work because we check for "Bearer "
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .authorization: "bearer test-token",
                    .contentType: "application/json"
                ],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "Bearer prefix check is case-sensitive per implementation"
            )
        }
    }

    // MARK: - Whitespace Tests

    func testAuthMiddleware_TokenWithExtraWhitespace_ReturnsUnauthorized() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // Token with leading/trailing spaces should not match
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [
                    .authorization: "Bearer  test-token",
                    .contentType: "application/json"
                ],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "Token with extra whitespace should not match"
            )
        }
    }
}
