// Tests/HummingbirdKnowledgeServerTests/Metrics/MetricsCollectorTests.swift
//
// Comprehensive tests for MetricsCollector: validates request counting, violation tracking,
// latency statistics, sample retention, eviction logic, and knowledge base metrics.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class MetricsCollectorTests: XCTestCase {

    // MARK: - Request Counting Tests

    func testRecordRequest_IncrementsTotalRequests() async throws {
        let collector = MetricsCollector()

        await collector.recordRequest(tool: "search", duration: 0.1)
        await collector.recordRequest(tool: "read", duration: 0.2)

        let total = await collector.getTotalRequests()
        XCTAssertEqual(total, 2, "Total requests should be incremented")
    }

    func testRecordRequest_IncrementsToolSpecificCount() async throws {
        let collector = MetricsCollector()

        await collector.recordRequest(tool: "search", duration: 0.1)
        await collector.recordRequest(tool: "search", duration: 0.15)
        await collector.recordRequest(tool: "read", duration: 0.2)

        let searchCount = await collector.getRequestCount(tool: "search")
        let readCount = await collector.getRequestCount(tool: "read")

        XCTAssertEqual(searchCount, 2, "Search tool should have 2 requests")
        XCTAssertEqual(readCount, 1, "Read tool should have 1 request")
    }

    func testGetRequestCount_ReturnsZeroForUnknownTool() async throws {
        let collector = MetricsCollector()

        let count = await collector.getRequestCount(tool: "unknown")
        XCTAssertEqual(count, 0, "Unknown tools should return zero count")
    }

    func testGetAllRequestCounts_ReturnsAllTools() async throws {
        let collector = MetricsCollector()

        await collector.recordRequest(tool: "search", duration: 0.1)
        await collector.recordRequest(tool: "search", duration: 0.15)
        await collector.recordRequest(tool: "read", duration: 0.2)
        await collector.recordRequest(tool: "write", duration: 0.3)

        let counts = await collector.getAllRequestCounts()

        XCTAssertEqual(counts.count, 3, "Should track 3 different tools")
        XCTAssertEqual(counts["search"], 2)
        XCTAssertEqual(counts["read"], 1)
        XCTAssertEqual(counts["write"], 1)
    }

    // MARK: - Violation Tracking Tests

    func testRecordViolation_IncrementsRuleCount() async throws {
        let collector = MetricsCollector()

        await collector.recordViolation(rule: "rate_limit")
        await collector.recordViolation(rule: "rate_limit")
        await collector.recordViolation(rule: "content_policy")

        let rateLimitCount = await collector.getViolationCount(rule: "rate_limit")
        let contentPolicyCount = await collector.getViolationCount(rule: "content_policy")

        XCTAssertEqual(rateLimitCount, 2, "Rate limit rule should have 2 violations")
        XCTAssertEqual(contentPolicyCount, 1, "Content policy rule should have 1 violation")
    }

    func testGetViolationCount_ReturnsZeroForUnknownRule() async throws {
        let collector = MetricsCollector()

        let count = await collector.getViolationCount(rule: "unknown")
        XCTAssertEqual(count, 0, "Unknown rules should return zero count")
    }

    func testGetAllViolationCounts_ReturnsAllRules() async throws {
        let collector = MetricsCollector()

        await collector.recordViolation(rule: "rate_limit")
        await collector.recordViolation(rule: "rate_limit")
        await collector.recordViolation(rule: "content_policy")
        await collector.recordViolation(rule: "auth_failure")

        let counts = await collector.getAllViolationCounts()

        XCTAssertEqual(counts.count, 3, "Should track 3 different rules")
        XCTAssertEqual(counts["rate_limit"], 2)
        XCTAssertEqual(counts["content_policy"], 1)
        XCTAssertEqual(counts["auth_failure"], 1)
    }

    // MARK: - Knowledge Base Stats Tests

    func testUpdateKnowledgeBaseStats_StoresEntryCount() async throws {
        let collector = MetricsCollector()

        await collector.updateKnowledgeBaseStats(entryCount: 42)

        let count = await collector.getKnowledgeBaseEntryCount()
        XCTAssertEqual(count, 42, "Should store knowledge base entry count")
    }

    func testUpdateKnowledgeBaseStats_UpdatesTimestamp() async throws {
        let collector = MetricsCollector()

        let beforeUpdate = Date()
        await collector.updateKnowledgeBaseStats(entryCount: 10)
        let afterUpdate = Date()

        let timestamp = await collector.getLastKnowledgeUpdate()

        XCTAssertNotNil(timestamp, "Should record update timestamp")
        XCTAssertGreaterThanOrEqual(timestamp!, beforeUpdate, "Timestamp should be after test start")
        XCTAssertLessThanOrEqual(timestamp!, afterUpdate, "Timestamp should be before test end")
    }

    func testGetLastKnowledgeUpdate_InitiallyNil() async throws {
        let collector = MetricsCollector()

        let timestamp = await collector.getLastKnowledgeUpdate()
        XCTAssertNil(timestamp, "Initial timestamp should be nil")
    }

    // MARK: - Latency Statistics Tests

    func testGetLatencyStats_CalculatesCorrectStatistics() async throws {
        let collector = MetricsCollector()

        // Record samples with known values for easy verification
        await collector.recordRequest(tool: "search", duration: 0.1)  // min
        await collector.recordRequest(tool: "search", duration: 0.2)
        await collector.recordRequest(tool: "search", duration: 0.3)
        await collector.recordRequest(tool: "search", duration: 0.4)
        await collector.recordRequest(tool: "search", duration: 0.5)  // max

        let stats = await collector.getLatencyStats(tool: "search")

        XCTAssertNotNil(stats, "Should return statistics for tool with samples")
        guard let stats = stats else {
            XCTFail("Stats should not be nil")
            return
        }
        XCTAssertEqual(stats.count, 5, "Should count all samples")
        XCTAssertEqual(stats.min, 0.1, accuracy: 0.001, "Min should be 0.1")
        XCTAssertEqual(stats.max, 0.5, accuracy: 0.001, "Max should be 0.5")
        XCTAssertEqual(stats.mean, 0.3, accuracy: 0.001, "Mean should be 0.3")
        XCTAssertEqual(stats.p50, 0.3, accuracy: 0.001, "P50 should be 0.3")
    }

    func testGetLatencyStats_ReturnsNilForUnknownTool() async throws {
        let collector = MetricsCollector()

        let stats = await collector.getLatencyStats(tool: "unknown")
        XCTAssertNil(stats, "Should return nil for unknown tool")
    }

    func testGetLatencyStats_ReturnsNilForToolWithNoSamples() async throws {
        let collector = MetricsCollector()

        // Record request for one tool but query another
        await collector.recordRequest(tool: "search", duration: 0.1)

        let stats = await collector.getLatencyStats(tool: "read")
        XCTAssertNil(stats, "Should return nil for tool with no samples")
    }

    func testGetAllLatencyStats_ReturnsAllTools() async throws {
        let collector = MetricsCollector()

        await collector.recordRequest(tool: "search", duration: 0.1)
        await collector.recordRequest(tool: "search", duration: 0.2)
        await collector.recordRequest(tool: "read", duration: 0.3)
        await collector.recordRequest(tool: "write", duration: 0.4)

        let allStats = await collector.getAllLatencyStats()

        XCTAssertEqual(allStats.count, 3, "Should return stats for 3 tools")
        XCTAssertNotNil(allStats["search"])
        XCTAssertNotNil(allStats["read"])
        XCTAssertNotNil(allStats["write"])
    }

    func testGetLatencyStats_HandlesPercentileEdgeCases() async throws {
        let collector = MetricsCollector()

        // Single sample
        await collector.recordRequest(tool: "single", duration: 0.5)

        let singleStats = await collector.getLatencyStats(tool: "single")
        XCTAssertNotNil(singleStats)
        guard let singleStats = singleStats else {
            XCTFail("Stats should not be nil")
            return
        }
        XCTAssertEqual(singleStats.count, 1)
        XCTAssertEqual(singleStats.min, 0.5, accuracy: 0.001)
        XCTAssertEqual(singleStats.max, 0.5, accuracy: 0.001)
        XCTAssertEqual(singleStats.mean, 0.5, accuracy: 0.001)
        XCTAssertEqual(singleStats.p50, 0.5, accuracy: 0.001)
        XCTAssertEqual(singleStats.p95, 0.5, accuracy: 0.001)
        XCTAssertEqual(singleStats.p99, 0.5, accuracy: 0.001)
    }

    // MARK: - Sample Retention Tests

    func testRecordRequest_LimitsSamplesPerTool() async throws {
        let collector = MetricsCollector()

        // Record more than maxSamplesPerTool (1000)
        for i in 1...1100 {
            await collector.recordRequest(tool: "search", duration: Double(i) * 0.001)
        }

        let stats = await collector.getLatencyStats(tool: "search")

        XCTAssertNotNil(stats)
        guard let stats = stats else {
            XCTFail("Stats should not be nil")
            return
        }
        XCTAssertLessThanOrEqual(
            stats.count,
            1000,
            "Should limit samples to maxSamplesPerTool"
        )
    }

    func testRecordRequest_RetainsMostRecentSamples() async throws {
        let collector = MetricsCollector()

        // Record more than maxSamplesPerTool with distinct values
        for i in 1...1100 {
            await collector.recordRequest(tool: "search", duration: Double(i) * 0.001)
        }

        let stats = await collector.getLatencyStats(tool: "search")

        // The minimum should be from recent samples (after first 100 were dropped)
        XCTAssertNotNil(stats)
        guard let stats = stats else {
            XCTFail("Stats should not be nil")
            return
        }
        XCTAssertGreaterThan(
            stats.min,
            0.1,
            "Should retain most recent samples, dropping oldest"
        )
    }

    // MARK: - Reset Tests

    func testReset_ClearsAllMetrics() async throws {
        let collector = MetricsCollector()

        // Populate all metric types
        await collector.recordRequest(tool: "search", duration: 0.1)
        await collector.recordViolation(rule: "rate_limit")
        await collector.updateKnowledgeBaseStats(entryCount: 42)

        await collector.reset()

        // Verify all metrics are cleared
        let totalRequests = await collector.getTotalRequests()
        let requestCounts = await collector.getAllRequestCounts()
        let violationCounts = await collector.getAllViolationCounts()
        let knowledgeCount = await collector.getKnowledgeBaseEntryCount()
        let knowledgeTimestamp = await collector.getLastKnowledgeUpdate()
        let latencyStats = await collector.getAllLatencyStats()

        XCTAssertEqual(totalRequests, 0, "Total requests should be reset")
        XCTAssertTrue(requestCounts.isEmpty, "Request counts should be empty")
        XCTAssertTrue(violationCounts.isEmpty, "Violation counts should be empty")
        XCTAssertEqual(knowledgeCount, 0, "Knowledge count should be reset")
        XCTAssertNil(knowledgeTimestamp, "Knowledge timestamp should be nil")
        XCTAssertTrue(latencyStats.isEmpty, "Latency stats should be empty")
    }

    func testReset_AllowsNewMetricsAfterReset() async throws {
        let collector = MetricsCollector()

        // Record, reset, then record again
        await collector.recordRequest(tool: "search", duration: 0.1)
        await collector.reset()
        await collector.recordRequest(tool: "read", duration: 0.2)

        let totalRequests = await collector.getTotalRequests()
        let requestCounts = await collector.getAllRequestCounts()

        XCTAssertEqual(totalRequests, 1, "Should count new requests after reset")
        XCTAssertEqual(requestCounts.count, 1, "Should only have post-reset tools")
        XCTAssertEqual(requestCounts["read"], 1)
        XCTAssertNil(requestCounts["search"], "Pre-reset tools should be gone")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentRequests_MaintainsAccurateCount() async throws {
        let collector = MetricsCollector()
        let iterations = 100

        // Execute concurrent requests
        await withTaskGroup(of: Void.self) { group in
            for i in 1...iterations {
                group.addTask {
                    await collector.recordRequest(tool: "search", duration: Double(i) * 0.001)
                }
            }
        }

        let totalRequests = await collector.getTotalRequests()
        let searchCount = await collector.getRequestCount(tool: "search")

        XCTAssertEqual(totalRequests, iterations, "Should count all concurrent requests")
        XCTAssertEqual(searchCount, iterations, "Should count all concurrent tool requests")
    }

    func testConcurrentViolations_MaintainsAccurateCount() async throws {
        let collector = MetricsCollector()
        let iterations = 100

        // Execute concurrent violations
        await withTaskGroup(of: Void.self) { group in
            for _ in 1...iterations {
                group.addTask {
                    await collector.recordViolation(rule: "rate_limit")
                }
            }
        }

        let count = await collector.getViolationCount(rule: "rate_limit")
        XCTAssertEqual(count, iterations, "Should count all concurrent violations")
    }

    func testConcurrentMixedOperations_MaintainsConsistency() async throws {
        let collector = MetricsCollector()

        // Mix of reads and writes
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 1...50 {
                group.addTask {
                    await collector.recordRequest(tool: "search", duration: Double(i) * 0.001)
                }
                group.addTask {
                    await collector.recordViolation(rule: "rate_limit")
                }
            }

            // Readers
            for _ in 1...50 {
                group.addTask {
                    _ = await collector.getTotalRequests()
                }
                group.addTask {
                    _ = await collector.getViolationCount(rule: "rate_limit")
                }
            }
        }

        let totalRequests = await collector.getTotalRequests()
        let violationCount = await collector.getViolationCount(rule: "rate_limit")

        XCTAssertEqual(totalRequests, 50, "Should count all requests despite concurrent operations")
        XCTAssertEqual(violationCount, 50, "Should count all violations despite concurrent operations")
    }

    // MARK: - Edge Cases Tests

    func testRecordRequest_HandlesZeroDuration() async throws {
        let collector = MetricsCollector()

        await collector.recordRequest(tool: "search", duration: 0.0)

        let stats = await collector.getLatencyStats(tool: "search")
        XCTAssertNotNil(stats)
        guard let stats = stats else {
            XCTFail("Stats should not be nil")
            return
        }
        XCTAssertEqual(stats.min, 0.0, "Should handle zero duration")
        XCTAssertEqual(stats.max, 0.0, "Should handle zero duration")
    }

    func testRecordRequest_HandlesLargeDuration() async throws {
        let collector = MetricsCollector()

        await collector.recordRequest(tool: "search", duration: 999.999)

        let stats = await collector.getLatencyStats(tool: "search")
        XCTAssertNotNil(stats)
        guard let stats = stats else {
            XCTFail("Stats should not be nil")
            return
        }
        XCTAssertEqual(stats.max, 999.999, accuracy: 0.001, "Should handle large duration")
    }

    func testRecordRequest_HandlesEmptyToolName() async throws {
        let collector = MetricsCollector()

        await collector.recordRequest(tool: "", duration: 0.1)

        let count = await collector.getRequestCount(tool: "")
        XCTAssertEqual(count, 1, "Should handle empty tool name")
    }

    func testRecordViolation_HandlesEmptyRuleName() async throws {
        let collector = MetricsCollector()

        await collector.recordViolation(rule: "")

        let count = await collector.getViolationCount(rule: "")
        XCTAssertEqual(count, 1, "Should handle empty rule name")
    }

    func testUpdateKnowledgeBaseStats_HandlesZeroEntries() async throws {
        let collector = MetricsCollector()

        await collector.updateKnowledgeBaseStats(entryCount: 0)

        let count = await collector.getKnowledgeBaseEntryCount()
        XCTAssertEqual(count, 0, "Should handle zero entries")
    }

    func testUpdateKnowledgeBaseStats_AllowsMultipleUpdates() async throws {
        let collector = MetricsCollector()

        await collector.updateKnowledgeBaseStats(entryCount: 10)
        let firstTimestamp = await collector.getLastKnowledgeUpdate()

        // Small delay to ensure different timestamp
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        await collector.updateKnowledgeBaseStats(entryCount: 20)
        let secondTimestamp = await collector.getLastKnowledgeUpdate()

        let finalCount = await collector.getKnowledgeBaseEntryCount()

        XCTAssertEqual(finalCount, 20, "Should update to latest count")
        XCTAssertNotNil(firstTimestamp)
        XCTAssertNotNil(secondTimestamp)
        XCTAssertGreaterThan(secondTimestamp!, firstTimestamp!, "Should update timestamp")
    }
}
