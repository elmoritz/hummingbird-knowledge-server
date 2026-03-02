// Sources/HummingbirdKnowledgeServer/Application+build.swift
//
// The single composition root for the entire application.
// This is the only file that knows about ALL concrete types simultaneously.
// Everything else depends only on protocols or the types it directly owns.
//
// Middleware registration order is critical:
//   1. DependencyInjectionMiddleware  ← always first
//   2. RequestLoggingMiddleware       ← always present
//   3. MetricsMiddleware              ← always present
//   4. AuthMiddleware                 ← only in hosted mode
//   5. RateLimitMiddleware            ← only in hosted mode

import Hummingbird
import MCP
import Logging
import ServiceLifecycle
@preconcurrency import RediStack
import NIOCore
import NIOPosix
import Foundation

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
    let knowledgeStore = try await KnowledgeStore.loadFromBundle()
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

    // ── Metrics ───────────────────────────────────────────────────────────────
    let metricsCollector = MetricsCollector()

    // ── Rate Limit Store ──────────────────────────────────────────────────────
    // Use Redis-backed store for distributed rate limiting if Redis is configured,
    // otherwise fall back to in-memory store for single-instance deployments.
    let rateLimitStore: (any RateLimitStore)?
    if configuration.rateLimitPerMinute != nil {
        if let redisHost = configuration.redisHost, let redisPort = configuration.redisPort {
            // Redis is configured — use distributed rate limiting
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            let redis = try await RedisConnection.make(
                configuration: try .init(
                    hostname: redisHost,
                    port: redisPort,
                    password: configuration.redisPassword
                ),
                boundEventLoop: eventLoopGroup.next()
            ).get()

            // Select database if configured (defaults to 0)
            if let database = configuration.redisDatabase, database != 0 {
                _ = try await redis.select(database: database).get()
            }

            rateLimitStore = RedisRateLimitStore(redis: redis)
            logger.info("Redis rate limit store initialized", metadata: [
                "host": "\(redisHost)",
                "port": "\(redisPort)"
            ])
        } else {
            // No Redis configured — use in-memory rate limiting
            rateLimitStore = InMemoryRateLimitStore()
            logger.info("In-memory rate limit store initialized")
        }
    } else {
        rateLimitStore = nil
    }

    // ── Dependencies ──────────────────────────────────────────────────────────
    let dependencies = AppDependencies(
        mcpServer: mcpServer,
        transport: primaryTransport,
        knowledgeStore: knowledgeStore,
        metricsCollector: metricsCollector
    )

    // ── Router ────────────────────────────────────────────────────────────────
    let router = Router(context: AppRequestContext.self)

    // Middleware — always present, always first
    router.add(middleware: DependencyInjectionMiddleware(dependencies: dependencies))
    router.add(middleware: RequestLoggingMiddleware())
    router.add(middleware: MetricsMiddleware(metricsCollector: metricsCollector))

    // Hosted-only middleware — not added at all in local mode
    if let token = configuration.authToken {
        router.add(middleware: AuthMiddleware(token: token))
        logger.info("Auth middleware active")
    }
    if let store = rateLimitStore, let limit = configuration.rateLimitPerMinute {
        router.add(middleware: RateLimitMiddleware(store: store, requestsPerMinute: limit))
        logger.info("Rate limiting active", metadata: ["requestsPerMinute": "\(limit)"])
    }

    // Infrastructure endpoints — always unauthenticated
    router.get("/health") { _, context in
        // Run all health checks concurrently
        async let knowledgeStoreCheck = KnowledgeStoreHealthCheck(
            store: context.dependencies.knowledgeStore
        ).check()
        async let githubCheck = GitHubAPIHealthCheck(
            githubToken: configuration.githubToken
        ).check()
        async let sswgCheck = SSWGIndexHealthCheck().check()

        let checks = await [knowledgeStoreCheck, githubCheck, sswgCheck]
        let response = DetailedHealthResponse(checks: checks)

        // Encode the response to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(response)

        // Create a ByteBuffer from the JSON data
        var buffer = ByteBufferAllocator().buffer(capacity: jsonData.count)
        buffer.writeBytes(jsonData)

        // Return 503 if any subsystem is unhealthy or degraded
        if response.status != .healthy {
            return Response(
                status: .serviceUnavailable,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: buffer)
            )
        }

        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: buffer)
        )
    }
    router.get("/ready") { _, context in
        let count = await context.dependencies.knowledgeStore.count
        return ["status": "ok", "knowledgeEntries": "\(count)"]
    }
    router.get("/metrics") { _, context in
        let count = await context.dependencies.knowledgeStore.count
        return [
            "knowledgeEntries": "\(count)",
            "status": "ok"
        ]
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
