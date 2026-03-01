// Sources/HummingbirdKnowledgeServer/Transport/HummingbirdSSETransport.swift
//
// Custom MCP ↔ Hummingbird bridge.
//
// The MCP Swift SDK only provides client-side HTTP transport — there is no
// built-in server transport for Hummingbird. This actor bridges Hummingbird's
// request handling into the MCP SDK's Transport protocol.
//
// Message flow:
//   POST /mcp  → feedMessage()         → incomingContinuation → receive() → MCP SDK
//   MCP SDK    → send(_:)              → broadcast to SSE clients
//   GET /mcp   → registerSSEClient()   → streams outbound events to connected client

import MCP
import Foundation
import Logging
import NIOCore

/// Bridges the MCP SDK's `Transport` protocol into Hummingbird's SSE streaming.
///
/// - **GET /mcp**: A client subscribes via `registerSSEClient()` and iterates the
///   returned stream, forwarding each `Data` frame as an SSE event.
/// - **POST /mcp**: The route handler calls `feedMessage(_:)` with the raw JSON-RPC
///   body. The MCP SDK reads these from `receive()` and processes them.
/// - **Responses**: The MCP SDK calls `send(_:)` with response data, which is
///   broadcast to all currently-connected SSE clients.
public actor HummingbirdSSETransport: HummingbirdTransport {

    // MARK: - Transport protocol

    public nonisolated let logger: Logger

    // MARK: - Client → Server

    private let incomingStream: AsyncThrowingStream<Data, Swift.Error>
    private let incomingContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    // MARK: - Server → Client

    /// One continuation per connected SSE client, keyed by a unique ID.
    private var sseClients: [UUID: AsyncThrowingStream<Data, Swift.Error>.Continuation] = [:]

    // MARK: - Init

    public init(logger: Logger) {
        self.logger = logger
        let (stream, continuation) = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        self.incomingStream = stream
        self.incomingContinuation = continuation
    }

    // MARK: - Transport conformance

    public func connect() async throws {
        logger.debug("MCP transport connected")
    }

    public func disconnect() async {
        logger.info("MCP transport disconnecting")
        incomingContinuation.finish()
        for (id, client) in sseClients {
            client.finish()
            logger.debug("Closed SSE client", metadata: ["clientId": "\(id)"])
        }
        sseClients.removeAll()
    }

    /// Called by the MCP SDK to deliver a response or notification to clients.
    /// Broadcasts `data` to every currently-connected SSE stream.
    public func send(_ data: Data) async throws {
        logger.debug("Broadcasting MCP message", metadata: ["bytes": "\(data.count)", "clients": "\(sseClients.count)"])
        for (_, continuation) in sseClients {
            continuation.yield(data)
        }
    }

    /// Called once by `server.start(transport:)` at startup.
    /// Returns the stream of inbound JSON-RPC messages fed by POST handlers.
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        incomingStream
    }

    // MARK: - Hummingbird integration

    /// Called by the POST /mcp handler to push a JSON-RPC message into the MCP SDK.
    public func feedMessage(_ data: Data) {
        logger.debug("Received client message", metadata: ["bytes": "\(data.count)"])
        incomingContinuation.yield(data)
    }

    /// Called by the GET /mcp handler when a new SSE connection opens.
    /// Returns a unique client ID (used to deregister on disconnect) and a stream
    /// to iterate for outbound SSE frames.
    public func registerSSEClient() -> (id: UUID, stream: AsyncThrowingStream<Data, Swift.Error>) {
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        sseClients[id] = continuation
        logger.info("SSE client connected", metadata: ["clientId": "\(id)", "totalClients": "\(sseClients.count)"])
        return (id, stream)
    }

    /// Called by the GET /mcp handler when an SSE connection closes.
    public func removeSSEClient(id: UUID) {
        sseClients[id]?.finish()
        sseClients.removeValue(forKey: id)
        logger.info("SSE client disconnected", metadata: ["clientId": "\(id)", "remainingClients": "\(sseClients.count)"])
    }
}
