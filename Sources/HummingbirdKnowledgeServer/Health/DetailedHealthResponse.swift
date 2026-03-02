// Sources/HummingbirdKnowledgeServer/Health/DetailedHealthResponse.swift
//
// Response model for the detailed /health endpoint.
// Aggregates health checks from multiple subsystems (KnowledgeStore, GitHub API,
// SSWG index, etc.) into a single response with overall status.
//
// Used by the enhanced /health endpoint to provide comprehensive operational
// status for monitoring and alerting.

import Foundation

/// Detailed health response that aggregates multiple subsystem health checks.
struct DetailedHealthResponse: Sendable, Codable {
    /// Overall health status of the system.
    /// - healthy: all subsystems are healthy
    /// - degraded: one or more subsystems are degraded but system is still operational
    /// - unhealthy: one or more critical subsystems are unhealthy
    let status: OverallStatus

    /// Individual health check results for each subsystem
    let checks: [HealthStatus]

    /// Timestamp when the health check was performed
    let timestamp: Date

    enum OverallStatus: String, Sendable, Codable {
        case healthy
        case degraded
        case unhealthy
    }

    init(checks: [HealthStatus]) {
        self.checks = checks
        self.timestamp = Date()

        // Compute overall status from individual checks
        if checks.contains(where: { $0.status == .unhealthy }) {
            self.status = .unhealthy
        } else if checks.contains(where: { $0.status == .degraded }) {
            self.status = .degraded
        } else {
            self.status = .healthy
        }
    }
}
