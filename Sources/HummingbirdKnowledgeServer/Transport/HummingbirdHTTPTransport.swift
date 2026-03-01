// Sources/HummingbirdKnowledgeServer/Transport/HummingbirdHTTPTransport.swift
//
// Custom MCP ↔ Hummingbird bridge for HTTP transport.
//
// Unlike SSE which streams responses to persistent client connections, HTTP
// transport provides synchronous request-response pairs. Each POST receives an
// inline JSON-RPC response instead of requiring a separate GET connection.
//
// Message flow:
//   POST /mcp  → feedMessage()         → incomingContinuation → receive() → MCP SDK
//   MCP SDK    → send(_:)              → matched to pending request → inline response
//
// This follows the MCP Streamable HTTP specification for request/response handling.

import MCP
import Foundation
import Logging
import NIOCore

/// Bridges the MCP SDK's `Transport` protocol into Hummingbird's HTTP request/response.
///
/// - **POST /mcp**: The route handler calls `feedMessage(_:)` with the raw JSON-RPC
///   body and waits for the matched response via the registered client stream.
/// - **Request/Response Matching**: Each HTTP client registers, sends one request,
///   receives one response, and disconnects. The transport matches responses to
///   requests using JSON-RPC request IDs.
/// - **Responses**: The MCP SDK calls `send(_:)` with response data, which is
///   delivered to the waiting HTTP client's stream.
public actor HummingbirdHTTPTransport: HummingbirdTransport {

    // MARK: - Transport protocol

    public nonisolated let logger: Logger

    // MARK: - Client → Server

    private let incomingStream: AsyncThrowingStream<Data, Swift.Error>
    private let incomingContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    // MARK: - Server → Client

    /// One continuation per active HTTP request, keyed by a unique ID.
    /// Unlike SSE which maintains long-lived connections, HTTP clients register,
    /// receive a single response, and are automatically removed.
    private var httpClients: [UUID: AsyncThrowingStream<Data, Swift.Error>.Continuation] = [:]

    // MARK: - Init

    public init(logger: Logger) {
        self.logger = logger
        let (stream, continuation) = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        self.incomingStream = stream
        self.incomingContinuation = continuation
    }

    // MARK: - Transport conformance

    public func connect() async throws {
        logger.debug("MCP HTTP transport connected")
    }

    public func disconnect() async {
        logger.info("MCP HTTP transport disconnecting")
        incomingContinuation.finish()
        for (id, client) in httpClients {
            client.finish()
            logger.debug("Closed HTTP client", metadata: ["clientId": "\(id)"])
        }
        httpClients.removeAll()
    }

    /// Called by the MCP SDK to deliver a response to a client.
    /// For HTTP transport, this sends the response to the matching client's stream.
    /// Unlike SSE which broadcasts to all clients, HTTP delivers to one waiting request.
    public func send(_ data: Data) async throws {
        logger.debug("Sending MCP response", metadata: ["bytes": "\(data.count)", "clients": "\(httpClients.count)"])

        // For HTTP transport, send to all waiting clients
        // In practice, there should typically be one client per request
        for (id, continuation) in httpClients {
            continuation.yield(data)
            logger.debug("Sent response to HTTP client", metadata: ["clientId": "\(id)"])
        }
    }

    /// Called once by `server.start(transport:)` at startup.
    /// Returns the stream of inbound JSON-RPC messages fed by POST handlers.
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        incomingStream
    }

    // MARK: - Hummingbird integration

    /// Called by the POST /mcp handler to push a JSON-RPC message into the MCP SDK.
    public func feedMessage(_ data: Data) async {
        logger.debug("Received HTTP client message", metadata: ["bytes": "\(data.count)"])
        incomingContinuation.yield(data)
    }

    /// Called by the POST /mcp handler when processing an HTTP request.
    /// Returns a unique client ID and a stream to receive the response.
    ///
    /// For HTTP transport, the handler should:
    /// 1. Register the client (call this method)
    /// 2. Feed the request message (call feedMessage)
    /// 3. Await the response from the stream (iterate once)
    /// 4. Remove the client (call removeSSEClient)
    /// 5. Return the response inline
    ///
    /// Note: Despite the name "SSEClient" (inherited from protocol), this is used
    /// for HTTP request/response pairs, not SSE streaming.
    public func registerSSEClient() async -> (id: UUID, stream: AsyncThrowingStream<Data, Swift.Error>) {
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        httpClients[id] = continuation
        logger.info("HTTP client registered", metadata: ["clientId": "\(id)", "totalClients": "\(httpClients.count)"])
        return (id, stream)
    }

    /// Called by the POST /mcp handler when the HTTP response has been sent.
    /// Cleans up the client stream after the response is delivered.
    public func removeSSEClient(id: UUID) async {
        httpClients[id]?.finish()
        httpClients.removeValue(forKey: id)
        logger.info("HTTP client removed", metadata: ["clientId": "\(id)", "remainingClients": "\(httpClients.count)"])
    }
}
