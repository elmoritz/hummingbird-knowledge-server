// Sources/HummingbirdKnowledgeServer/RateLimit/RedisRateLimitStore.swift
//
// Redis-backed distributed rate limiter using sorted sets for sliding window.
// Thread-safe actor-based storage for multi-instance deployments.
//
// Uses Redis sorted sets to track request timestamps within a sliding 60-second window.
// Each client IP has a dedicated sorted set where timestamps are stored as both members and scores.
// Old entries are automatically removed before counting to maintain accuracy.

import Foundation
import RediStack
import NIOCore

/// Redis-backed sliding window rate limiter for distributed deployments.
///
/// This implementation uses Redis sorted sets to track request timestamps,
/// enabling accurate rate limiting across multiple server instances.
///
/// For single-instance deployments, use InMemoryRateLimitStore for better performance.
actor RedisRateLimitStore: RateLimitStore {

    private let redis: any RedisClient

    /// Initialize with a Redis client.
    ///
    /// - Parameter redis: An active Redis client to use for rate limiting operations.
    init(redis: any RedisClient) {
        self.redis = redis
    }

    func recordRequest(from clientIP: String, limit: Int) async -> Bool {
        let key = RedisKey("ratelimit:\(clientIP)")
        let now = Date().timeIntervalSince1970
        let windowStart = now - 60  // 60-second sliding window

        do {
            // Remove timestamps older than 60 seconds
            _ = try await redis.zremrangebyscore(from: key, withMaximumScoreOf: .exclusive(windowStart)).get()

            // Count current requests in the window
            let count = try await redis.zcard(of: key).get()

            guard count < limit else {
                // Rate limit exceeded
                return false
            }

            // Add new request timestamp
            // Use timestamp with microsecond precision as member to ensure uniqueness
            let member = "\(now)-\(Int.random(in: 0..<1_000_000))"
            _ = try await redis.zadd((member, now), to: key).get()

            // Set expiration to 2 minutes to prevent unbounded memory growth
            // This cleans up inactive clients automatically
            _ = try await redis.expire(key, after: .seconds(120)).get()

            return true

        } catch {
            // On Redis errors, fail closed (reject request) to protect the system
            // In production, this should be logged for monitoring
            return false
        }
    }
}
