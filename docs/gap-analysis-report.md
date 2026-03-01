# API Gap Analysis Report

[← Knowledge Coverage Checklist](knowledge-coverage-checklist.md) | [Home](index.md)

---

**Report Date:** 2026-03-01
**Analysis Scope:** Hummingbird 2.x Core APIs
**Source Materials:** `core-concepts.md`, `integrations.md`, official Hummingbird 2.x documentation
**Current KB Entries:** 18
**Target KB Entries:** 40-50

---

## Executive Summary

This report identifies **25 critical API gaps** in the knowledge base that must be addressed to provide comprehensive coverage of Hummingbird 2.x patterns. The gaps span across routing, request handling, middleware, database integration, authentication, WebSockets, background jobs, and testing.

**Priority Distribution:**
- 🔴 **Critical (10):** Core APIs required for basic functionality
- 🟡 **High (10):** Common patterns needed for production applications
- 🟢 **Medium (5):** Advanced features for specific use cases

---

## 1. Routing APIs (7 gaps)

### 🔴 GAP-001: Router Groups
**Status:** Not Covered
**Priority:** Critical
**API:** `Router.group(_:)`, scoped middleware

**Description:**
Router groups enable API versioning and scoped middleware application. Pattern shown in `core-concepts.md`:

```swift
let api = router.group("/api/v1")
    .add(middleware: AuthMiddleware())
api.get("/profile", use: getProfile)  // GET /api/v1/profile
```

**Knowledge Entry Required:**
- Route group creation and nesting
- Scoped middleware application
- Path prefix concatenation
- Common use cases (API versioning, feature modules)

**Pitfall:** Middleware added to a group only applies to routes registered on that group, not retroactively to existing routes.

---

### 🔴 GAP-002: Wildcard Routes
**Status:** Not Covered
**Priority:** Critical
**API:** `context.parameters.getCatchAll()`

**Description:**
Catch-all route patterns using `**` syntax for file serving, proxying, or dynamic path handling:

```swift
router.get("/files/**") { request, context in
    let path = context.parameters.getCatchAll()
    // path contains everything after /files/
}
```

**Knowledge Entry Required:**
- Wildcard syntax (`**`)
- `getCatchAll()` API
- Use cases (static file serving, reverse proxy)
- Security considerations (path traversal attacks)

---

### 🔴 GAP-003: Parameter Extraction
**Status:** Partial (mentioned in validation patterns)
**Priority:** Critical
**API:** `context.parameters.require(_:as:)`, `context.parameters.get(_:as:)`

**Description:**
Type-safe parameter extraction with automatic validation and error handling:

```swift
let id = try context.parameters.require("id", as: UUID.self)
// throws HTTPError(.badRequest) if missing or invalid
let slug: String? = context.parameters.get("slug")
```

**Knowledge Entry Required:**
- `require(_:as:)` for mandatory parameters
- `get(_:as:)` for optional parameters
- Type conversion failures → 400 Bad Request
- Custom type conformance to `LosslessStringConvertible`

**Pitfall:** Always use `try` with `require`. The compiler won't warn, but runtime errors will occur.

---

### 🟡 GAP-004: Route Priority Rules
**Status:** Not Covered
**Priority:** High
**API:** Router matching algorithm

**Description:**
Static route segments always take precedence over parameterized segments, regardless of registration order:

```swift
router.get("/users/me", use: getCurrentUser)   // matches first
router.get("/users/:id", use: getUser)         // matches if not "me"
```

**Knowledge Entry Required:**
- Static vs dynamic segment priority
- Registration order independence
- Trie-based routing performance (O(path segments))
- Debugging route conflicts

---

### 🟡 GAP-005: Query Parameters
**Status:** Partial (validation covered)
**Priority:** High
**API:** `request.uri.queryParameters.get(_:as:)`

**Description:**
Query parameter extraction with type conversion:

```swift
let q = request.uri.queryParameters.get("q") ?? ""
let page = request.uri.queryParameters.get("page", as: Int.self) ?? 1
```

**Knowledge Entry Required:**
- Query parameter extraction API
- Type conversion (Int, Bool, UUID, etc.)
- Default value handling
- Multiple values (getAll)

---

### 🟢 GAP-006: URI Parsing
**Status:** Not Covered
**Priority:** Medium
**API:** `request.uri` manipulation

**Description:**
Parsing and manipulating URI components (scheme, host, path, query, fragment).

**Knowledge Entry Required:**
- URI component access
- Query string parsing
- Path manipulation
- Percent-encoding handling

---

### 🟢 GAP-007: Multipart Form Data
**Status:** Not Covered
**Priority:** Medium
**API:** Multipart parsing for file uploads

**Description:**
Handling file uploads and form data with multiple parts.

**Knowledge Entry Required:**
- Multipart parser setup
- File upload handling
- Streaming large files
- Memory considerations

---

## 2. Request & Response Handling (5 gaps)

### 🔴 GAP-008: Request Body Streaming
**Status:** Not Covered
**Priority:** Critical
**API:** `request.body` AsyncSequence

**Description:**
Streaming request bodies for large uploads without buffering entire payload in memory:

```swift
for try await chunk in request.body {
    // process ByteBuffer chunk
}
```

**Knowledge Entry Required:**
- AsyncSequence iteration over body chunks
- ByteBuffer processing
- Memory efficiency for large uploads
- Pitfall: body consumed only once

**Pitfall:** The request body is a stream consumed exactly once. If middleware reads it, the route handler sees an empty body. Solution: collect in middleware and store on context.

---

### 🟡 GAP-009: Response Body Types
**Status:** Not Covered
**Priority:** High
**API:** `Response.body` types (ByteBuffer, AsyncSequence)

**Description:**
Different response body types for various use cases:

```swift
// String
return "Hello"

// Encodable → JSON
return UserResponse(user)

// Custom status
return EditedResponse(status: .created, response: UserResponse(user))

// No content
return Response(status: .noContent)
```

**Knowledge Entry Required:**
- ByteBuffer responses
- AsyncSequence for streaming
- String and Encodable shortcuts
- EditedResponse for custom status codes

---

### 🟡 GAP-010: Response Streaming
**Status:** Not Covered
**Priority:** High
**API:** AsyncSequence response bodies

**Description:**
Streaming large responses (file downloads, generated data) without buffering.

**Knowledge Entry Required:**
- AsyncSequence as response body
- Chunked transfer encoding
- Use cases (large files, real-time data)
- Error handling mid-stream

---

### 🟡 GAP-011: Headers API
**Status:** Partial (Content-Type covered)
**Priority:** High
**API:** `HTTPFields` reading and writing

**Description:**
Complete headers API for reading request headers and writing response headers:

```swift
// Reading
let auth = request.headers[.authorization]

// Writing
var headers = HTTPFields()
headers[.cacheControl] = "no-store"
headers[.xContentTypeOptions] = "nosniff"
return Response(status: .ok, headers: headers, body: body)
```

**Knowledge Entry Required:**
- HTTPFields API
- Standard header names (via extensions)
- Custom header handling
- Security headers (CSP, HSTS, etc.)

---

### 🟢 GAP-012: ResponseEncoder Protocol
**Status:** Not Covered
**Priority:** Medium
**API:** Custom response encoding

**Description:**
Custom encoders for non-JSON response formats (XML, Protobuf, etc.).

**Knowledge Entry Required:**
- ResponseEncoder protocol
- Custom encoder implementation
- Encoder registration
- Content-Type negotiation

---

## 3. Middleware (6 gaps)

### 🔴 GAP-013: RouterMiddleware Protocol
**Status:** Covered (entry exists)
**Priority:** N/A (already covered)
**Note:** Entry `router-middleware-pattern` exists but should be verified for completeness.

---

### 🟡 GAP-014: Middleware Composition & Ordering
**Status:** Partial
**Priority:** High
**API:** `router.add(middleware:)`, execution order

**Description:**
Middleware executes in registration order. Critical for security:

```swift
router.add(middleware: LoggingMiddleware())
router.add(middleware: CORSMiddleware())
router.add(middleware: AuthMiddleware())  // runs after logging
```

**Knowledge Entry Required:**
- Execution order rules
- Pre-processing vs post-processing
- Short-circuiting (returning without calling next)
- Common ordering patterns (logging → CORS → auth)

**Pitfall:** Auth middleware added after logging will still log unauthenticated requests. Order matters for security.

---

### 🟡 GAP-015: Built-in Middleware
**Status:** Partial
**Priority:** High
**APIs:** FileMiddleware, CORSMiddleware, MetricsMiddleware, TracingMiddleware, LogRequestsMiddleware

**Description:**
Hummingbird provides production-ready middleware for common concerns:

- `FileMiddleware` — static file serving
- `CORSMiddleware` — Cross-Origin Resource Sharing
- `MetricsMiddleware` — request/response metrics (swift-metrics)
- `TracingMiddleware` — OpenTelemetry distributed tracing
- `LogRequestsMiddleware` — structured request logging

**Knowledge Entry Required:**
- Configuration for each middleware
- Common use cases
- Performance implications
- Integration with observability systems

---

### 🟡 GAP-016: Error Handling Middleware
**Status:** Not Covered
**Priority:** High
**Pattern:** Global error handler

**Description:**
Middleware to catch and transform errors into proper HTTP responses.

**Knowledge Entry Required:**
- Error catching pattern
- HTTPError vs other errors
- Error response formatting
- Logging errors
- Hiding internal errors from clients

---

### 🟢 GAP-017: Rate Limiting Middleware
**Status:** Not Covered
**Priority:** Medium
**Pattern:** Request throttling

**Description:**
Protecting APIs from abuse via rate limiting.

**Knowledge Entry Required:**
- Rate limiting algorithms
- Storage backends (in-memory, Redis)
- Per-IP vs per-user limits
- 429 Too Many Requests responses

---

### 🟢 GAP-018: Request ID Injection
**Status:** Not Covered
**Priority:** Medium
**Pattern:** Distributed tracing

**Description:**
Injecting unique request IDs for log correlation and distributed tracing.

**Knowledge Entry Required:**
- Request ID generation
- Propagating to logger context
- Response header injection
- Integration with tracing systems

---

## 4. Database Integration (4 gaps)

### 🔴 GAP-019: PostgresNIO Query Patterns
**Status:** Not Covered
**Priority:** Critical
**API:** Parameterized queries with string interpolation

**Description:**
PostgresNIO's type-safe query interpolation for SQL injection prevention:

```swift
let rows = try await pool.query(
    "SELECT id, name FROM users WHERE id = \(userId)",
    logger: context.logger
)
for try await row in rows {
    let (id, name) = try row.decode(UUID.self, String.self)
}
```

**Knowledge Entry Required:**
- `\(variable)` interpolation → bind parameter (NOT string substitution)
- Row decoding API
- AsyncSequence iteration over rows
- Query logging

**Pitfall:** Never build queries with string concatenation. PostgresNIO's `\(variable)` interpolation is type-safe parameterization, not string formatting. The two look identical in source but behave completely differently.

---

### 🔴 GAP-020: Connection Pool Sizing
**Status:** Not Covered
**Priority:** Critical
**API:** PostgresConnectionSource configuration

**Description:**
Proper connection pool sizing to avoid connection exhaustion:

Rule of thumb: `(num_cpu_cores × 2) + num_spindle_disks`

For managed databases, check `max_connections` limit and leave headroom.

**Knowledge Entry Required:**
- Pool sizing formula
- max_connections limits
- PgBouncer integration
- Connection exhaustion symptoms
- Multi-instance considerations

**Pitfall:** PostgreSQL's default max_connections is 100. Multiple app instances with large pools will exhaust connections under load.

---

### 🟡 GAP-021: Transaction Management
**Status:** Not Covered
**Priority:** High
**API:** Database transactions

**Description:**
Managing database transactions for ACID guarantees.

**Knowledge Entry Required:**
- Transaction boundaries
- Commit vs rollback
- Transaction isolation levels
- Nested transaction handling
- Error handling in transactions

---

### 🟢 GAP-022: N+1 Query Prevention
**Status:** Not Covered
**Priority:** Medium
**Pattern:** Query optimization

**Description:**
Identifying and preventing N+1 query antipatterns.

**Knowledge Entry Required:**
- N+1 query detection
- JOIN-based solutions
- Eager loading patterns
- Performance profiling

---

## 5. Authentication & Authorization (3 gaps)

### 🟡 GAP-023: Bcrypt Password Hashing
**Status:** Not Covered
**Priority:** High
**API:** HummingbirdBcrypt

**Description:**
Secure password hashing with Bcrypt:

```swift
import HummingbirdBcrypt

let hash = try await Bcrypt.hash(plaintext, cost: 12)
let isValid = try await Bcrypt.verify(plaintext, hash: storedHash)
```

**Knowledge Entry Required:**
- Bcrypt.hash with cost factor (default 12)
- Bcrypt.verify for validation
- Cost factor selection
- Migration from legacy hashes

**Pitfall:** Never use SHA-256, SHA-512, or MD5 for passwords. These are designed to be fast, making them trivially brute-forceable. Bcrypt is intentionally slow and salted. Cost factor 12 is reasonable for 2025; increase as hardware speeds up.

---

### 🟡 GAP-024: JWT Middleware Pattern
**Status:** Not Covered
**Priority:** High
**API:** JWT validation in middleware

**Description:**
JWT authentication middleware pattern:

```swift
struct JWTMiddleware<C: AuthContext>: RouterMiddleware {
    let secret: String
    func handle(_ request: Request, context: C, next: ...) async throws -> Response {
        guard let bearer = request.headers[.authorization],
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

**Knowledge Entry Required:**
- Bearer token extraction
- JWT verification
- Claims injection into context
- Token expiry handling
- 401 Unauthorized responses

---

### 🟢 GAP-025: Authorization Middleware
**Status:** Not Covered
**Priority:** Medium
**Pattern:** Permission checking

**Description:**
Role-based and permission-based authorization patterns.

**Knowledge Entry Required:**
- Role checking in middleware
- Permission-based access control
- Resource ownership validation
- 403 Forbidden vs 401 Unauthorized

---

## 6. WebSockets (3 gaps)

### 🔴 GAP-026: WebSocket Upgrade Pattern
**Status:** Not Covered
**Priority:** Critical
**API:** `router.ws(_:)`, `.upgrade()`

**Description:**
WebSocket upgrade and handler registration:

```swift
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

**Knowledge Entry Required:**
- `.ws()` route registration
- `.upgrade()` handshake
- Inbound/outbound streams
- Text vs binary messages

---

### 🟡 GAP-027: WebSocket Broadcasting
**Status:** Not Covered
**Priority:** High
**Pattern:** Multi-client messaging

**Description:**
Broadcasting messages to multiple WebSocket clients.

**Knowledge Entry Required:**
- Maintaining client collections
- Actor-based state management
- Graceful disconnect handling
- Memory leak prevention

**Pitfall:** If you hold references to outbound writers in a collection for broadcasting, remove them when the connection closes. Dead connections accumulate silently and will eventually exhaust memory.

---

### 🟢 GAP-028: WebSocket Authentication
**Status:** Not Covered
**Priority:** Medium
**Pattern:** Authenticating WebSocket connections

**Description:**
Authenticating WebSocket upgrades via query params or initial message.

**Knowledge Entry Required:**
- Query param authentication
- Initial handshake message auth
- Token validation before upgrade
- Rejecting unauthorized connections

---

## 7. Background Jobs (3 gaps)

### 🔴 GAP-029: Job Queue Setup
**Status:** Not Covered
**Priority:** Critical
**API:** hummingbird-jobs

**Description:**
Background job queue setup and integration:

```swift
.package(url: "https://github.com/hummingbird-project/hummingbird-jobs.git", from: "2.0.0")

struct SendEmailJob: JobParameters {
    static let jobName = "sendEmail"
    let to: String
    let subject: String
    let body: String
}

jobQueue.registerJob(parameters: SendEmailJob.self) { params, context in
    try await emailService.send(to: params.to, subject: params.subject, body: params.body)
}

try await context.dependencies.jobQueue.push(
    SendEmailJob(to: "user@example.com", subject: "Welcome", body: "...")
)
```

**Knowledge Entry Required:**
- JobParameters protocol
- registerJob handler registration
- push() to enqueue jobs
- Job queue backends (memory, PostgreSQL, Redis)

---

### 🟡 GAP-030: Job Idempotency
**Status:** Not Covered
**Priority:** High
**Pattern:** Retry-safe job handlers

**Description:**
Ensuring job handlers can safely retry on failure:

**Knowledge Entry Required:**
- Idempotency requirements
- Idempotency key patterns
- Checking prior completion
- Database-based deduplication

**Pitfall:** Jobs can be retried on failure. Handlers must be idempotent — safe to run more than once with the same parameters. Check for prior completion or use idempotency keys.

---

### 🟢 GAP-031: Job Scheduling
**Status:** Not Covered
**Priority:** Medium
**API:** Delayed and recurring jobs

**Description:**
Scheduling jobs for future execution or recurring intervals.

**Knowledge Entry Required:**
- Delayed job execution
- Cron-style scheduling
- Recurring job patterns
- Job cancellation

---

## 8. Testing (2 gaps)

### 🔴 GAP-032: HummingbirdTesting Patterns
**Status:** Not Covered
**Priority:** Critical
**API:** Application.test vs Application.router test modes

**Description:**
Testing strategies with HummingbirdTesting framework.

**Knowledge Entry Required:**
- `.router` test mode (lightweight)
- `.live` test mode (full lifecycle)
- Test request building
- Response assertions
- Async test patterns

---

### 🟡 GAP-033: Repository Test Doubles
**Status:** Not Covered
**Priority:** High
**Pattern:** In-memory repositories for testing

**Description:**
Creating in-memory repository implementations for fast tests.

**Knowledge Entry Required:**
- Protocol-based repository pattern
- In-memory implementation
- Test data fixtures
- Avoiding database in unit tests

---

## 9. Application Setup (2 gaps)

### 🔴 GAP-034: Composition Root Pattern
**Status:** Partial
**Priority:** Critical
**Pattern:** `buildApplication()` dependency assembly

**Description:**
The composition root is the single place where concrete types are instantiated:

```swift
func buildApplication(configuration: AppConfiguration) async throws -> some ApplicationProtocol {
    let dbPool = try await DatabasePool(configuration.database)
    let userRepository = PostgresUserRepository(pool: dbPool)
    let userService = UserService(repository: userRepository)
    let dependencies = AppDependencies(userService: userService)

    let router = Router(context: AppRequestContext.self)
    router.add(middleware: DependencyInjectionMiddleware(dependencies: dependencies))

    UserController().registerRoutes(on: router.group("/users"))

    var app = Application(router: router, configuration: .init(address: .hostname(...)))
    app.addServices(dbPool)
    return app
}
```

**Knowledge Entry Required:**
- Composition root concept
- Dependency injection pattern
- Service registration (app.addServices)
- Configuration loading
- Startup error handling

**Pitfall:** This is the only file that imports both Hummingbird and database drivers. Everything else depends on protocols.

---

### 🟡 GAP-035: Package.swift Setup
**Status:** Not Covered
**Priority:** High
**API:** Swift Package Manager configuration

**Description:**
Package.swift configuration for Hummingbird 2.x projects:

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "MyServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
    ],
    swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
    ]
)
```

**Knowledge Entry Required:**
- Required dependencies (Hummingbird, Logging, ServiceLifecycle)
- StrictConcurrency requirement
- Swift version requirements (5.9+, 6.0 recommended)
- Platform requirements (.macOS(.v14))

**Pitfall:** Hummingbird 2.x requires Swift 5.9+. Swift 6.0 strongly recommended for full strict concurrency support. Older toolchains produce cryptic concurrency errors.

---

## Summary

### Gap Distribution by Category

| Category | Critical | High | Medium | Total |
|----------|----------|------|--------|-------|
| Routing | 3 | 2 | 2 | 7 |
| Request/Response | 1 | 3 | 1 | 5 |
| Middleware | 0 | 3 | 3 | 6 |
| Database | 2 | 1 | 1 | 4 |
| Auth | 0 | 2 | 1 | 3 |
| WebSockets | 1 | 1 | 1 | 3 |
| Background Jobs | 1 | 1 | 1 | 3 |
| Testing | 1 | 1 | 0 | 2 |
| Application Setup | 1 | 1 | 0 | 2 |
| **TOTAL** | **10** | **15** | **10** | **35** |

### Recommended Implementation Priority

**Phase 1 — Critical Foundation (10 entries):**
1. Router groups (GAP-001)
2. Wildcard routes (GAP-002)
3. Parameter extraction (GAP-003)
4. Request body streaming (GAP-008)
5. PostgresNIO query patterns (GAP-019)
6. Connection pool sizing (GAP-020)
7. WebSocket upgrade pattern (GAP-026)
8. Job queue setup (GAP-029)
9. HummingbirdTesting patterns (GAP-032)
10. Composition root pattern (GAP-034)

**Phase 2 — Production Essentials (15 entries):**
All "High" priority gaps (GAP-004, GAP-005, GAP-009 through GAP-011, GAP-014 through GAP-016, GAP-021, GAP-023, GAP-024, GAP-027, GAP-030, GAP-033, GAP-035)

**Phase 3 — Advanced Features (10 entries):**
All "Medium" priority gaps for specialized use cases

---

## Methodology

This analysis was conducted by:
1. Reviewing existing documentation (`core-concepts.md`, `integrations.md`)
2. Cross-referencing with current knowledge base checklist
3. Identifying documented patterns without corresponding KB entries
4. Cataloging critical pitfalls requiring dedicated knowledge entries
5. Prioritizing based on:
   - Frequency of use in production applications
   - Complexity and common pitfalls
   - Dependencies on other patterns

---

**Next Steps:**
1. Review and approve gap analysis
2. Create knowledge base entries for Phase 1 (Critical) gaps
3. Expand checklist with newly identified gaps
4. Track completion in `knowledge-coverage-checklist.md`

---

[← Knowledge Coverage Checklist](knowledge-coverage-checklist.md) | [Home](index.md)
