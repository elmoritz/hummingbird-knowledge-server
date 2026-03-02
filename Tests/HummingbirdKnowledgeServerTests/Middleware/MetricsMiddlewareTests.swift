// Tests/HummingbirdKnowledgeServerTests/Middleware/MetricsMiddlewareTests.swift
//
// Comprehensive tests for MetricsMiddleware: validates request counting,
// latency recording, tool name extraction, and error handling.

import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import Logging
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class MetricsMiddlewareTests: XCTestCase {

    // MARK: - Test Helpers

    /// Builds a test application that returns both the app and metrics collector for testing
    func buildMetricsTestApplication(
        enableAuth: Bool = false,
        enableRateLimit: Bool = false
    ) async throws -> (app: some ApplicationProtocol, metricsCollector: MetricsCollector) {
        let seedEntries = try loadTestFixture()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetricsMiddlewareTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dynamicViolationsURL = tempDir.appendingPathComponent("dynamic-violations.json")

        let knowledgeStore = KnowledgeStore(seedEntries: seedEntries, dynamicViolationsFileURL: dynamicViolationsURL)

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

        let transport = HummingbirdSSETransport(
            logger: Logger(label: "com.hummingbird-knowledge-server.test.transport")
        )

        let metricsCollector = MetricsCollector()

        let dependencies = AppDependencies(
            mcpServer: mcpServer,
            transport: transport,
            knowledgeStore: knowledgeStore,
            metricsCollector: metricsCollector
        )

        let router = Router(context: AppRequestContext.self)

        router.add(middleware: DependencyInjectionMiddleware(dependencies: dependencies))
        router.add(middleware: RequestLoggingMiddleware())
        router.add(middleware: MetricsMiddleware(metricsCollector: metricsCollector))

        if enableAuth {
            router.add(middleware: AuthMiddleware(token: "test-token"))
        }
        if enableRateLimit {
            router.add(middleware: RateLimitMiddleware(requestsPerMinute: 10))
        }

        router.get("/health") { _, _ in
            ["status": "ok"]
        }
        router.get("/ready") { _, context in
            let count = await context.dependencies.knowledgeStore.count
            return ["status": "ok", "knowledgeEntries": "\(count)"]
        }

        MCPController().registerRoutes(on: router.group("/mcp"))

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: 0),
                serverName: "hummingbird-knowledge-server-test/0.1.0"
            )
        )

        return (app: app, metricsCollector: metricsCollector)
    }

    // MARK: - Request Counting Tests

    func testMetricsMiddleware_RecordsSingleRequest() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            // Make a single request
            _ = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "{}")
            )

            // Verify metrics were recorded
            let totalRequests = await metricsCollector.getTotalRequests()
            XCTAssertEqual(
                totalRequests,
                1,
                "Should record exactly one request"
            )

            let mcpCount = await metricsCollector.getRequestCount(tool: "mcp")
            XCTAssertEqual(
                mcpCount,
                1,
                "Should record one request for 'mcp' tool"
            )
        }
    }

    func testMetricsMiddleware_RecordsMultipleRequests() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            // Make multiple requests
            for _ in 1...5 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: ByteBuffer(string: "{}")
                )
            }

            // Verify total count
            let totalRequests = await metricsCollector.getTotalRequests()
            XCTAssertEqual(
                totalRequests,
                5,
                "Should record all 5 requests"
            )

            let mcpCount = await metricsCollector.getRequestCount(tool: "mcp")
            XCTAssertEqual(
                mcpCount,
                5,
                "Should record all 5 requests for 'mcp' tool"
            )
        }
    }

    func testMetricsMiddleware_TracksRequestsPerTool() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            // Make requests to different endpoints
            _ = try await client.execute(uri: "/mcp", method: .post, headers: [:])
            _ = try await client.execute(uri: "/mcp", method: .post, headers: [:])
            _ = try await client.execute(uri: "/health", method: .get, headers: [:])
            _ = try await client.execute(uri: "/ready", method: .get, headers: [:])

            // Verify counts per tool
            let mcpCount = await metricsCollector.getRequestCount(tool: "mcp")
            XCTAssertEqual(mcpCount, 2, "Should record 2 requests for 'mcp'")

            let healthCount = await metricsCollector.getRequestCount(tool: "health")
            XCTAssertEqual(healthCount, 1, "Should record 1 request for 'health'")

            let readyCount = await metricsCollector.getRequestCount(tool: "ready")
            XCTAssertEqual(readyCount, 1, "Should record 1 request for 'ready'")

            let totalRequests = await metricsCollector.getTotalRequests()
            XCTAssertEqual(totalRequests, 4, "Should record total of 4 requests")
        }
    }

    // MARK: - Tool Name Extraction Tests

    func testMetricsMiddleware_ExtractsMCPToolName() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            _ = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "{}")
            )

            let allCounts = await metricsCollector.getAllRequestCounts()
            XCTAssertTrue(
                allCounts.keys.contains("mcp"),
                "Should extract 'mcp' tool name from /mcp path"
            )
        }
    }

    func testMetricsMiddleware_ExtractsHealthToolName() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            _ = try await client.execute(uri: "/health", method: .get, headers: [:])

            let allCounts = await metricsCollector.getAllRequestCounts()
            XCTAssertTrue(
                allCounts.keys.contains("health"),
                "Should extract 'health' tool name from /health path"
            )
        }
    }

    func testMetricsMiddleware_ExtractsReadyToolName() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            _ = try await client.execute(uri: "/ready", method: .get, headers: [:])

            let allCounts = await metricsCollector.getAllRequestCounts()
            XCTAssertTrue(
                allCounts.keys.contains("ready"),
                "Should extract 'ready' tool name from /ready path"
            )
        }
    }

    // MARK: - Latency Recording Tests

    func testMetricsMiddleware_RecordsLatency() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            _ = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "{}")
            )

            let stats = await metricsCollector.getLatencyStats(tool: "mcp")
            XCTAssertNotNil(stats, "Should record latency statistics")
            XCTAssertEqual(stats?.count, 1, "Should have one latency sample")
            XCTAssertGreaterThanOrEqual(stats?.mean ?? 0, 0, "Mean latency should be non-negative")
            XCTAssertGreaterThanOrEqual(stats?.min ?? 0, 0, "Min latency should be non-negative")
            XCTAssertGreaterThanOrEqual(stats?.max ?? 0, 0, "Max latency should be non-negative")
        }
    }

    func testMetricsMiddleware_RecordsMultipleLatencies() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            // Make multiple requests
            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: ByteBuffer(string: "{}")
                )
            }

            let stats = await metricsCollector.getLatencyStats(tool: "mcp")
            XCTAssertNotNil(stats, "Should record latency statistics")
            XCTAssertEqual(stats?.count, 10, "Should have 10 latency samples")
            XCTAssertGreaterThan(stats?.mean ?? 0, 0, "Mean latency should be positive")
            XCTAssertGreaterThanOrEqual(stats?.p50 ?? 0, 0, "p50 should be non-negative")
            XCTAssertGreaterThanOrEqual(stats?.p95 ?? 0, 0, "p95 should be non-negative")
            XCTAssertGreaterThanOrEqual(stats?.p99 ?? 0, 0, "p99 should be non-negative")
        }
    }

    func testMetricsMiddleware_RecordsLatencyPerTool() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            // Make requests to different endpoints
            _ = try await client.execute(uri: "/mcp", method: .post, headers: [:])
            _ = try await client.execute(uri: "/health", method: .get, headers: [:])
            _ = try await client.execute(uri: "/ready", method: .get, headers: [:])

            // Verify each tool has its own latency stats
            let mcpStats = await metricsCollector.getLatencyStats(tool: "mcp")
            XCTAssertNotNil(mcpStats, "Should have latency stats for 'mcp'")
            XCTAssertEqual(mcpStats?.count, 1, "Should have 1 sample for 'mcp'")

            let healthStats = await metricsCollector.getLatencyStats(tool: "health")
            XCTAssertNotNil(healthStats, "Should have latency stats for 'health'")
            XCTAssertEqual(healthStats?.count, 1, "Should have 1 sample for 'health'")

            let readyStats = await metricsCollector.getLatencyStats(tool: "ready")
            XCTAssertNotNil(readyStats, "Should have latency stats for 'ready'")
            XCTAssertEqual(readyStats?.count, 1, "Should have 1 sample for 'ready'")
        }
    }

    // MARK: - Error Handling Tests

    func testMetricsMiddleware_RecordsMetricsOnSuccess() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            let response = try await client.execute(uri: "/health", method: .get, headers: [:])

            XCTAssertEqual(response.status, .ok, "Request should succeed")

            let totalRequests = await metricsCollector.getTotalRequests()
            XCTAssertEqual(
                totalRequests,
                1,
                "Should record metrics for successful request"
            )
        }
    }

    func testMetricsMiddleware_RecordsMetricsOnNotFound() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            let response = try await client.execute(uri: "/nonexistent", method: .get, headers: [:])

            XCTAssertEqual(response.status, .notFound, "Request should return 404")

            let totalRequests = await metricsCollector.getTotalRequests()
            XCTAssertEqual(
                totalRequests,
                1,
                "Should record metrics even for 404 responses"
            )

            // Should be recorded as "unknown" tool since path doesn't match known patterns
            let unknownCount = await metricsCollector.getRequestCount(tool: "unknown")
            XCTAssertEqual(
                unknownCount,
                1,
                "Should record unknown path as 'unknown' tool"
            )
        }
    }

    func testMetricsMiddleware_RecordsLatencyOnErrors() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            // Make request that will result in an error (404)
            _ = try await client.execute(uri: "/nonexistent", method: .get, headers: [:])

            // Verify latency was still recorded
            let stats = await metricsCollector.getLatencyStats(tool: "unknown")
            XCTAssertNotNil(
                stats,
                "Should record latency statistics even on errors"
            )
            XCTAssertEqual(stats?.count, 1, "Should have one latency sample")
            XCTAssertGreaterThanOrEqual(
                stats?.mean ?? 0,
                0,
                "Mean latency should be non-negative even on errors"
            )
        }
    }

    // MARK: - Integration Tests

    func testMetricsMiddleware_WorksWithRateLimiting() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication(enableRateLimit: true)

        try await app.test(.router) { client in

            // Make requests up to the rate limit
            for _ in 1...10 {
                _ = try await client.execute(
                    uri: "/mcp",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: ByteBuffer(string: "{}")
                )
            }

            // Make request that will be rate limited
            let rateLimitedResponse = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: "{}")
            )

            XCTAssertEqual(
                rateLimitedResponse.status,
                .tooManyRequests,
                "11th request should be rate limited"
            )

            // Verify metrics still recorded for rate-limited request
            let totalRequests = await metricsCollector.getTotalRequests()
            XCTAssertEqual(
                totalRequests,
                11,
                "Should record metrics even for rate-limited requests"
            )

            let mcpCount = await metricsCollector.getRequestCount(tool: "mcp")
            XCTAssertEqual(
                mcpCount,
                11,
                "Should count rate-limited requests in metrics"
            )
        }
    }

    func testMetricsMiddleware_WorksWithAuthentication() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication(enableAuth: true)

        try await app.test(.router) { client in

            // Make authenticated request
            var headers = HTTPFields()
            headers[.authorization] = "Bearer test-token"

            let response = try await client.execute(
                uri: "/mcp",
                method: .post,
                headers: headers,
                body: ByteBuffer(string: "{}")
            )

            XCTAssertNotEqual(
                response.status,
                .unauthorized,
                "Authenticated request should succeed"
            )

            // Verify metrics were recorded
            let totalRequests = await metricsCollector.getTotalRequests()
            XCTAssertEqual(
                totalRequests,
                1,
                "Should record metrics for authenticated requests"
            )
        }
    }

    func testMetricsMiddleware_CapturesAllRequestsInSession() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            // Simulate a complete session with multiple endpoints
            _ = try await client.execute(uri: "/health", method: .get, headers: [:])
            _ = try await client.execute(uri: "/ready", method: .get, headers: [:])
            _ = try await client.execute(uri: "/mcp", method: .post, headers: [:])
            _ = try await client.execute(uri: "/mcp", method: .post, headers: [:])
            _ = try await client.execute(uri: "/mcp", method: .post, headers: [:])
            _ = try await client.execute(uri: "/health", method: .get, headers: [:])

            // Verify all requests were captured
            let totalRequests = await metricsCollector.getTotalRequests()
            XCTAssertEqual(totalRequests, 6, "Should capture all 6 requests")

            let allCounts = await metricsCollector.getAllRequestCounts()
            XCTAssertEqual(allCounts["health"], 2, "Should have 2 health requests")
            XCTAssertEqual(allCounts["ready"], 1, "Should have 1 ready request")
            XCTAssertEqual(allCounts["mcp"], 3, "Should have 3 mcp requests")

            // Verify latency stats exist for all tools
            let allStats = await metricsCollector.getAllLatencyStats()
            XCTAssertEqual(allStats.count, 3, "Should have stats for 3 different tools")
            XCTAssertNotNil(allStats["health"], "Should have latency stats for health")
            XCTAssertNotNil(allStats["ready"], "Should have latency stats for ready")
            XCTAssertNotNil(allStats["mcp"], "Should have latency stats for mcp")
        }
    }

    // MARK: - Performance Tests

    func testMetricsMiddleware_LowOverhead() async throws {
        let (app, metricsCollector) = try await buildMetricsTestApplication()

        try await app.test(.router) { client in

            // Make a request and measure latency
            _ = try await client.execute(
                uri: "/health",
                method: .get,
                headers: [:]
            )

            let stats = await metricsCollector.getLatencyStats(tool: "health")
            XCTAssertNotNil(stats, "Should record latency")

            // Verify middleware overhead is reasonable (<1ms for health check)
            // Health endpoint is simple, so total latency should be very low
            XCTAssertLessThan(
                stats?.mean ?? 1.0,
                0.1,
                "Metrics middleware should add minimal overhead"
            )
        }
    }
}
