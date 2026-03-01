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

## Hallucination-Prone Areas Requiring Extra Detail

This section identifies **specific areas where AI language models commonly hallucinate incorrect Hummingbird 2.x patterns**. These hallucinations arise from:
- Training data containing Hummingbird 1.x examples (incompatible APIs)
- Cross-contamination from other Swift web frameworks (Vapor, Perfect, Kitura)
- Invention of plausible-sounding but non-existent convenience APIs
- Outdated async patterns (completion handlers instead of async/await)

**Critical for AI consumers:** These patterns require explicit counter-examples and version-specific validation in knowledge base entries.

---

### 🚨 HALLUCINATION-001: Hummingbird 1.x vs 2.x API Confusion

**Hallucination Pattern:**
AI models frequently generate Hummingbird 1.x code when asked for 2.x patterns, leading to complete compilation failure.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — Hummingbird 1.x Router syntax (does not compile in 2.x)
let router = HBRouter()
router.get("/users") { request -> HBResponse in
    return request.success("Hello")
}

// ❌ HALLUCINATION — HBApplication (1.x name)
let app = HBApplication(router: router)

// ✅ CORRECT — Hummingbird 2.x actual API
let router = Router(context: AppRequestContext.self)
router.get("/users") { request, context in
    return "Hello"
}
let app = Application(router: router)
```

**Why This Happens:**
Hummingbird 2.x was a complete rewrite (2023-2024). Training data contains far more 1.x examples. The two versions are **entirely incompatible** — different package names, different APIs, different concurrency models.

**Required KB Coverage:**
- Explicit "2.x vs 1.x" comparison table
- Version detection from `import Hummingbird` (no `HB` prefixes in 2.x)
- Migration guide references
- **violationId:** `hummingbird-1x-api-in-2x-context`

---

### 🚨 HALLUCINATION-002: Vapor Pattern Cross-Contamination

**Hallucination Pattern:**
AI models mix Vapor framework patterns into Hummingbird code, creating non-existent APIs.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — Vapor's `.req` parameter name
router.get("/users") { req in
    return req.view.render("users", ["users": users])  // Vapor API, not Hummingbird
}

// ❌ HALLUCINATION — Vapor's EventLoopFuture
router.get("/users") { req -> EventLoopFuture<[User]> in
    return userService.getAll()  // Hummingbird 2.x uses async/await, not futures
}

// ❌ HALLUCINATION — Vapor's `.on()` syntax
router.on(.GET, "/users", use: getUsers)  // Hummingbird uses .get(), not .on()

// ✅ CORRECT — Hummingbird 2.x actual API
router.get("/users") { request, context in
    let users = try await context.dependencies.userService.getAll()
    return UsersResponse(users)
}
```

**Why This Happens:**
Vapor is the most popular Swift web framework, so training data is heavily weighted toward Vapor examples. AI models pattern-match the task (Swift web server) and retrieve Vapor syntax.

**Required KB Coverage:**
- Explicit "NOT Vapor" annotations in route handler examples
- Comparison table showing Vapor vs Hummingbird 2.x equivalents
- **violationId:** `vapor-api-in-hummingbird`

---

### 🚨 HALLUCINATION-003: Request API Hallucinations

**Hallucination Pattern:**
AI models invent plausible-sounding but non-existent convenience methods on `Request`.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — non-existent .parameter() method
let id = request.parameter("id")  // doesn't exist

// ❌ HALLUCINATION — non-existent .query() method
let page = request.query("page", as: Int.self)  // doesn't exist

// ❌ HALLUCINATION — non-existent .json() method
let user = try await request.json(User.self)  // doesn't exist

// ❌ HALLUCINATION — non-existent .body.collect() method
let data = try await request.body.collect()  // doesn't exist

// ✅ CORRECT — actual Hummingbird 2.x API
let id = try context.parameters.require("id")  // from context, not request
let page = request.uri.queryParameters.get("page", as: Int.self) ?? 1
let user = try await request.decode(as: User.self, context: context)
var buffer = ByteBuffer()
for try await chunk in request.body {
    buffer.writeImmutableBuffer(chunk)
}
```

**Why This Happens:**
These invented methods are plausible simplifications that "should" exist based on patterns from other frameworks. The AI generates what makes sense conceptually, not what actually exists.

**Required KB Coverage:**
- Explicit examples of parameter extraction (via `context.parameters`, NOT `request.parameter`)
- Explicit examples of query parameter extraction (via `request.uri.queryParameters`)
- Explicit examples of body decoding (via `request.decode(as:context:)`)
- Body streaming patterns (AsyncSequence iteration)
- **violationIds:** `invented-request-convenience-method`, `request-parameter-instead-of-context-parameter`

---

### 🚨 HALLUCINATION-004: Middleware API Hallucinations

**Hallucination Pattern:**
AI models generate pre-2.x middleware patterns or invent simplified APIs that don't exist.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — non-existent Middleware protocol (no "Router" prefix)
struct AuthMiddleware: Middleware {
    func handle(_ request: Request, next: Responder) async throws -> Response {
        // ...
    }
}

// ❌ HALLUCINATION — non-existent .use() method for middleware
router.use(AuthMiddleware())

// ❌ HALLUCINATION — invented simplified signature
struct LoggingMiddleware: RouterMiddleware {
    func handle(_ request: Request) async throws -> Response {
        // missing context and next parameters
    }
}

// ✅ CORRECT — actual Hummingbird 2.x RouterMiddleware
struct AuthMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        // validate auth
        return try await next(request, context)
    }
}

router.add(middleware: AuthMiddleware())  // .add(), not .use()
```

**Why This Happens:**
Middleware APIs vary widely across frameworks. AI models generate "average" middleware patterns that don't match Hummingbird 2.x's specific `RouterMiddleware` protocol.

**Required KB Coverage:**
- Full `RouterMiddleware` protocol signature (all three parameters!)
- Associated type `Context` requirement
- `.add(middleware:)` registration (NOT `.use()`)
- Order-dependent execution
- **violationIds:** `wrong-middleware-protocol`, `middleware-use-instead-of-add`, `middleware-missing-context`

---

### 🚨 HALLUCINATION-005: Context Mutation Anti-Patterns

**Hallucination Pattern:**
AI models incorrectly mutate context without understanding Swift's value semantics.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — mutating context without reassignment
func handle(_ request: Request, context: AppRequestContext, next: ...) async throws -> Response {
    context.userId = extractUserId(from: request)  // mutation lost!
    return try await next(request, context)  // original context passed
}

// ❌ HALLUCINATION — mutating context in handler (impossible)
router.get("/protected") { request, context in
    context.userId = "123"  // context is immutable in handlers
    return "OK"
}

// ✅ CORRECT — var context and pass mutated copy
func handle(_ request: Request, context: AppRequestContext, next: ...) async throws -> Response {
    var ctx = context  // create mutable copy
    ctx.userId = extractUserId(from: request)
    return try await next(request, ctx)  // pass mutated copy
}
```

**Why This Happens:**
Swift structs have value semantics. Mutations create new copies unless captured with `var`. AI models trained on reference-heavy languages (JavaScript, Python, Java) don't internalize this pattern.

**Required KB Coverage:**
- `var context` pattern in middleware
- Value vs reference semantics explanation
- Context mutation examples
- Pitfall: forgetting `var` makes mutations invisible
- **violationIds:** `context-mutation-without-var`, `context-mutation-in-handler`

---

### 🚨 HALLUCINATION-006: Repository Protocol Hallucinations

**Hallucination Pattern:**
AI models invent Hummingbird-provided repository protocols that don't exist.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — invented "HBRepository" protocol
import Hummingbird

protocol UserRepository: HBRepository {  // HBRepository doesn't exist!
    func find(id: UUID) async throws -> User
}

// ❌ HALLUCINATION — invented "DatabaseRepository" protocol
struct PostgresUserRepository: DatabaseRepository {  // doesn't exist
    // ...
}

// ❌ HALLUCINATION — invented repository registration API
router.add(repository: PostgresUserRepository.self)  // doesn't exist

// ✅ CORRECT — user-defined protocols (no Hummingbird involvement)
protocol UserRepositoryProtocol {  // YOUR protocol, not Hummingbird's
    func find(id: UUID) async throws -> User
}

struct PostgresUserRepository: UserRepositoryProtocol {
    let pool: PostgresConnectionPool
    // implementation
}

// Inject via AppDependencies, not router registration
struct AppDependencies {
    let userRepository: any UserRepositoryProtocol
}
```

**Why This Happens:**
Repository pattern is common in web frameworks. AI models assume Hummingbird provides base protocols like many ORM-heavy frameworks do. **It doesn't.** Repositories are user-defined patterns.

**Required KB Coverage:**
- Explicit statement: "Hummingbird provides NO repository protocols or base classes"
- User-defined protocol patterns
- Protocol naming conventions (avoid `HB` prefix)
- Dependency injection via `AppDependencies`
- **violationIds:** `invented-hummingbird-repository-protocol`, `repository-registration-api`

---

### 🚨 HALLUCINATION-007: Error Handling Hallucinations

**Hallucination Pattern:**
AI models invent HTTPError convenience initializers and error transformation APIs.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — invented HTTPError convenience
throw HTTPError.badRequest("Invalid email")  // .badRequest doesn't take message

// ❌ HALLUCINATION — invented HTTPError.message property
catch {
    throw HTTPError(.internalServerError, message: error.localizedDescription)
}

// ❌ HALLUCINATION — invented error middleware registration
router.addErrorHandler { error in
    return Response(status: .internalServerError, body: "Error: \(error)")
}

// ✅ CORRECT — actual HTTPError API
throw HTTPError(.badRequest)  // status only, no message parameter

// ✅ CORRECT — wrap in AppError for messages
enum AppError: Error {
    case invalidInput(reason: String)
    case internalError(reason: String)
}

throw AppError.invalidInput(reason: "Invalid email")

// ✅ CORRECT — error handling middleware (manual)
struct ErrorHandlerMiddleware: RouterMiddleware {
    func handle(_ request: Request, context: AppRequestContext, next: ...) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as HTTPError {
            return Response(status: error.status)
        } catch {
            return Response(status: .internalServerError)
        }
    }
}
```

**Why This Happens:**
Many frameworks provide rich error APIs with messages, codes, and automatic transformation. Hummingbird 2.x keeps `HTTPError` minimal — just an HTTP status. AI models hallucinate richer APIs.

**Required KB Coverage:**
- `HTTPError` is just a status wrapper (no message, no code)
- Custom `AppError` enum pattern for typed errors
- Manual error handling middleware pattern
- Error wrapping at boundaries
- **violationIds:** `http-error-message-parameter`, `invented-error-handler-registration`

---

### 🚨 HALLUCINATION-008: Async/Await Confusion

**Hallucination Pattern:**
AI models mix completion handlers, EventLoopFutures, and async/await.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — completion handler (pre-async/await)
router.get("/users") { request, context, completion in
    userService.getAll { users in
        completion(.success(users))
    }
}

// ❌ HALLUCINATION — EventLoopFuture (SwiftNIO 1.x pattern)
router.get("/users") { request, context -> EventLoopFuture<[User]> in
    return userService.getAll()
}

// ❌ HALLUCINATION — mixing async and callbacks
router.get("/users") { request, context in
    userService.getAll { users in  // callback inside async handler
        return users  // doesn't compile
    }
}

// ✅ CORRECT — pure async/await
router.get("/users") { request, context in
    let users = try await context.dependencies.userService.getAll()
    return UsersResponse(users)
}
```

**Why This Happens:**
Training data contains Swift code from multiple eras: pre-async/await (completion handlers), SwiftNIO futures, and modern async/await. AI models blend patterns from different concurrency models.

**Required KB Coverage:**
- "Hummingbird 2.x is 100% async/await — no callbacks, no futures"
- Explicit examples showing NO completion handlers
- Migration notes from EventLoopFuture patterns
- **violationIds:** `completion-handler-in-2x`, `event-loop-future-in-2x`

---

### 🚨 HALLUCINATION-009: Service Lifecycle Hallucinations

**Hallucination Pattern:**
AI models invent application lifecycle hooks that don't exist.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — invented .onStartup() hook
app.onStartup {
    print("Server started")
}

// ❌ HALLUCINATION — invented .onShutdown() hook
app.onShutdown {
    print("Server stopped")
}

// ❌ HALLUCINATION — invented .configure() method
app.configure { config in
    config.port = 8080
}

// ✅ CORRECT — swift-service-lifecycle Service protocol
struct StartupService: Service {
    func run() async throws {
        print("Server started")
        // Keep running until cancelled
        try await Task.sleep(for: .seconds(.max))
    }
}

app.addServices(StartupService())

// ✅ CORRECT — configuration at initialization
let app = Application(
    router: router,
    configuration: .init(address: .hostname("0.0.0.0", port: 8080))
)
```

**Why This Happens:**
Many frameworks provide lifecycle hooks (onStartup, onShutdown, configure). Hummingbird 2.x uses `swift-service-lifecycle` instead, which is less intuitive for developers coming from other frameworks.

**Required KB Coverage:**
- "NO onStartup/onShutdown hooks — use Service protocol"
- Service lifecycle pattern examples
- Configuration at initialization (not post-construction)
- `app.addServices()` for background services
- **violationIds:** `invented-lifecycle-hook`, `post-init-configuration`

---

### 🚨 HALLUCINATION-010: Testing API Hallucinations

**Hallucination Pattern:**
AI models invent XCTest-style test helpers that don't exist in HummingbirdTesting.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — invented test client
let client = app.testClient()
let response = try await client.get("/users")

// ❌ HALLUCINATION — invented .send() method
let response = try await app.send(.GET, "/users")

// ❌ HALLUCINATION — invented test environment
app.testEnvironment {
    try await testApp.test(.router) { client in
        // nested test environment doesn't exist
    }
}

// ✅ CORRECT — actual HummingbirdTesting API
try await testApp.test(.router) { client in
    try await client.execute(uri: "/users", method: .get) { response in
        XCTAssertEqual(response.status, .ok)
    }
}
```

**Why This Happens:**
Testing APIs vary widely. AI models generate patterns inspired by HTTP testing libraries from other ecosystems (supertest, requests, etc.) that don't match Hummingbird's actual API.

**Required KB Coverage:**
- `.test(_:)` method with mode parameter (`.router` or `.live`)
- `client.execute(uri:method:)` pattern
- Response assertion patterns
- No `.send()`, no `.testClient()`, no test environment nesting
- **violationIds:** `invented-test-client-api`, `invented-test-send-method`

---

### 🚨 HALLUCINATION-011: Configuration & Environment Variable Hallucinations

**Hallucination Pattern:**
AI models invent configuration APIs and environment variable access patterns.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — invented .env() method
let dbURL = app.env("DATABASE_URL")

// ❌ HALLUCINATION — invented Config protocol
struct AppConfig: HBConfig {  // HBConfig doesn't exist
    var databaseURL: String
}

// ❌ HALLUCINATION — invented .config property
app.config.databaseURL = "postgres://localhost/db"

// ❌ HALLUCINATION — direct env access in service
struct UserService {
    func getJWTSecret() -> String {
        ProcessInfo.processInfo.environment["JWT_SECRET"]!  // anti-pattern
    }
}

// ✅ CORRECT — user-defined Configuration struct
struct AppConfiguration: Sendable {
    let databaseURL: String
    let jwtSecret: String

    static func fromEnvironment() throws -> AppConfiguration {
        guard let dbURL = ProcessInfo.processInfo.environment["DATABASE_URL"],
              let jwtSecret = ProcessInfo.processInfo.environment["JWT_SECRET"] else {
            throw AppError.configurationError(reason: "Missing env vars")
        }
        return AppConfiguration(databaseURL: dbURL, jwtSecret: jwtSecret)
    }
}

// Inject via AppDependencies
struct AppDependencies: Sendable {
    let configuration: AppConfiguration
    let userService: UserService
}
```

**Why This Happens:**
Configuration management is a solved problem in many frameworks (dotenv, config files, etc.). AI models assume Hummingbird provides similar conveniences. **It doesn't.** Configuration is entirely user-defined.

**Required KB Coverage:**
- "Hummingbird provides NO configuration system"
- User-defined `AppConfiguration` struct pattern
- Environment variable access at startup only
- Injection via `AppDependencies`
- Never access `ProcessInfo.processInfo.environment` in services/handlers
- **violationIds:** `invented-config-api`, `direct-env-access-in-service`

---

### 🚨 HALLUCINATION-012: Database Query API Hallucinations

**Hallucination Pattern:**
AI models invent ORM-style query builders that don't exist in PostgresNIO.

**Common Mistakes:**
```swift
// ❌ HALLUCINATION — invented query builder
let users = try await pool
    .table("users")
    .where("age", ">", 18)
    .orderBy("name")
    .get()

// ❌ HALLUCINATION — invented Model protocol
struct User: PostgresModel {  // doesn't exist
    static let tableName = "users"
}

// ❌ HALLUCINATION — string concatenation (SQL INJECTION!)
let userId = request.parameter("id")
let rows = try await pool.query("SELECT * FROM users WHERE id = '\(userId)'")

// ✅ CORRECT — PostgresNIO raw SQL with safe interpolation
let userId: UUID = try context.parameters.require("id", as: UUID.self)
let rows = try await pool.query(
    "SELECT id, email, name FROM users WHERE id = \(userId)",
    logger: context.logger
)
for try await row in rows {
    let user = try row.decode(User.self)
    return user
}

// Note: \(userId) is SAFE — it's bind parameter syntax, not string interpolation!
```

**Why This Happens:**
ORMs and query builders are ubiquitous (ActiveRecord, SQLAlchemy, Eloquent, etc.). AI models assume similar conveniences exist. PostgresNIO is a **driver**, not an ORM — it provides safe parameterized queries, not query builders.

**Required KB Coverage:**
- "PostgresNIO is NOT an ORM — no query builder, no models"
- Raw SQL with `\(variable)` bind parameters (SAFE, not string concat!)
- Manual row decoding
- Pitfall: `"\(var)"` in query string is SAFE (bind param), but in regular Swift string is dangerous
- ORM alternatives (Fluent, separate layer)
- **violationIds:** `invented-query-builder`, `invented-postgres-model`, `sql-string-concatenation`

---

### Summary: Hallucination Risk Mitigation Strategy

To minimize hallucinations in AI-generated Hummingbird 2.x code, knowledge base entries must:

1. **Include explicit version annotations:** "Hummingbird 2.x" in every code example
2. **Provide counter-examples:** Show what does NOT work (Vapor, 1.x, invented APIs)
3. **State non-existence explicitly:** "Hummingbird does NOT provide X" for common assumptions
4. **Cross-reference official docs:** Link to `hummingbird-project/hummingbird` GitHub
5. **Emphasize minimalism:** Hummingbird provides building blocks, not batteries-included conveniences
6. **Highlight breaking changes:** 1.x → 2.x migration notes
7. **Show full signatures:** Middleware, handlers, protocols — no simplified "pseudocode"
8. **Use violation IDs:** Tag anti-patterns for pattern-matching during validation

**High-Risk Hallucination Categories (require extra validation):**
- Middleware (protocol signature, registration)
- Request parameter extraction (context vs request)
- Error handling (HTTPError limitations)
- Configuration (no built-in system)
- Database queries (no ORM, raw SQL only)
- Testing (actual HummingbirdTesting API)

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
