// Tests/HummingbirdKnowledgeServerTests/RateLimit/RedisRateLimitStoreTests.swift
//
// Comprehensive tests for RedisRateLimitStore: validates distributed rate limiting using Redis,
// sorted set operations, sliding window cleanup, expiration, and error handling.

import Foundation
import Logging
import NIOCore
import NIOEmbedded
@preconcurrency import RediStack
import XCTest

@testable import HummingbirdKnowledgeServer

final class RedisRateLimitStoreTests: XCTestCase {

    // MARK: - Request Recording Tests

    func testRecordRequest_WithinLimit_ReturnsTrue() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        let result = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertTrue(result, "First request should be allowed")
        XCTAssertEqual(redis.zaddCallCount, 1, "Should add timestamp to sorted set")
        XCTAssertEqual(redis.expireCallCount, 1, "Should set expiration on key")
    }

    func testRecordRequest_AtExactLimit_ReturnsTrue() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        // Simulate 9 existing requests in the window
        redis.mockCount = 9

        let result = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertTrue(result, "10th request should be allowed (count is 9, adding 1 = 10)")
    }

    func testRecordRequest_ExceedsLimit_ReturnsFalse() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        // Simulate 10 existing requests in the window
        redis.mockCount = 10

        let result = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertFalse(result, "Request exceeding limit should be rejected")
        XCTAssertEqual(redis.zaddCallCount, 0, "Should not add timestamp when limit exceeded")
    }

    func testRecordRequest_ExceedsLimit_DoesNotRecordTimestamp() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        // Simulate being at the limit
        redis.mockCount = 10

        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertEqual(redis.zaddCallCount, 0, "Should not record timestamp when limit exceeded")
    }

    // MARK: - Sliding Window Tests

    func testRecordRequest_RemovesOldEntries_BeforeCounting() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertEqual(
            redis.zremrangebyscoreCallCount,
            1,
            "Should remove old entries before counting"
        )
    }

    func testRecordRequest_UsesCorrectWindowDuration() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)

        guard let lastWindowStart = redis.lastWindowStart else {
            XCTFail("Window start should be recorded")
            return
        }

        let now = Date().timeIntervalSince1970
        let expectedWindowStart = now - 60

        // Allow 1 second tolerance for test execution time
        XCTAssertEqual(
            lastWindowStart,
            expectedWindowStart,
            accuracy: 1.0,
            "Window should be 60 seconds"
        )
    }

    func testRecordRequest_SeparatesClientsIndependently() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        // Client 1 makes requests
        redis.mockCount = 9
        let result1 = await store.recordRequest(from: "192.168.1.1", limit: 10)

        // Client 2 makes requests (separate counter)
        redis.mockCount = 0
        let result2 = await store.recordRequest(from: "192.168.1.2", limit: 10)

        XCTAssertTrue(result1, "Client 1 should be allowed")
        XCTAssertTrue(result2, "Client 2 should have independent counter")

        let keysUsed = Set(redis.keysUsed)
        XCTAssertEqual(keysUsed.count, 2, "Should use separate keys per client")
        XCTAssertTrue(keysUsed.contains("ratelimit:192.168.1.1"))
        XCTAssertTrue(keysUsed.contains("ratelimit:192.168.1.2"))
    }

    // MARK: - Redis Key Management Tests

    func testRecordRequest_UsesCorrectKeyFormat() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        _ = await store.recordRequest(from: "192.168.1.100", limit: 10)

        XCTAssertTrue(
            redis.keysUsed.contains("ratelimit:192.168.1.100"),
            "Should use 'ratelimit:' prefix with client IP"
        )
    }

    func testRecordRequest_SetsExpiration_To120Seconds() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertEqual(
            redis.lastExpirationSeconds,
            120,
            "Should set 2-minute expiration to prevent unbounded growth"
        )
    }

    func testRecordRequest_SetsExpiration_OnEveryRequest() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)
        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)
        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertEqual(
            redis.expireCallCount,
            3,
            "Should refresh expiration on each request"
        )
    }

    // MARK: - Timestamp Uniqueness Tests

    func testRecordRequest_GeneratesUniqueTimestamps() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        // Make multiple rapid requests
        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)
        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)
        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)

        // All members should be unique due to random component
        let members = redis.membersAdded
        let uniqueMembers = Set(members)

        XCTAssertEqual(
            members.count,
            uniqueMembers.count,
            "All timestamps should be unique"
        )
    }

    func testRecordRequest_TimestampContainsRandomComponent() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        _ = await store.recordRequest(from: "192.168.1.1", limit: 10)

        guard let member = redis.membersAdded.first else {
            XCTFail("Should have added a member")
            return
        }

        XCTAssertTrue(
            member.contains("-"),
            "Timestamp should contain separator for random component"
        )

        let components = member.split(separator: "-")
        XCTAssertEqual(
            components.count,
            2,
            "Timestamp should have format: timestamp-random"
        )
    }

    // MARK: - Error Handling Tests

    func testRecordRequest_OnZremError_ReturnsFalse() async throws {
        let redis = MockRedisClient()
        redis.shouldFailZrem = true
        let store = RedisRateLimitStore(redis: redis)

        let result = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertFalse(result, "Should fail closed on Redis errors")
    }

    func testRecordRequest_OnZcardError_ReturnsFalse() async throws {
        let redis = MockRedisClient()
        redis.shouldFailZcard = true
        let store = RedisRateLimitStore(redis: redis)

        let result = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertFalse(result, "Should fail closed on count errors")
    }

    func testRecordRequest_OnZaddError_ReturnsFalse() async throws {
        let redis = MockRedisClient()
        redis.shouldFailZadd = true
        let store = RedisRateLimitStore(redis: redis)

        let result = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertFalse(result, "Should fail closed on add errors")
    }

    func testRecordRequest_OnExpireError_StillReturnsFalse() async throws {
        let redis = MockRedisClient()
        redis.shouldFailExpire = true
        let store = RedisRateLimitStore(redis: redis)

        let result = await store.recordRequest(from: "192.168.1.1", limit: 10)

        XCTAssertFalse(result, "Should fail closed even on expiration errors")
    }

    func testRecordRequest_FailsClosed_ProtectsSystem() async throws {
        let redis = MockRedisClient()
        redis.shouldFailZcard = true
        let store = RedisRateLimitStore(redis: redis)

        // Multiple requests should all be rejected when Redis fails
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 1...10 {
                group.addTask {
                    await store.recordRequest(from: "192.168.1.1", limit: 10)
                }
            }

            var collected: [Bool] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertTrue(
            results.allSatisfy { !$0 },
            "All requests should be rejected when Redis is unavailable"
        )
    }

    // MARK: - Concurrent Access Tests

    func testRecordRequest_ConcurrentRequests_SameClient() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        let iterations = 50

        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 1...iterations {
                group.addTask {
                    await store.recordRequest(from: "192.168.1.1", limit: 100)
                }
            }

            var collected: [Bool] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        let allowedCount = results.filter { $0 }.count
        XCTAssertEqual(
            allowedCount,
            iterations,
            "All concurrent requests within limit should succeed"
        )
    }

    func testRecordRequest_ConcurrentRequests_DifferentClients() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        let iterations = 25

        let results = await withTaskGroup(of: Bool.self) { group in
            for i in 1...iterations {
                group.addTask {
                    await store.recordRequest(from: "192.168.1.\(i)", limit: 10)
                }
            }

            var collected: [Bool] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertTrue(
            results.allSatisfy { $0 },
            "Different clients should have independent rate limits"
        )

        let uniqueKeys = Set(redis.keysUsed)
        XCTAssertEqual(
            uniqueKeys.count,
            iterations,
            "Should create separate keys for each client"
        )
    }

    // MARK: - Edge Cases Tests

    func testRecordRequest_WithEmptyClientIP_HandlesGracefully() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        let result = await store.recordRequest(from: "", limit: 10)

        XCTAssertTrue(result, "Should handle empty IP (though not recommended)")
        XCTAssertTrue(redis.keysUsed.contains("ratelimit:"))
    }

    func testRecordRequest_WithZeroLimit_AlwaysRejects() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        let result = await store.recordRequest(from: "192.168.1.1", limit: 0)

        XCTAssertFalse(result, "Zero limit should reject all requests")
    }

    func testRecordRequest_WithNegativeLimit_AlwaysRejects() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        let result = await store.recordRequest(from: "192.168.1.1", limit: -1)

        XCTAssertFalse(result, "Negative limit should reject all requests")
    }

    func testRecordRequest_WithVeryLargeLimit_Succeeds() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        let result = await store.recordRequest(from: "192.168.1.1", limit: 1_000_000)

        XCTAssertTrue(result, "Very large limits should work correctly")
    }

    func testRecordRequest_WithSpecialCharactersInIP_HandlesCorrectly() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        // IPv6 address
        let result = await store.recordRequest(from: "2001:0db8:85a3::8a2e:0370:7334", limit: 10)

        XCTAssertTrue(result, "Should handle IPv6 addresses")
        XCTAssertTrue(
            redis.keysUsed.contains("ratelimit:2001:0db8:85a3::8a2e:0370:7334"),
            "Should properly encode IPv6 in key"
        )
    }

    // MARK: - Integration Tests

    func testRecordRequest_SequentialRequests_RespectLimit() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        // Make requests up to the limit
        for i in 1...10 {
            redis.mockCount = i - 1
            let result = await store.recordRequest(from: "192.168.1.1", limit: 10)
            XCTAssertTrue(result, "Request \(i) should succeed")
        }

        // Next request should fail
        redis.mockCount = 10
        let overLimitResult = await store.recordRequest(from: "192.168.1.1", limit: 10)
        XCTAssertFalse(overLimitResult, "11th request should be rejected")
    }

    func testRecordRequest_MultipleClientsAtLimit_IndependentlyEnforced() async throws {
        let redis = MockRedisClient()
        let store = RedisRateLimitStore(redis: redis)

        // Client 1 at limit
        redis.mockCount = 10
        let client1Result = await store.recordRequest(from: "192.168.1.1", limit: 10)

        // Client 2 fresh
        redis.mockCount = 0
        let client2Result = await store.recordRequest(from: "192.168.1.2", limit: 10)

        // Client 3 near limit
        redis.mockCount = 9
        let client3Result = await store.recordRequest(from: "192.168.1.3", limit: 10)

        XCTAssertFalse(client1Result, "Client 1 should be blocked")
        XCTAssertTrue(client2Result, "Client 2 should be allowed")
        XCTAssertTrue(client3Result, "Client 3 should be allowed")
    }
}

// MARK: - Mock Redis Client

/// Mock RedisClient for testing RedisRateLimitStore without requiring a real Redis server.
/// Simulates sorted set operations and error conditions.
final class MockRedisClient: RedisClient, @unchecked Sendable {

    // MARK: - Mock State

    var mockCount: Int = 0
    var keysUsed: [String] = []
    var membersAdded: [String] = []
    var lastWindowStart: Double?
    var lastExpirationSeconds: Int?

    // MARK: - Call Counters

    var zremrangebyscoreCallCount = 0
    var zcardCallCount = 0
    var zaddCallCount = 0
    var expireCallCount = 0

    // MARK: - Error Simulation

    var shouldFailZrem = false
    var shouldFailZcard = false
    var shouldFailZadd = false
    var shouldFailExpire = false

    // MARK: - RedisClient Protocol

    var eventLoop: EventLoop {
        EmbeddedEventLoop()
    }

    func logging(to logger: Logger) -> RedisClient {
        self
    }

    func send(command: String, with arguments: [RESPValue]) -> EventLoopFuture<RESPValue> {
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: RESPValue.self)

        switch command.uppercased() {
        case "ZREMRANGEBYSCORE":
            // ZREMRANGEBYSCORE key min max
            if arguments.count >= 3, case .bulkString(let keyData) = arguments[0] {
                let key = String(buffer: keyData!)
                keysUsed.append(key)
                zremrangebyscoreCallCount += 1

                // Extract max score from arguments
                if case .bulkString(let maxData) = arguments[2] {
                    let maxString = String(buffer: maxData!)
                    if let maxScore = Double(maxString.trimmingCharacters(in: CharacterSet(charactersIn: "("))) {
                        lastWindowStart = maxScore
                    }
                }

                if shouldFailZrem {
                    promise.fail(MockRedisError.simulatedFailure)
                } else {
                    promise.succeed(.integer(0))
                }
            }

        case "ZCARD":
            // ZCARD key
            if arguments.count >= 1, case .bulkString(let keyData) = arguments[0] {
                let key = String(buffer: keyData!)
                keysUsed.append(key)
                zcardCallCount += 1

                if shouldFailZcard {
                    promise.fail(MockRedisError.simulatedFailure)
                } else {
                    promise.succeed(.integer(mockCount))
                }
            }

        case "ZADD":
            // ZADD key score member
            if arguments.count >= 3, case .bulkString(let keyData) = arguments[0] {
                let key = String(buffer: keyData!)
                keysUsed.append(key)
                zaddCallCount += 1

                // Extract member
                if case .bulkString(let memberData) = arguments[2] {
                    let member = String(buffer: memberData!)
                    membersAdded.append(member)
                }

                if shouldFailZadd {
                    promise.fail(MockRedisError.simulatedFailure)
                } else {
                    promise.succeed(.integer(1))
                }
            }

        case "EXPIRE":
            // EXPIRE key seconds
            if arguments.count >= 2, case .bulkString(let keyData) = arguments[0] {
                let key = String(buffer: keyData!)
                keysUsed.append(key)
                expireCallCount += 1

                // Extract seconds - could be integer or bulk string
                if case .integer(let seconds) = arguments[1] {
                    lastExpirationSeconds = seconds
                } else if case .bulkString(let secondsData) = arguments[1] {
                    let secondsString = String(buffer: secondsData!)
                    if let seconds = Int(secondsString) {
                        lastExpirationSeconds = seconds
                    }
                }

                if shouldFailExpire {
                    promise.fail(MockRedisError.simulatedFailure)
                } else {
                    promise.succeed(.integer(1))
                }
            }

        default:
            promise.fail(MockRedisError.unknownCommand(command))
        }

        return promise.futureResult
    }

    func subscribe(
        to channels: [RedisChannelName],
        messageReceiver receiver: @escaping RedisSubscriptionMessageReceiver,
        onSubscribe subscribeHandler: RedisSubscriptionChangeHandler?,
        onUnsubscribe unsubscribeHandler: RedisSubscriptionChangeHandler?
    ) -> EventLoopFuture<Void> {
        fatalError("subscribe not implemented in mock")
    }

    func psubscribe(
        to patterns: [String],
        messageReceiver receiver: @escaping RedisSubscriptionMessageReceiver,
        onSubscribe subscribeHandler: RedisSubscriptionChangeHandler?,
        onUnsubscribe unsubscribeHandler: RedisSubscriptionChangeHandler?
    ) -> EventLoopFuture<Void> {
        fatalError("psubscribe not implemented in mock")
    }

    func unsubscribe(from channels: [RedisChannelName]) -> EventLoopFuture<Void> {
        fatalError("unsubscribe not implemented in mock")
    }

    func punsubscribe(from patterns: [String]) -> EventLoopFuture<Void> {
        fatalError("punsubscribe not implemented in mock")
    }
}

// MARK: - Mock Error

enum MockRedisError: Error {
    case simulatedFailure
    case unknownCommand(String)
}
