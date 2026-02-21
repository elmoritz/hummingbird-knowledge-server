// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/ExplainErrorTool.swift
//
// Diagnoses error messages and stack traces from Hummingbird 2.x applications.
// Searches the knowledge base for matching pitfalls and correction guidance.

import MCP

struct ExplainErrorTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "explain_error",
            description: "Diagnose a Hummingbird 2.x error message or stack trace. "
                + "Returns the likely cause, the architectural pattern that produced it, "
                + "and the corrected code.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "error_message": [
                        "type": "string",
                        "description": "The full error message or stack trace to diagnose",
                    ],
                    "context": [
                        "type": "string",
                        "description": "Optional: surrounding code or description of what you were doing",
                    ],
                    "hummingbird_version": [
                        "type": "string",
                        "description": "Hummingbird version (e.g. '2.5.0'). Defaults to latest 2.x.",
                    ],
                ],
                "required": ["error_message"],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let errorMessage) = arguments["error_message"] else {
            return CallTool.Result(
                content: [.text("Missing required argument: 'error_message'")],
                isError: true
            )
        }

        let context = arguments["context"].flatMap { if case .string(let s) = $0 { s } else { nil } }

        // Search knowledge entries for relevant matches
        let allEntries = await store.allEntries()
        let lowerError = errorMessage.lowercased()

        let matches = allEntries.filter { entry in
            let searchText = (entry.title + " " + entry.content).lowercased()
            return lowerError.split(separator: " ").contains { word in
                searchText.contains(word)
            }
        }.sorted { $0.confidence > $1.confidence }.prefix(3)

        var lines: [String] = []
        lines.append("## Error Diagnosis\n")
        lines.append("**Error:** \(errorMessage)\n")

        if let ctx = context {
            lines.append("**Context:** \(ctx)\n")
        }

        if matches.isEmpty {
            lines.append("No matching knowledge base entries found for this error.")
            lines.append("")
            lines.append("**Suggestions:**")
            lines.append("• Use `check_architecture` to analyse the surrounding code")
            lines.append("• Use `report_issue` if this is a recurring error not covered here")
        } else {
            lines.append("**Relevant knowledge entries:**\n")
            for entry in matches {
                lines.append("### \(entry.title)")
                lines.append(entry.content)
                lines.append("")
            }
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
