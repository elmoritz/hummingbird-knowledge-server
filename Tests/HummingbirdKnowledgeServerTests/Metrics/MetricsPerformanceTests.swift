// Tests/HummingbirdKnowledgeServerTests/Metrics/MetricsPerformanceTests.swift
//
// Performance tests for MetricsCollector: validates that metrics overhead is <1ms per request
// as specified in the acceptance criteria.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class MetricsPerformanceTests: XCTestCase {

    // MARK: - Metrics Overhead Tests

    func testMetricsOverhead_LessThan1Millisecond() async throws {
        let collector = MetricsCollector()
        let iterations = 1000

        // Measure time WITH metrics
        let withMetricsStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            await collector.recordRequest(tool: "test-tool", duration: 0.1)
        }
        let withMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withMetricsDuration = withMetricsEnd - withMetricsStart

        // Measure time WITHOUT metrics (baseline: just loop overhead)
        let withoutMetricsStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            // Simulate similar work without metrics
        }
        let withoutMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withoutMetricsDuration = withoutMetricsEnd - withoutMetricsStart

        // Calculate overhead per request
        let totalOverhead = withMetricsDuration - withoutMetricsDuration
        let overheadPerRequest = totalOverhead / Double(iterations)
        let overheadMilliseconds = overheadPerRequest * 1000

        // Print for debugging
        print("""

        Metrics Performance Results:
        ----------------------------
        Iterations: \(iterations)
        With metrics: \(String(format: "%.6f", withMetricsDuration))s
        Without metrics: \(String(format: "%.6f", withoutMetricsDuration))s
        Total overhead: \(String(format: "%.6f", totalOverhead))s
        Overhead per request: \(String(format: "%.6f", overheadPerRequest))s (\(String(format: "%.3f", overheadMilliseconds))ms)

        """)

        // Assert overhead is less than 1ms
        XCTAssertLessThan(
            overheadMilliseconds,
            1.0,
            "Metrics overhead per request should be <1ms, got \(String(format: "%.3f", overheadMilliseconds))ms"
        )
    }

    func testMetricsOverhead_WithMultipleTools() async throws {
        let collector = MetricsCollector()
        let iterations = 1000
        let tools = ["search", "read", "write", "generate", "validate"]

        // Measure time WITH metrics (rotating through tools)
        let withMetricsStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            let tool = tools[i % tools.count]
            await collector.recordRequest(tool: tool, duration: 0.1)
        }
        let withMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withMetricsDuration = withMetricsEnd - withMetricsStart

        // Measure time WITHOUT metrics (baseline)
        let withoutMetricsStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            let tool = tools[i % tools.count]
            _ = tool
        }
        let withoutMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withoutMetricsDuration = withoutMetricsEnd - withoutMetricsStart

        // Calculate overhead per request
        let totalOverhead = withMetricsDuration - withoutMetricsDuration
        let overheadPerRequest = totalOverhead / Double(iterations)
        let overheadMilliseconds = overheadPerRequest * 1000

        print("""

        Metrics Performance (Multiple Tools):
        --------------------------------------
        Iterations: \(iterations)
        Tools: \(tools.count)
        With metrics: \(String(format: "%.6f", withMetricsDuration))s
        Without metrics: \(String(format: "%.6f", withoutMetricsDuration))s
        Overhead per request: \(String(format: "%.6f", overheadPerRequest))s (\(String(format: "%.3f", overheadMilliseconds))ms)

        """)

        // Assert overhead is less than 1ms
        XCTAssertLessThan(
            overheadMilliseconds,
            1.0,
            "Metrics overhead with multiple tools should be <1ms, got \(String(format: "%.3f", overheadMilliseconds))ms"
        )
    }

    func testMetricsOverhead_WithViolationTracking() async throws {
        let collector = MetricsCollector()
        let iterations = 1000

        // Measure time WITH metrics and violations
        let withMetricsStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            await collector.recordRequest(tool: "test-tool", duration: 0.1)
            if i % 10 == 0 {
                await collector.recordViolation(rule: "test-rule")
            }
        }
        let withMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withMetricsDuration = withMetricsEnd - withMetricsStart

        // Measure time WITHOUT metrics (baseline)
        let withoutMetricsStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            _ = i
            if i % 10 == 0 {
                _ = "test-rule"
            }
        }
        let withoutMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withoutMetricsDuration = withoutMetricsEnd - withoutMetricsStart

        // Calculate overhead per request
        let totalOverhead = withMetricsDuration - withoutMetricsDuration
        let overheadPerRequest = totalOverhead / Double(iterations)
        let overheadMilliseconds = overheadPerRequest * 1000

        print("""

        Metrics Performance (With Violations):
        --------------------------------------
        Iterations: \(iterations)
        With metrics: \(String(format: "%.6f", withMetricsDuration))s
        Without metrics: \(String(format: "%.6f", withoutMetricsDuration))s
        Overhead per request: \(String(format: "%.6f", overheadPerRequest))s (\(String(format: "%.3f", overheadMilliseconds))ms)

        """)

        // Assert overhead is less than 1ms
        XCTAssertLessThan(
            overheadMilliseconds,
            1.0,
            "Metrics overhead with violations should be <1ms, got \(String(format: "%.3f", overheadMilliseconds))ms"
        )
    }

    func testMetricsOverhead_UnderConcurrentLoad() async throws {
        let collector = MetricsCollector()
        let iterations = 100
        let concurrentTasks = 10

        // Measure time WITH metrics under concurrent load
        let withMetricsStart = CFAbsoluteTimeGetCurrent()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrentTasks {
                group.addTask {
                    for _ in 0..<iterations {
                        await collector.recordRequest(tool: "concurrent-tool", duration: 0.1)
                    }
                }
            }
        }
        let withMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withMetricsDuration = withMetricsEnd - withMetricsStart

        // Measure time WITHOUT metrics (baseline)
        let withoutMetricsStart = CFAbsoluteTimeGetCurrent()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrentTasks {
                group.addTask {
                    for i in 0..<iterations {
                        _ = i
                    }
                }
            }
        }
        let withoutMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withoutMetricsDuration = withoutMetricsEnd - withoutMetricsStart

        // Calculate overhead per request
        let totalRequests = iterations * concurrentTasks
        let totalOverhead = withMetricsDuration - withoutMetricsDuration
        let overheadPerRequest = totalOverhead / Double(totalRequests)
        let overheadMilliseconds = overheadPerRequest * 1000

        print("""

        Metrics Performance (Concurrent):
        ---------------------------------
        Total requests: \(totalRequests)
        Concurrent tasks: \(concurrentTasks)
        With metrics: \(String(format: "%.6f", withMetricsDuration))s
        Without metrics: \(String(format: "%.6f", withoutMetricsDuration))s
        Overhead per request: \(String(format: "%.6f", overheadPerRequest))s (\(String(format: "%.3f", overheadMilliseconds))ms)

        """)

        // Assert overhead is less than 1ms even under concurrent load
        XCTAssertLessThan(
            overheadMilliseconds,
            1.0,
            "Metrics overhead under concurrent load should be <1ms, got \(String(format: "%.3f", overheadMilliseconds))ms"
        )
    }

    func testMetricsOverhead_WithLatencyStatistics() async throws {
        let collector = MetricsCollector()
        let iterations = 1000

        // Measure time WITH metrics including latency calculations
        let withMetricsStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            await collector.recordRequest(tool: "test-tool", duration: Double(i) * 0.001)
            // Periodically get stats to simulate real usage
            if i % 100 == 0 {
                _ = await collector.getLatencyStats(tool: "test-tool")
            }
        }
        let withMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withMetricsDuration = withMetricsEnd - withMetricsStart

        // Measure time WITHOUT metrics (baseline)
        let withoutMetricsStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            _ = Double(i) * 0.001
        }
        let withoutMetricsEnd = CFAbsoluteTimeGetCurrent()
        let withoutMetricsDuration = withoutMetricsEnd - withoutMetricsStart

        // Calculate overhead per request
        let totalOverhead = withMetricsDuration - withoutMetricsDuration
        let overheadPerRequest = totalOverhead / Double(iterations)
        let overheadMilliseconds = overheadPerRequest * 1000

        print("""

        Metrics Performance (With Stats):
        ---------------------------------
        Iterations: \(iterations)
        With metrics: \(String(format: "%.6f", withMetricsDuration))s
        Without metrics: \(String(format: "%.6f", withoutMetricsDuration))s
        Overhead per request: \(String(format: "%.6f", overheadPerRequest))s (\(String(format: "%.3f", overheadMilliseconds))ms)

        """)

        // Assert overhead is less than 1ms
        XCTAssertLessThan(
            overheadMilliseconds,
            1.0,
            "Metrics overhead with stats should be <1ms, got \(String(format: "%.3f", overheadMilliseconds))ms"
        )
    }
}
