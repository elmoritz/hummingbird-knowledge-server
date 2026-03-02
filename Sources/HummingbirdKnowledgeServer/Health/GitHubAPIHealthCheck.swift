// Sources/HummingbirdKnowledgeServer/Health/GitHubAPIHealthCheck.swift
//
// Health check for the GitHub API subsystem.
// Verifies that api.github.com is reachable with a quick HEAD request.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Health check that verifies GitHub API is reachable.
/// Uses a simple HEAD request to minimize overhead and avoid rate limit consumption.
struct GitHubAPIHealthCheck: HealthCheck {
    private let timeout: TimeInterval
    private let githubToken: String?

    /// Initialize with optional GitHub token and timeout.
    ///
    /// - Parameters:
    ///   - githubToken: Optional GitHub personal access token for authenticated requests
    ///   - timeout: Request timeout in seconds (default: 0.5s)
    init(githubToken: String? = nil, timeout: TimeInterval = 0.5) {
        self.githubToken = githubToken
        self.timeout = timeout
    }

    func check() async -> HealthStatus {
        let startTime = Date()
        let url = URL(string: "https://api.github.com")!

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = timeout
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if let token = githubToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return HealthStatus(
                    name: "github_api",
                    status: .unhealthy,
                    message: "Invalid response type"
                )
            }

            let responseTime = Date().timeIntervalSince(startTime)
            let responseTimeMs = String(format: "%.0f", responseTime * 1000)

            // GitHub API returns 200 for authenticated requests, 404 for unauthenticated
            // Both indicate the API is reachable
            if http.statusCode == 200 || http.statusCode == 404 {
                return HealthStatus(
                    name: "github_api",
                    status: .healthy,
                    message: "GitHub API is reachable",
                    metadata: [
                        "response_time_ms": responseTimeMs,
                        "status_code": String(http.statusCode)
                    ]
                )
            } else if http.statusCode == 403 {
                // Rate limited - degraded but still reachable
                return HealthStatus(
                    name: "github_api",
                    status: .degraded,
                    message: "GitHub API rate limited",
                    metadata: [
                        "response_time_ms": responseTimeMs,
                        "status_code": "403"
                    ]
                )
            } else {
                return HealthStatus(
                    name: "github_api",
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
                name: "github_api",
                status: .unhealthy,
                message: "Request timed out"
            )
        } catch {
            return HealthStatus(
                name: "github_api",
                status: .unhealthy,
                message: "Connection failed: \(error.localizedDescription)"
            )
        }
    }
}
