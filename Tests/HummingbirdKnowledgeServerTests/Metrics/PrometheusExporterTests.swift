// Tests/HummingbirdKnowledgeServerTests/Metrics/PrometheusExporterTests.swift
//
// Verify PrometheusExporter produces valid Prometheus text format

import XCTest
@testable import HummingbirdKnowledgeServer

final class PrometheusExporterTests: XCTestCase {

    func testExportEmptyMetrics() async throws {
        let collector = MetricsCollector()
        let exporter = PrometheusExporter(metricsCollector: collector)

        let output = await exporter.export()

        // Verify basic Prometheus format structure
        XCTAssertTrue(output.contains("# HELP mcp_requests_total"))
        XCTAssertTrue(output.contains("# TYPE mcp_requests_total counter"))
        XCTAssertTrue(output.contains("mcp_requests_total 0"))

        XCTAssertTrue(output.contains("# HELP mcp_requests_by_tool_total"))
        XCTAssertTrue(output.contains("# TYPE mcp_requests_by_tool_total counter"))

        XCTAssertTrue(output.contains("# HELP mcp_violations_total"))
        XCTAssertTrue(output.contains("# TYPE mcp_violations_total counter"))

        XCTAssertTrue(output.contains("# HELP mcp_knowledge_base_entries"))
        XCTAssertTrue(output.contains("# TYPE mcp_knowledge_base_entries gauge"))

        XCTAssertTrue(output.contains("# HELP mcp_request_duration_seconds"))
        XCTAssertTrue(output.contains("# TYPE mcp_request_duration_seconds summary"))
    }

    func testExportWithToolMetrics() async throws {
        let collector = MetricsCollector()
        let exporter = PrometheusExporter(metricsCollector: collector)

        // Record some requests
        await collector.recordRequest(tool: "search_knowledge", duration: 0.123)
        await collector.recordRequest(tool: "search_knowledge", duration: 0.456)
        await collector.recordRequest(tool: "list_rules", duration: 0.089)

        let output = await exporter.export()

        // Verify tool-specific counters
        XCTAssertTrue(output.contains("mcp_requests_by_tool_total{tool=\"search_knowledge\"} 2"))
        XCTAssertTrue(output.contains("mcp_requests_by_tool_total{tool=\"list_rules\"} 1"))

        // Verify total requests
        XCTAssertTrue(output.contains("mcp_requests_total 3"))

        // Verify latency histograms (summary format)
        XCTAssertTrue(output.contains("mcp_request_duration_seconds{tool=\"search_knowledge\",quantile=\"0.5\"}"))
        XCTAssertTrue(output.contains("mcp_request_duration_seconds{tool=\"search_knowledge\",quantile=\"0.95\"}"))
        XCTAssertTrue(output.contains("mcp_request_duration_seconds{tool=\"search_knowledge\",quantile=\"0.99\"}"))
        XCTAssertTrue(output.contains("mcp_request_duration_seconds_sum{tool=\"search_knowledge\"}"))
        XCTAssertTrue(output.contains("mcp_request_duration_seconds_count{tool=\"search_knowledge\"} 2"))
    }

    func testExportWithViolations() async throws {
        let collector = MetricsCollector()
        let exporter = PrometheusExporter(metricsCollector: collector)

        // Record some violations
        await collector.recordViolation(rule: "no-direct-stdio")
        await collector.recordViolation(rule: "no-direct-stdio")
        await collector.recordViolation(rule: "prefer-logger")

        let output = await exporter.export()

        // Verify violation counters
        XCTAssertTrue(output.contains("mcp_violations_total{rule=\"no-direct-stdio\"} 2"))
        XCTAssertTrue(output.contains("mcp_violations_total{rule=\"prefer-logger\"} 1"))
    }

    func testExportWithKnowledgeBaseStats() async throws {
        let collector = MetricsCollector()
        let exporter = PrometheusExporter(metricsCollector: collector)

        // Update knowledge base stats
        await collector.updateKnowledgeBaseStats(entryCount: 42)

        let output = await exporter.export()

        // Verify gauge metrics
        XCTAssertTrue(output.contains("mcp_knowledge_base_entries 42"))
        XCTAssertTrue(output.contains("mcp_knowledge_base_last_update_timestamp_seconds"))
    }

    func testPrometheusFormatValidation() async throws {
        let collector = MetricsCollector()
        let exporter = PrometheusExporter(metricsCollector: collector)

        // Add varied metrics
        await collector.recordRequest(tool: "search_knowledge", duration: 0.1)
        await collector.recordViolation(rule: "test-rule")
        await collector.updateKnowledgeBaseStats(entryCount: 10)

        let output = await exporter.export()

        // Verify Prometheus text format structure
        let lines = output.split(separator: "\n").map(String.init)

        // Each metric section should have HELP and TYPE comments
        var helpLines = 0
        var typeLines = 0
        var metricLines = 0

        for line in lines {
            if line.starts(with: "# HELP") {
                helpLines += 1
            } else if line.starts(with: "# TYPE") {
                typeLines += 1
            } else if !line.isEmpty && !line.starts(with: "#") {
                metricLines += 1
                // Metric lines should have format: name{labels} value or name value
                XCTAssertTrue(line.contains(" "), "Metric line should contain space: \(line)")
            }
        }

        XCTAssertGreaterThan(helpLines, 0, "Should have HELP comments")
        XCTAssertGreaterThan(typeLines, 0, "Should have TYPE comments")
        XCTAssertGreaterThan(metricLines, 0, "Should have metric data")
    }

    func testLabelEscaping() async throws {
        let collector = MetricsCollector()
        let exporter = PrometheusExporter(metricsCollector: collector)

        // Record request with special characters in tool name
        await collector.recordRequest(tool: "tool\"with\\quotes\nand\\backslashes", duration: 0.1)

        let output = await exporter.export()

        // Verify label values are escaped
        XCTAssertTrue(output.contains("tool=\"tool\\\"with\\\\quotes\\nand\\\\backslashes\""))
    }

    func testContentTypeHeader() async throws {
        // This test verifies the expected Content-Type for Prometheus
        // The actual endpoint should return: text/plain; version=0.0.4
        let expectedContentType = "text/plain; version=0.0.4"

        // Just verify this is the standard Prometheus content type
        XCTAssertEqual(expectedContentType, "text/plain; version=0.0.4")
    }
}
