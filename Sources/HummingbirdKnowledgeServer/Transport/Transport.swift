// Sources/HummingbirdKnowledgeServer/Transport/Transport.swift
//
// Protocol abstraction for MCP transports in Hummingbird.
//
// This protocol extends MCP.Transport with Hummingbird-specific message handling
// methods, enabling dependency injection and supporting multiple transport
// implementations (SSE, HTTP, etc.).

import MCP
import Foundation

/// Protocol for MCP transports that integrate with Hummingbird's request/response
/// handling. Extends the MCP SDK's `Transport` protocol with methods for feeding
/// messages from HTTP handlers and managing client connections.
///
/// Conforming types (e.g., `HummingbirdSSETransport`, `HummingbirdHTTPTransport`)
/// bridge Hummingbird's HTTP layer into the MCP SDK's message processing.
public protocol HummingbirdTransport: Transport {

    /// Feeds an inbound JSON-RPC message into the transport.
    ///
    /// Called by POST request handlers to push client messages into the MCP SDK's
    /// receive pipeline. The transport queues this data for consumption by the
    /// MCP server via the `receive()` method.
    ///
    /// - Parameter data: Raw JSON-RPC message body from the HTTP request
    func feedMessage(_ data: Data) async

    /// Registers a new client connection for receiving outbound messages.
    ///
    /// Called when a client opens a connection to receive server responses and
    /// notifications. Returns a unique client ID and an async stream that yields
    /// outbound message data.
    ///
    /// - Returns: A tuple containing the client's unique ID and a stream of
    ///   outbound message data. The caller should iterate the stream and forward
    ///   each data frame to the client (e.g., as SSE events or HTTP response chunks).
    func registerSSEClient() async -> (id: UUID, stream: AsyncThrowingStream<Data, Swift.Error>)

    /// Removes a client connection when it closes.
    ///
    /// Called when a client disconnects or the connection is terminated. The
    /// transport should clean up resources associated with this client ID and
    /// close its outbound stream.
    ///
    /// - Parameter id: The unique ID returned by `registerSSEClient()`
    func removeSSEClient(id: UUID) async
}
