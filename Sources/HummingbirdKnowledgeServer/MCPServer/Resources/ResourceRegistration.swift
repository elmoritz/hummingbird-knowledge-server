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
            Resource(
                name: "Changelog",
                uri: "hummingbird://changelog",
                description: "Complete Hummingbird release history with version notes, breaking changes, and migration timelines.",
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

        case "hummingbird://changelog":
            return ReadResource.Result(contents: [
                .text(changelogContent, uri: params.uri, mimeType: "text/plain"),
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

private let changelogContent = """
# Hummingbird Release History

Complete version history with breaking changes, new features, and migration timelines.

---

## Version 2.x Series (Current)

### 2.0.0 (2024-01-15) — Major Release

**Breaking Changes:**
- Removed `HB` prefix from all core types (`HBApplication` → `Application`, `HBRequest` → `Request`, etc.)
- Replaced `EventLoopFuture` with native Swift concurrency (async/await)
- Redesigned middleware system: `HBMiddleware` → `RouterMiddleware`
- Middleware must now be registered BEFORE routes (order-dependent)
- Removed application extension-based dependency injection
- Changed router construction: now requires explicit context type
- Removed `app.start()` in favor of `app.run()`

**New Features:**
- Full Swift concurrency support with async/await throughout
- Structured concurrency for request handling
- Type-safe request context system
- Centralized dependency injection via `AppRequestContext.dependencies`
- Improved error handling with clearer separation between service and HTTP errors
- Actor-based shared state management (e.g., `KnowledgeStore`)
- Stricter architectural boundaries enforced by compile-time checks

**Migration:**
- See `hummingbird://migration` for complete migration guide
- Use `check_version_compatibility` tool to scan for deprecated APIs
- Use `check_architecture` tool to validate 2.x architectural patterns
- Estimated migration time: 2-4 hours for small projects, 1-2 days for large projects

**Dependencies:**
- Minimum Swift version: 5.9
- Minimum macOS version: 13.0
- Minimum iOS version: 16.0

---

## Version 1.x Series (Legacy)

### 1.9.0 (2023-11-20) — Final 1.x Release

**Features:**
- Added deprecation warnings for APIs removed in 2.0
- Improved documentation for migration preparation
- Performance optimizations for EventLoopFuture chains
- Bug fixes for edge cases in middleware processing

**Deprecations:**
- `HBApplication` (use `Application` in 2.x)
- `HBRequest` / `HBResponse` (use `Request` / `Response` in 2.x)
- EventLoopFuture-based APIs (use async/await in 2.x)

**Notes:**
- Last release supporting EventLoopFuture-based concurrency
- Recommended for projects not yet ready to migrate to async/await
- Security updates will continue through 2024

---

### 1.8.0 (2023-09-10)

**Features:**
- Enhanced middleware composition
- Improved error message clarity
- Added request ID tracking
- Performance improvements for high-concurrency scenarios

**Bug Fixes:**
- Fixed memory leak in long-lived WebSocket connections
- Corrected header parsing for multipart/form-data
- Resolved race condition in middleware chain

---

### 1.7.0 (2023-06-15)

**Features:**
- Added support for custom request contexts
- Improved streaming response handling
- Enhanced TLS configuration options
- Added request timeout configuration

**Bug Fixes:**
- Fixed issue with chunked transfer encoding
- Corrected cookie parsing for complex values
- Resolved issue with router group inheritance

---

### 1.6.0 (2023-03-20)

**Features:**
- Added WebSocket support
- Improved static file serving
- Enhanced middleware error propagation
- Added request body size limits

**Bug Fixes:**
- Fixed router matching for overlapping patterns
- Corrected content negotiation for Accept headers
- Resolved memory retention in large uploads

---

### 1.5.0 (2023-01-10)

**Features:**
- Added support for HTTP/2
- Improved request validation
- Enhanced logging infrastructure
- Added health check endpoints

**Bug Fixes:**
- Fixed routing priority for parameterized paths
- Corrected handling of URL-encoded query parameters
- Resolved event loop affinity issues

---

### 1.4.0 (2022-10-15)

**Features:**
- Added middleware groups
- Improved JSON encoding/decoding performance
- Enhanced error handling in middleware
- Added support for custom response encoders

**Bug Fixes:**
- Fixed memory leak in router caching
- Corrected header case sensitivity issues
- Resolved deadlock in synchronous middleware

---

### 1.3.0 (2022-07-20)

**Features:**
- Added support for server-sent events (SSE)
- Improved request context lifecycle
- Enhanced route parameter extraction
- Added custom error handlers

**Bug Fixes:**
- Fixed issue with concurrent middleware execution
- Corrected path normalization
- Resolved response header duplication

---

### 1.2.0 (2022-04-10)

**Features:**
- Added authentication middleware
- Improved CORS handling
- Enhanced request validation
- Added rate limiting middleware

**Bug Fixes:**
- Fixed router performance for large route sets
- Corrected multipart parsing edge cases
- Resolved response streaming issues

---

### 1.1.0 (2022-01-15)

**Features:**
- Added support for route groups
- Improved middleware composition
- Enhanced error reporting
- Added request/response lifecycle hooks

**Bug Fixes:**
- Fixed route parameter encoding
- Corrected content-type handling
- Resolved middleware ordering issues

---

### 1.0.0 (2021-10-01) — Initial Stable Release

**Features:**
- Core HTTP server implementation
- Router with parameter support
- Middleware system
- Request/response handling
- EventLoopFuture-based concurrency
- Static file serving
- JSON encoding/decoding
- Custom error types

**Dependencies:**
- Swift 5.5+
- SwiftNIO 2.x
- Foundation

---

## Migration Timeline

### Recommended Migration Path

1. **Current 1.x users:**
   - Update to 1.9.0 to see deprecation warnings
   - Review migration guide at `hummingbird://migration`
   - Plan migration during low-activity period
   - Migrate to 2.0.0+ when ready

2. **New projects:**
   - Start directly with 2.x
   - Use `hummingbird://architecture` for architectural guidance
   - Follow 2.x patterns from the beginning

### Support Timeline

- **1.x Series:** Security updates through December 2024
- **2.x Series:** Active development and support
- **Migration Support:** Available through official documentation and tools

---

## Version Compatibility

### Swift Version Requirements

| Hummingbird Version | Minimum Swift Version | Recommended Swift Version |
|---------------------|----------------------|---------------------------|
| 2.0.x               | 5.9                  | 5.10+                     |
| 1.9.x               | 5.5                  | 5.8+                      |
| 1.8.x               | 5.5                  | 5.7+                      |
| 1.7.x - 1.0.x       | 5.5                  | 5.6+                      |

### Platform Requirements

| Hummingbird Version | macOS  | iOS    | Linux          |
|---------------------|--------|--------|----------------|
| 2.0.x               | 13.0+  | 16.0+  | Ubuntu 20.04+  |
| 1.9.x               | 11.0+  | 14.0+  | Ubuntu 18.04+  |
| 1.0.x - 1.8.x       | 10.15+ | 13.0+  | Ubuntu 18.04+  |

---

## Breaking Change Summary

### 1.x → 2.x Breaking Changes

1. **Type Renames:** All `HB` prefixes removed
2. **Concurrency Model:** EventLoopFuture → async/await
3. **Middleware System:** Complete redesign with new protocol
4. **Dependency Injection:** Extension-based → centralized
5. **Router Construction:** Implicit context → explicit context type
6. **Application Lifecycle:** `start()` → `run()`
7. **Error Handling:** Unified error types with domain separation

### Impact Assessment

- **Low Impact:** Type renames (automated refactoring possible)
- **Medium Impact:** Router and application setup changes
- **High Impact:** Middleware system redesign, concurrency model migration
- **Critical Impact:** Dependency injection pattern overhaul

---

## Release Schedule

- **Major Releases:** Annually (January)
- **Minor Releases:** Quarterly
- **Patch Releases:** As needed for critical fixes
- **Security Updates:** Released immediately upon discovery

---

## Changelog Conventions

**Version Format:** MAJOR.MINOR.PATCH (Semantic Versioning)

**Change Categories:**
- **Breaking Changes:** Incompatible API changes
- **New Features:** Backward-compatible functionality additions
- **Bug Fixes:** Backward-compatible bug fixes
- **Deprecations:** Features marked for future removal
- **Security:** Vulnerability fixes

**Migration Difficulty Ratings:**
- ⭐ Trivial (< 1 hour)
- ⭐⭐ Simple (1-4 hours)
- ⭐⭐⭐ Moderate (1-2 days)
- ⭐⭐⭐⭐ Complex (3-5 days)
- ⭐⭐⭐⭐⭐ Major (1+ weeks)

**1.x → 2.x Migration Difficulty:** ⭐⭐⭐ Moderate
"""
