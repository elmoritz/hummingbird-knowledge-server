// Sources/HummingbirdKnowledgeServer/main.swift
//
// Bootstrap — logging, config, runService().
//
// Responsibilities:
//   1. Load and validate configuration from environment variables
//   2. Bootstrap the logging system with the configured log level
//   3. Build the application (composition root in Application+build.swift)
//   4. Hand off to Hummingbird's service runner
//
// No application logic lives here — this file is kept intentionally minimal
// so that buildApplication() can be tested independently.

import Hummingbird
import Logging

// Step 1: Load configuration (fails fast on invalid env vars)
let configuration = try AppConfiguration.load()

// Step 2: Bootstrap logging with the configured level
LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = configuration.logLevel
    return handler
}

// Step 3: Build the application
let app = try await buildApplication(configuration: configuration)

// Step 4: Run — this blocks until a shutdown signal is received
try await app.runService()
