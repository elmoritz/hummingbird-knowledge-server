// Sources/HummingbirdKnowledgeServer/Configuration/AppConfiguration.swift
//
// All configuration is read from environment variables at startup.
// Missing required variables cause an immediate crash with a clear message.
//
// Two deployment modes are supported and detected automatically:
//
// **Local mode** (default): MCP_AUTH_TOKEN is not set.
//   - Binds to 127.0.0.1 by default
//   - No authentication required
//   - Rate limiting disabled
//
// **Hosted mode**: MCP_AUTH_TOKEN is set.
//   - Binds to 0.0.0.0 by default (override with HOST)
//   - All /mcp requests require Authorization: Bearer <token>
//   - Rate limiting active (default: 60 req/min, override with RATE_LIMIT_PER_MINUTE)

import Foundation
import Logging

struct AppConfiguration: Sendable {

    let host: String
    let port: Int
    let logLevel: Logger.Level
    let githubToken: String?
    let knowledgeUpdateInterval: Duration

    // Auth — nil means local mode (no authentication)
    let authToken: String?

    // Rate limiting — nil means disabled (local mode default)
    let rateLimitPerMinute: Int?

    // Transport configuration — which MCP transport(s) to enable
    let transport: TransportMode

    /// True when running as a shared hosted server (MCP_AUTH_TOKEN is set).
    var isHosted: Bool { authToken != nil }

    static func load() throws -> AppConfiguration {
        let authToken = Environment.string("MCP_AUTH_TOKEN")
        let isHosted = authToken != nil

        // In hosted mode, default to binding all interfaces.
        // In local mode, default to loopback only — safer.
        let defaultHost = isHosted ? "0.0.0.0" : "127.0.0.1"

        return AppConfiguration(
            host: Environment.string("HOST", default: defaultHost),
            port: try Environment.int("PORT", default: 8080),
            logLevel: Environment.logLevel,
            githubToken: Environment.string("GITHUB_TOKEN"),
            knowledgeUpdateInterval: .seconds(
                try Environment.int("KNOWLEDGE_UPDATE_INTERVAL", default: 3600)
            ),
            authToken: authToken,
            rateLimitPerMinute: isHosted
                ? (try? Environment.int("RATE_LIMIT_PER_MINUTE", default: 60)) ?? 60
                : nil,
            transport: try Environment.transportMode
        )
    }
}

// MARK: - Transport Mode

enum TransportMode: String, Sendable {
    case sse
    case http
    case both

    var supportsSSE: Bool {
        self == .sse || self == .both
    }

    var supportsHTTP: Bool {
        self == .http || self == .both
    }
}

// MARK: - Environment helpers

enum Environment {

    static func string(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    static func string(_ key: String, default defaultValue: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? defaultValue
    }

    static func int(_ key: String, default defaultValue: Int) throws -> Int {
        guard let raw = ProcessInfo.processInfo.environment[key] else {
            return defaultValue
        }
        guard let value = Int(raw) else {
            throw ConfigurationError.invalidValue(key: key, value: raw, expected: "integer")
        }
        return value
    }

    static var logLevel: Logger.Level {
        guard
            let raw = ProcessInfo.processInfo.environment["LOG_LEVEL"],
            let level = Logger.Level(rawValue: raw.lowercased())
        else { return .info }
        return level
    }

    static var transportMode: TransportMode {
        get throws {
            let raw = ProcessInfo.processInfo.environment["TRANSPORT"] ?? "both"
            guard let mode = TransportMode(rawValue: raw.lowercased()) else {
                throw ConfigurationError.invalidValue(
                    key: "TRANSPORT",
                    value: raw,
                    expected: "sse, http, or both"
                )
            }
            return mode
        }
    }
}

// MARK: - Errors

enum ConfigurationError: Error, CustomStringConvertible {
    case missingRequired(key: String)
    case invalidValue(key: String, value: String, expected: String)

    var description: String {
        switch self {
        case .missingRequired(let key):
            return "Missing required environment variable: \(key)"
        case .invalidValue(let key, let value, let expected):
            return "Invalid value '\(value)' for '\(key)' — expected \(expected)"
        }
    }
}
