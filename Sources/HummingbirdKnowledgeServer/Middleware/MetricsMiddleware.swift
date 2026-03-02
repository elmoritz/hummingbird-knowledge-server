// Sources/HummingbirdKnowledgeServer/Middleware/MetricsMiddleware.swift
//
// Captures request metrics: duration, counts by path, and MCP tool usage.
// Designed for <1ms overhead per request through efficient async actor access.

import Hummingbird
import Foundation

struct MetricsMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    let metricsCollector: MetricsCollector

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        let start = Date()
        let path = request.uri.path

        do {
            let response = try await next(request, context)
            let duration = Date().timeIntervalSince(start)

            // Record metrics asynchronously — actor ensures thread safety
            // Tool name extraction happens in MCP SDK layer; here we use path
            let tool = extractToolName(from: path)
            await metricsCollector.recordRequest(tool: tool, duration: duration)

            return response
        } catch {
            let duration = Date().timeIntervalSince(start)
            // Still record the request even on failure for complete observability
            let tool = extractToolName(from: path)
            await metricsCollector.recordRequest(tool: tool, duration: duration)
            throw error
        }
    }

    // MARK: - Private helpers

    /// Extract a tool name or path identifier for metrics labeling.
    /// For MCP requests, this returns "mcp" as a placeholder.
    /// Tool-specific metrics are captured at the MCP handler level.
    private func extractToolName(from path: String) -> String {
        if path.starts(with: "/mcp") {
            return "mcp"
        } else if path.starts(with: "/health") {
            return "health"
        } else if path.starts(with: "/ready") {
            return "ready"
        } else if path.starts(with: "/metrics") {
            return "metrics"
        } else {
            return "unknown"
        }
    }
}
