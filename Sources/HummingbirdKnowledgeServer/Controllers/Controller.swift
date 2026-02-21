// Sources/HummingbirdKnowledgeServer/Controllers/Controller.swift
//
// The protocol all route controllers conform to.
// A controller registers one or more related routes on a given router group.
// Route handlers inside controllers are dispatchers only — no business logic.

import Hummingbird

/// Protocol all route controllers conform to.
///
/// Controllers are responsible solely for HTTP mechanics:
/// decoding requests, dispatching to the service layer via `context.dependencies`,
/// and encoding responses. Business logic must not appear in conforming types.
protocol Controller {
    func registerRoutes(on group: RouterGroup<AppRequestContext>)
}
