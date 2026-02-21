// Sources/HummingbirdKnowledgeServer/AutoUpdate/MCPServerService.swift
//
// Wraps `server.start(transport:)` as a swift-service-lifecycle Service so it
// runs concurrently with the Hummingbird HTTP server inside the service group.
//
// `server.start()` is long-running — it processes the MCP message loop until
// the transport disconnects or an error is thrown. Running it as a Service
// ensures it starts with the application and stops cleanly on shutdown.

import ServiceLifecycle
import MCP
import Logging

/// Lifecycle service that drives the MCP SDK message loop.
///
/// Added to the application via `app.addServices(MCPServerService(...))`.
/// Starts when the service group starts, stops when the transport disconnects.
struct MCPServerService: Service {

    let server: Server
    let transport: HummingbirdSSETransport
    let logger: Logger

    func run() async throws {
        logger.info("MCP server service starting")
        do {
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        } catch {
            logger.error("MCP server stopped with error", metadata: ["error": "\(error)"])
            throw error
        }
        logger.info("MCP server service stopped")
    }
}
