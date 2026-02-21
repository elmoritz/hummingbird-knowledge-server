// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/ReportIssueTool.swift
//
// Self-healing feedback mechanism.
// Reports incorrect or outdated answers from the MCP server.
// Reports are logged and prioritised in the next KnowledgeUpdateService cycle.

import MCP
import Logging

struct ReportIssueTool: ToolHandler {

    let store: KnowledgeStore

    // Logger is module-level to avoid capturing `self` in the actor-isolated handler
    private let logger = Logger(label: "com.hummingbird-knowledge-server.report")

    var tool: Tool {
        Tool(
            name: "report_issue",
            description: "Report an incorrect, outdated, or missing answer from this MCP server. "
                + "Reports are logged and prioritised in the next knowledge base update cycle. "
                + "This is the primary mechanism by which the knowledge base improves over time.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "tool_name": [
                        "type": "string",
                        "description": "The tool that gave the incorrect answer (e.g. 'check_architecture')",
                    ],
                    "query": [
                        "type": "string",
                        "description": "The question or input that produced the wrong answer",
                    ],
                    "problem": [
                        "type": "string",
                        "description": "What was wrong with the answer",
                    ],
                    "correct_answer": [
                        "type": "string",
                        "description": "Optional: what the correct answer should be",
                    ],
                    "hummingbird_version": [
                        "type": "string",
                        "description": "Hummingbird version you were using (e.g. '2.5.0')",
                    ],
                    "swift_version": [
                        "type": "string",
                        "description": "Swift version you were using (e.g. '6.0')",
                    ],
                ],
                "required": ["tool_name", "query", "problem"],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let toolName) = arguments["tool_name"] else {
            return CallTool.Result(content: [.text("Missing required argument: 'tool_name'")], isError: true)
        }
        guard case .string(let query) = arguments["query"] else {
            return CallTool.Result(content: [.text("Missing required argument: 'query'")], isError: true)
        }
        guard case .string(let problem) = arguments["problem"] else {
            return CallTool.Result(content: [.text("Missing required argument: 'problem'")], isError: true)
        }

        let correctAnswer = arguments["correct_answer"].flatMap { if case .string(let s) = $0 { s } else { nil } }
        let hbVersion = arguments["hummingbird_version"].flatMap { if case .string(let s) = $0 { s } else { nil } }
        let swiftVersion = arguments["swift_version"].flatMap { if case .string(let s) = $0 { s } else { nil } }

        logger.warning(
            "Knowledge base issue reported",
            metadata: [
                "tool": "\(toolName)",
                "query": "\(query.prefix(200))",
                "problem": "\(problem.prefix(500))",
                "hummingbird_version": "\(hbVersion ?? "unknown")",
                "swift_version": "\(swiftVersion ?? "unknown")",
                "has_correction": "\(correctAnswer != nil)",
            ]
        )

        let response = """
        ✅ Issue reported. Thank you for improving the knowledge base.

        **Summary:**
        - Tool: \(toolName)
        - Problem: \(problem.prefix(200))
        \(hbVersion.map { "- Hummingbird: \($0)" } ?? "")
        \(swiftVersion.map { "- Swift: \($0)" } ?? "")

        This report has been logged and will be reviewed in the next knowledge update cycle.
        The `KnowledgeUpdateService` uses these reports to prioritise which areas need
        verification against the latest Hummingbird releases and SSWG index.
        """

        return CallTool.Result(content: [.text(response)])
    }
}
