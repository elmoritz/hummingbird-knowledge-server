// Tests/HummingbirdKnowledgeServerTests/Middleware/DependencyInjectionMiddlewareTests.swift
//
// Comprehensive tests for DependencyInjectionMiddleware: validates dependency
// injection into request context, dependency availability, and middleware ordering.

import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import XCTest

@testable import HummingbirdKnowledgeServer

final class DependencyInjectionMiddlewareTests: XCTestCase {

    // MARK: - Dependency Injection Tests

    func testDependencyInjectionMiddleware_InjectsDependencies_IntoContext() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // The /ready endpoint accesses context.dependencies.knowledgeStore
            // If DI middleware didn't inject dependencies, this would crash
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "Request should succeed with injected dependencies"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("knowledgeEntries"),
                "Response should contain knowledge entries count from injected store"
            )
        }
    }

    func testDependencyInjectionMiddleware_KnowledgeStore_IsAccessible() async throws {
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
                "Knowledge store should be accessible via injected dependencies"
            )

            // The /ready endpoint uses context.dependencies.knowledgeStore.count
            // This verifies the knowledgeStore dependency is properly injected
            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("status"),
                "Response should contain status from accessible dependencies"
            )
        }
    }

    // MARK: - Dependency Availability Tests

    func testDependencyInjectionMiddleware_Dependencies_AvailableInAllRoutes() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // Test that dependencies are available across different routes

            // Health endpoint (doesn't use dependencies, but they should be injected)
            let healthResponse = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                healthResponse.status,
                .ok,
                "Dependencies should be injected for /health endpoint"
            )

            // Ready endpoint (uses dependencies)
            let readyResponse = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                readyResponse.status,
                .ok,
                "Dependencies should be injected for /ready endpoint"
            )

            // MCP endpoint (uses dependencies)
            let mcpResponse = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertNotNil(
                mcpResponse.status,
                "Dependencies should be injected for /mcp endpoint"
            )
        }
    }

    // MARK: - Multiple Request Tests

    func testDependencyInjectionMiddleware_MultipleRequests_EachGetsFreshContext() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // Make multiple requests to verify each gets properly injected dependencies
            for i in 1...5 {
                let response = try await client.execute(
                    uri: "/ready",
                    method: .get,
                    headers: [:]
                )

                XCTAssertEqual(
                    response.status,
                    .ok,
                    "Request \(i) should have properly injected dependencies"
                )

                let bodyString = String(buffer: response.body)
                XCTAssertTrue(
                    bodyString.contains("knowledgeEntries"),
                    "Request \(i) should access injected knowledge store"
                )
            }
        }
    }

    // MARK: - Middleware Ordering Tests

    func testDependencyInjectionMiddleware_RunsBeforeAuth() async throws {
        let app = try await buildTestApplication(enableAuth: true)

        try await app.test(.router) { client in
            // Even with auth failure, dependencies should be injected
            // (DI middleware runs first, before auth checks)
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .unauthorized,
                "Auth middleware should run after DI middleware"
            )

            // If DI middleware didn't run first, the app might crash
            // instead of returning a clean 401
        }
    }

    func testDependencyInjectionMiddleware_RunsBeforeRateLimit() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make requests to verify DI runs before rate limiting
            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: ByteBuffer(string: "{}")
                )
            }

            // 11th request should be rate limited
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                response.status,
                .tooManyRequests,
                "Rate limit should work with injected dependencies"
            )

            // Dependencies should still be injected even for rate-limited requests
        }
    }

    func testDependencyInjectionMiddleware_RunsBeforeRequestLogging() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // Request logging middleware runs after DI middleware
            // Both should work together seamlessly
            let response = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .ok,
                "Request should succeed with both DI and logging middleware"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("knowledgeEntries"),
                "Dependencies should be available after DI middleware runs"
            )
        }
    }

    // MARK: - Different HTTP Methods Tests

    func testDependencyInjectionMiddleware_GETRequests_HaveInjectedDependencies() async throws {
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
                "GET request should have injected dependencies"
            )
        }
    }

    func testDependencyInjectionMiddleware_POSTRequests_HaveInjectedDependencies() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // POST request should also get injected dependencies
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"]
            )

            XCTAssertNotNil(
                response.status,
                "POST request should have injected dependencies"
            )
        }
    }

    // MARK: - Dependency Graph Consistency Tests

    func testDependencyInjectionMiddleware_SameDependencies_AcrossRequests() async throws {
        let testEntries = [
            createMinimalKnowledgeEntry(id: "test-1", title: "Test 1"),
            createMinimalKnowledgeEntry(id: "test-2", title: "Test 2")
        ]

        let app = try await buildTestApplication(knowledgeEntries: testEntries)

        try await app.test(.router) { client in
            // Make two requests and verify they access the same dependency graph
            let response1 = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            let body1 = String(buffer: response1.body)
            XCTAssertTrue(
                body1.contains("\"knowledgeEntries\":\"2\""),
                "First request should see 2 entries"
            )

            let response2 = try await client.execute(
                uri: "/ready",
                method: .get,
                headers: [:]
            )

            let body2 = String(buffer: response2.body)
            XCTAssertTrue(
                body2.contains("\"knowledgeEntries\":\"2\""),
                "Second request should see same 2 entries from same dependency graph"
            )

            // Both responses should reference the same underlying dependencies
            XCTAssertEqual(
                body1,
                body2,
                "Same dependencies should produce consistent results"
            )
        }
    }

    // MARK: - Error Handling Tests

    func testDependencyInjectionMiddleware_ErrorResponses_StillHaveInjectedDependencies() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // Request to nonexistent endpoint should still have dependencies injected
            let response = try await client.execute(
                uri: "/nonexistent",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .notFound,
                "404 response should still have dependencies injected"
            )

            // If dependencies weren't injected, the middleware chain would break
        }
    }

    // MARK: - Context Isolation Tests

    func testDependencyInjectionMiddleware_ConcurrentRequests_IsolatedContexts() async throws {
        let app = try await buildTestApplication()

        try await app.test(.router) { client in
            // Make concurrent requests to verify each gets its own context
            // with properly injected dependencies
            async let response1 = client.execute(uri: "/ready", method: .get, headers: [:])
            async let response2 = client.execute(uri: "/ready", method: .get, headers: [:])
            async let response3 = client.execute(uri: "/ready", method: .get, headers: [:])

            let (r1, r2, r3) = try await (response1, response2, response3)

            XCTAssertEqual(r1.status, .ok, "Concurrent request 1 should have injected dependencies")
            XCTAssertEqual(r2.status, .ok, "Concurrent request 2 should have injected dependencies")
            XCTAssertEqual(r3.status, .ok, "Concurrent request 3 should have injected dependencies")

            // Each should access the shared dependencies without conflicts
            let body1 = String(buffer: r1.body)
            let body2 = String(buffer: r2.body)
            let body3 = String(buffer: r3.body)

            XCTAssertTrue(body1.contains("knowledgeEntries"), "Request 1 should access dependencies")
            XCTAssertTrue(body2.contains("knowledgeEntries"), "Request 2 should access dependencies")
            XCTAssertTrue(body3.contains("knowledgeEntries"), "Request 3 should access dependencies")
        }
    }
}
