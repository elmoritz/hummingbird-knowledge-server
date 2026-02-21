// Sources/HummingbirdKnowledgeServer/Middleware/RequestLoggingMiddleware.swift
//
// Logs every completed request with method, path, status code, and duration.
// Always present in both local and hosted mode — lightweight enough to never skip.

import Hummingbird
import Foundation

struct RequestLoggingMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        let start = Date()
        let method = request.method
        let path = request.uri.path

        do {
            let response = try await next(request, context)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            context.logger.info(
                "Request completed",
                metadata: [
                    "method": "\(method)",
                    "path": "\(path)",
                    "status": "\(response.status.code)",
                    "duration_ms": "\(ms)",
                ]
            )
            return response
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            context.logger.warning(
                "Request failed",
                metadata: [
                    "method": "\(method)",
                    "path": "\(path)",
                    "duration_ms": "\(ms)",
                    "error": "\(error)",
                ]
            )
            throw error
        }
    }
}
