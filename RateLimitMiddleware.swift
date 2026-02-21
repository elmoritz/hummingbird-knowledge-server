// Sources/HummingbirdKnowledgeServer/Middleware/RateLimitMiddleware.swift
//
// Simple in-memory sliding window rate limiter.
// Only added to the router when RATE_LIMIT_PER_MINUTE is set in the environment.
//
// For a multi-instance hosted deployment, replace the in-memory store with
// a Redis-backed counter (e.g. via RediStack) so limits are shared across pods.
// For a single-instance deployment, this in-memory actor is sufficient.

import Hummingbird
import Logging
import Foundation

struct RateLimitMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    private let store: RateLimitStore
    private let requestsPerMinute: Int

    init(requestsPerMinute: Int) {
        self.requestsPerMinute = requestsPerMinute
        self.store = RateLimitStore()
    }

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        // Always exempt infrastructure endpoints from rate limiting
        let path = request.uri.path
        guard path != "/health", path != "/ready" else {
            return try await next(request, context)
        }

        // Prefer X-Forwarded-For when behind a reverse proxy, fall back to peer address
        let clientIP = request.headers["x-forwarded-for"]
            .flatMap { $0.split(separator: ",").first.map(String.init) }
            ?? request.headers["x-real-ip"]
            ?? "unknown"

        let allowed = await store.recordRequest(from: clientIP, limit: requestsPerMinute)

        guard allowed else {
            context.logger.warning(
                "Rate limit exceeded",
                metadata: ["clientIP": "\(clientIP)", "limit": "\(requestsPerMinute)/min"]
            )
            var headers = HTTPFields()
            headers[.retryAfter] = "60"
            throw HTTPError(
                .init(statusCode: 429),
                message: "Rate limit exceeded. Maximum \(requestsPerMinute) requests per minute."
            )
        }

        return try await next(request, context)
    }
}

// MARK: - Rate limit store

/// Thread-safe sliding window counter per client IP.
/// Automatically evicts stale entries to prevent unbounded memory growth.
private actor RateLimitStore {

    private struct Window {
        var timestamps: [Date] = []
    }

    private var windows: [String: Window] = [:]
    private var lastEviction: Date = Date()
    private let evictionInterval: TimeInterval = 120  // evict stale entries every 2 minutes

    func recordRequest(from clientIP: String, limit: Int) -> Bool {
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
