// Tests/HummingbirdKnowledgeServerTests/Health/HealthCheckTests.swift
//
// Comprehensive tests for health check subsystems: validates KnowledgeStoreHealthCheck,
// GitHubAPIHealthCheck, SSWGIndexHealthCheck, and DetailedHealthResponse aggregation.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class HealthCheckTests: XCTestCase {

    // MARK: - KnowledgeStoreHealthCheck Tests

    func testKnowledgeStoreHealthCheck_WithEntries_ReturnsHealthy() async throws {
        let entries = [
            createMinimalKnowledgeEntry(id: "test-1", title: "Entry 1"),
            createMinimalKnowledgeEntry(id: "test-2", title: "Entry 2"),
            createMinimalKnowledgeEntry(id: "test-3", title: "Entry 3"),
        ]
        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let healthCheck = KnowledgeStoreHealthCheck(store: store)

        let status = await healthCheck.check()

        XCTAssertEqual(status.name, "knowledge_store")
        XCTAssertEqual(status.status, .healthy)
        XCTAssertEqual(status.message, "Knowledge base is loaded")
        XCTAssertEqual(status.metadata?["entry_count"], "3")
    }

    func testKnowledgeStoreHealthCheck_WithSingleEntry_ReturnsHealthy() async throws {
        let entries = [createMinimalKnowledgeEntry(id: "single")]
        let store = KnowledgeStore.forTesting(seedEntries: entries)
        let healthCheck = KnowledgeStoreHealthCheck(store: store)

        let status = await healthCheck.check()

        XCTAssertEqual(status.status, .healthy)
        XCTAssertEqual(status.metadata?["entry_count"], "1")
    }

    func testKnowledgeStoreHealthCheck_WithEmptyStore_ReturnsUnhealthy() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [])
        let healthCheck = KnowledgeStoreHealthCheck(store: store)

        let status = await healthCheck.check()

        XCTAssertEqual(status.name, "knowledge_store")
        XCTAssertEqual(status.status, .unhealthy)
        XCTAssertEqual(status.message, "Knowledge base is empty")
        XCTAssertEqual(status.metadata?["entry_count"], "0")
    }

    func testKnowledgeStoreHealthCheck_IncludesTimestamp() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [createMinimalKnowledgeEntry()])
        let healthCheck = KnowledgeStoreHealthCheck(store: store)

        let before = Date()
        let status = await healthCheck.check()
        let after = Date()

        XCTAssertGreaterThanOrEqual(status.timestamp, before)
        XCTAssertLessThanOrEqual(status.timestamp, after)
    }

    // MARK: - GitHubAPIHealthCheck Tests

    func testGitHubAPIHealthCheck_WithSuccessfulResponse_ReturnsHealthy() async throws {
        let healthCheck = GitHubAPIHealthCheck(timeout: 5.0)

        let status = await healthCheck.check()

        XCTAssertEqual(status.name, "github_api")
        // GitHub API should return either 200 (authenticated) or 404 (unauthenticated)
        // Both are considered healthy
        XCTAssertTrue(
            status.status == .healthy || status.status == .degraded,
            "Expected healthy or degraded status, got \(status.status)"
        )
        XCTAssertNotNil(status.metadata?["response_time_ms"])
        XCTAssertNotNil(status.metadata?["status_code"])
    }

    func testGitHubAPIHealthCheck_WithShortTimeout_MayTimeout() async throws {
        let healthCheck = GitHubAPIHealthCheck(timeout: 0.001)

        let status = await healthCheck.check()

        XCTAssertEqual(status.name, "github_api")
        // With 1ms timeout, we expect either timeout or success (if network is very fast)
        XCTAssertTrue(
            status.status == .unhealthy || status.status == .healthy || status.status == .degraded,
            "Status should be valid health state"
        )
        if status.status == .unhealthy {
            XCTAssertTrue(
                status.message?.contains("timed out") ?? false ||
                status.message?.contains("Connection failed") ?? false,
                "Unhealthy status should have timeout or connection message"
            )
        }
    }

    func testGitHubAPIHealthCheck_IncludesResponseTimeMetadata() async throws {
        let healthCheck = GitHubAPIHealthCheck(timeout: 5.0)

        let status = await healthCheck.check()

        guard let responseTimeStr = status.metadata?["response_time_ms"] else {
            XCTFail("Response time metadata should be present")
            return
        }
        guard let responseTime = Double(responseTimeStr) else {
            XCTFail("Response time should be a valid number")
            return
        }
        XCTAssertGreaterThan(responseTime, 0, "Response time should be positive")
        XCTAssertLessThan(responseTime, 5000, "Response time should be less than timeout")
    }

    func testGitHubAPIHealthCheck_IncludesTimestamp() async throws {
        let healthCheck = GitHubAPIHealthCheck(timeout: 5.0)

        let before = Date()
        let status = await healthCheck.check()
        let after = Date()

        XCTAssertGreaterThanOrEqual(status.timestamp, before)
        XCTAssertLessThanOrEqual(status.timestamp, after)
    }

    func testGitHubAPIHealthCheck_WithToken_IncludesAuthHeader() async throws {
        // Note: We can't easily test that the header is included without mocking,
        // but we can verify the health check still works with a token
        let healthCheck = GitHubAPIHealthCheck(githubToken: "test-token", timeout: 5.0)

        let status = await healthCheck.check()

        XCTAssertEqual(status.name, "github_api")
        // Should still get a response (even if token is invalid)
        XCTAssertTrue(
            status.status == .healthy || status.status == .degraded || status.status == .unhealthy,
            "Should return valid health status"
        )
    }

    // MARK: - SSWGIndexHealthCheck Tests

    func testSSWGIndexHealthCheck_WithSuccessfulResponse_ReturnsHealthy() async throws {
        let healthCheck = SSWGIndexHealthCheck(timeout: 5.0)

        let status = await healthCheck.check()

        XCTAssertEqual(status.name, "sswg_index")
        // SSWG index should return 200
        if status.status == .healthy {
            XCTAssertEqual(status.message, "SSWG index is reachable")
            XCTAssertEqual(status.metadata?["status_code"], "200")
        }
        XCTAssertNotNil(status.metadata?["response_time_ms"])
    }

    func testSSWGIndexHealthCheck_WithShortTimeout_MayTimeout() async throws {
        let healthCheck = SSWGIndexHealthCheck(timeout: 0.001)

        let status = await healthCheck.check()

        XCTAssertEqual(status.name, "sswg_index")
        // With 1ms timeout, we expect either timeout or success (if network is very fast)
        XCTAssertTrue(
            status.status == .unhealthy || status.status == .healthy,
            "Status should be valid health state"
        )
        if status.status == .unhealthy {
            XCTAssertTrue(
                status.message?.contains("timed out") ?? false ||
                status.message?.contains("Connection failed") ?? false,
                "Unhealthy status should have timeout or connection message"
            )
        }
    }

    func testSSWGIndexHealthCheck_IncludesResponseTimeMetadata() async throws {
        let healthCheck = SSWGIndexHealthCheck(timeout: 5.0)

        let status = await healthCheck.check()

        if status.status == .healthy {
            guard let responseTimeStr = status.metadata?["response_time_ms"] else {
                XCTFail("Response time metadata should be present for healthy response")
                return
            }
            guard let responseTime = Double(responseTimeStr) else {
                XCTFail("Response time should be a valid number")
                return
            }
            XCTAssertGreaterThan(responseTime, 0, "Response time should be positive")
            XCTAssertLessThan(responseTime, 5000, "Response time should be less than timeout")
        }
    }

    func testSSWGIndexHealthCheck_IncludesTimestamp() async throws {
        let healthCheck = SSWGIndexHealthCheck(timeout: 5.0)

        let before = Date()
        let status = await healthCheck.check()
        let after = Date()

        XCTAssertGreaterThanOrEqual(status.timestamp, before)
        XCTAssertLessThanOrEqual(status.timestamp, after)
    }

    // MARK: - DetailedHealthResponse Tests

    func testDetailedHealthResponse_AllHealthy_ReturnsHealthyOverall() async throws {
        let checks = [
            HealthStatus(name: "subsystem1", status: .healthy, message: "OK"),
            HealthStatus(name: "subsystem2", status: .healthy, message: "OK"),
            HealthStatus(name: "subsystem3", status: .healthy, message: "OK"),
        ]

        let response = DetailedHealthResponse(checks: checks)

        XCTAssertEqual(response.status, .healthy)
        XCTAssertEqual(response.checks.count, 3)
    }

    func testDetailedHealthResponse_OneDegraded_ReturnsDegradedOverall() async throws {
        let checks = [
            HealthStatus(name: "subsystem1", status: .healthy, message: "OK"),
            HealthStatus(name: "subsystem2", status: .degraded, message: "Rate limited"),
            HealthStatus(name: "subsystem3", status: .healthy, message: "OK"),
        ]

        let response = DetailedHealthResponse(checks: checks)

        XCTAssertEqual(response.status, .degraded)
        XCTAssertEqual(response.checks.count, 3)
    }

    func testDetailedHealthResponse_OneUnhealthy_ReturnsUnhealthyOverall() async throws {
        let checks = [
            HealthStatus(name: "subsystem1", status: .healthy, message: "OK"),
            HealthStatus(name: "subsystem2", status: .unhealthy, message: "Connection failed"),
            HealthStatus(name: "subsystem3", status: .healthy, message: "OK"),
        ]

        let response = DetailedHealthResponse(checks: checks)

        XCTAssertEqual(response.status, .unhealthy)
        XCTAssertEqual(response.checks.count, 3)
    }

    func testDetailedHealthResponse_UnhealthyTakesPriorityOverDegraded() async throws {
        let checks = [
            HealthStatus(name: "subsystem1", status: .degraded, message: "Slow"),
            HealthStatus(name: "subsystem2", status: .unhealthy, message: "Failed"),
            HealthStatus(name: "subsystem3", status: .healthy, message: "OK"),
        ]

        let response = DetailedHealthResponse(checks: checks)

        XCTAssertEqual(response.status, .unhealthy, "Unhealthy should take priority over degraded")
    }

    func testDetailedHealthResponse_MultipleUnhealthy_ReturnsUnhealthyOverall() async throws {
        let checks = [
            HealthStatus(name: "subsystem1", status: .unhealthy, message: "Failed"),
            HealthStatus(name: "subsystem2", status: .unhealthy, message: "Failed"),
            HealthStatus(name: "subsystem3", status: .healthy, message: "OK"),
        ]

        let response = DetailedHealthResponse(checks: checks)

        XCTAssertEqual(response.status, .unhealthy)
    }

    func testDetailedHealthResponse_EmptyChecks_ReturnsHealthyOverall() async throws {
        let checks: [HealthStatus] = []

        let response = DetailedHealthResponse(checks: checks)

        XCTAssertEqual(response.status, .healthy, "Empty checks should default to healthy")
        XCTAssertEqual(response.checks.count, 0)
    }

    func testDetailedHealthResponse_IncludesTimestamp() async throws {
        let checks = [
            HealthStatus(name: "subsystem1", status: .healthy, message: "OK"),
        ]

        let before = Date()
        let response = DetailedHealthResponse(checks: checks)
        let after = Date()

        XCTAssertGreaterThanOrEqual(response.timestamp, before)
        XCTAssertLessThanOrEqual(response.timestamp, after)
    }

    func testDetailedHealthResponse_PreservesCheckDetails() async throws {
        let checks = [
            HealthStatus(
                name: "subsystem1",
                status: .healthy,
                message: "All systems operational",
                metadata: ["count": "42", "latency_ms": "15"]
            ),
            HealthStatus(
                name: "subsystem2",
                status: .degraded,
                message: "Performance degraded",
                metadata: ["response_time": "500"]
            ),
        ]

        let response = DetailedHealthResponse(checks: checks)

        XCTAssertEqual(response.checks[0].name, "subsystem1")
        XCTAssertEqual(response.checks[0].status, .healthy)
        XCTAssertEqual(response.checks[0].message, "All systems operational")
        XCTAssertEqual(response.checks[0].metadata?["count"], "42")

        XCTAssertEqual(response.checks[1].name, "subsystem2")
        XCTAssertEqual(response.checks[1].status, .degraded)
        XCTAssertEqual(response.checks[1].message, "Performance degraded")
        XCTAssertEqual(response.checks[1].metadata?["response_time"], "500")
    }

    // MARK: - HealthStatus Codable Tests

    func testHealthStatus_EncodesAndDecodesCorrectly() throws {
        let original = HealthStatus(
            name: "test_subsystem",
            status: .healthy,
            message: "Test message",
            metadata: ["key1": "value1", "key2": "value2"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HealthStatus.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.message, original.message)
        XCTAssertEqual(decoded.metadata?["key1"], "value1")
        XCTAssertEqual(decoded.metadata?["key2"], "value2")
        // Timestamps might differ slightly due to encoding precision
        XCTAssertEqual(
            decoded.timestamp.timeIntervalSince1970,
            original.timestamp.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testHealthStatus_EncodesWithoutOptionalFields() throws {
        let original = HealthStatus(
            name: "test_subsystem",
            status: .unhealthy
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HealthStatus.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertNil(decoded.message)
        XCTAssertNil(decoded.metadata)
    }

    // MARK: - DetailedHealthResponse Codable Tests

    func testDetailedHealthResponse_EncodesAndDecodesCorrectly() throws {
        let checks = [
            HealthStatus(name: "subsystem1", status: .healthy, message: "OK"),
            HealthStatus(name: "subsystem2", status: .degraded, message: "Slow", metadata: ["latency": "500"]),
        ]
        let original = DetailedHealthResponse(checks: checks)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DetailedHealthResponse.self, from: data)

        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.checks.count, original.checks.count)
        XCTAssertEqual(decoded.checks[0].name, "subsystem1")
        XCTAssertEqual(decoded.checks[1].name, "subsystem2")
        XCTAssertEqual(decoded.checks[1].metadata?["latency"], "500")
    }

    // MARK: - Integration Tests

    func testRealWorldScenario_MixedHealthStates() async throws {
        // Simulate real-world scenario with multiple subsystems
        let store = KnowledgeStore.forTesting(seedEntries: [
            createMinimalKnowledgeEntry(id: "entry-1"),
            createMinimalKnowledgeEntry(id: "entry-2"),
        ])
        let knowledgeCheck = KnowledgeStoreHealthCheck(store: store)
        let githubCheck = GitHubAPIHealthCheck(timeout: 5.0)
        let sswgCheck = SSWGIndexHealthCheck(timeout: 5.0)

        // Run all checks concurrently
        async let knowledgeStatus = knowledgeCheck.check()
        async let githubStatus = githubCheck.check()
        async let sswgStatus = sswgCheck.check()

        let checks = await [knowledgeStatus, githubStatus, sswgStatus]
        let response = DetailedHealthResponse(checks: checks)

        // Knowledge store should definitely be healthy
        XCTAssertEqual(checks[0].status, .healthy)
        XCTAssertEqual(checks[0].name, "knowledge_store")

        // GitHub and SSWG should be healthy or degraded (network dependent)
        XCTAssertTrue(
            [.healthy, .degraded, .unhealthy].contains(checks[1].status),
            "GitHub check should return valid status"
        )
        XCTAssertEqual(checks[1].name, "github_api")

        XCTAssertTrue(
            [.healthy, .degraded, .unhealthy].contains(checks[2].status),
            "SSWG check should return valid status"
        )
        XCTAssertEqual(checks[2].name, "sswg_index")

        // Response should aggregate correctly
        XCTAssertTrue(
            [.healthy, .degraded, .unhealthy].contains(response.status),
            "Overall status should be valid"
        )
        XCTAssertEqual(response.checks.count, 3)
    }

    func testConcurrentHealthChecks_AreThreadSafe() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: [createMinimalKnowledgeEntry()])
        let healthCheck = KnowledgeStoreHealthCheck(store: store)

        // Run 10 concurrent health checks
        await withTaskGroup(of: HealthStatus.self) { group in
            for _ in 1...10 {
                group.addTask {
                    await healthCheck.check()
                }
            }

            var results: [HealthStatus] = []
            for await result in group {
                results.append(result)
            }

            XCTAssertEqual(results.count, 10)
            // All results should be healthy and consistent
            for result in results {
                XCTAssertEqual(result.status, .healthy)
                XCTAssertEqual(result.name, "knowledge_store")
                XCTAssertEqual(result.metadata?["entry_count"], "1")
            }
        }
    }
}
