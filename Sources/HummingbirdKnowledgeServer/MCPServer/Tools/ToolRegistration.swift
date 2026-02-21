// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/ToolRegistration.swift
//
// Aggregates all tool handlers and registers them on the MCP server.
//
// The MCP SDK supports only one ListTools handler and one CallTool handler per server.
// This file is the single registration point that collects all tool implementations
// into those two handlers. Adding a new tool = add a new conforming type here.

import MCP

// MARK: - Tool handler protocol

/// Contract for all MCP tool implementations.
///
/// Each tool defines its MCP `Tool` descriptor (name, description, input schema)
/// and a `handle` function that processes arguments and returns a result.
/// `ToolRegistration.registerTools(on:knowledgeStore:)` aggregates all handlers.
protocol ToolHandler: Sendable {
    var tool: Tool { get }
    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result
}

// MARK: - Registration

/// Registers all tools on the MCP server.
///
/// Called once during application startup, before `server.start(transport:)`.
/// The `knowledgeStore` actor reference is captured by tool handler closures;
/// all actor calls inside handlers are correctly `await`ed.
func registerTools(on server: Server, knowledgeStore: KnowledgeStore) async {
    let handlers: [any ToolHandler] = [
        CheckArchitectureTool(store: knowledgeStore),
        ExplainErrorTool(store: knowledgeStore),
        ExplainPatternTool(store: knowledgeStore),
        GenerateCodeTool(store: knowledgeStore),
        GetBestPracticeTool(store: knowledgeStore),
        ListPitfallsTool(store: knowledgeStore),
        DiagnoseStartupFailureTool(store: knowledgeStore),
        CheckVersionCompatibilityTool(store: knowledgeStore),
        GetPackageRecommendationTool(store: knowledgeStore),
        ReportIssueTool(store: knowledgeStore),
    ]

    // One ListTools handler aggregates every tool's descriptor
    await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: handlers.map(\.tool))
    }

    // One CallTool handler dispatches to the matching tool by name
    await server.withMethodHandler(CallTool.self) { params in
        let name = params.name
        let arguments = params.arguments ?? [:]

        for handler in handlers where handler.tool.name == name {
            return try await handler.handle(arguments)
        }

        return CallTool.Result(
            content: [.text("Unknown tool: \(name). Available: \(handlers.map(\.tool.name).joined(separator: ", "))")],
            isError: true
        )
    }
}
