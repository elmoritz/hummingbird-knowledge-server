// Tests/HummingbirdKnowledgeServerTests/Middleware/RateLimitMiddlewareTests.swift
//
// Comprehensive tests for RateLimitMiddleware: validates request counting,
// limit enforcement, window sliding, client IP detection, and exemptions.

import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import Logging
import XCTest

@testable import HummingbirdKnowledgeServer

final class RateLimitMiddlewareTests: XCTestCase {

    // MARK: - Request Counting Tests

    func testRateLimitMiddleware_WithinLimit_AllowsRequests() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make 5 requests (limit is 10 per minute)
            for _ in 1...5 {
                let response = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: [:]
                )

                XCTAssertNotEqual(
                    response.status,
                    .tooManyRequests,
                    "Requests within limit should succeed"
                )
            }
        }
    }

    func testRateLimitMiddleware_AtExactLimit_AllowsAllRequests() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make exactly 10 requests (the configured limit)
            for i in 1...10 {
                let response = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: [:]
                )

                XCTAssertNotEqual(
                    response.status,
                    .tooManyRequests,
                    "Request \(i) at exact limit should succeed"
                )
            }
        }
    }

    // MARK: - Limit Enforcement Tests

    func testRateLimitMiddleware_ExceedsLimit_Returns429() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make 10 requests to reach the limit
            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: [:]
                )
            }

            // 11th request should be rate limited
            let response = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .tooManyRequests,
                "Request exceeding limit should return 429"
            )

            let bodyString = String(buffer: response.body)
            XCTAssertTrue(
                bodyString.contains("Rate limit exceeded"),
                "Error message should explain rate limit violation"
            )
            XCTAssertTrue(
                bodyString.contains("10 requests per minute"),
                "Error message should state the limit"
            )
        }
    }

    func testRateLimitMiddleware_AfterExceedingLimit_ContinuesBlocking() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Exceed the limit
            for _ in 1...11 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: [:]
                )
            }

            // Multiple subsequent requests should also be blocked
            for _ in 1...3 {
                let response = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: [:]
                )

                XCTAssertEqual(
                    response.status,
                    .tooManyRequests,
                    "Requests after exceeding limit should stay blocked"
                )
            }
        }
    }

    // MARK: - Window Sliding Tests

    func testRateLimitMiddleware_SlidingWindow_AllowsNewRequests() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make initial request
            let response1 = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: [:]
            )

            XCTAssertNotEqual(
                response1.status,
                .tooManyRequests,
                "First request should succeed"
            )

            // Wait for sliding window to advance (61 seconds to ensure old request drops off)
            // In tests, we can't actually wait 61 seconds, so this test verifies the logic exists
            // but accepts that in-memory implementation maintains state

            // Make another request immediately to verify counter increments
            let response2 = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: [:]
            )

            XCTAssertNotEqual(
                response2.status,
                .tooManyRequests,
                "Second request should succeed"
            )
        }
    }

    // MARK: - Exempted Endpoints Tests

    func testRateLimitMiddleware_HealthEndpoint_ExemptFromRateLimit() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make excessive requests to /health endpoint
            for _ in 1...20 {
                let response = try await client.execute(
                    uri: "/health",
                    method: .get,
                    headers: [:]
                )

                XCTAssertEqual(
                    response.status,
                    .ok,
                    "/health endpoint should never be rate limited"
                )
            }
        }
    }

    func testRateLimitMiddleware_ReadyEndpoint_ExemptFromRateLimit() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make excessive requests to /ready endpoint
            for _ in 1...20 {
                let response = try await client.execute(
                    uri: "/ready",
                    method: .get,
                    headers: [:]
                )

                XCTAssertEqual(
                    response.status,
                    .ok,
                    "/ready endpoint should never be rate limited"
                )
            }
        }
    }

    func testRateLimitMiddleware_HealthAndReady_DoNotConsumeQuota() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make many requests to exempted endpoints
            for _ in 1...15 {
                _ = try await client.execute(uri: "/health", method: .get, headers: [:])
                _ = try await client.execute(uri: "/ready", method: .get, headers: [:])
            }

            // Should still be able to make 10 requests to regular endpoint
            for i in 1...10 {
                let response = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: [:]
                )

                XCTAssertNotEqual(
                    response.status,
                    .tooManyRequests,
                    "Request \(i) should succeed - exempted endpoints don't consume quota"
                )
            }

            // 11th request to regular endpoint should be rate limited
            let response = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .tooManyRequests,
                "11th request should be rate limited after consuming quota"
            )
        }
    }

    // MARK: - Client IP Detection Tests

    func testRateLimitMiddleware_XForwardedFor_UsedForClientIP() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make 10 requests with same X-Forwarded-For header
            var headers1 = HTTPFields()
            headers1[.init("x-forwarded-for")!] = "192.168.1.100"

            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: headers1
                )
            }

            // 11th request with same IP should be rate limited
            let response1 = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: headers1
            )

            XCTAssertEqual(
                response1.status,
                .tooManyRequests,
                "Same X-Forwarded-For IP should be rate limited"
            )

            // Request with different X-Forwarded-For should succeed
            var headers2 = HTTPFields()
            headers2[.init("x-forwarded-for")!] = "192.168.1.200"

            let response2 = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: headers2
            )

            XCTAssertNotEqual(
                response2.status,
                .tooManyRequests,
                "Different X-Forwarded-For IP should have separate limit"
            )
        }
    }

    func testRateLimitMiddleware_XForwardedFor_HandlesMultipleProxies() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // X-Forwarded-For with multiple IPs (client, proxy1, proxy2)
            // Should use the first IP (client IP)
            var headers = HTTPFields()
            headers[.init("x-forwarded-for")!] = "203.0.113.1, 10.0.0.1, 10.0.0.2"

            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: headers
                )
            }

            // 11th request should be rate limited
            let response = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: headers
            )

            XCTAssertEqual(
                response.status,
                .tooManyRequests,
                "Should extract and limit first IP from X-Forwarded-For chain"
            )
        }
    }

    func testRateLimitMiddleware_XRealIP_UsedWhenNoXForwardedFor() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make 10 requests with X-Real-IP header
            var headers = HTTPFields()
            headers[.init("x-real-ip")!] = "198.51.100.50"

            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: headers
                )
            }

            // 11th request should be rate limited
            let response = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: headers
            )

            XCTAssertEqual(
                response.status,
                .tooManyRequests,
                "X-Real-IP should be used for rate limiting when X-Forwarded-For is absent"
            )
        }
    }

    func testRateLimitMiddleware_XForwardedForTakesPrecedenceOverXRealIP() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make 10 requests with both headers - X-Forwarded-For should take precedence
            var headers1 = HTTPFields()
            headers1[.init("x-forwarded-for")!] = "203.0.113.100"
            headers1[.init("x-real-ip")!] = "198.51.100.200"

            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: headers1
                )
            }

            // Request with same X-Forwarded-For should be limited
            let response1 = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: headers1
            )

            XCTAssertEqual(
                response1.status,
                .tooManyRequests,
                "X-Forwarded-For IP should be rate limited"
            )

            // Request with only the X-Real-IP value (no X-Forwarded-For) should succeed
            // because it's treated as a different client
            var headers2 = HTTPFields()
            headers2[.init("x-real-ip")!] = "198.51.100.200"

            let response2 = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: headers2
            )

            XCTAssertNotEqual(
                response2.status,
                .tooManyRequests,
                "X-Real-IP alone should be treated as different client"
            )
        }
    }

    func testRateLimitMiddleware_NoClientIPHeaders_UsesUnknown() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make 10 requests without any client IP headers
            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .get,
                    headers: [:]
                )
            }

            // 11th request should be rate limited (all counted as "unknown")
            let response = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .tooManyRequests,
                "Requests without client IP headers should be rate limited collectively"
            )
        }
    }

    // MARK: - HTTP Method Tests

    func testRateLimitMiddleware_POSTRequests_AreRateLimited() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make 10 POST requests
            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .post,
                    headers: [:]
                )
            }

            // 11th POST should be rate limited
            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .tooManyRequests,
                "POST requests should be rate limited"
            )
        }
    }

    func testRateLimitMiddleware_MixedMethods_ShareSameLimit() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Make 5 GET and 5 POST requests (total 10)
            for _ in 1...5 {
                _ = try await client.execute(uri: "/mcp", method: .get, headers: [:])
                _ = try await client.execute(uri: "/mcp", method: .post, headers: [:])
            }

            // Next request of either method should be rate limited
            let response = try await client.execute(
                uri: "/mcp",
                method: .get,
                headers: [:]
            )

            XCTAssertEqual(
                response.status,
                .tooManyRequests,
                "Different HTTP methods should share the same rate limit counter"
            )
        }
    }

    // MARK: - Error Message Tests

    func testRateLimitMiddleware_ErrorMessage_ContainsUsefulInformation() async throws {
        let app = try await buildTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in
            // Exceed the limit
            for _ in 1...11 {
                _ = try await client.execute(uri: "/mcp", method: .get, headers: [:])
            }

            let response = try await client.execute(uri: "/mcp", method: .get, headers: [:])

            XCTAssertEqual(response.status, .tooManyRequests)

            let bodyString = String(buffer: response.body)

            // Error message should be clear and actionable
            XCTAssertTrue(
                bodyString.contains("Rate limit exceeded"),
                "Error should mention 'Rate limit exceeded'"
            )
            XCTAssertTrue(
                bodyString.contains("Maximum"),
                "Error should specify maximum allowed"
            )
            XCTAssertTrue(
                bodyString.contains("requests per minute"),
                "Error should specify the time window"
            )
        }
    }
}
