// Sources/HummingbirdKnowledgeServer/Health/HealthCheck.swift
//
// Protocol for subsystem health checks.
// Each subsystem (KnowledgeStore, GitHub API, SSWG index, etc.) can implement
// this protocol to provide detailed health status information.
//
// Used by the enhanced /health endpoint to provide detailed operational status
// beyond simple liveness checks.

import Foundation

/// Result of a health check for a subsystem.
struct HealthStatus: Sendable, Codable {
    /// Name of the subsystem being checked (e.g., "knowledge_store", "github_api")
    let name: String

    /// Current health state
    let status: Status

    /// Optional human-readable message with additional context
    let message: String?

    /// Optional metadata about the check (e.g., response time, entry count)
    let metadata: [String: String]?

    /// Timestamp when the check was performed
    let timestamp: Date

    enum Status: String, Sendable, Codable {
        case healthy
        case degraded
        case unhealthy
    }

    init(
        name: String,
        status: Status,
        message: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.name = name
        self.status = status
        self.message = message
        self.metadata = metadata
        self.timestamp = Date()
    }
}

/// Protocol for health checks of individual subsystems.
/// Implementations should be quick (< 1 second) and not block critical paths.
protocol HealthCheck: Sendable {

    /// Perform the health check and return the current status.
    ///
    /// - Returns: HealthStatus indicating the subsystem's current state
    func check() async -> HealthStatus
}
