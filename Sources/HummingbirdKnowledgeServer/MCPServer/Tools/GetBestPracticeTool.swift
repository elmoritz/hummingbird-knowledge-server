// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/GetBestPracticeTool.swift
//
// Returns the definitive best practice for a given Hummingbird 2.x topic.
// Answers are drawn from the knowledge base and the compiled violation catalogue.

import MCP

struct GetBestPracticeTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "get_best_practice",
            description: "Return the definitive Hummingbird 2.x best practice for a topic. "
                + "Covers layering, dependency injection, error handling, concurrency, testing, and deployment.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "topic": [
                        "type": "string",
                        "description": "The topic to get best practices for (e.g. 'error handling', 'dependency injection', 'service layer', 'testing', 'middleware')",
                    ],
                    "layer": [
                        "type": "string",
                        "enum": ["controller", "service", "repository", "model", "middleware", "configuration"],
                        "description": "Optional: restrict to a specific architectural layer",
                    ],
                ],
                "required": ["topic"],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let topic) = arguments["topic"] else {
            return CallTool.Result(
                content: [.text("Missing required argument: 'topic'")],
                isError: true
            )
        }

        let layerFilter = arguments["layer"].flatMap {
            if case .string(let s) = $0 { ArchitecturalLayer(rawValue: s) } else { nil }
        }

        let lowerTopic = topic.lowercased()
        var allEntries = await store.allEntries()

        if let layer = layerFilter {
            allEntries = allEntries.filter { $0.layer == layer }
        }

        let matches = allEntries.filter { entry in
            guard !entry.isTutorialPattern else { return false }
            return entry.title.lowercased().contains(lowerTopic)
                || entry.content.lowercased().contains(lowerTopic)
                || entry.patternIds.contains { $0.contains(lowerTopic) }
        }.sorted { $0.confidence > $1.confidence }

        if matches.isEmpty {
            return CallTool.Result(
                content: [.text("No best practice found for '\(topic)'\(layerFilter.map { " in the \($0.rawValue) layer" } ?? ""). Try list_pitfalls to browse available topics.")],
                isError: false
            )
        }

        var lines: [String] = ["# Best Practice: \(topic)\n"]
        if let layer = layerFilter {
            lines.append("**Layer:** \(layer.rawValue)\n")
        }

        for entry in matches.prefix(3) {
            lines.append("## \(entry.title)")
            lines.append(entry.content)
            lines.append("")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
