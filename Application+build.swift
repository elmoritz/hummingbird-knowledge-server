// Sources/HummingbirdKnowledgeServer/Application+build.swift
//
// The single composition root for the entire application.
// This is the only file that knows about concrete implementations.
// All other files depend on protocols.

import Hummingbird
import Logging
import MCP

func buildApplication(
    configuration: AppConfiguration
) async throws -> some ApplicationProtocol {

    let logger = Logger(label: "com.hummingbird-knowledge-server.app")

    // Log which mode we're running in so it's immediately clear from startup output
    if configuration.isHosted {
        logger.info("Running in hosted mode — authentication and rate limiting active")
    } else {
        logger.info("Running in local mode — no authentication required")
    }

    // ── Knowledge base ────────────────────────────────────────────────────────
    let knowledgeStore = try KnowledgeStore.loadFromBundle()

    // ── MCP Server ────────────────────────────────────────────────────────────
    let mcpServer = Server(
        name: "hummingbird-knowledge-server",
        version: "0.1.0",
        capabilities: .init(
            tools: .init(listChanged: true),
            resources: .init(subscribe: false, listChanged: true),
            prompts: .init(listChanged: false)
        )
    )

    registerTools(on: mcpServer, knowledgeStore: knowledgeStore)
    registerResources(on: mcpServer, knowledgeStore: knowledgeStore)
    registerPrompts(on: mcpServer)

    // ── SSE Transport ─────────────────────────────────────────────────────────
    let transport = HummingbirdSSETransport(logger: logger)

    // ── Dependencies ──────────────────────────────────────────────────────────
    let dependencies = AppDependencies(
        mcpServer: mcpServer,
        transport: transport,
        knowledgeStore: knowledgeStore
    )

    // ── Router ────────────────────────────────────────────────────────────────
    let router = Router(context: AppRequestContext.self)

    // Always present
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
    router.get("/health") { _, _ in ["status": "ok"] }
    router.get("/ready") { _, context in
        ["status": "ok", "knowledgeEntries": context.dependencies.knowledgeStore.count]
    }

    // The MCP endpoint — single path, GET (SSE stream) + POST (messages)
    MCPController().registerRoutes(on: router.group("/mcp"))

    // ── Application ───────────────────────────────────────────────────────────
    var app = Application(
        router: router,
        configuration: .init(
            address: .hostname(configuration.host, port: configuration.port),
            serverName: "hummingbird-knowledge-server/0.1.0",
            gracefulShutdownTimeout: .seconds(30)
        )
    )

    app.addServices(
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
