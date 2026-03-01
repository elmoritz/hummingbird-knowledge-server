// Sources/HummingbirdKnowledgeServer/Controllers/MCPController.swift
//
// The single MCP endpoint controller.
//
// GET  /mcp → Opens an SSE stream for server-to-client messages and notifications.
// POST /mcp → Receives a JSON-RPC message and feeds it into the MCP SDK.
//
// Streamable HTTP transport (MCP spec 2025-06-18):
//   - GET opens a persistent SSE connection; responses travel back through it.
//   - POST returns 202 Accepted immediately; the actual response is an SSE event.
//
// Route handlers here are pure dispatchers — no MCP logic lives in this file.

import Hummingbird
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore

struct MCPController: Controller {
    func registerRoutes(on group: RouterGroup<AppRequestContext>) {
        group.get(use: handleSSEStream)
        group.post(use: handleMessage)
    }
}

// MARK: - Route handlers

extension MCPController {

    /// Opens a persistent SSE stream for this client.
    ///
    /// The MCP SDK pushes responses and notifications through `HummingbirdSSETransport.send()`,
    /// which broadcasts them to all connected SSE clients. Each SSE frame is a `data:` line
    /// containing a JSON-RPC response object, terminated by `\n\n`.
    @Sendable
    func handleSSEStream(
        _ request: Request,
        context: AppRequestContext
    ) async throws -> Response {
        let transport = context.dependencies.transport

        let (clientId, sseStream) = await transport.registerSSEClient()

        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"

        let body = ResponseBody { writer in
            defer {
                // Deregister when the SSE connection closes (normally or via error/disconnect)
                Task { await transport.removeSSEClient(id: clientId) }
            }

            for try await data in sseStream {
                guard let text = String(data: data, encoding: .utf8) else { continue }
                let event = "data: \(text)\n\n"
                var buffer = ByteBufferAllocator().buffer(capacity: event.utf8.count)
                buffer.writeString(event)
                try await writer.write(buffer)
            }

            try await writer.finish(nil)
        }

        return Response(status: .ok, headers: headers, body: body)
    }

    /// Receives a JSON-RPC message from the client.
    ///
    /// Feeds the raw body into `HummingbirdSSETransport`, where the MCP SDK reads it,
    /// processes it, and emits the response through `send()` to the SSE stream.
    /// Returns 202 Accepted immediately — the actual JSON-RPC response is an SSE event.
    @Sendable
    func handleMessage(
        _ request: Request,
        context: AppRequestContext
    ) async throws -> Response {
        let bodyBuffer = try await request.body.collect(upTo: 1 * 1024 * 1024)
        let bytes = bodyBuffer.getBytes(at: bodyBuffer.readerIndex, length: bodyBuffer.readableBytes) ?? []
        let data = Data(bytes)

        guard !data.isEmpty else {
            throw HTTPError(.badRequest, message: "Request body must not be empty")
        }

        let transport = context.dependencies.transport
        await transport.feedMessage(data)

        return Response(status: .accepted)
    }
}
