// Sources/HummingbirdKnowledgeServer/Metrics/MetricsCollector.swift
//
// Thread-safe metrics collection using Swift actors.
// Stores request counts, latencies, violation stats, and knowledge base metrics.
//
// Automatically evicts old histogram data to prevent unbounded memory growth.
// For production deployment with persistence, export to Prometheus or similar.

import Foundation

/// Thread-safe metrics collector for observability.
/// Tracks request counts, response latencies, violation detection, and knowledge base stats.
actor MetricsCollector {

    // MARK: - Counter metrics

    private var requestCounts: [String: Int] = [:]          // tool -> count
    private var violationCounts: [String: Int] = [:]        // rule -> count
    private var totalRequests: Int = 0

    // MARK: - Gauge metrics

    private var knowledgeBaseEntryCount: Int = 0
    private var lastKnowledgeUpdate: Date?

    // MARK: - Histogram metrics

    private struct LatencySample {
        let duration: TimeInterval
        let timestamp: Date
    }

    private var latencySamples: [String: [LatencySample]] = [:]  // tool -> samples
    private let maxSamplesPerTool: Int = 1000
    private let sampleRetentionPeriod: TimeInterval = 3600  // 1 hour

    // MARK: - Eviction tracking

    private var lastEviction: Date = Date()
    private let evictionInterval: TimeInterval = 300  // evict stale samples every 5 minutes

    // MARK: - Public interface

    /// Record a completed request for a specific tool
    func recordRequest(tool: String, duration: TimeInterval) {
        let now = Date()

        // Update counters
        totalRequests += 1
        requestCounts[tool, default: 0] += 1

        // Record latency sample
        var samples = latencySamples[tool] ?? []
        samples.append(LatencySample(duration: duration, timestamp: now))

        // Limit samples per tool to prevent unbounded growth
        if samples.count > maxSamplesPerTool {
            samples.removeFirst(samples.count - maxSamplesPerTool)
        }

        latencySamples[tool] = samples

        // Periodic eviction of stale samples
        if now.timeIntervalSince(lastEviction) > evictionInterval {
            evictStaleSamples(before: now.addingTimeInterval(-sampleRetentionPeriod))
            lastEviction = now
        }
    }

    /// Record a violation detection for a specific rule
    func recordViolation(rule: String) {
        violationCounts[rule, default: 0] += 1
    }

    /// Update knowledge base metrics
    func updateKnowledgeBaseStats(entryCount: Int) {
        knowledgeBaseEntryCount = entryCount
        lastKnowledgeUpdate = Date()
    }

    /// Get current request count for a specific tool
    func getRequestCount(tool: String) -> Int {
        requestCounts[tool] ?? 0
    }

    /// Get total request count across all tools
    func getTotalRequests() -> Int {
        totalRequests
    }

    /// Get all tool request counts
    func getAllRequestCounts() -> [String: Int] {
        requestCounts
    }

    /// Get violation count for a specific rule
    func getViolationCount(rule: String) -> Int {
        violationCounts[rule] ?? 0
    }

    /// Get all violation counts
    func getAllViolationCounts() -> [String: Int] {
        violationCounts
    }

    /// Get knowledge base entry count
    func getKnowledgeBaseEntryCount() -> Int {
        knowledgeBaseEntryCount
    }

    /// Get last knowledge update timestamp
    func getLastKnowledgeUpdate() -> Date? {
        lastKnowledgeUpdate
    }

    /// Get latency statistics for a specific tool
    func getLatencyStats(tool: String) -> LatencyStats? {
        guard let samples = latencySamples[tool], !samples.isEmpty else {
            return nil
        }

        let durations = samples.map { $0.duration }.sorted()
        let count = durations.count

        let sum = durations.reduce(0, +)
        let mean = sum / Double(count)

        let p50 = durations[count / 2]
        let p95 = durations[Int(Double(count) * 0.95)]
        let p99 = durations[Int(Double(count) * 0.99)]

        return LatencyStats(
            count: count,
            mean: mean,
            p50: p50,
            p95: p95,
            p99: p99,
            min: durations.first!,
            max: durations.last!
        )
    }

    /// Get latency statistics for all tools
    func getAllLatencyStats() -> [String: LatencyStats] {
        var stats: [String: LatencyStats] = [:]
        for tool in latencySamples.keys {
            if let toolStats = getLatencyStats(tool: tool) {
                stats[tool] = toolStats
            }
        }
        return stats
    }

    /// Reset all metrics (useful for testing)
    func reset() {
        requestCounts.removeAll()
        violationCounts.removeAll()
        totalRequests = 0
        knowledgeBaseEntryCount = 0
        lastKnowledgeUpdate = nil
        latencySamples.removeAll()
        lastEviction = Date()
    }

    // MARK: - Private helpers

    private func evictStaleSamples(before cutoff: Date) {
        for (tool, samples) in latencySamples {
            let freshSamples = samples.filter { $0.timestamp > cutoff }
            if freshSamples.isEmpty {
                latencySamples.removeValue(forKey: tool)
            } else {
                latencySamples[tool] = freshSamples
            }
        }
    }
}

// MARK: - Supporting types

/// Latency statistics for a specific tool
struct LatencyStats: Codable {
    let count: Int
    let mean: TimeInterval
    let p50: TimeInterval
    let p95: TimeInterval
    let p99: TimeInterval
    let min: TimeInterval
    let max: TimeInterval
}
