// Sources/HummingbirdKnowledgeServer/Alerts/WebhookAlertHook.swift
//
// Webhook-based alert implementation.
// Sends HTTP POST requests to a configured webhook URL with JSON payload.
// Optional — only enabled when ALERT_WEBHOOK_URL is configured.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

/// Webhook-based alert hook that sends alerts to an HTTP endpoint.
/// Useful for integrating with external monitoring systems (PagerDuty, Slack, etc.)
struct WebhookAlertHook: AlertHook {
    private let webhookURL: URL
    private let timeout: TimeInterval
    private let logger: Logger

    /// Initialize with webhook URL and optional timeout.
    ///
    /// - Parameters:
    ///   - webhookURL: The webhook endpoint to POST alerts to
    ///   - timeout: Request timeout in seconds (default: 5s)
    ///   - logger: Logger for recording webhook delivery status
    init(webhookURL: URL, timeout: TimeInterval = 5.0, logger: Logger) {
        self.webhookURL = webhookURL
        self.timeout = timeout
        self.logger = logger
    }

    func trigger(event: AlertEvent) async {
        do {
            // Build JSON payload
            let payload: [String: Any] = [
                "alert_type": event.eventType,
                "message": event.description,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "metadata": event.metadata
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: payload)

            // Create POST request
            var request = URLRequest(url: webhookURL)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            // Send request (ignore response)
            let (_, response) = try await URLSession.shared.data(for: request)

            // Log success or failure
            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    logger.debug(
                        "Alert webhook delivered successfully",
                        metadata: [
                            "webhook_url": .string(webhookURL.absoluteString),
                            "alert_type": .string(event.eventType),
                            "status_code": .stringConvertible(http.statusCode)
                        ]
                    )
                } else {
                    logger.warning(
                        "Alert webhook returned non-success status",
                        metadata: [
                            "webhook_url": .string(webhookURL.absoluteString),
                            "alert_type": .string(event.eventType),
                            "status_code": .stringConvertible(http.statusCode)
                        ]
                    )
                }
            }
        } catch let error as URLError where error.code == .timedOut {
            logger.warning(
                "Alert webhook timed out",
                metadata: [
                    "webhook_url": .string(webhookURL.absoluteString),
                    "alert_type": .string(event.eventType),
                    "timeout": .stringConvertible(timeout)
                ]
            )
        } catch {
            logger.warning(
                "Alert webhook failed",
                metadata: [
                    "webhook_url": .string(webhookURL.absoluteString),
                    "alert_type": .string(event.eventType),
                    "error": .string(error.localizedDescription)
                ]
            )
        }
    }
}
