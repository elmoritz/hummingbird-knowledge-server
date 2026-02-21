// Sources/HummingbirdKnowledgeServer/Middleware/DependencyInjectionMiddleware.swift
//
// Must be the first middleware registered on the router.
// Populates AppRequestContext.dependencies before any other middleware or
// route handler runs. All downstream code reads from context.dependencies.

import Hummingbird

/// Injects the application-level dependency graph into every request context.
///
/// This middleware must be registered first — before AuthMiddleware,
/// RateLimitMiddleware, or any route handler — so that subsequent middleware
/// and handlers can safely access `context.dependencies`.
struct DependencyInjectionMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    let dependencies: AppDependencies

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        var context = context
        context.dependencies = dependencies
        return try await next(request, context)
    }
}
