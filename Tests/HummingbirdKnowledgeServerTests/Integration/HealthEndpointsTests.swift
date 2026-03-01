// Tests/HummingbirdKnowledgeServerTests/Integration/HealthEndpointsTests.swift
//
// Integration tests for health check endpoints (/health and /ready).
// These endpoints must always be available without authentication for
// load balancers, orchestrators, and monitoring systems.

import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

@testable import HummingbirdKnowledgeServer

final class HealthEndpointsTests: XCTestCase {

    // MARK: - /health Endpoint Tests

    func testHealthEndpoint_ReturnsOk() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/health should return 200 OK"
            )
        }
    }

    func testHealthEndpoint_ReturnsCorrectJSON() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("\"status\""),
                "Response should contain status field"
            )
            XCTAssertTrue(
                bodyString.contains("\"ok\""),
                "Status should be 'ok'"
            )
        }
    }

    func testHealthEndpoint_WorksWithoutAuthentication() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // Should work without any auth header
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/health must be accessible without authentication"
            )
        }
    }

    func testHealthEndpoint_WorksWithInvalidToken() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // Should work even with invalid token (auth is bypassed)
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [.authorization: "Bearer invalid-token"]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/health should ignore auth middleware"
            )
        }
    }

    func testHealthEndpoint_IsAlwaysHealthy() async throws {
        // Health endpoint should always return ok, regardless of dependencies
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // Call it multiple times
            for _ in 1...5 {
                let response = try await client.execute(
                    uri: "/health",
                    method: .get,
                    headers: [:]
                )

                XCTAssertEqual(
                    response.status,
                    .ok,
                    "/health should consistently return ok"
                )

                let bodyString = String(buffer: response.body)
                XCTAssertTrue(
                    bodyString.contains("ok"),
                    "Every response should contain 'ok'"
                )
            }
        }
    }

    // MARK: - /ready Endpoint Tests

    func testReadyEndpoint_ReturnsOk() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/ready should return 200 OK"
            )
        }
    }

    func testReadyEndpoint_ReturnsStatusAndCount() async throws {
        let testEntries = [
            createMinimalKnowledgeEntry(id: "test-1", title: "Entry 1"),
            createMinimalKnowledgeEntry(id: "test-2", title: "Entry 2"),
            createMinimalKnowledgeEntry(id: "test-3", title: "Entry 3"),
        ]
        let app = try await buildTestApplication(knowledgeEntries: testEntries)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("\"status\""),
                "Response should contain status field"
            )
            XCTAssertTrue(
                bodyString.contains("\"ok\""),
                "Status should be 'ok'"
            )
            XCTAssertTrue(
                bodyString.contains("\"knowledgeEntries\""),
                "Response should contain knowledgeEntries field"
            )
            XCTAssertTrue(
                bodyString.contains("\"3\""),
                "Knowledge entries count should be 3"
            )
        }
    }

    func testReadyEndpoint_ReflectsActualKnowledgeCount() async throws {
        // Test with different knowledge entry counts
        let singleEntry = [createMinimalKnowledgeEntry(id: "single")]
        let app = try await buildTestApplication(knowledgeEntries: singleEntry)

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("\"1\""),
                "Knowledge entries count should match actual count (1)"
            )
        }
    }

    func testReadyEndpoint_WorksWithEmptyKnowledgeStore() async throws {
        let app = try await buildTestApplication(knowledgeEntries: [])

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/ready should work even with empty knowledge store"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("\"0\""),
                "Knowledge entries count should be 0 for empty store"
            )
        }
    }

    func testReadyEndpoint_WorksWithoutAuthentication() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // Should work without any auth header
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/ready must be accessible without authentication"
            )
        }
    }

    func testReadyEndpoint_WorksWithInvalidToken() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // Should work even with invalid token (auth is bypassed)
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [.authorization: "Bearer invalid-token"]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/ready should ignore auth middleware"
            )
        }
    }

    // MARK: - Content-Type Tests

    func testHealthEndpoint_ReturnsJSONContentType() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            // Hummingbird automatically sets content-type for JSON responses
            let bodyString = String(buffer: response.body)
            // Just verify it's valid JSON by checking structure
            XCTAssertTrue(
                bodyString.hasPrefix("{") && bodyString.hasSuffix("}"),
                "Response should be valid JSON object"
            )
        }
    }

    func testReadyEndpoint_ReturnsJSONContentType() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            // Hummingbird automatically sets content-type for JSON responses
            let bodyString = String(buffer: response.body)
            // Just verify it's valid JSON by checking structure
            XCTAssertTrue(
                bodyString.hasPrefix("{") && bodyString.hasSuffix("}"),
                "Response should be valid JSON object"
            )
        }
    }

    // MARK: - Response Consistency Tests

    func testHealthAndReadyEndpoints_BothReturnStatusOk() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            let healthResponse = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            let readyResponse = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            // Both should return 200 OK
            XCTAssertEqual(healthResponse.status, .ok)
            XCTAssertEqual(readyResponse.status, .ok)

            // Both should have "status": "ok" in response
            let healthBody = String(buffer: healthResponse.body)
            let readyBody = String(buffer: readyResponse.body)

            XCTAssertTrue(
                healthBody.contains("\"ok\""),
                "/health should contain status ok"
            )
            XCTAssertTrue(
                readyBody.contains("\"ok\""),
                "/ready should contain status ok"
            )
        }
    }

    // MARK: - HTTP Method Tests

    func testHealthEndpoint_OnlySupportsGET() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // POST should not be supported
            let postResponse = try await client.execute(
                uri: "/health",
                method: .post,
                headers: [:]
            )

            // Should return method not allowed or not found
            XCTAssertNotEqual(
                postResponse.status,
                .ok,
                "POST to /health should not return 200"
            )

            // GET should work
            let getResponse = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                getResponse.status,
                .ok,
                "GET to /health should work"
            )
        }
    }

    func testReadyEndpoint_OnlySupportsGET() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // POST should not be supported
            let postResponse = try await client.execute(
                uri: "/ready",
                method: .post,
                headers: [:]
            )

            // Should return method not allowed or not found
            XCTAssertNotEqual(
                postResponse.status,
                .ok,
                "POST to /ready should not return 200"
            )

            // GET should work
            let getResponse = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                getResponse.status,
                .ok,
                "GET to /ready should work"
            )
        }
    }

    // MARK: - Integration with Middleware Stack

    func testHealthEndpoint_WorksWithRateLimiting() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Health endpoint should work even with rate limiting enabled
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/health should work with rate limiting enabled"
            )
        }
    }

    func testReadyEndpoint_WorksWithRateLimiting() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Ready endpoint should work even with rate limiting enabled
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/ready should work with rate limiting enabled"
            )
        }
    }

    func testHealthEndpoint_WorksWithAllMiddlewareEnabled() async throws {
        let app = try await buildTestApplication(
            enableAuth: true,
            enableRateLimit: true
        )

        try await app.test(.router) { client in
            // Health endpoint should bypass all middleware
            let response = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/health should work with all middleware enabled"
            )
        }
    }

    func testReadyEndpoint_WorksWithAllMiddlewareEnabled() async throws {
        let app = try await buildTestApplication(
            enableAuth: true,
            enableRateLimit: true
        )

        try await app.test(.router) { client in
            // Ready endpoint should bypass all middleware
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "/ready should work with all middleware enabled"
            )
        }
    }
}
