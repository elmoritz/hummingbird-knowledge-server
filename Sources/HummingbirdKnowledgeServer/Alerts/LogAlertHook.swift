// Sources/HummingbirdKnowledgeServer/Alerts/LogAlertHook.swift
//
// Log-based alert implementation.
// Logs alerts at error level using swift-log Logger.
// Always enabled as the default fallback alert mechanism.

import Foundation
import Logging

/// Log-based alert hook that writes alerts to structured logs.
/// This is the default alert mechanism, always enabled.
struct LogAlertHook: AlertHook {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func trigger(event: AlertEvent) async {
        // Log at error level with structured metadata
        logger.error(
            "Alert triggered",
            metadata: [
                "alert_type": .string(event.eventType),
                "message": .string(event.description),
                "timestamp": .string(ISO8601DateFormatter().string(from: Date()))
            ].merging(
                event.metadata.mapValues { Logger.MetadataValue.string($0) },
                uniquingKeysWith: { _, new in new }
            )
        )
    }
}
