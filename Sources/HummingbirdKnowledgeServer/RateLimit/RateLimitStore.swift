// Sources/HummingbirdKnowledgeServer/RateLimit/RateLimitStore.swift
//
// Protocol for abstracting rate limit storage backends.
// Allows switching between in-memory (single instance) and distributed (Redis) stores.
//
// Implementations:
// - InMemoryRateLimitStore: Fast, local sliding window counter (single instance only)
// - RedisRateLimitStore: Distributed counter using Redis (multi-instance deployments)

import Foundation

/// Storage backend for rate limiting.
/// Implementations must be thread-safe and support async operations.
protocol RateLimitStore: Sendable {

    /// Record a request from a client and check if it should be allowed.
    ///
    /// - Parameters:
    ///   - clientIP: The client's IP address (used as the rate limit key)
    ///   - limit: Maximum requests allowed per minute
    /// - Returns: `true` if the request is within the limit, `false` if rate limit exceeded
    func recordRequest(from clientIP: String, limit: Int) async -> Bool
}
