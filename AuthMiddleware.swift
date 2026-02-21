// Sources/HummingbirdKnowledgeServer/Middleware/AuthMiddleware.swift
//
// When MCP_AUTH_TOKEN is not set, this middleware is not added to the router
// at all — zero overhead for local deployments.
//
// When MCP_AUTH_TOKEN is set, every request to /mcp must include:
//   Authorization: Bearer <token>
//
// Health and readiness probes (/health, /ready) are always exempt so that
// load balancers and container orchestrators work without credentials.

import Hummingbird
import Logging

struct AuthMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    private let token: String

    init(token: String) {
        self.token = token
    }

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        // Always exempt infrastructure endpoints
        let path = request.uri.path
        guard path != "/health", path != "/ready" else {
            return try await next(request, context)
        }

        guard
            let header = request.headers[.authorization],
            header.hasPrefix("Bearer "),
            String(header.dropFirst(7)) == token
        else {
            context.logger.warning(
                "Rejected unauthenticated request",
                metadata: ["path": "\(path)", "method": "\(request.method)"]
            )
            throw HTTPError(
                .unauthorized,
                message: "Valid Bearer token required. Set Authorization: Bearer <token>"
            )
        }

        return try await next(request, context)
    }
}
