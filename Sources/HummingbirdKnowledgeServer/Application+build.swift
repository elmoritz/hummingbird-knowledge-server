// Sources/HummingbirdKnowledgeServer/Application+build.swift
//
// The single composition root for the entire application.
// This is the only file that knows about ALL concrete types simultaneously.
// Everything else depends only on protocols or the types it directly owns.
//
// Middleware registration order is critical:
//   1. DependencyInjectionMiddleware  ← always first
//   2. RequestLoggingMiddleware       ← always present
//   3. AuthMiddleware                 ← only in hosted mode
//   4. RateLimitMiddleware            ← only in hosted mode

import Hummingbird
import MCP
import Logging

func buildApplication(
    configuration: AppConfiguration
) async throws -> some ApplicationProtocol {

    let logger = Logger(label: "com.hummingbird-knowledge-server.app")

    if configuration.isHosted {
        logger.info("Running in hosted mode — authentication and rate limiting active")
    } else {
        logger.info("Running in local mode — no authentication required")
    }

    // ── Knowledge base ────────────────────────────────────────────────────────
    let knowledgeStore = try KnowledgeStore.loadFromBundle()
    let entryCount = await knowledgeStore.count
    logger.info("Knowledge base loaded", metadata: ["entries": "\(entryCount)"])

    // ── MCP Server ────────────────────────────────────────────────────────────
    let mcpServer = Server(
        name: "hummingbird-knowledge-server",
        version: "0.1.0",
        capabilities: .init(
            prompts: .init(listChanged: false),
            resources: .init(subscribe: false, listChanged: true),
            tools: .init(listChanged: true)
        )
    )

    // Register handlers before start() is called — order does not matter here
    await registerTools(on: mcpServer, knowledgeStore: knowledgeStore)
    await registerResources(on: mcpServer, knowledgeStore: knowledgeStore)
    await registerPrompts(on: mcpServer)

    // ── SSE Transport ─────────────────────────────────────────────────────────
    let transport = HummingbirdSSETransport(
        logger: Logger(label: "com.hummingbird-knowledge-server.transport")
    )

    // ── Dependencies ──────────────────────────────────────────────────────────
    let dependencies = AppDependencies(
        mcpServer: mcpServer,
        transport: transport,
        knowledgeStore: knowledgeStore
    )

    // ── Router ────────────────────────────────────────────────────────────────
    let router = Router(context: AppRequestContext.self)

    // Middleware — always present, always first
    router.add(middleware: DependencyInjectionMiddleware(dependencies: dependencies))
    router.add(middleware: RequestLoggingMiddleware())

    // Hosted-only middleware — not added at all in local mode
    if let token = configuration.authToken {
        router.add(middleware: AuthMiddleware(token: token))
        logger.info("Auth middleware active")
    }
    if let limit = configuration.rateLimitPerMinute {
        router.add(middleware: RateLimitMiddleware(requestsPerMinute: limit))
        logger.info("Rate limiting active", metadata: ["requestsPerMinute": "\(limit)"])
    }

    // Infrastructure endpoints — always unauthenticated
    router.get("/health") { _, _ in
        ["status": "ok"]
    }
    router.get("/ready") { _, context in
        let count = await context.dependencies.knowledgeStore.count
        return ["status": "ok", "knowledgeEntries": "\(count)"]
    }

    // The MCP endpoint — single path, GET (SSE stream) + POST (messages)
    MCPController().registerRoutes(on: router.group("/mcp"))

    // ── Application ───────────────────────────────────────────────────────────
    var app = Application(
        router: router,
        configuration: .init(
            address: .hostname(configuration.host, port: configuration.port),
            serverName: "hummingbird-knowledge-server/0.1.0"
        )
    )

    // Background services run concurrently with the HTTP server
    app.addServices(
        MCPServerService(
            server: mcpServer,
            transport: transport,
            logger: Logger(label: "com.hummingbird-knowledge-server.mcp")
        ),
        KnowledgeUpdateService(
            store: knowledgeStore,
            githubToken: configuration.githubToken,
            updateInterval: configuration.knowledgeUpdateInterval,
            logger: Logger(label: "com.hummingbird-knowledge-server.updater")
        )
    )

    logger.info(
        "Application built",
        metadata: [
            "host": "\(configuration.host)",
            "port": "\(configuration.port)",
            "mode": "\(configuration.isHosted ? "hosted" : "local")",
        ]
    )

    return app
}
