// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/ListPitfallsTool.swift
//
// Returns a ranked list of known Hummingbird 2.x pitfalls, filterable by category.
// Pitfalls are sorted by confidence (most impactful first).

import MCP

struct ListPitfallsTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "list_pitfalls",
            description: "List known Hummingbird 2.x pitfalls and anti-patterns, ranked by impact. "
                + "Filter by layer or severity. Use the returned IDs with explain_pattern for full details.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "layer": [
                        "type": "string",
                        "enum": ["controller", "service", "repository", "model", "middleware", "configuration"],
                        "description": "Optional: filter by architectural layer",
                    ],
                    "severity": [
                        "type": "string",
                        "enum": ["critical", "error", "warning"],
                        "description": "Optional: filter by violation severity",
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of pitfalls to return (default: 10)",
                    ],
                ],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        let layerFilter = arguments["layer"].flatMap {
            if case .string(let s) = $0 { ArchitecturalLayer(rawValue: s) } else { nil }
        }
        let severityFilter = arguments["severity"].flatMap {
            if case .string(let s) = $0 { s } else { nil }
        }
        let limit = arguments["limit"].flatMap { if case .int(let n) = $0 { n } else { nil } } ?? 10

        var pitfalls = await store.pitfalls()

        if let layer = layerFilter {
            pitfalls = pitfalls.filter { $0.layer == layer }
        }

        let violations = ArchitecturalViolations.all.filter { violation in
            guard let sev = severityFilter else { return true }
            switch violation.severity {
            case .critical: return sev == "critical"
            case .error:    return sev == "error"
            case .warning:  return sev == "warning"
            }
        }

        var lines: [String] = ["# Hummingbird 2.x Pitfall Catalogue\n"]

        if !violations.isEmpty {
            lines.append("## Architectural Violations (detected by check_architecture)\n")
            for (i, v) in violations.prefix(limit).enumerated() {
                let icon: String
                switch v.severity {
                case .critical: icon = "🔴"
                case .error:    icon = "🟠"
                case .warning:  icon = "🟡"
                }
                lines.append("\(i + 1). \(icon) **\(v.id)**")
                lines.append("   \(v.description)")
                lines.append("   *Correction:* `\(v.correctionId)`\n")
            }
        }

        if !pitfalls.isEmpty {
            lines.append("## Knowledge Base Pitfalls\n")
            for (i, entry) in pitfalls.prefix(limit).enumerated() {
                lines.append("\(i + 1). **\(entry.title)** (id: `\(entry.id)`)")
                let preview = String(entry.content.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                lines.append("   \(preview)…\n")
            }
        }

        lines.append("\nUse `explain_pattern` with an entry ID for the full pattern with code examples.")

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
