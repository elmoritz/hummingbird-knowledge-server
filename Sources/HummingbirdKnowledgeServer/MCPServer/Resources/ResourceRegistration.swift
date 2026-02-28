// Sources/HummingbirdKnowledgeServer/MCPServer/Resources/ResourceRegistration.swift
//
// Exposes knowledge base content as readable MCP resources.
// Resources are documents that AI clients can read directly — unlike tools,
// they do not require parameters to be invoked.

import MCP

/// Registers all MCP resources on the server.
///
/// Resources expose static or semi-static content from the knowledge base.
/// They complement tools: tools answer questions interactively; resources
/// provide documents that can be read in full.
func registerResources(on server: Server, knowledgeStore: KnowledgeStore) async {
    await server.withMethodHandler(ListResources.self) { _ in
        ListResources.Result(resources: [
            Resource(
                name: "Pitfall Catalogue",
                uri: "hummingbird://pitfalls",
                description: "Complete ranked catalogue of known Hummingbird 2.x architectural pitfalls and anti-patterns.",
                mimeType: "text/plain"
            ),
            Resource(
                name: "Architecture Reference",
                uri: "hummingbird://architecture",
                description: "Clean architecture reference for Hummingbird 2.x: layers, responsibilities, and injection points.",
                mimeType: "text/plain"
            ),
            Resource(
                name: "Violation Catalogue",
                uri: "hummingbird://violations",
                description: "The compiled architectural violation rule set used by check_architecture.",
                mimeType: "text/plain"
            ),
            Resource(
                name: "Migration Guide",
                uri: "hummingbird://migration",
                description: "Complete migration guide from Hummingbird 1.x to 2.x with API mappings, breaking changes, and step-by-step instructions.",
                mimeType: "text/plain"
            ),
        ])
    }

    await server.withMethodHandler(ReadResource.self) { params in
        switch params.uri {

        case "hummingbird://pitfalls":
            let content = await knowledgeStore.pitfallCatalogueText()
            return ReadResource.Result(contents: [
                .text(content, uri: params.uri, mimeType: "text/plain"),
            ])

        case "hummingbird://architecture":
            return ReadResource.Result(contents: [
                .text(architectureReferenceContent, uri: params.uri, mimeType: "text/plain"),
            ])

        case "hummingbird://violations":
            let violationText = ArchitecturalViolations.all.map { v in
                let severity: String
                switch v.severity {
                case .critical: severity = "CRITICAL"
                case .error:    severity = "ERROR"
                case .warning:  severity = "WARNING"
                }
                return "[\(severity)] \(v.id)\n\(v.description)\nCorrection: \(v.correctionId)"
            }.joined(separator: "\n\n---\n\n")

            return ReadResource.Result(contents: [
                .text(violationText, uri: params.uri, mimeType: "text/plain"),
            ])

        case "hummingbird://migration":
            return ReadResource.Result(contents: [
                .text(migrationGuideContent, uri: params.uri, mimeType: "text/plain"),
            ])

        default:
            throw AppError.resourceNotFound(uri: params.uri)
        }
    }
}

// MARK: - Static content

private let architectureReferenceContent = """
# Hummingbird 2.x Clean Architecture Reference

## Layers and Responsibilities

### Controller Layer
- **Files:** `Sources/App/Controllers/*.swift`
- **Allowed imports:** `Hummingbird`, `Foundation`
- **Responsibility:** Decode HTTP requests, dispatch to services, encode responses
- **Forbidden:** Business logic, database calls, service construction

### Service Layer
- **Files:** `Sources/App/Services/*.swift`
- **Allowed imports:** `Foundation`, domain protocols — NOT Hummingbird
- **Responsibility:** Business logic, validation, orchestration
- **Forbidden:** HTTP types, Hummingbird imports, direct database access

### Repository Layer
- **Files:** `Sources/App/Repositories/*.swift`
- **Allowed imports:** Database driver, Foundation — NOT Hummingbird
- **Responsibility:** Data persistence, query construction
- **Forbidden:** Business logic, HTTP types

### Model Layer
- **Files:** `Sources/App/Models/*.swift`
- **Responsibility:** Domain entities — plain Swift structs and classes
- **Forbidden:** Framework imports, HTTP types, persistence logic

### Middleware Layer
- **Files:** `Sources/App/Middleware/*.swift`
- **Allowed imports:** `Hummingbird`
- **Responsibility:** Cross-cutting concerns: auth, rate limiting, logging
- **Pattern:** Conform to `RouterMiddleware` with `typealias Context = AppRequestContext`

## Dependency Injection

All dependencies flow through `AppRequestContext.dependencies`:

1. `AppDependencies` is constructed once in `Application+build.swift`
2. `DependencyInjectionMiddleware` copies it into every request context
3. Handlers read `context.dependencies.myService`
4. Nothing constructs services inline — ever

## Error Handling

- Service and repository layers throw `AppError`
- Controllers catch `AppError` and throw `HTTPError` with appropriate status codes
- Third-party errors are ALWAYS wrapped before propagating

## Concurrency Rules

- Shared mutable state lives in actors
- Route handler closures are `@Sendable`
- All `async` functions use structured concurrency (no unstructured `Task {}` unless coordinating lifecycle)
- `KnowledgeStore` is an actor — all reads/writes are serialised
"""

private let migrationGuideContent = """
# Hummingbird 1.x → 2.x Migration Guide

This guide provides comprehensive API mappings and step-by-step instructions for migrating from Hummingbird 1.x to 2.x.

## Overview

Hummingbird 2.x is a major rewrite that removes the `HB` prefix from types, introduces a new middleware system, and enforces stricter architectural boundaries. This guide maps every deprecated API to its 2.x equivalent.

---

## Core Type Mappings

### Application and Server

| 1.x API | 2.x API | Notes |
|---------|---------|-------|
| `HBApplication` | `Application` | Core application type renamed |
| `HBApplication()` | `Application(router: router)` | Constructor now requires a router |
| `app.start()` | `try await app.run()` | Method renamed; now async |

**Migration:**
```swift
// 1.x
let app = HBApplication()
try app.start()

// 2.x
let router = Router(context: AppRequestContext.self)
let app = Application(router: router)
try await app.run()
```

---

### Request and Response

| 1.x API | 2.x API | Notes |
|---------|---------|-------|
| `HBRequest` | `Request` | Request type renamed |
| `HBResponse` | `Response` | Response type renamed |
| `HBHTTPError` | `HTTPError` | HTTP error type renamed |
| `request.body.buffer` | `request.body.buffer` | Body access unchanged |
| `HBResponse(status:headers:body:)` | `Response(status:headers:body:)` | Constructor signature unchanged |

**Migration:**
```swift
// 1.x
func handler(request: HBRequest, context: SomeContext) throws -> HBResponse {
    throw HBHTTPError(.notFound)
}

// 2.x
func handler(request: Request, context: AppRequestContext) async throws -> Response {
    throw HTTPError(.notFound)
}
```

---

### Routing

| 1.x API | 2.x API | Notes |
|---------|---------|-------|
| `HBRouterBuilder` | `Router(context:)` | Router builder replaced by Router type |
| `app.router.get(...)` | `router.get(...)` | Routing methods now on router instance |
| `app.router.post(...)` | `router.post(...)` | Same pattern for all HTTP methods |
| `app.router.group(...)` | `router.group(...)` | Route groups unchanged in concept |

**Migration:**
```swift
// 1.x
app.router.get("/users") { request, context -> HBResponse in
    // handler
}

// 2.x
router.get("/users") { request, context -> Response in
    // handler
}
```

---

## Middleware System

### Breaking Changes

| 1.x API | 2.x API | Notes |
|---------|---------|-------|
| `HBMiddleware` | `RouterMiddleware` | Protocol renamed and redesigned |
| `app.middleware.add(...)` | `router.add(middleware:)` | Middleware registration moved to router |
| `func apply(to request:next:)` | `func handle(_:context:next:)` | Method signature changed |

**Critical:** Middleware MUST be registered BEFORE routes in 2.x.

**Migration:**
```swift
// 1.x
struct MyMiddleware: HBMiddleware {
    func apply(to request: HBRequest, next: HBResponder) -> EventLoopFuture<HBResponse> {
        // middleware logic
    }
}
app.middleware.add(MyMiddleware())

// 2.x
struct MyMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        // middleware logic
    }
}
router.add(middleware: MyMiddleware())  // MUST be before routes
```

---

## Dependency Injection

### 1.x Pattern (Extensions on HBApplication)

```swift
// 1.x - services stored as application extensions
extension HBApplication {
    var myService: MyService {
        get { extensions.get(\\.myService) }
        set { extensions.set(\\.myService, value: newValue) }
    }
}
```

### 2.x Pattern (Centralized Dependencies)

```swift
// 2.x - all dependencies in AppRequestContext.dependencies
struct AppDependencies {
    let myService: MyService
}

struct AppRequestContext: RequestContext {
    var dependencies: AppDependencies
    // ...
}

// Usage in handlers
router.get("/endpoint") { request, context in
    let result = await context.dependencies.myService.doWork()
    return Response(status: .ok)
}
```

**Migration Steps:**
1. Create an `AppDependencies` struct with all services
2. Add a `dependencies` property to your request context
3. Construct dependencies once in `Application+build.swift`
4. Use `DependencyInjectionMiddleware` to copy into every request
5. Replace all `app.myService` with `context.dependencies.myService`

---

## Error Handling

### 1.x Error Handling

```swift
// 1.x
throw HBHTTPError(.badRequest, message: "Invalid input")
```

### 2.x Error Handling

```swift
// 2.x - Controllers throw HTTPError
throw HTTPError(.badRequest, message: "Invalid input")

// 2.x - Services throw AppError
throw AppError.validation("Invalid input")
```

**Best Practice:** Services throw domain errors (`AppError`), controllers catch and convert to `HTTPError`.

---

## Package Dependencies

### Update Package.swift

```swift
// 1.x
.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "1.9.0")

// 2.x
.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
```

### Module Imports

```swift
// 1.x and 2.x - import statement unchanged
import Hummingbird
```

---

## Concurrency Changes

### EventLoopFuture → async/await

| 1.x Pattern | 2.x Pattern | Notes |
|-------------|-------------|-------|
| `EventLoopFuture<T>` | `async throws -> T` | All futures replaced with async/await |
| `future.map { }` | `let result = await ...` | Transformation now uses await |
| `future.flatMap { }` | `let result = await ...; return await ...` | Chaining now sequential |

**Migration:**
```swift
// 1.x
func getUser(id: String) -> EventLoopFuture<User> {
    database.query(...).map { rows in
        User(from: rows)
    }
}

// 2.x
func getUser(id: String) async throws -> User {
    let rows = await database.query(...)
    return User(from: rows)
}
```

---

## Step-by-Step Migration Checklist

### 1. Update Dependencies
- [ ] Update `Package.swift` to Hummingbird 2.x
- [ ] Run `swift package update`
- [ ] Fix any immediate compilation errors

### 2. Rename Core Types
- [ ] Replace `HBApplication` → `Application`
- [ ] Replace `HBRequest` → `Request`
- [ ] Replace `HBResponse` → `Response`
- [ ] Replace `HBHTTPError` → `HTTPError`
- [ ] Replace `HBRouterBuilder` usage with `Router(context:)`

### 3. Refactor Middleware
- [ ] Replace `HBMiddleware` → `RouterMiddleware`
- [ ] Add `typealias Context = AppRequestContext`
- [ ] Update `apply` → `handle` method signature
- [ ] Move middleware registration BEFORE route definitions
- [ ] Replace `app.middleware.add` → `router.add(middleware:)`

### 4. Migrate to async/await
- [ ] Replace `EventLoopFuture<T>` → `async throws -> T`
- [ ] Add `async` to route handler closures
- [ ] Replace `.map`/`.flatMap` with `await`

### 5. Centralize Dependency Injection
- [ ] Create `AppDependencies` struct
- [ ] Move all services from `HBApplication` extensions to `AppDependencies`
- [ ] Add `dependencies` property to request context
- [ ] Create `DependencyInjectionMiddleware`
- [ ] Update all handlers to use `context.dependencies`

### 6. Validate Architecture
- [ ] Run `check_architecture` tool to validate 2.x patterns
- [ ] Fix any architectural violations
- [ ] Ensure clean layer separation (Controller → Service → Repository)

### 7. Testing
- [ ] Update test setup to use `Application(router:)`
- [ ] Replace future-based assertions with async assertions
- [ ] Verify all routes work correctly

---

## Common Pitfalls

1. **Middleware Order:** Middleware MUST be registered before routes in 2.x
2. **Async Handlers:** All route handlers should be `async` — sync handlers block the event loop
3. **Dependency Construction:** Never construct services inline — always use `context.dependencies`
4. **Import Statements:** Services should NOT import Hummingbird — only Foundation and domain types
5. **Error Propagation:** Always wrap third-party errors in `AppError` before throwing

---

## Additional Resources

- Use `check_version_compatibility` tool to scan code for 1.x APIs
- Use `check_architecture` tool to validate 2.x architectural patterns
- Read `hummingbird://architecture` for clean architecture reference
- Read `hummingbird://pitfalls` for common architectural anti-patterns

---

## Support

If you encounter migration issues not covered here:
1. Check the Hummingbird 2.x official documentation
2. Use `check_version_compatibility` to identify deprecated APIs
3. Consult the architectural violation catalogue for pattern guidance
"""
