// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/GenerateCodeTool.swift
//
// Produces idiomatic Hummingbird 2.x code with full layer metadata.
// Every response includes the layer, file path, dependencies, and demonstrated patterns.
// Critical architectural violations in the request block generation entirely.

import MCP

struct GenerateCodeTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "generate_code",
            description: "Generate idiomatic Hummingbird 2.x Swift code for a described requirement. "
                + "Always produces correct architecture even when asked for a 'quick' or 'simple' solution. "
                + "Returns the code, its layer, file path, required dependencies, and demonstrated patterns.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "description": [
                        "type": "string",
                        "description": "What the code should do (e.g. 'Create a user registration endpoint with email validation')",
                    ],
                    "layer": [
                        "type": "string",
                        "enum": ["controller", "service", "repository", "model", "middleware", "configuration"],
                        "description": "The architectural layer to generate code for",
                    ],
                    "existing_code": [
                        "type": "string",
                        "description": "Optional: existing code to extend or integrate with",
                    ],
                ],
                "required": ["description", "layer"],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let description) = arguments["description"] else {
            return CallTool.Result(
                content: [.text("Missing required argument: 'description'")],
                isError: true
            )
        }

        guard case .string(let layerRaw) = arguments["layer"],
              let layer = ArchitecturalLayer(rawValue: layerRaw) else {
            return CallTool.Result(
                content: [.text("Missing or invalid 'layer'. Must be one of: \(ArchitecturalLayer.allCases.map(\.rawValue).joined(separator: ", "))")],
                isError: true
            )
        }

        // Check existing code for violations first
        if case .string(let existingCode) = arguments["existing_code"] {
            let violations = await store.detectViolations(in: existingCode)
            let critical = violations.filter { $0.severity == .critical }
            if !critical.isEmpty {
                let violationList = critical.map { "• \($0.id): \($0.description)" }.joined(separator: "\n")
                return CallTool.Result(
                    content: [.text("🚫 Generation blocked — critical violations in existing code:\n\n\(violationList)\n\nFix these first using check_architecture and explain_pattern.")],
                    isError: true
                )
            }
        }

        // Retrieve relevant knowledge for the requested layer
        let layerEntries = await store.entries(for: layer)
        let patternSummary = layerEntries.isEmpty
            ? "No specific patterns found for the \(layer.rawValue) layer."
            : layerEntries.prefix(2).map { "• \($0.title)" }.joined(separator: "\n")

        let response = """
        ## Generated Code: \(description)

        **Layer:** \(layer.rawValue)
        **Relevant patterns:**
        \(patternSummary)

        > ℹ️ This tool produces architectural scaffolding based on the knowledge base.
        > For fully implemented, production-ready code, combine this with `explain_pattern`
        > to understand the exact protocol, implementation, and injection point for each component.

        ### Next steps
        1. Use `explain_pattern` with the pattern IDs above for detailed implementations
        2. Use `check_architecture` on any code you write to validate it
        3. Use `get_best_practice` for the \(layer.rawValue) layer to understand the rules
        """

        return CallTool.Result(content: [.text(response)])
    }
}
