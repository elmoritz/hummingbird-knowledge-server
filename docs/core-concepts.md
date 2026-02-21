# Core Concepts

[← Introduction](introduction.md) | [Home](index.md) | [Next: Concurrency & Services →](concurrency-services.md)

---

## 5. Application Setup & Entry Point

### Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyServer",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: [
                // Catch data races at compile time — keep this enabled always
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
```

> **Pitfall:** Hummingbird 2.x requires Swift 5.9+. Swift 6.0 is strongly recommended for full strict concurrency support. Using an older toolchain produces cryptic errors about missing concurrency features.

### Entry Point (main.swift)

```swift
import Hummingbird
import Logging

LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .info
    return handler
}

do {
    let app = try await buildApplication(configuration: .load())
    try await app.runService()
} catch {
    Logger(label: "main").critical("Fatal startup error: \(error)")
    exit(1)
}
```

### Composition Root (Application+build.swift)

```swift
import Hummingbird

func buildApplication(configuration: AppConfiguration) async throws -> some ApplicationProtocol {
    // Build infrastructure
    let dbPool = try await DatabasePool(configuration.database)

    // Build repositories
    let userRepository = PostgresUserRepository(pool: dbPool)

    // Build services
    let userService = UserService(repository: userRepository)

    // Assemble dependencies
    let dependencies = AppDependencies(userService: userService)

    // Build router — no business logic here, ever
    let router = Router(context: AppRequestContext.self)
    router.add(middleware: DependencyInjectionMiddleware(dependencies: dependencies))
    router.add(middleware: RequestLoggingMiddleware())

    UserController().registerRoutes(on: router.group("/users"))

    var app = Application(
        router: router,
        configuration: .init(address: .hostname(configuration.host, port: configuration.port))
    )
    app.addServices(dbPool)

    return app
}
```

This is the **only file** that imports both Hummingbird and PostgresNIO (or any database driver). It is the single place in the codebase where concrete types are mentioned. Everything else depends on protocols.

---

## 6. Routing

### Basics

Hummingbird uses a trie-based router. Route matching is O(path segment count), not O(number of routes). Routing is never a bottleneck.

```swift
let router = Router(context: AppRequestContext.self)

router.get("/users", use: listUsers)
router.post("/users", use: createUser)
router.get("/users/:id", use: getUser)
router.put("/users/:id", use: updateUser)
router.delete("/users/:id", use: deleteUser)

// Catch-all wildcard
router.get("/files/**") { request, context in
    let path = context.parameters.getCatchAll()
    // path contains everything after /files/
}
```

### Route Groups

```swift
let api = router.group("/api/v1")
    .add(middleware: AuthMiddleware())

api.get("/profile", use: getProfile)      // GET /api/v1/profile
api.put("/profile", use: updateProfile)   // PUT /api/v1/profile
```

### Parameter Extraction

```swift
router.get("/users/:id") { request, context in
    let id = try context.parameters.require("id", as: UUID.self)
    // throws HTTPError(.badRequest) if missing or not a valid UUID
}

// Optional parameter
let slug: String? = context.parameters.get("slug")

// Catch-all
let remainder = context.parameters.getCatchAll()
```

> **Pitfall:** `context.parameters.require(_:as:)` throws `HTTPError(.badRequest)` if the parameter cannot be converted to the requested type. Always use `try` — and let Hummingbird's error handling surface it as a 400.

### Route Priority

Static segments always beat parameterised ones. `/users/me` matches the static route before `/users/:id` regardless of registration order.

---

## 7. Request & Response Handling

### Reading the Body

```swift
// Collect entire body (for JSON decoding)
let body = try await request.body.collect(upTo: 1024 * 1024) // 1MB limit

// Decode JSON directly — preferred
let dto = try await request.decode(as: CreateUserInput.self, context: context)

// Stream for large uploads — never collect into memory
for try await chunk in request.body {
    // process ByteBuffer chunk
}
```

> **Pitfall:** The request body is a stream consumed exactly once. If middleware reads it, the route handler sees an empty body. If you need the body in both middleware and a handler, collect it in middleware and store the result on the request context.

### Building Responses

```swift
// String → 200 OK text/plain
return "Hello"

// Encodable struct → 200 OK application/json
return UserResponse(user)

// Custom status code
return EditedResponse(status: .created, response: UserResponse(user))

// 204 No Content
return Response(status: .noContent)
```

### Query Parameters

```swift
// GET /search?q=swift&page=2
let q    = request.uri.queryParameters.get("q") ?? ""
let page = request.uri.queryParameters.get("page", as: Int.self) ?? 1
```

### Headers

```swift
// Reading
let auth = request.headers[.authorization]

// Writing response headers
var headers = HTTPFields()
headers[.cacheControl] = "no-store"
headers[.xContentTypeOptions] = "nosniff"
return Response(status: .ok, headers: headers, body: body)
```

---

## 8. Middleware

### Protocol

```swift
struct MyMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // pre-processing
        let response = try await next(request, context)
        // post-processing
        return response
    }
}
```

### Registering

```swift
// Global — all routes
router.add(middleware: LoggingMiddleware())
router.add(middleware: CORSMiddleware())

// Group-scoped — only routes in this group
router.group("/admin")
    .add(middleware: AdminAuthMiddleware())
    .get("/stats", use: getStats)
```

> **Pitfall:** Middleware executes in registration order. Auth middleware added after logging middleware will still log unauthenticated requests. Order matters — especially for security-critical middleware.

### Built-in Middleware

- `FileMiddleware` — serves static files
- `CORSMiddleware` — Cross-Origin Resource Sharing headers
- `MetricsMiddleware` — request/response metrics via swift-metrics
- `TracingMiddleware` — OpenTelemetry distributed tracing
- `LogRequestsMiddleware` — structured request logging

---

[← Introduction](introduction.md) | [Home](index.md) | [Next: Concurrency & Services →](concurrency-services.md)
