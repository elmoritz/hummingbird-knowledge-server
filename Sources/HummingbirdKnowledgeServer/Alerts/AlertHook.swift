// Sources/HummingbirdKnowledgeServer/Alerts/AlertHook.swift
//
// Protocol for alerting hooks.
// Allows notification of operational issues like knowledge update failures,
// rate limit exhaustion, and startup failures.
//
// Implementations:
// - LogAlertHook: Logs alerts at error level (default, always enabled)
// - WebhookAlertHook: Sends alerts to a webhook URL (optional, for production)

import Foundation

/// Event types that can trigger alerts
enum AlertEvent: Sendable {
    case knowledgeUpdateFailure(error: String)
    case rateLimitExhaustion(clientIP: String, limit: Int)
    case startupFailure(error: String)

    /// Human-readable description of the event
    var description: String {
        switch self {
        case .knowledgeUpdateFailure(let error):
            return "Knowledge update failed: \(error)"
        case .rateLimitExhaustion(let clientIP, let limit):
            return "Rate limit exhausted for \(clientIP) (limit: \(limit) req/min)"
        case .startupFailure(let error):
            return "Application startup failed: \(error)"
        }
    }

    /// Event type name for structured logging/webhooks
    var eventType: String {
        switch self {
        case .knowledgeUpdateFailure:
            return "knowledge_update_failure"
        case .rateLimitExhaustion:
            return "rate_limit_exhaustion"
        case .startupFailure:
            return "startup_failure"
        }
    }

    /// Additional metadata about the event
    var metadata: [String: String] {
        switch self {
        case .knowledgeUpdateFailure(let error):
            return ["error": error]
        case .rateLimitExhaustion(let clientIP, let limit):
            return ["client_ip": clientIP, "limit": "\(limit)"]
        case .startupFailure(let error):
            return ["error": error]
        }
    }
}

/// Protocol for alert hooks.
/// Implementations should be non-blocking and handle failures gracefully.
protocol AlertHook: Sendable {

    /// Trigger an alert for the given event.
    ///
    /// - Parameter event: The event to alert on
    /// - Note: Should not throw — implementations must handle errors internally
    func trigger(event: AlertEvent) async
}
