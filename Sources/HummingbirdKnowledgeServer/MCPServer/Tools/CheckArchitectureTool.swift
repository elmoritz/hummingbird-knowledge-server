// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/CheckArchitectureTool.swift
//
// Fully implemented tool — the reference pattern for all other tools.
//
// Detects architectural violations in submitted Hummingbird 2.x source code using
// the compiled regex catalogue in ArchitecturalViolations. Critical violations are
// surfaced as errors; others as warnings with correction guidance.

import MCP

struct CheckArchitectureTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "check_architecture",
            description: "Analyse Hummingbird 2.x Swift source code for architectural violations. "
                + "Returns a list of detected violations with severity, description, and the "
                + "knowledge base entry ID that explains the correct approach.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "code": [
                        "type": "string",
                        "description": "Swift source code to analyse (paste the full file contents)",
                    ],
                    "file_path": [
                        "type": "string",
                        "description": "Optional file path hint (e.g. 'Sources/App/Services/UserService.swift'). Used to apply layer-specific rules.",
                    ],
                ],
                "required": ["code"],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let code) = arguments["code"] else {
            return CallTool.Result(
                content: [.text("Missing required argument: 'code' (must be a string)")],
                isError: true
            )
        }

        let filePath = arguments["file_path"].flatMap { if case .string(let s) = $0 { s } else { nil } }

        let violations = await store.detectViolations(in: code)

        if violations.isEmpty {
            let message = [
                "✅ No architectural violations detected.",
                filePath.map { "File: \($0)" } ?? nil,
                "",
                "The submitted code passes all architecture checks:",
                "• Route handlers appear to be pure dispatchers",
                "• No Hummingbird imports detected in service files",
                "• No inline service construction found",
                "• Error handling follows the AppError pattern",
            ].compactMap { $0 }.joined(separator: "\n")

            return CallTool.Result(content: [.text(message)])
        }

        let hasCritical = violations.contains { $0.severity == .critical }

        var lines: [String] = []

        if hasCritical {
            lines.append("🚫 CODE GENERATION BLOCKED — critical violations found.\n")
        } else {
            lines.append("⚠️ Architectural violations detected:\n")
        }

        for (i, violation) in violations.enumerated() {
            let icon: String
            switch violation.severity {
            case .critical: icon = "🔴 CRITICAL"
            case .error:    icon = "🟠 ERROR"
            case .warning:  icon = "🟡 WARNING"
            }

            lines.append("\(i + 1). [\(icon)] \(violation.id)")
            lines.append("   \(violation.description)")

            if let correction = await store.entry(for: violation.correctionId) {
                lines.append("   → Fix: \(correction.title)")
                lines.append("")
                lines.append("   \(correction.content)")
                lines.append("")
                lines.append("   (pattern_id: \(violation.correctionId))")
            } else {
                lines.append("   → Correction ID: \(violation.correctionId)")
            }
            lines.append("")
        }

        if hasCritical {
            lines.append("Correct all critical violations before requesting code generation.")
        }

        return CallTool.Result(
            content: [.text(lines.joined(separator: "\n"))],
            isError: hasCritical
        )
    }
}
