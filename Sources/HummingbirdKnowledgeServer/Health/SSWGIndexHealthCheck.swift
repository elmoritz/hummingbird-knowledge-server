// Sources/HummingbirdKnowledgeServer/Health/SSWGIndexHealthCheck.swift
//
// Health check for the SSWG package index subsystem.
// Verifies that the Swift Server Work Group package collection is reachable.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Health check that verifies SSWG package index is reachable.
/// Uses a simple HEAD request to minimize overhead and bandwidth.
struct SSWGIndexHealthCheck: HealthCheck {
    private let timeout: TimeInterval

    /// Initialize with timeout.
    ///
    /// - Parameter timeout: Request timeout in seconds (default: 0.5s)
    init(timeout: TimeInterval = 0.5) {
        self.timeout = timeout
    }

    func check() async -> HealthStatus {
        let startTime = Date()
        let url = URL(string: "https://swiftserver.group/collection/sswg.json")!

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return HealthStatus(
                    name: "sswg_index",
                    status: .unhealthy,
                    message: "Invalid response type"
                )
            }

            let responseTime = Date().timeIntervalSince(startTime)
            let responseTimeMs = String(format: "%.0f", responseTime * 1000)

            // SSWG collection endpoint should return 200
            if http.statusCode == 200 {
                return HealthStatus(
                    name: "sswg_index",
                    status: .healthy,
                    message: "SSWG index is reachable",
                    metadata: [
                        "response_time_ms": responseTimeMs,
                        "status_code": "200"
                    ]
                )
            } else {
                return HealthStatus(
                    name: "sswg_index",
                    status: .unhealthy,
                    message: "Unexpected status code",
                    metadata: [
                        "response_time_ms": responseTimeMs,
                        "status_code": String(http.statusCode)
                    ]
                )
            }
        } catch let error as URLError where error.code == .timedOut {
            return HealthStatus(
                name: "sswg_index",
                status: .unhealthy,
                message: "Request timed out"
            )
        } catch {
            return HealthStatus(
                name: "sswg_index",
                status: .unhealthy,
                message: "Connection failed: \(error.localizedDescription)"
            )
        }
    }
}
