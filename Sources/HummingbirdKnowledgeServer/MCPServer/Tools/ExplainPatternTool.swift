// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/ExplainPatternTool.swift
//
// Returns a full pattern explanation: the protocol definition, a concrete
// implementation, the injection point, and common mistakes to avoid.
// Always shows all three layers — never just usage without origin.

import MCP

struct ExplainPatternTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "explain_pattern",
            description: "Explain a Hummingbird 2.x architectural pattern in full. "
                + "Always shows: (1) the protocol, (2) the implementation, (3) the injection point. "
                + "Never shows just usage without showing where the dependency comes from.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "pattern_id": [
                        "type": "string",
                        "description": "Knowledge base entry ID (e.g. 'route-handler-dispatcher-only'). Use list_pitfalls or check_architecture to discover IDs.",
                    ],
                    "topic": [
                        "type": "string",
                        "description": "Free-text topic if you don't know the entry ID (e.g. 'dependency injection', 'service layer', 'middleware')",
                    ],
                ],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        let patternId = arguments["pattern_id"].flatMap { if case .string(let s) = $0 { s } else { nil } }
        let topic = arguments["topic"].flatMap { if case .string(let s) = $0 { s } else { nil } }

        guard patternId != nil || topic != nil else {
            return CallTool.Result(
                content: [.text("Provide either 'pattern_id' or 'topic'")],
                isError: true
            )
        }

        // Try exact ID lookup first
        if let id = patternId, let entry = await store.entry(for: id) {
            return CallTool.Result(content: [.text(formatEntry(entry))])
        }

        // Fall back to topic search
        let searchTerm = topic ?? patternId ?? ""
        let lowerSearch = searchTerm.lowercased()
        let allEntries = await store.allEntries()

        let matches = allEntries.filter { entry in
            entry.title.lowercased().contains(lowerSearch)
            || entry.content.lowercased().contains(lowerSearch)
        }.sorted { $0.confidence > $1.confidence }

        if matches.isEmpty {
            return CallTool.Result(
                content: [.text("No pattern found for '\(searchTerm)'. Use list_pitfalls to browse available entries.")],
                isError: false
            )
        }

        let formatted = matches.prefix(2).map(formatEntry).joined(separator: "\n\n---\n\n")
        return CallTool.Result(content: [.text(formatted)])
    }

    private func formatEntry(_ entry: KnowledgeEntry) -> String {
        var lines: [String] = []
        lines.append("# \(entry.title)")
        lines.append("")
        if let layer = entry.layer {
            lines.append("**Layer:** \(layer.rawValue)")
        }
        lines.append("**Hummingbird:** \(entry.hummingbirdVersionRange) | **Swift:** \(entry.swiftVersionRange)")
        if entry.isTutorialPattern {
            lines.append("⚠️ **This is an anti-pattern.** See correction: `\(entry.correctionId ?? "none")`")
        }
        lines.append("")
        lines.append(entry.content)
        return lines.joined(separator: "\n")
    }
}
