# Concurrency & Services

[← Core Concepts](core-concepts.md) | [Home](index.md) | [Next: Integrations →](integrations.md)

---

## 9. Concurrency Model & Pitfalls

Hummingbird 2.x is built entirely on Swift Structured Concurrency. Every route handler is async. The framework manages a thread pool internally via SwiftNIO's `MultiThreadedEventLoopGroup`. You should never interact with event loops directly.

### Never Block the Event Loop Thread

SwiftNIO's thread pool defaults to one thread per CPU core. Blocking any thread stalls all concurrent requests on that thread.

```swift
// ❌ Blocks the event loop
router.get("/data") { _, _ in
    let data = try Data(contentsOf: url)    // synchronous file I/O
    Thread.sleep(forTimeInterval: 1)        // blocks entire thread
    return data
}

// ✅ Async file I/O
import NIOFileSystem

router.get("/data") { _, _ in
    let content = try await FileSystem.shared.withFileHandle(forReadingAt: path) { handle in
        try await handle.readToEnd(maximumSizeAllowed: .megabytes(10))
    }
    return Response(body: .init(byteBuffer: content))
}

// ✅ CPU-heavy work on a detached task
router.post("/process") { request, _ in
    let input = try await request.body.collect(upTo: .max)
    return try await Task.detached(priority: .userInitiated) {
        heavyComputation(input)
    }.value
}
```

### Actor-Protected Shared State

```swift
// ❌ Data race under concurrent requests
class UserCache {
    var users: [UUID: User] = [:]   // not thread-safe
}

// ✅ Actor serialises all access
actor UserCache {
    private var users: [UUID: User] = [:]
    func get(_ id: UUID) -> User? { users[id] }
    func store(_ user: User) { users[user.id] = user }
}
```

### Task Cancellation

When a client disconnects, Hummingbird cancels the task running the route handler. Every `await` point is a cancellation point.

```swift
for item in items {
    try Task.checkCancellation()    // throw CancellationError if cancelled
    await process(item)
}

try await withTaskCancellationHandler {
    try await database.longQuery()
} onCancel: {
    // synchronous cleanup only
}
```

### Enable Strict Concurrency in Package.swift

```swift
swiftSettings: [
    .enableUpcomingFeature("StrictConcurrency"),
]
```

This catches data races at compile time. Keep it enabled. Do not use `@preconcurrency` as a workaround for legitimate race conditions.

---

## 10. Services & Application Lifecycle

### ServiceLifecycle Integration

```swift
// Services start before the HTTP server accepts connections
// and stop after it stops accepting them
app.addServices(DatabasePoolService(), RedisService(), JobQueueService())

try await app.runService()  // blocks until SIGTERM/SIGINT
```

### Building a Service

```swift
struct DatabasePoolService: Service {
    let pool: DatabasePool

    func run() async throws {
        try await withGracefulShutdownHandler {
            try await Task.sleep(for: .seconds(.max))   // keep alive
        } onGracefulShutdown: {
            await pool.drain()  // finish in-flight queries, close connections
        }
    }
}
```

> **Pitfall:** A service that doesn't respond to graceful shutdown blocks the process for up to `gracefulShutdownTimeout` before force-killing. Always implement `onGracefulShutdown`.

### Graceful Shutdown Timeout

```swift
ApplicationConfiguration(
    address: .hostname("0.0.0.0", port: 8080),
    gracefulShutdownTimeout: .seconds(30)
)
```

In Docker, set `stop_grace_period` to slightly more than this value:

```yaml
services:
  app:
    stop_grace_period: 35s
```

---

[← Core Concepts](core-concepts.md) | [Home](index.md) | [Next: Integrations →](integrations.md)
