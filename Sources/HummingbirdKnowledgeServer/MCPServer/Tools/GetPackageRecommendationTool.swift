// Sources/HummingbirdKnowledgeServer/MCPServer/Tools/GetPackageRecommendationTool.swift
//
// Returns SSWG-vetted Swift package recommendations for a given need.
// Prioritises packages at SSWG Graduated or Incubating status.

import MCP

struct GetPackageRecommendationTool: ToolHandler {

    let store: KnowledgeStore

    var tool: Tool {
        Tool(
            name: "get_package_recommendation",
            description: "Get SSWG-vetted Swift package recommendations for a given need "
                + "(e.g. 'database', 'authentication', 'logging', 'redis', 'metrics'). "
                + "Prioritises packages at SSWG Graduated or Incubating status.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "need": [
                        "type": "string",
                        "description": "What you need the package for (e.g. 'PostgreSQL database', 'JWT authentication', 'structured logging', 'Redis caching')",
                    ],
                ],
                "required": ["need"],
            ]
        )
    }

    func handle(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard case .string(let need) = arguments["need"] else {
            return CallTool.Result(
                content: [.text("Missing required argument: 'need'")],
                isError: true
            )
        }

        // Embedded SSWG package catalogue — updated by KnowledgeUpdateService
        let catalogue: [(need: String, package: String, url: String, status: String, notes: String)] = [
            ("database postgresql postgres", "PostgresNIO / FluentPostgresDriver",
             "https://github.com/vapor/postgres-nio",
             "SSWG Graduated",
             "Low-level PostgreSQL driver. Use FluentPostgresDriver for ORM support."),
            ("mysql database", "MySQLNIO / FluentMySQLDriver",
             "https://github.com/vapor/mysql-nio",
             "SSWG Graduated",
             "Low-level MySQL driver."),
            ("sqlite database", "SQLiteNIO / FluentSQLiteDriver",
             "https://github.com/vapor/sqlite-nio",
             "SSWG Graduated",
             "SQLite driver, ideal for local/testing deployments."),
            ("redis caching", "RediStack",
             "https://github.com/swift-server/RediStack",
             "SSWG Graduated",
             "Pure Swift Redis client. Use for rate limiting shared state across instances."),
            ("logging structured", "swift-log",
             "https://github.com/apple/swift-log",
             "SSWG Graduated",
             "The standard Swift structured logging API. Already used by Hummingbird."),
            ("metrics observability", "swift-metrics",
             "https://github.com/apple/swift-metrics",
             "SSWG Graduated",
             "Standard Swift metrics API. Add prometheus backend for hosted deployments."),
            ("jwt authentication", "swift-jwt JWTKit",
             "https://github.com/vapor/jwt-kit",
             "SSWG Incubating",
             "JWT signing and verification. Integrate with Hummingbird's auth middleware."),
            ("websocket", "Hummingbird WebSocket",
             "https://github.com/hummingbird-project/hummingbird-websocket",
             "Hummingbird ecosystem",
             "Official WebSocket support for Hummingbird 2.x."),
            ("http client", "AsyncHTTPClient",
             "https://github.com/swift-server/async-http-client",
             "SSWG Graduated",
             "NIO-based async HTTP client. Use for outbound HTTP calls from services."),
            ("email smtp", "Smtp",
             "https://github.com/apple/swift-nio",
             "Community",
             "Use NIO SMTP or a third-party email service API (SendGrid, Postmark)."),
        ]

        let lowerNeed = need.lowercased()
        let matches = catalogue.filter { item in
            item.need.split(separator: " ").contains { lowerNeed.contains($0) }
                || lowerNeed.split(separator: " ").contains { item.need.contains($0) }
        }

        var lines: [String] = ["# Package Recommendation: \(need)\n"]

        if matches.isEmpty {
            lines.append("No specific SSWG package found for '\(need)'.")
            lines.append("")
            lines.append("**Browse the full index:** https://swift.org/server/packages/")
            lines.append("**SSWG process:** https://github.com/swift-server/sswg")
        } else {
            for match in matches {
                lines.append("## \(match.package)")
                lines.append("**Status:** \(match.status)")
                lines.append("**URL:** \(match.url)")
                lines.append("")
                lines.append(match.notes)
                lines.append("")
            }
            lines.append("---")
            lines.append("Verify current status at: https://swift.org/server/packages/")
        }

        return CallTool.Result(content: [.text(lines.joined(separator: "\n"))])
    }
}
