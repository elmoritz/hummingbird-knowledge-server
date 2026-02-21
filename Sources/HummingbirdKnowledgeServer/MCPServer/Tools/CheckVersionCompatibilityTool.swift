// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/CheckVersionCompatibilityTool.swift
//
// Checks a code snippet or dependency for 1.x vs 2.x compatibility.
// Identifies deprecated APIs, renamed types, and migration steps.

import MCP

struct CheckVersionCompatibilityTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "check_version_compatibility",
            description: "Check a Hummingbird code snippet or dependency for 1.x vs 2.x compatibility. "
                + "Identifies deprecated APIs, breaking changes, and migration steps.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "code": [
                        "type": "string",
                        "description": "Swift code snippet or Package.swift dependency to check",
                    ],
                    "from_version": [
                        "type": "string",
                        "description": "Source Hummingbird version (e.g. '1.9.0'). Default: '1.x'",
                    ],
                    "to_version": [
                        "type": "string",
                        "description": "Target Hummingbird version (e.g. '2.5.0'). Default: '2.x latest'",
                    ],
                ],
                "required": ["code"],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let code) = arguments["code"] else {
            return CallTool.Result(
                content: [.text("Missing required argument: 'code'")],
                isError: true
            )
        }

        let fromVersion = arguments["from_version"].flatMap { if case .string(let s) = $0 { s } else { nil } } ?? "1.x"
        let toVersion = arguments["to_version"].flatMap { if case .string(let s) = $0 { s } else { nil } } ?? "2.x"

        // Known 1.x → 2.x breaking changes
        let breakingChanges: [(pattern: String, description: String, migration: String)] = [
            ("HBApplication", "HBApplication renamed to Application in 2.x",
             "Replace `HBApplication` with `Application` from `import Hummingbird`"),
            ("HBRequest", "HBRequest renamed to Request in 2.x",
             "Replace `HBRequest` with `Request`"),
            ("HBResponse", "HBResponse renamed to Response in 2.x",
             "Replace `HBResponse` with `Response`"),
            ("HBMiddleware", "HBMiddleware replaced by RouterMiddleware protocol in 2.x",
             "Conform to `RouterMiddleware` with an associated `Context` type instead"),
            ("HBRouterBuilder", "HBRouterBuilder replaced by `Router(context:)` in 2.x",
             "Use `Router(context: AppRequestContext.self)` instead"),
            ("HBHTTPError", "HBHTTPError renamed to HTTPError in 2.x",
             "Replace `HBHTTPError` with `HTTPError`"),
            ("addMiddleware", "`addMiddleware` replaced by `router.add(middleware:)` in 2.x",
             "Use `router.add(middleware: MyMiddleware())` — note: must be called before routes"),
        ]

        var issues: [(description: String, migration: String)] = []
        for change in breakingChanges {
            if code.contains(change.pattern) {
                issues.append((change.description, change.migration))
            }
        }

        var lines: [String] = ["# Compatibility Check: \(fromVersion) → \(toVersion)\n"]

        if issues.isEmpty {
            lines.append("✅ No known compatibility issues detected in the submitted code.")
            lines.append("")
            lines.append("The code does not use any known deprecated 1.x APIs.")
            lines.append("Run `check_architecture` to validate the 2.x architectural patterns.")
        } else {
            lines.append("⚠️ **\(issues.count) compatibility issue(s) found:**\n")
            for (i, issue) in issues.enumerated() {
                lines.append("\(i + 1). **\(issue.description)**")
                lines.append("   Migration: \(issue.migration)")
                lines.append("")
            }
            lines.append("After migrating, run `check_architecture` to validate the 2.x patterns.")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
