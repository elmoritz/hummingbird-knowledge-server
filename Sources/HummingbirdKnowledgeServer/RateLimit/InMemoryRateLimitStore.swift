// Sources/HummingbirdKnowledgeServer/RateLimit/InMemoryRateLimitStore.swift
//
// In-memory sliding window rate limiter implementation.
// Thread-safe actor-based storage for single-instance deployments.
//
// For multi-instance hosted deployments, use RedisRateLimitStore instead
// so that rate limits are shared across all instances.

import Foundation

/// Thread-safe in-memory sliding window counter per client IP.
/// Automatically evicts stale entries to prevent unbounded memory growth.
///
/// This implementation is suitable for single-instance deployments.
/// For distributed deployments with multiple instances, use RedisRateLimitStore.
actor InMemoryRateLimitStore: RateLimitStore {

    private struct Window {
        var timestamps: [Date] = []
    }

    private var windows: [String: Window] = [:]
    private var lastEviction: Date = Date()
    private let evictionInterval: TimeInterval = 120  // evict stale entries every 2 minutes

    func recordRequest(from clientIP: String, limit: Int) async -> Bool {
        let now = Date()
        let windowStart = now.addingTimeInterval(-60)

        // Periodic eviction of clients with no recent activity
        if now.timeIntervalSince(lastEviction) > evictionInterval {
            evictStaleWindows(before: windowStart)
            lastEviction = now
        }

        var window = windows[clientIP] ?? Window()

        // Remove timestamps outside the current 1-minute window
        window.timestamps = window.timestamps.filter { $0 > windowStart }

        guard window.timestamps.count < limit else {
            windows[clientIP] = window
            return false
        }

        window.timestamps.append(now)
        windows[clientIP] = window
        return true
    }

    private func evictStaleWindows(before cutoff: Date) {
        windows = windows.filter { _, window in
            window.timestamps.contains { $0 > cutoff }
        }
    }
}
