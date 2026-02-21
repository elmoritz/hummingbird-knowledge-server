// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/DiagnoseStartupFailureTool.swift
//
// Step-by-step diagnosis of Hummingbird 2.x startup errors.
// Covers common startup failure modes: missing services, configuration errors,
// port conflicts, Swift concurrency issues, and dependency graph failures.

import MCP

struct DiagnoseStartupFailureTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "diagnose_startup_failure",
            description: "Step-by-step diagnosis of a Hummingbird 2.x application startup failure. "
                + "Covers configuration errors, missing services, port conflicts, "
                + "Swift concurrency issues, and dependency graph failures.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "error_output": [
                        "type": "string",
                        "description": "The full startup error output or crash log",
                    ],
                    "configuration": [
                        "type": "string",
                        "description": "Optional: relevant configuration (env vars, Package.swift, etc.)",
                    ],
                ],
                "required": ["error_output"],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let errorOutput) = arguments["error_output"] else {
            return CallTool.Result(
                content: [.text("Missing required argument: 'error_output'")],
                isError: true
            )
        }

        let lower = errorOutput.lowercased()

        // Pattern-match against common startup failure signatures
        var diagnosis: String

        if lower.contains("address already in use") || lower.contains("eaddrinuse") {
            diagnosis = """
            ## Diagnosis: Port Already In Use

            Another process is binding to the same port.

            **Fixes:**
            1. Find the conflicting process: `lsof -i :<PORT>` then `kill <PID>`
            2. Change the port: set `PORT=8081` in your environment
            3. If running via Docker: ensure no other container uses the same host port

            **Environment variable:** `PORT=8080` (default)
            """
        } else if lower.contains("preconditionfailure") && lower.contains("appdependencies") {
            diagnosis = """
            ## Diagnosis: DependencyInjectionMiddleware Not Registered

            `AppDependencies.placeholder` was accessed — this means `DependencyInjectionMiddleware`
            is either missing or registered after a route that tries to access `context.dependencies`.

            **Fix in Application+build.swift:**
            ```swift
            // ✅ DI middleware MUST be first
            router.add(middleware: DependencyInjectionMiddleware(dependencies: dependencies))
            router.add(middleware: RequestLoggingMiddleware())
            // Other middleware...
            // Routes last
            router.get("/") { ... }
            ```
            """
        } else if lower.contains("cannot find type") || lower.contains("no such module") {
            diagnosis = """
            ## Diagnosis: Missing Module or Type

            A required module is not in Package.swift or a type name is wrong.

            **Common causes:**
            1. Missing `.product(name: "MCP", package: "mcp-swift-sdk")` in Package.swift
            2. `swift package resolve` not run after adding a dependency
            3. Incorrect module name (e.g. `ModelContextProtocol` instead of `MCP`)

            **Steps:**
            1. Run: `swift package resolve`
            2. Check `Package.swift` dependencies match the exact package/product names
            3. Clean build: `swift package clean && swift build`
            """
        } else if lower.contains("task cancelled") || lower.contains("cancelerror") {
            diagnosis = """
            ## Diagnosis: Task Cancelled at Startup

            A background service or async task was cancelled before it could complete initialisation.

            **Common causes:**
            1. `server.start(transport:)` not running before the first client request
            2. `KnowledgeStore.loadFromBundle()` failing silently
            3. A `Service.run()` throwing on startup

            **Fix:** Ensure `MCPServerService` and `KnowledgeUpdateService` are added via
            `app.addServices(...)` and that `KnowledgeStore.loadFromBundle()` succeeds.
            """
        } else {
            // General guidance
            let entries = await store.allEntries()
            let relevant = entries.filter { lower.contains($0.title.lowercased().split(separator: " ").first.map(String.init) ?? "") }

            diagnosis = """
            ## Startup Failure Diagnosis

            **Error:** \(errorOutput.prefix(500))

            **General checklist:**
            1. Run `swift build` first — compilation errors must be fixed before startup
            2. Check that `knowledge.json` is included as a Package.swift resource
            3. Verify `PORT` is not already bound by another process
            4. Ensure `MCP_AUTH_TOKEN` is set if running in hosted mode
            5. Run with `LOG_LEVEL=debug` for more detail

            \(relevant.isEmpty ? "" : "**Potentially relevant patterns:**\n" + relevant.prefix(2).map { "• \($0.title) (id: `\($0.id)`)" }.joined(separator: "\n"))
            """
        }

        return CallTool.Result(content: [.text(diagnosis)])
    }
}
