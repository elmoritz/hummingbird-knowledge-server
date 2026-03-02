// Sources/HummingbirdKnowledgeServer/main.swift
//
// Bootstrap — logging, config, runService().
//
// Responsibilities:
//   1. Load and validate configuration from environment variables
//   2. Bootstrap the logging system with the configured log level
//   3. Build the application (composition root in Application+build.swift)
//   4. Hand off to Hummingbird's service runner
//   5. Trigger startup failure alerts if initialization fails
//
// No application logic lives here — this file is kept intentionally minimal
// so that buildApplication() can be tested independently.

import Hummingbird
import Logging
import Foundation

do {
    // Step 1: Load configuration (fails fast on invalid env vars)
    let configuration = try AppConfiguration.load()

    // Step 2: Bootstrap logging with the configured level
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = configuration.logLevel
        return handler
    }

    // Step 2.5: Create alert hook for startup failures
    // This is created early so we can alert on buildApplication() failures
    let alertLogger = Logger(label: "com.hummingbird-knowledge-server.startup-alerts")
    let alertHook: AlertHook = if let webhookURLString = configuration.alertWebhookURL,
                                   let webhookURL = URL(string: webhookURLString) {
        WebhookAlertHook(webhookURL: webhookURL, logger: alertLogger)
    } else {
        LogAlertHook(logger: alertLogger)
    }

    do {
        // Step 3: Build the application
        let app = try await buildApplication(configuration: configuration)

        // Step 4: Run — this blocks until a shutdown signal is received
        try await app.runService()
    } catch {
        // Application build or runtime failure — trigger alert and re-throw
        await alertHook.trigger(event: .startupFailure(error: error.localizedDescription))
        throw error
    }
} catch {
    // Configuration loading failure — log to stderr and exit
    // (Can't trigger alert hook because we don't have configuration yet)
    var errorHandler = StreamLogHandler.standardError(label: "startup-error")
    errorHandler.logLevel = .error
    let errorLogger = Logger(label: "startup-error", factory: { _ in errorHandler })
    errorLogger.critical("Startup failed: \(error.localizedDescription)")
    throw error
}
