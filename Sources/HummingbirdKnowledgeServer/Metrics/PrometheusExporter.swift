// Sources/HummingbirdKnowledgeServer/Metrics/PrometheusExporter.swift
//
// Formats metrics from MetricsCollector into Prometheus text format.
// Supports counters, gauges, and summaries (histogram percentiles).
//
// Output format follows the Prometheus exposition format:
// https://prometheus.io/docs/instrumenting/exposition_formats/

import Foundation

/// Formats metrics in Prometheus text exposition format
struct PrometheusExporter {

    private let metricsCollector: MetricsCollector

    init(metricsCollector: MetricsCollector) {
        self.metricsCollector = metricsCollector
    }

    /// Export all metrics in Prometheus text format
    func export() async -> String {
        var output: [String] = []

        // Counter: Total requests
        output.append("# HELP mcp_requests_total Total number of MCP requests")
        output.append("# TYPE mcp_requests_total counter")
        let totalRequests = await metricsCollector.getTotalRequests()
        output.append("mcp_requests_total \(totalRequests)")
        output.append("")

        // Counter: Requests by tool
        output.append("# HELP mcp_requests_by_tool_total Number of requests per MCP tool")
        output.append("# TYPE mcp_requests_by_tool_total counter")
        let requestCounts = await metricsCollector.getAllRequestCounts()
        if requestCounts.isEmpty {
            output.append("# No data yet")
        } else {
            for (tool, count) in requestCounts.sorted(by: { $0.key < $1.key }) {
                output.append("mcp_requests_by_tool_total{tool=\"\(escapeLabelValue(tool))\"} \(count)")
            }
        }
        output.append("")

        // Counter: Violations by rule
        output.append("# HELP mcp_violations_total Number of architectural violations detected per rule")
        output.append("# TYPE mcp_violations_total counter")
        let violationCounts = await metricsCollector.getAllViolationCounts()
        if violationCounts.isEmpty {
            output.append("# No data yet")
        } else {
            for (rule, count) in violationCounts.sorted(by: { $0.key < $1.key }) {
                output.append("mcp_violations_total{rule=\"\(escapeLabelValue(rule))\"} \(count)")
            }
        }
        output.append("")

        // Gauge: Knowledge base entry count
        output.append("# HELP mcp_knowledge_base_entries Current number of entries in the knowledge base")
        output.append("# TYPE mcp_knowledge_base_entries gauge")
        let entryCount = await metricsCollector.getKnowledgeBaseEntryCount()
        output.append("mcp_knowledge_base_entries \(entryCount)")
        output.append("")

        // Gauge: Last knowledge update timestamp
        output.append("# HELP mcp_knowledge_base_last_update_timestamp_seconds Unix timestamp of last knowledge base update")
        output.append("# TYPE mcp_knowledge_base_last_update_timestamp_seconds gauge")
        if let lastUpdate = await metricsCollector.getLastKnowledgeUpdate() {
            let timestamp = lastUpdate.timeIntervalSince1970
            output.append("mcp_knowledge_base_last_update_timestamp_seconds \(timestamp)")
        } else {
            output.append("# No updates yet")
        }
        output.append("")

        // Summary: Request latency per tool
        output.append("# HELP mcp_request_duration_seconds Request duration in seconds per tool")
        output.append("# TYPE mcp_request_duration_seconds summary")
        let latencyStats = await metricsCollector.getAllLatencyStats()
        if latencyStats.isEmpty {
            output.append("# No data yet")
        } else {
            for (tool, stats) in latencyStats.sorted(by: { $0.key < $1.key }) {
                let escapedTool = escapeLabelValue(tool)
                // Prometheus summary format: metric{labels,quantile="X"} value
                output.append("mcp_request_duration_seconds{tool=\"\(escapedTool)\",quantile=\"0.5\"} \(stats.p50)")
                output.append("mcp_request_duration_seconds{tool=\"\(escapedTool)\",quantile=\"0.95\"} \(stats.p95)")
                output.append("mcp_request_duration_seconds{tool=\"\(escapedTool)\",quantile=\"0.99\"} \(stats.p99)")
                output.append("mcp_request_duration_seconds_sum{tool=\"\(escapedTool)\"} \(stats.mean * Double(stats.count))")
                output.append("mcp_request_duration_seconds_count{tool=\"\(escapedTool)\"} \(stats.count)")
            }
        }
        output.append("")

        return output.joined(separator: "\n")
    }

    // MARK: - Private helpers

    /// Escape label values for Prometheus format
    /// Backslash and double quote must be escaped
    private func escapeLabelValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
