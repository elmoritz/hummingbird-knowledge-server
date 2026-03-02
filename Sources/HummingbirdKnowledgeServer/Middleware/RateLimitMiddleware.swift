// Sources/HummingbirdKnowledgeServer/Middleware/RateLimitMiddleware.swift
//
// Simple in-memory sliding window rate limiter.
// Only added to the router when MCP_AUTH_TOKEN is set (hosted mode).
//
// For a multi-instance hosted deployment, replace the in-memory store with
// a Redis-backed counter (e.g. via RediStack) so limits are shared across pods.
// For a single-instance deployment, this in-memory actor is sufficient.

import Hummingbird
import HTTPTypes
import Logging
import Foundation

struct RateLimitMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    private let store: RateLimitStore
    private let requestsPerMinute: Int
    private let alertHook: AlertHook

    init(store: RateLimitStore, requestsPerMinute: Int, alertHook: AlertHook) {
        self.store = store
        self.requestsPerMinute = requestsPerMinute
        self.alertHook = alertHook
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
        let clientIP: String
        if let forwarded = request.headers[HTTPField.Name("x-forwarded-for")!] {
            clientIP = String(forwarded.split(separator: ",").first ?? "unknown")
        } else if let realIP = request.headers[HTTPField.Name("x-real-ip")!] {
            clientIP = realIP
        } else {
            clientIP = "unknown"
        }

        let allowed = await store.recordRequest(from: clientIP, limit: requestsPerMinute)

        guard allowed else {
            context.logger.warning(
                "Rate limit exceeded",
                metadata: ["clientIP": "\(clientIP)", "limit": "\(requestsPerMinute)/min"]
            )
            await alertHook.trigger(event: .rateLimitExhaustion(clientIP: clientIP, limit: requestsPerMinute))
            throw HTTPError(
                .init(code: 429),
                message: "Rate limit exceeded. Maximum \(requestsPerMinute) requests per minute."
            )
        }

        return try await next(request, context)
    }
}

