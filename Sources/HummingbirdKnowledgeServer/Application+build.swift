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
import ServiceLifecycle

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

    // ── MCP Server(s) ─────────────────────────────────────────────────────────
    // Create separate server instances for each transport when "both" is configured.
    // Each server has its own handlers but shares the same knowledge store.
    func createMCPServer() async -> Server {
        let server = Server(
            name: "hummingbird-knowledge-server",
            version: "0.1.0",
            capabilities: .init(
                prompts: .init(listChanged: false),
                resources: .init(subscribe: false, listChanged: true),
                tools: .init(listChanged: true)
            )
        )
        await registerTools(on: server, knowledgeStore: knowledgeStore)
        await registerResources(on: server, knowledgeStore: knowledgeStore)
        await registerPrompts(on: server)
        return server
    }

    let mcpServer = await createMCPServer()

    // ── Transport(s) ──────────────────────────────────────────────────────────
    // Instantiate transport(s) based on configuration.
    // In "both" mode, both transports are created and run concurrently.
    let sseTransport: HummingbirdSSETransport?
    let httpTransport: HummingbirdHTTPTransport?

    if configuration.transport.supportsSSE {
        sseTransport = HummingbirdSSETransport(
            logger: Logger(label: "com.hummingbird-knowledge-server.transport.sse")
        )
        logger.info("SSE transport enabled")
    } else {
        sseTransport = nil
    }

    if configuration.transport.supportsHTTP {
        httpTransport = HummingbirdHTTPTransport(
            logger: Logger(label: "com.hummingbird-knowledge-server.transport.http")
        )
        logger.info("HTTP transport enabled")
    } else {
        httpTransport = nil
    }

    // Primary transport for dependencies (SSE if available, otherwise HTTP)
    let primaryTransport: HummingbirdTransport
    if let sse = sseTransport {
        primaryTransport = sse
    } else if let http = httpTransport {
        primaryTransport = http
    } else {
        throw AppError.noTransportConfigured
    }

    // ── Dependencies ──────────────────────────────────────────────────────────
    let dependencies = AppDependencies(
        mcpServer: mcpServer,
        transport: primaryTransport,
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
    // Register MCP server service(s) for each enabled transport.
    // When "both" is configured, each transport gets its own MCP Server instance.
    var services: [any Service] = []

    if let sse = sseTransport {
        let sseServer = configuration.transport == .both ? await createMCPServer() : mcpServer
        services.append(
            MCPServerService(
                server: sseServer,
                transport: sse,
                logger: Logger(label: "com.hummingbird-knowledge-server.mcp.sse")
            )
        )
    }

    if let http = httpTransport {
        let httpServer = configuration.transport == .both ? await createMCPServer() : mcpServer
        services.append(
            MCPServerService(
                server: httpServer,
                transport: http,
                logger: Logger(label: "com.hummingbird-knowledge-server.mcp.http")
            )
        )
    }

    services.append(
        KnowledgeUpdateService(
            store: knowledgeStore,
            githubToken: configuration.githubToken,
            updateInterval: configuration.knowledgeUpdateInterval,
            logger: Logger(label: "com.hummingbird-knowledge-server.updater")
        )
    )

    app.addServices(services)

    logger.info(
        "Application built",
        metadata: [
            "host": "\(configuration.host)",
            "port": "\(configuration.port)",
            "mode": "\(configuration.isHosted ? "hosted" : "local")",
            "transport": "\(configuration.transport)",
        ]
    )

    return app
}
