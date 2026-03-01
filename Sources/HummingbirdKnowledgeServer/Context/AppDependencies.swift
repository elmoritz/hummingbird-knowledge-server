// Sources/HummingbirdKnowledgeServer/Context/AppDependencies.swift
//
// Immutable dependency graph threaded through every request via AppRequestContext.
// The only file that constructs this is Application+build.swift.

import MCP

/// All application-level dependencies, assembled once at startup and carried
/// through every request. The transport field uses the protocol type to enable
/// dependency injection of different transport implementations (SSE, HTTP, etc.).
struct AppDependencies: Sendable {
    let mcpServer: Server
    let transport: HummingbirdTransport
    let knowledgeStore: KnowledgeStore

}
