// Sources/HummingbirdKnowledgeServer/Context/AppDependencies.swift
//
// Immutable dependency graph threaded through every request via AppRequestContext.
// The only file that constructs this is Application+build.swift.

import MCP

/// All application-level dependencies, assembled once at startup and carried
/// through every request. All fields are concrete types — this is the composition
/// boundary where protocols meet implementations.
struct AppDependencies: Sendable {
    let mcpServer: Server
    let transport: HummingbirdSSETransport
    let knowledgeStore: KnowledgeStore

}
