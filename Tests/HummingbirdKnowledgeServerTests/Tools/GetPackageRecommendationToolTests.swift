// Tests/HummingbirdKnowledgeServerTests/Tools/GetPackageRecommendationToolTests.swift
//
// Comprehensive tests for GetPackageRecommendationTool: validates SSWG package
// recommendations and need-based matching.

import Foundation
import MCP
import XCTest

@testable import HummingbirdKnowledgeServer

final class GetPackageRecommendationToolTests: XCTestCase {

    // MARK: - Test Helpers

    /// Creates test SSWG package entries for seeding the knowledge store
    static func createSSWGPackageSeedData() -> [KnowledgeEntry] {
        [
            // PostgreSQL
            KnowledgeEntry(
                id: "sswg-postgresql-nio",
                title: "SSWG Package: PostgresNIO",
                content: "Low-level PostgreSQL database driver built on SwiftNIO.\n\n**Status:** SSWG Graduated\n**URL:** https://github.com/vapor/postgres-nio",
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 1.0,
                source: "sswg-index",
                lastVerifiedAt: Date()
            ),
            // MySQL
            KnowledgeEntry(
                id: "sswg-mysql-nio",
                title: "SSWG Package: MySQLNIO",
                content: "MySQL database client library built on SwiftNIO.\n\n**Status:** SSWG Graduated\n**URL:** https://github.com/vapor/mysql-nio",
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 1.0,
                source: "sswg-index",
                lastVerifiedAt: Date()
            ),
            // SQLite
            KnowledgeEntry(
                id: "sswg-sqlite-nio",
                title: "SSWG Package: SQLiteNIO",
                content: "SQLite database client library built on SwiftNIO.\n\n**Status:** SSWG Graduated\n**URL:** https://github.com/vapor/sqlite-nio",
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 1.0,
                source: "sswg-index",
                lastVerifiedAt: Date()
            ),
            // Redis
            KnowledgeEntry(
                id: "sswg-redis-stack",
                title: "SSWG Package: RediStack",
                content: "Redis client for Swift. Use for caching, rate limiting, and session storage.\n\n**Status:** SSWG Graduated\n**URL:** https://github.com/swift-server/RediStack",
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 1.0,
                source: "sswg-index",
                lastVerifiedAt: Date()
            ),
            // Logging
            KnowledgeEntry(
                id: "sswg-swift-log",
                title: "SSWG Package: swift-log",
                content: "Logging API for Swift.\nMaturity: SSWG Graduated\nRepository: https://github.com/apple/swift-log",
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 1.0,
                source: "sswg-index",
                lastVerifiedAt: Date()
            ),
            // Metrics
            KnowledgeEntry(
                id: "sswg-swift-metrics",
                title: "SSWG Package: swift-metrics",
                content: "Metrics API for Swift.\nMaturity: SSWG Graduated\nRepository: https://github.com/apple/swift-metrics",
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 1.0,
                source: "sswg-index",
                lastVerifiedAt: Date()
            ),
            // JWT
            KnowledgeEntry(
                id: "sswg-jwt-kit",
                title: "SSWG Package: JWTKit",
                content: "JWT signing and verification library.\nMaturity: SSWG Incubating\nRepository: https://github.com/vapor/jwt-kit",
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 1.0,
                source: "sswg-index",
                lastVerifiedAt: Date()
            ),
            // HTTP Client
            KnowledgeEntry(
                id: "sswg-async-http-client",
                title: "SSWG Package: AsyncHTTPClient",
                content: "HTTP client library built on SwiftNIO.\nMaturity: SSWG Graduated\nRepository: https://github.com/swift-server/async-http-client",
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 1.0,
                source: "sswg-index",
                lastVerifiedAt: Date()
            ),
            // WebSocket
            KnowledgeEntry(
                id: "sswg-hummingbird-websocket",
                title: "SSWG Package: Hummingbird WebSocket",
                content: "WebSocket support for Hummingbird.\nMaturity: Hummingbird ecosystem\nRepository: https://github.com/hummingbird-project/hummingbird-websocket",
                layer: nil,
                patternIds: [],
                violationIds: [],
                hummingbirdVersionRange: ">=2.0.0",
                swiftVersionRange: ">=6.0",
                isTutorialPattern: false,
                correctionId: nil,
                confidence: 1.0,
                source: "sswg-index",
                lastVerifiedAt: Date()
            ),
        ]
    }

    // MARK: - Tool Configuration

    func testToolDefinition() {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        XCTAssertEqual(tool.tool.name, "get_package_recommendation")
        XCTAssertNotNil(tool.tool.description)
        XCTAssertFalse(tool.tool.description?.isEmpty ?? true)

        // Verify input schema structure
        guard case .object(let schema) = tool.tool.inputSchema else {
            XCTFail("Input schema must be an object")
            return
        }

        // Verify required fields
        if case .array(let requiredArray) = schema["required"] {
            let requiredStrings = requiredArray.compactMap { value -> String? in
                if case .string(let s) = value { return s }
                return nil
            }
            XCTAssertTrue(requiredStrings.contains("need"), "need must be required")
        } else {
            XCTFail("Schema must have 'required' array")
        }
    }

    // MARK: - Argument Validation

    func testHandle_MissingNeedArgument_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle([:])

        XCTAssertEqual(result.isError, true, "Should return error for missing need")

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
            XCTAssertTrue(message.contains("need"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_InvalidNeedType_ReturnsError() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .int(123)])

        XCTAssertEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Missing required argument"))
        }
    }

    // MARK: - Database Recommendations

    func testHandle_PostgreSQLNeed_ReturnsRecommendation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("PostgreSQL database")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("# Package Recommendation: PostgreSQL"))
            XCTAssertTrue(message.contains("PostgresNIO"))
            XCTAssertTrue(message.contains("SSWG Graduated"))
            XCTAssertTrue(message.contains("**Status:**"))
            XCTAssertTrue(message.contains("**URL:**"))
            XCTAssertTrue(message.contains("github.com"))
        } else {
            XCTFail("Content should be text")
        }
    }

    func testHandle_MySQLNeed_ReturnsRecommendation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("mysql database")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("MySQLNIO"))
            XCTAssertTrue(message.contains("SSWG Graduated"))
        }
    }

    func testHandle_SQLiteNeed_ReturnsRecommendation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("sqlite")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("SQLiteNIO"))
            XCTAssertTrue(message.contains("SSWG Graduated"))
        }
    }

    // MARK: - Caching and State

    func testHandle_RedisNeed_ReturnsRecommendation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("redis caching")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("RediStack"))
            XCTAssertTrue(message.contains("SSWG Graduated"))
            XCTAssertTrue(message.contains("rate limiting"))
        }
    }

    // MARK: - Logging and Metrics

    func testHandle_LoggingNeed_ReturnsRecommendation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("structured logging")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("swift-log"))
            XCTAssertTrue(message.contains("SSWG Graduated"))
        }
    }

    func testHandle_MetricsNeed_ReturnsRecommendation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("metrics observability")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("swift-metrics"))
            XCTAssertTrue(message.contains("SSWG Graduated"))
        }
    }

    // MARK: - Authentication

    func testHandle_JWTNeed_ReturnsRecommendation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("JWT authentication")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("JWTKit") || message.contains("swift-jwt"))
            XCTAssertTrue(message.contains("SSWG Incubating"))
        }
    }

    // MARK: - HTTP and Networking

    func testHandle_HTTPClientNeed_ReturnsRecommendation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("http client")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("AsyncHTTPClient"))
            XCTAssertTrue(message.contains("SSWG Graduated"))
        }
    }

    func testHandle_WebSocketNeed_ReturnsRecommendation() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("websocket")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Hummingbird WebSocket"))
            XCTAssertTrue(message.contains("Hummingbird ecosystem"))
        }
    }

    // MARK: - No Matches

    func testHandle_UnknownNeed_ReturnsGuidance() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("quantum computing framework")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No specific SSWG package found"))
            XCTAssertTrue(message.contains("swift.org/server/packages"))
            XCTAssertTrue(message.contains("SSWG process"))
        }
    }

    // MARK: - Case Insensitivity

    func testHandle_CaseInsensitiveMatching_Works() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("POSTGRESQL DATABASE")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("PostgresNIO"))
        }
    }

    // MARK: - Multiple Matches

    func testHandle_MultipleMatches_ShowsAll() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("database")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should show multiple database options
            let headerCount = message.components(separatedBy: "\n## ").count - 1
            XCTAssertGreaterThan(headerCount, 1, "Should show multiple database packages")
        }
    }

    // MARK: - Formatting

    func testHandle_IncludesVerificationLink() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("redis")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Verify current status at"))
            XCTAssertTrue(message.contains("swift.org/server/packages"))
        }
    }

    func testHandle_IncludesPackageNotes() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("PostgreSQL")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should include notes about the package
            XCTAssertTrue(message.contains("Low-level") || message.contains("ORM") || message.contains("driver"))
        }
    }

    // MARK: - Partial Matching

    func testHandle_PartialWordMatching_FindsMatches() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("I need postgres")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("PostgresNIO"))
        }
    }

    func testHandle_MultiwordNeed_MatchesAnyWord() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("I need authentication and logging")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            // Should match both authentication and logging packages
            XCTAssertTrue(message.contains("swift-log") || message.contains("jwt"))
        }
    }

    // MARK: - Edge Cases

    func testHandle_EmptyNeed_ReturnsNoMatches() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No specific SSWG package found"))
        }
    }

    func testHandle_WhitespaceNeed_ReturnsNoMatches() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("   \n  \t  ")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("No specific SSWG package found"))
        }
    }

    func testHandle_SpecialCharacters_HandlesGracefully() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("@#$% postgres &*()")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("PostgresNIO") || message.contains("No specific"))
        }
    }

    // MARK: - Email/SMTP

    func testHandle_EmailNeed_ReturnsGuidance() async throws {
        let store = KnowledgeStore.forTesting(seedEntries: Self.createSSWGPackageSeedData())
        let tool = GetPackageRecommendationTool(store: store)

        let result = try await tool.handle(["need": .string("email smtp")])

        XCTAssertNotEqual(result.isError, true)

        if case .text(let message) = result.content[0] {
            XCTAssertTrue(message.contains("Smtp") || message.contains("SendGrid") || message.contains("email"))
        }
    }
}
