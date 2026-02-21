# Integrations

[← Concurrency & Services](concurrency-services.md) | [Home](index.md) | [Next: Testing & Deployment →](testing-deployment.md)

---

## 11. Database Integration

Hummingbird is database-agnostic. Common choices:

| Library | Database | Pattern | Notes |
|---------|---------|---------|-------|
| `postgres-nio` | PostgreSQL | Raw async SQL | Official SSWG, lowest overhead |
| `MongoKitten` | MongoDB | Query builder | Full-featured |
| `FluentKit` | PG / MySQL / SQLite | ORM | Vapor's ORM, usable standalone |
| `sqlite-nio` | SQLite | Raw async SQL | Great for dev/test |
| `RediStack` | Redis | Command API | SSWG-incubated |

### PostgresNIO Best Practices

```swift
// Always use parameterised queries — the \(variable) interpolation
// creates a bind parameter, NOT a string substitution
let rows = try await pool.query(
    "SELECT id, name FROM users WHERE id = \(userId)",
    logger: context.logger
)

// Decode rows
for try await row in rows {
    let (id, name) = try row.decode(UUID.self, String.self)
}
```

> **Pitfall:** Never build queries with string concatenation. PostgresNIO's `\(variable)` interpolation is type-safe parameterisation, not string formatting. The two look identical in source but behave completely differently.

### Connection Pool Sizing

Rule of thumb: `(num_cpu_cores × 2) + num_spindle_disks`.

For managed cloud databases, check the plan's `max_connections` limit and leave headroom. Use PgBouncer or the platform's connection pooler in front of PostgreSQL in production.

> **Pitfall:** PostgreSQL's default `max_connections` is 100. If you run multiple app instances each with a large pool, you will exhaust the database connection limit under load.

---

## 12. Authentication & Authorization

### hummingbird-auth

```swift
.package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.0.0"),
.product(name: "HummingbirdAuth", package: "hummingbird-auth"),
.product(name: "HummingbirdBcrypt", package: "hummingbird-auth"),
```

### Password Hashing

```swift
import HummingbirdBcrypt

// Hash — cost factor 12 is correct as of 2025
let hash = try await Bcrypt.hash(plaintext, cost: 12)

// Verify
let isValid = try await Bcrypt.verify(plaintext, hash: storedHash)
```

> **Pitfall:** Never use SHA-256, SHA-512, or MD5 for passwords. These hash functions are designed to be fast, which makes them trivially brute-forceable. Bcrypt is intentionally slow and salted. Cost factor 12 is a reasonable default; increase it as hardware speeds up.

### JWT Pattern

```swift
struct JWTMiddleware<C: AuthContext>: RouterMiddleware {
    let secret: String

    func handle(_ request: Request, context: C, next: ...) async throws -> Response {
        guard
            let bearer = request.headers[.authorization],
            bearer.hasPrefix("Bearer ")
        else { throw HTTPError(.unauthorized) }

        let token = String(bearer.dropFirst(7))
        let claims = try JWT.verify(token, secret: secret)

        var ctx = context
        ctx.userId = claims.subject
        return try await next(request, ctx)
    }
}
```

---

## 13. WebSockets

```swift
.package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),

router.ws("/chat") { request, wsContext in
    return .upgrade([:]) { inbound, outbound, context in
        for try await message in inbound {
            switch message {
            case .text(let text):
                try await outbound.write(.text("Echo: \(text)"))
            case .binary(let data):
                try await outbound.write(.binary(data))
            }
        }
    }
}
```

> **Pitfall:** If you hold references to `outbound` writers in a collection for broadcasting, remove them when the connection closes. Dead connections accumulate silently and will eventually exhaust memory.

---

## 14. Background Jobs

```swift
.package(url: "https://github.com/hummingbird-project/hummingbird-jobs.git", from: "2.0.0"),

// Define
struct SendEmailJob: JobParameters {
    static let jobName = "sendEmail"
    let to: String
    let subject: String
    let body: String
}

// Register handler
jobQueue.registerJob(parameters: SendEmailJob.self) { params, context in
    try await emailService.send(to: params.to, subject: params.subject, body: params.body)
}

// Enqueue from a route handler
try await context.dependencies.jobQueue.push(
    SendEmailJob(to: "user@example.com", subject: "Welcome", body: "...")
)
```

> **Pitfall:** Jobs can be retried on failure. Handlers **must be idempotent** — safe to run more than once with the same parameters. Check for prior completion or use idempotency keys.

---

[← Concurrency & Services](concurrency-services.md) | [Home](index.md) | [Next: Testing & Deployment →](testing-deployment.md)
