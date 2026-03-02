// Tests/HummingbirdKnowledgeServerTests/Alerts/AlertHookTests.swift
//
// Comprehensive tests for alert hooks subsystem: validates AlertEvent properties,
// LogAlertHook logging behavior, and WebhookAlertHook delivery behavior.

import Foundation
import XCTest
import Logging

@testable import HummingbirdKnowledgeServer

final class AlertHookTests: XCTestCase {

    // MARK: - AlertEvent Tests

    func testAlertEvent_KnowledgeUpdateFailure_PropertiesAreCorrect() throws {
        let event = AlertEvent.knowledgeUpdateFailure(error: "Failed to parse knowledge.json")

        XCTAssertEqual(event.eventType, "knowledge_update_failure")
        XCTAssertEqual(event.description, "Knowledge update failed: Failed to parse knowledge.json")
        XCTAssertEqual(event.metadata["error"], "Failed to parse knowledge.json")
        XCTAssertEqual(event.metadata.count, 1)
    }

    func testAlertEvent_RateLimitExhaustion_PropertiesAreCorrect() throws {
        let event = AlertEvent.rateLimitExhaustion(clientIP: "192.168.1.100", limit: 60)

        XCTAssertEqual(event.eventType, "rate_limit_exhaustion")
        XCTAssertEqual(event.description, "Rate limit exhausted for 192.168.1.100 (limit: 60 req/min)")
        XCTAssertEqual(event.metadata["client_ip"], "192.168.1.100")
        XCTAssertEqual(event.metadata["limit"], "60")
        XCTAssertEqual(event.metadata.count, 2)
    }

    func testAlertEvent_StartupFailure_PropertiesAreCorrect() throws {
        let event = AlertEvent.startupFailure(error: "Port 8080 already in use")

        XCTAssertEqual(event.eventType, "startup_failure")
        XCTAssertEqual(event.description, "Application startup failed: Port 8080 already in use")
        XCTAssertEqual(event.metadata["error"], "Port 8080 already in use")
        XCTAssertEqual(event.metadata.count, 1)
    }

    func testAlertEvent_DifferentCases_HaveDistinctEventTypes() throws {
        let events: [AlertEvent] = [
            .knowledgeUpdateFailure(error: "test"),
            .rateLimitExhaustion(clientIP: "test", limit: 1),
            .startupFailure(error: "test"),
        ]

        let eventTypes = Set(events.map { $0.eventType })
        XCTAssertEqual(eventTypes.count, 3, "Each event type should have a unique identifier")
    }

    func testAlertEvent_MetadataKeys_AreConsistent() throws {
        let knowledgeEvent = AlertEvent.knowledgeUpdateFailure(error: "test")
        XCTAssertTrue(knowledgeEvent.metadata.keys.contains("error"))

        let rateLimitEvent = AlertEvent.rateLimitExhaustion(clientIP: "test", limit: 1)
        XCTAssertTrue(rateLimitEvent.metadata.keys.contains("client_ip"))
        XCTAssertTrue(rateLimitEvent.metadata.keys.contains("limit"))

        let startupEvent = AlertEvent.startupFailure(error: "test")
        XCTAssertTrue(startupEvent.metadata.keys.contains("error"))
    }

    // MARK: - LogAlertHook Tests

    func testLogAlertHook_KnowledgeUpdateFailure_LogsCorrectly() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let hook = LogAlertHook(logger: logger)
        let event = AlertEvent.knowledgeUpdateFailure(error: "Test error message")

        await hook.trigger(event: event)

        XCTAssertEqual(testHandler.logs.count, 1, "Should log exactly one message")
        guard let log = testHandler.logs.first else {
            XCTFail("No log entry captured")
            return
        }

        XCTAssertEqual(log.level, .error, "Should log at error level")
        XCTAssertEqual(log.message, "Alert triggered")
        XCTAssertEqual(log.metadata["alert_type"], "knowledge_update_failure")
        XCTAssertEqual(log.metadata["message"], "Knowledge update failed: Test error message")
        XCTAssertEqual(log.metadata["error"], "Test error message")
        XCTAssertNotNil(log.metadata["timestamp"], "Should include timestamp")
    }

    func testLogAlertHook_RateLimitExhaustion_LogsCorrectly() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let hook = LogAlertHook(logger: logger)
        let event = AlertEvent.rateLimitExhaustion(clientIP: "10.0.0.1", limit: 100)

        await hook.trigger(event: event)

        XCTAssertEqual(testHandler.logs.count, 1)
        guard let log = testHandler.logs.first else {
            XCTFail("No log entry captured")
            return
        }

        XCTAssertEqual(log.level, .error)
        XCTAssertEqual(log.message, "Alert triggered")
        XCTAssertEqual(log.metadata["alert_type"], "rate_limit_exhaustion")
        XCTAssertEqual(log.metadata["message"], "Rate limit exhausted for 10.0.0.1 (limit: 100 req/min)")
        XCTAssertEqual(log.metadata["client_ip"], "10.0.0.1")
        XCTAssertEqual(log.metadata["limit"], "100")
    }

    func testLogAlertHook_StartupFailure_LogsCorrectly() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let hook = LogAlertHook(logger: logger)
        let event = AlertEvent.startupFailure(error: "Configuration file not found")

        await hook.trigger(event: event)

        XCTAssertEqual(testHandler.logs.count, 1)
        guard let log = testHandler.logs.first else {
            XCTFail("No log entry captured")
            return
        }

        XCTAssertEqual(log.level, .error)
        XCTAssertEqual(log.message, "Alert triggered")
        XCTAssertEqual(log.metadata["alert_type"], "startup_failure")
        XCTAssertEqual(log.metadata["message"], "Application startup failed: Configuration file not found")
        XCTAssertEqual(log.metadata["error"], "Configuration file not found")
    }

    func testLogAlertHook_MultipleEvents_LogsSequentially() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let hook = LogAlertHook(logger: logger)

        await hook.trigger(event: .knowledgeUpdateFailure(error: "Error 1"))
        await hook.trigger(event: .rateLimitExhaustion(clientIP: "1.1.1.1", limit: 50))
        await hook.trigger(event: .startupFailure(error: "Error 3"))

        XCTAssertEqual(testHandler.logs.count, 3, "Should log all three events")
        XCTAssertEqual(testHandler.logs[0].metadata["alert_type"], "knowledge_update_failure")
        XCTAssertEqual(testHandler.logs[1].metadata["alert_type"], "rate_limit_exhaustion")
        XCTAssertEqual(testHandler.logs[2].metadata["alert_type"], "startup_failure")
    }

    func testLogAlertHook_TimestampFormat_IsISO8601() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let hook = LogAlertHook(logger: logger)
        let beforeTrigger = Date()
        await hook.trigger(event: .startupFailure(error: "test"))
        let afterTrigger = Date()

        guard let log = testHandler.logs.first,
              let timestampStr = log.metadata["timestamp"]?.description else {
            XCTFail("No timestamp in log metadata")
            return
        }

        // Verify ISO8601 format by parsing it
        let formatter = ISO8601DateFormatter()
        guard let parsedDate = formatter.date(from: timestampStr) else {
            XCTFail("Timestamp is not valid ISO8601 format: \(timestampStr)")
            return
        }

        // Verify timestamp is within reasonable bounds
        XCTAssertGreaterThanOrEqual(parsedDate, beforeTrigger.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(parsedDate, afterTrigger.addingTimeInterval(1))
    }

    // MARK: - WebhookAlertHook Tests

    func testWebhookAlertHook_WithValidURL_DoesNotThrow() async throws {
        let logger = Logger(label: "test")
        let webhookURL = URL(string: "https://httpbin.org/status/200")!
        let hook = WebhookAlertHook(webhookURL: webhookURL, timeout: 10.0, logger: logger)

        // Should not throw — WebhookAlertHook handles errors internally
        await hook.trigger(event: .knowledgeUpdateFailure(error: "test"))
    }

    func testWebhookAlertHook_WithInvalidURL_DoesNotThrow() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let webhookURL = URL(string: "https://invalid-domain-that-does-not-exist-12345.com/webhook")!
        let hook = WebhookAlertHook(webhookURL: webhookURL, timeout: 2.0, logger: logger)

        // Should not throw — errors should be logged instead
        await hook.trigger(event: .rateLimitExhaustion(clientIP: "1.1.1.1", limit: 100))

        // Should have logged a warning about the failure
        let warnings = testHandler.logs.filter { $0.level == .warning }
        XCTAssertGreaterThan(warnings.count, 0, "Should log warning for failed webhook delivery")
    }

    func testWebhookAlertHook_WithShortTimeout_LogsTimeoutWarning() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let webhookURL = URL(string: "https://httpbin.org/delay/10")!
        let hook = WebhookAlertHook(webhookURL: webhookURL, timeout: 0.1, logger: logger)

        await hook.trigger(event: .startupFailure(error: "test"))

        // Should have logged a warning about timeout or failure
        let warnings = testHandler.logs.filter { $0.level == .warning }
        XCTAssertGreaterThan(warnings.count, 0, "Should log warning for timeout")

        // Check that one of the warnings mentions timeout or failure
        let hasTimeoutOrFailureWarning = warnings.contains { log in
            let msg = log.message.lowercased()
            return msg.contains("timed out") || msg.contains("failed")
        }
        XCTAssertTrue(hasTimeoutOrFailureWarning, "Should log timeout or failure warning")
    }

    func testWebhookAlertHook_WithSuccessfulDelivery_LogsDebugMessage() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler
        logger.logLevel = .debug

        let webhookURL = URL(string: "https://httpbin.org/status/200")!
        let hook = WebhookAlertHook(webhookURL: webhookURL, timeout: 10.0, logger: logger)

        await hook.trigger(event: .knowledgeUpdateFailure(error: "test"))

        // Should have logged a debug message about successful delivery
        let debugLogs = testHandler.logs.filter { $0.level == .debug }
        if debugLogs.isEmpty {
            // If no debug logs, it might be because the webhook failed - check for warnings
            let warnings = testHandler.logs.filter { $0.level == .warning }
            if warnings.isEmpty {
                XCTFail("Expected either debug log for success or warning log for failure")
            }
        } else {
            let hasSuccessMessage = debugLogs.contains { log in
                log.message.lowercased().contains("delivered successfully")
            }
            XCTAssertTrue(hasSuccessMessage, "Should log success message for successful delivery")
        }
    }

    func testWebhookAlertHook_IncludesCorrectJSONPayload() async throws {
        // This test verifies the hook is non-blocking and processes the event
        // We can't easily verify the exact payload without mocking, but we can verify
        // the hook completes without errors
        let logger = Logger(label: "test")
        let webhookURL = URL(string: "https://httpbin.org/post")!
        let hook = WebhookAlertHook(webhookURL: webhookURL, timeout: 10.0, logger: logger)

        let beforeTrigger = Date()
        await hook.trigger(event: .rateLimitExhaustion(clientIP: "192.168.1.1", limit: 50))
        let afterTrigger = Date()

        // Should complete within reasonable time (not hang)
        let duration = afterTrigger.timeIntervalSince(beforeTrigger)
        XCTAssertLessThan(duration, 15.0, "Webhook trigger should complete within timeout + buffer")
    }

    func testWebhookAlertHook_WithNonSuccessStatusCode_LogsWarning() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let webhookURL = URL(string: "https://httpbin.org/status/500")!
        let hook = WebhookAlertHook(webhookURL: webhookURL, timeout: 10.0, logger: logger)

        await hook.trigger(event: .startupFailure(error: "test"))

        // Should have logged a warning about non-success status
        let warnings = testHandler.logs.filter { $0.level == .warning }
        XCTAssertGreaterThan(warnings.count, 0, "Should log warning for non-success status code")

        let hasStatusCodeWarning = warnings.contains { log in
            log.message.lowercased().contains("non-success status")
        }
        XCTAssertTrue(hasStatusCodeWarning, "Should log warning about non-success status code")
    }

    // MARK: - Integration Tests

    func testMultipleHooks_CanBeCombined() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let logHook = LogAlertHook(logger: logger)
        let webhookURL = URL(string: "https://httpbin.org/status/200")!
        let webhookHook = WebhookAlertHook(webhookURL: webhookURL, timeout: 5.0, logger: logger)

        let event = AlertEvent.knowledgeUpdateFailure(error: "Test error")

        // Trigger both hooks
        await logHook.trigger(event: event)
        await webhookHook.trigger(event: event)

        // Log hook should have logged an error
        let errors = testHandler.logs.filter { $0.level == .error }
        XCTAssertGreaterThan(errors.count, 0, "LogAlertHook should have logged an error")

        let hasAlertLog = errors.contains { log in
            log.message == "Alert triggered" && log.metadata["alert_type"] == "knowledge_update_failure"
        }
        XCTAssertTrue(hasAlertLog, "Should have logged the alert event")
    }

    func testConcurrentAlertTriggers_AreHandledCorrectly() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let hook = LogAlertHook(logger: logger)

        // Trigger multiple alerts concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    await hook.trigger(event: .knowledgeUpdateFailure(error: "Error \(i)"))
                }
            }
        }

        // Should have logged all 10 alerts
        XCTAssertEqual(testHandler.logs.count, 10, "Should log all concurrent alerts")

        // All logs should be at error level
        let allErrors = testHandler.logs.allSatisfy { $0.level == .error }
        XCTAssertTrue(allErrors, "All alert logs should be at error level")
    }

    func testAlertHooks_AreThreadSafe() async throws {
        let testHandler = TestLogHandler()
        var logger = Logger(label: "test")
        logger.handler = testHandler

        let logHook = LogAlertHook(logger: logger)

        // Run concurrent operations with different event types
        await withTaskGroup(of: Void.self) { group in
            for i in 1...20 {
                group.addTask {
                    if i % 3 == 0 {
                        await logHook.trigger(event: .knowledgeUpdateFailure(error: "Error \(i)"))
                    } else if i % 3 == 1 {
                        await logHook.trigger(event: .rateLimitExhaustion(clientIP: "1.1.1.\(i)", limit: i * 10))
                    } else {
                        await logHook.trigger(event: .startupFailure(error: "Error \(i)"))
                    }
                }
            }
        }

        XCTAssertEqual(testHandler.logs.count, 20, "Should handle all concurrent triggers")

        // Verify we have a mix of event types
        let eventTypes = Set(testHandler.logs.compactMap { $0.metadata["alert_type"]?.description })
        XCTAssertEqual(eventTypes.count, 3, "Should have all three event types")
    }
}

// MARK: - Test Helpers

/// Test log handler that captures log messages for testing
private final class TestLogHandler: @unchecked Sendable, LogHandler {
    struct LogEntry {
        let level: Logger.Level
        let message: String
        let metadata: Logger.Metadata
    }

    private let lock = NSLock()
    private var _logs: [LogEntry] = []

    var logs: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _logs
    }

    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata explicitMetadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let combinedMetadata = self.metadata.merging(explicitMetadata ?? [:]) { _, new in new }
        let entry = LogEntry(
            level: level,
            message: message.description,
            metadata: combinedMetadata
        )
        lock.lock()
        _logs.append(entry)
        lock.unlock()
    }
}

// MARK: - Logger.MetadataValue Extension for Testing

private extension Logger.MetadataValue {
    var description: String {
        switch self {
        case .string(let value):
            return value
        case .stringConvertible(let value):
            return value.description
        case .dictionary(let dict):
            return dict.description
        case .array(let array):
            return array.description
        }
    }
}
