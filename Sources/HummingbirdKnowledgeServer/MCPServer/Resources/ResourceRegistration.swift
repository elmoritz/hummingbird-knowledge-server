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
            Resource(
                name: "Code Examples",
                uri: "hummingbird://examples",
                description: "Production-grade code examples for Hummingbird 2.x: controllers, services, repositories, middleware, and dependency injection patterns.",
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

        case "hummingbird://examples":
            return ReadResource.Result(contents: [
                .text(codeExamplesContent, uri: params.uri, mimeType: "text/plain"),
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

private let codeExamplesContent = """
# Hummingbird 2.x Production-Grade Code Examples

Comprehensive examples demonstrating clean architecture patterns, dependency injection, error handling, and production-ready implementations.

---

## Table of Contents

1. [Controller Layer](#controller-layer)
2. [Service Layer](#service-layer)
3. [Repository Layer](#repository-layer)
4. [Middleware](#middleware)
5. [Dependency Injection](#dependency-injection)
6. [Error Handling](#error-handling)
7. [Request Context](#request-context)
8. [Application Setup](#application-setup)

---

## Controller Layer

Controllers decode HTTP requests, dispatch to services, and encode responses. They should contain NO business logic.

### Example: User Controller

```swift
// Sources/App/Controllers/UserController.swift

import Hummingbird
import Foundation

struct UserController {

    /// Registers all user-related routes on the router
    func registerRoutes(on router: Router<AppRequestContext>) {
        router.group("/users")
            .get(use: listUsers)
            .post(use: createUser)
            .get("/:id", use: getUser)
            .put("/:id", use: updateUser)
            .delete("/:id", use: deleteUser)
    }

    // MARK: - Route Handlers

    /// GET /users — List all users with optional filtering
    @Sendable
    func listUsers(_ request: Request, context: AppRequestContext) async throws -> Response {
        // Extract query parameters (if any)
        let limit = request.uri.queryParameters.get("limit").flatMap(Int.init) ?? 20
        let offset = request.uri.queryParameters.get("offset").flatMap(Int.init) ?? 0

        // Dispatch to service layer
        let users = try await context.dependencies.userService.listUsers(
            limit: limit,
            offset: offset
        )

        // Encode response
        let dto = users.map { UserDTO(from: $0) }
        return try await Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(asyncSequence: JSONEncoder().encodeAsyncSequence(dto))
        )
    }

    /// POST /users — Create a new user
    @Sendable
    func createUser(_ request: Request, context: AppRequestContext) async throws -> Response {
        // Decode request body
        guard let body = request.body.buffer else {
            throw HTTPError(.badRequest, message: "Request body required")
        }

        let dto = try JSONDecoder().decode(CreateUserRequest.self, from: body)

        // Dispatch to service layer
        do {
            let user = try await context.dependencies.userService.createUser(
                name: dto.name,
                email: dto.email
            )

            // Encode response
            let responseDTO = UserDTO(from: user)
            return try await Response(
                status: .created,
                headers: [
                    .contentType: "application/json",
                    .location: "/users/\\(user.id)"
                ],
                body: .init(asyncSequence: JSONEncoder().encodeAsyncSequence(responseDTO))
            )

        } catch let error as AppError {
            // Convert domain errors to HTTP errors
            switch error {
            case .validation(let message):
                throw HTTPError(.badRequest, message: message)
            case .duplicateEntry(let field):
                throw HTTPError(.conflict, message: "\\(field) already exists")
            default:
                throw HTTPError(.internalServerError, message: "Failed to create user")
            }
        }
    }

    /// GET /users/:id — Get a specific user by ID
    @Sendable
    func getUser(_ request: Request, context: AppRequestContext) async throws -> Response {
        // Extract path parameter
        guard let id = context.parameters.get("id", as: String.self) else {
            throw HTTPError(.badRequest, message: "Missing user ID")
        }

        // Dispatch to service layer
        do {
            let user = try await context.dependencies.userService.getUser(id: id)

            // Encode response
            let dto = UserDTO(from: user)
            return try await Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(asyncSequence: JSONEncoder().encodeAsyncSequence(dto))
            )

        } catch AppError.notFound {
            throw HTTPError(.notFound, message: "User not found")
        }
    }

    /// PUT /users/:id — Update an existing user
    @Sendable
    func updateUser(_ request: Request, context: AppRequestContext) async throws -> Response {
        guard let id = context.parameters.get("id", as: String.self) else {
            throw HTTPError(.badRequest, message: "Missing user ID")
        }

        guard let body = request.body.buffer else {
            throw HTTPError(.badRequest, message: "Request body required")
        }

        let dto = try JSONDecoder().decode(UpdateUserRequest.self, from: body)

        do {
            let user = try await context.dependencies.userService.updateUser(
                id: id,
                name: dto.name,
                email: dto.email
            )

            let responseDTO = UserDTO(from: user)
            return try await Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(asyncSequence: JSONEncoder().encodeAsyncSequence(responseDTO))
            )

        } catch AppError.notFound {
            throw HTTPError(.notFound, message: "User not found")
        } catch AppError.validation(let message) {
            throw HTTPError(.badRequest, message: message)
        }
    }

    /// DELETE /users/:id — Delete a user
    @Sendable
    func deleteUser(_ request: Request, context: AppRequestContext) async throws -> Response {
        guard let id = context.parameters.get("id", as: String.self) else {
            throw HTTPError(.badRequest, message: "Missing user ID")
        }

        do {
            try await context.dependencies.userService.deleteUser(id: id)
            return Response(status: .noContent)

        } catch AppError.notFound {
            throw HTTPError(.notFound, message: "User not found")
        }
    }
}

// MARK: - DTOs (Data Transfer Objects)

/// Request DTO for creating a user
struct CreateUserRequest: Codable {
    let name: String
    let email: String
}

/// Request DTO for updating a user
struct UpdateUserRequest: Codable {
    let name: String?
    let email: String?
}

/// Response DTO for user data
struct UserDTO: Codable {
    let id: String
    let name: String
    let email: String
    let createdAt: Date

    init(from user: User) {
        self.id = user.id
        self.name = user.name
        self.email = user.email
        self.createdAt = user.createdAt
    }
}
```

**Key Patterns:**
- ✅ All handlers are `@Sendable` and `async`
- ✅ Controllers only handle HTTP concerns (decode, encode, status codes)
- ✅ Business logic delegated to service layer
- ✅ Domain errors converted to HTTP errors
- ✅ DTOs separate external API from internal models
- ✅ No service construction — uses `context.dependencies`

---

## Service Layer

Services contain business logic, validation, and orchestration. They should NOT import Hummingbird.

### Example: User Service

```swift
// Sources/App/Services/UserService.swift

import Foundation

/// Business logic for user management
protocol UserServiceProtocol: Sendable {
    func listUsers(limit: Int, offset: Int) async throws -> [User]
    func getUser(id: String) async throws -> User
    func createUser(name: String, email: String) async throws -> User
    func updateUser(id: String, name: String?, email: String?) async throws -> User
    func deleteUser(id: String) async throws
}

/// Production implementation of UserService
struct UserService: UserServiceProtocol {

    private let repository: UserRepositoryProtocol
    private let emailValidator: EmailValidatorProtocol

    init(repository: UserRepositoryProtocol, emailValidator: EmailValidatorProtocol) {
        self.repository = repository
        self.emailValidator = emailValidator
    }

    // MARK: - Public API

    func listUsers(limit: Int, offset: Int) async throws -> [User] {
        // Validate pagination parameters
        guard limit > 0 && limit <= 100 else {
            throw AppError.validation("Limit must be between 1 and 100")
        }
        guard offset >= 0 else {
            throw AppError.validation("Offset must be non-negative")
        }

        // Delegate to repository
        return try await repository.findAll(limit: limit, offset: offset)
    }

    func getUser(id: String) async throws -> User {
        // Validate ID format
        guard !id.isEmpty else {
            throw AppError.validation("User ID cannot be empty")
        }

        // Fetch from repository
        guard let user = try await repository.findById(id) else {
            throw AppError.notFound(entity: "User", id: id)
        }

        return user
    }

    func createUser(name: String, email: String) async throws -> User {
        // Validate inputs
        try validateName(name)
        try validateEmail(email)

        // Check for duplicate email
        if try await repository.existsByEmail(email) {
            throw AppError.duplicateEntry(field: "email")
        }

        // Create user entity
        let user = User(
            id: UUID().uuidString,
            name: name,
            email: email,
            createdAt: Date()
        )

        // Persist to repository
        try await repository.save(user)

        return user
    }

    func updateUser(id: String, name: String?, email: String?) async throws -> User {
        // Fetch existing user
        guard var user = try await repository.findById(id) else {
            throw AppError.notFound(entity: "User", id: id)
        }

        // Update fields if provided
        if let newName = name {
            try validateName(newName)
            user.name = newName
        }

        if let newEmail = email {
            try validateEmail(newEmail)

            // Check for duplicate email (excluding current user)
            if newEmail != user.email && (try await repository.existsByEmail(newEmail)) {
                throw AppError.duplicateEntry(field: "email")
            }

            user.email = newEmail
        }

        // Persist changes
        try await repository.update(user)

        return user
    }

    func deleteUser(id: String) async throws {
        // Check if user exists
        guard try await repository.findById(id) != nil else {
            throw AppError.notFound(entity: "User", id: id)
        }

        // Delete from repository
        try await repository.delete(id: id)
    }

    // MARK: - Private Validation

    private func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AppError.validation("Name cannot be empty")
        }
        guard name.count <= 100 else {
            throw AppError.validation("Name cannot exceed 100 characters")
        }
    }

    private func validateEmail(_ email: String) throws {
        guard emailValidator.isValid(email) else {
            throw AppError.validation("Invalid email format")
        }
    }
}

// MARK: - Email Validator

protocol EmailValidatorProtocol: Sendable {
    func isValid(_ email: String) -> Bool
}

struct EmailValidator: EmailValidatorProtocol {
    func isValid(_ email: String) -> Bool {
        let emailRegex = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\\\.[A-Z]{2,}$"
        let predicate = NSPredicate(format: "SELF MATCHES[c] %@", emailRegex)
        return predicate.evaluate(with: email)
    }
}
```

**Key Patterns:**
- ✅ Protocol-based design for testability
- ✅ All dependencies injected via constructor
- ✅ NO Hummingbird imports (only Foundation and domain types)
- ✅ Comprehensive input validation
- ✅ Throws `AppError` (not HTTPError)
- ✅ Single Responsibility Principle — each method does one thing

---

## Repository Layer

Repositories handle data persistence. They should NOT contain business logic.

### Example: User Repository

```swift
// Sources/App/Repositories/UserRepository.swift

import Foundation

/// Protocol for user data persistence
protocol UserRepositoryProtocol: Sendable {
    func findAll(limit: Int, offset: Int) async throws -> [User]
    func findById(_ id: String) async throws -> User?
    func existsByEmail(_ email: String) async throws -> Bool
    func save(_ user: User) async throws
    func update(_ user: User) async throws
    func delete(id: String) async throws
}

/// In-memory implementation for development/testing
actor InMemoryUserRepository: UserRepositoryProtocol {

    private var users: [String: User] = [:]

    func findAll(limit: Int, offset: Int) async throws -> [User] {
        let sorted = users.values.sorted { $0.createdAt < $1.createdAt }
        let start = min(offset, sorted.count)
        let end = min(offset + limit, sorted.count)
        return Array(sorted[start..<end])
    }

    func findById(_ id: String) async throws -> User? {
        return users[id]
    }

    func existsByEmail(_ email: String) async throws -> Bool {
        return users.values.contains { $0.email == email }
    }

    func save(_ user: User) async throws {
        users[user.id] = user
    }

    func update(_ user: User) async throws {
        guard users[user.id] != nil else {
            throw AppError.notFound(entity: "User", id: user.id)
        }
        users[user.id] = user
    }

    func delete(id: String) async throws {
        guard users.removeValue(forKey: id) != nil else {
            throw AppError.notFound(entity: "User", id: id)
        }
    }
}

/// PostgreSQL implementation (example with PostgresNIO)
/// Uncomment if using a real database driver
/*
import PostgresNIO

actor PostgresUserRepository: UserRepositoryProtocol {

    private let pool: PostgresConnection.Pool

    init(pool: PostgresConnection.Pool) {
        self.pool = pool
    }

    func findAll(limit: Int, offset: Int) async throws -> [User] {
        let query = "SELECT id, name, email, created_at FROM users ORDER BY created_at LIMIT $1 OFFSET $2"

        do {
            let rows = try await pool.query(query, [limit, offset])
            return try rows.map { row in
                try User(
                    id: row.decode(column: "id", as: String.self),
                    name: row.decode(column: "name", as: String.self),
                    email: row.decode(column: "email", as: String.self),
                    createdAt: row.decode(column: "created_at", as: Date.self)
                )
            }
        } catch {
            throw AppError.databaseError(underlying: error)
        }
    }

    func findById(_ id: String) async throws -> User? {
        let query = "SELECT id, name, email, created_at FROM users WHERE id = $1"

        do {
            guard let row = try await pool.query(query, [id]).first else {
                return nil
            }

            return try User(
                id: row.decode(column: "id", as: String.self),
                name: row.decode(column: "name", as: String.self),
                email: row.decode(column: "email", as: String.self),
                createdAt: row.decode(column: "created_at", as: Date.self)
            )
        } catch {
            throw AppError.databaseError(underlying: error)
        }
    }

    func existsByEmail(_ email: String) async throws -> Bool {
        let query = "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)"

        do {
            let result = try await pool.query(query, [email])
            return try result.first?.decode(column: 0, as: Bool.self) ?? false
        } catch {
            throw AppError.databaseError(underlying: error)
        }
    }

    func save(_ user: User) async throws {
        let query = "INSERT INTO users (id, name, email, created_at) VALUES ($1, $2, $3, $4)"

        do {
            try await pool.query(query, [user.id, user.name, user.email, user.createdAt])
        } catch {
            throw AppError.databaseError(underlying: error)
        }
    }

    func update(_ user: User) async throws {
        let query = "UPDATE users SET name = $1, email = $2 WHERE id = $3"

        do {
            try await pool.query(query, [user.name, user.email, user.id])
        } catch {
            throw AppError.databaseError(underlying: error)
        }
    }

    func delete(id: String) async throws {
        let query = "DELETE FROM users WHERE id = $1"

        do {
            try await pool.query(query, [id])
        } catch {
            throw AppError.databaseError(underlying: error)
        }
    }
}
*/
```

**Key Patterns:**
- ✅ Protocol-based for swappable implementations
- ✅ Actor-based for thread-safe shared state
- ✅ NO business logic — pure data access
- ✅ Third-party errors wrapped in `AppError`
- ✅ All methods are `async` for consistency

---

## Middleware

Middleware handles cross-cutting concerns like authentication, logging, and rate limiting.

### Example: Authentication Middleware

```swift
// Sources/App/Middleware/AuthMiddleware.swift

import Hummingbird

/// Validates authentication tokens on incoming requests
struct AuthMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    private let token: String

    init(token: String) {
        self.token = token
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {

        // Extract Authorization header
        guard let authHeader = request.headers[.authorization] else {
            throw HTTPError(.unauthorized, message: "Missing Authorization header")
        }

        // Validate Bearer token format
        let prefix = "Bearer "
        guard authHeader.hasPrefix(prefix) else {
            throw HTTPError(.unauthorized, message: "Invalid Authorization format")
        }

        let providedToken = String(authHeader.dropFirst(prefix.count))

        // Validate token value
        guard providedToken == token else {
            throw HTTPError(.unauthorized, message: "Invalid authentication token")
        }

        // Token valid — proceed to next handler
        return try await next(request, context)
    }
}
```

### Example: Rate Limiting Middleware

```swift
// Sources/App/Middleware/RateLimitMiddleware.swift

import Hummingbird
import Foundation

/// Rate limits requests per client IP address
actor RateLimitMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    private let requestsPerMinute: Int
    private var clientRequests: [String: [Date]] = [:]

    init(requestsPerMinute: Int) {
        self.requestsPerMinute = requestsPerMinute
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {

        // Extract client IP (simplified — production should use X-Forwarded-For)
        let clientIP = request.headers[.forwarded] ?? "unknown"

        // Get current timestamp
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)

        // Clean up old requests and count recent ones
        var timestamps = clientRequests[clientIP] ?? []
        timestamps = timestamps.filter { $0 > oneMinuteAgo }

        // Check rate limit
        if timestamps.count >= requestsPerMinute {
            throw HTTPError(
                .tooManyRequests,
                headers: [.retryAfter: "60"],
                message: "Rate limit exceeded"
            )
        }

        // Record this request
        timestamps.append(now)
        clientRequests[clientIP] = timestamps

        // Proceed to next handler
        return try await next(request, context)
    }
}
```

### Example: Request Logging Middleware

```swift
// Sources/App/Middleware/RequestLoggingMiddleware.swift

import Hummingbird
import Logging

/// Logs all HTTP requests and responses
struct RequestLoggingMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    private let logger = Logger(label: "com.app.requests")

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {

        let startTime = Date()

        // Log incoming request
        logger.info(
            "→ \\(request.method) \\(request.uri.path)",
            metadata: [
                "method": "\\(request.method)",
                "path": "\\(request.uri.path)",
                "query": "\\(request.uri.query ?? "")",
            ]
        )

        do {
            // Execute request
            let response = try await next(request, context)

            // Log successful response
            let duration = Date().timeIntervalSince(startTime)
            logger.info(
                "← \\(response.status.code) \\(request.method) \\(request.uri.path)",
                metadata: [
                    "status": "\\(response.status.code)",
                    "duration_ms": "\\(Int(duration * 1000))",
                ]
            )

            return response

        } catch {
            // Log error response
            let duration = Date().timeIntervalSince(startTime)
            logger.error(
                "← ERROR \\(request.method) \\(request.uri.path)",
                metadata: [
                    "error": "\\(error)",
                    "duration_ms": "\\(Int(duration * 1000))",
                ]
            )
            throw error
        }
    }
}
```

**Key Patterns:**
- ✅ Conforms to `RouterMiddleware` with `typealias Context = AppRequestContext`
- ✅ Actor-based for stateful middleware (rate limiting)
- ✅ Struct-based for stateless middleware (auth, logging)
- ✅ Always calls `next()` to continue the middleware chain
- ✅ Can throw `HTTPError` to short-circuit the chain

---

## Dependency Injection

All dependencies are constructed once and injected via `AppRequestContext`.

### Example: AppDependencies

```swift
// Sources/App/AppDependencies.swift

import Foundation

/// Container for all application dependencies
struct AppDependencies: Sendable {
    let userService: UserServiceProtocol
    let userRepository: UserRepositoryProtocol
    let emailValidator: EmailValidatorProtocol

    /// Production initializer with real implementations
    static func production() async throws -> AppDependencies {
        // Create leaf dependencies first
        let emailValidator = EmailValidator()
        let userRepository = InMemoryUserRepository()

        // Compose services with their dependencies
        let userService = UserService(
            repository: userRepository,
            emailValidator: emailValidator
        )

        return AppDependencies(
            userService: userService,
            userRepository: userRepository,
            emailValidator: emailValidator
        )
    }

    /// Test initializer with mock implementations
    static func test(
        userService: UserServiceProtocol? = nil,
        userRepository: UserRepositoryProtocol? = nil,
        emailValidator: EmailValidatorProtocol? = nil
    ) async throws -> AppDependencies {

        let emailValidator = emailValidator ?? EmailValidator()
        let userRepository = userRepository ?? InMemoryUserRepository()
        let userService = userService ?? UserService(
            repository: userRepository,
            emailValidator: emailValidator
        )

        return AppDependencies(
            userService: userService,
            userRepository: userRepository,
            emailValidator: emailValidator
        )
    }
}
```

### Example: DependencyInjectionMiddleware

```swift
// Sources/App/Middleware/DependencyInjectionMiddleware.swift

import Hummingbird

/// Copies dependencies into every request context
struct DependencyInjectionMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {

        // Copy dependencies into context
        var context = context
        context.dependencies = dependencies

        // Proceed with updated context
        return try await next(request, context)
    }
}
```

**Key Patterns:**
- ✅ All dependencies constructed ONCE at application startup
- ✅ Middleware copies into every request context
- ✅ Handlers NEVER construct services inline
- ✅ Static factory methods for production and test configurations

---

## Error Handling

Domain errors in services, HTTP errors in controllers.

### Example: AppError

```swift
// Sources/App/AppError.swift

import Foundation

/// Application-wide error type for domain logic
enum AppError: Error, CustomStringConvertible {
    case validation(String)
    case notFound(entity: String, id: String)
    case duplicateEntry(field: String)
    case databaseError(underlying: Error)
    case resourceNotFound(uri: String)
    case unauthorized
    case internalError(String)

    var description: String {
        switch self {
        case .validation(let message):
            return "Validation error: \\(message)"
        case .notFound(let entity, let id):
            return "\\(entity) with ID '\\(id)' not found"
        case .duplicateEntry(let field):
            return "Duplicate entry for field '\\(field)'"
        case .databaseError(let error):
            return "Database error: \\(error.localizedDescription)"
        case .resourceNotFound(let uri):
            return "Resource not found: \\(uri)"
        case .unauthorized:
            return "Unauthorized access"
        case .internalError(let message):
            return "Internal error: \\(message)"
        }
    }
}
```

**Usage Pattern:**
- Services throw `AppError`
- Controllers catch `AppError` and convert to `HTTPError`
- Never let third-party errors propagate unwrapped

---

## Request Context

Custom request context carries dependencies and metadata.

### Example: AppRequestContext

```swift
// Sources/App/AppRequestContext.swift

import Hummingbird

/// Request context with dependencies and metadata
struct AppRequestContext: RequestContext {
    var coreContext: CoreRequestContext
    var dependencies: AppDependencies

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.dependencies = AppDependencies.production()  // Will be replaced by middleware
    }
}
```

**Key Patterns:**
- ✅ Conforms to `RequestContext`
- ✅ Contains `CoreRequestContext` for framework internals
- ✅ Contains `dependencies` for application services
- ✅ Can be extended with additional metadata (user ID, request ID, etc.)

---

## Application Setup

The composition root where everything is wired together.

### Example: Application+build.swift

```swift
// Sources/App/Application+build.swift

import Hummingbird
import Logging

func buildApplication(configuration: AppConfiguration) async throws -> some ApplicationProtocol {

    let logger = Logger(label: "com.app.main")

    // ── Dependencies ──────────────────────────────────────────────────────────
    let dependencies = try await AppDependencies.production()
    logger.info("Dependencies initialized")

    // ── Router ────────────────────────────────────────────────────────────────
    let router = Router(context: AppRequestContext.self)

    // Middleware — MUST be registered BEFORE routes
    router.add(middleware: DependencyInjectionMiddleware(dependencies: dependencies))
    router.add(middleware: RequestLoggingMiddleware())

    if let token = configuration.authToken {
        router.add(middleware: AuthMiddleware(token: token))
    }

    if let limit = configuration.rateLimitPerMinute {
        router.add(middleware: RateLimitMiddleware(requestsPerMinute: limit))
    }

    // Health check endpoints
    router.get("/health") { _, _ in
        ["status": "ok"]
    }

    // Register controllers
    UserController().registerRoutes(on: router)

    // ── Application ───────────────────────────────────────────────────────────
    var app = Application(
        router: router,
        configuration: .init(
            address: .hostname(configuration.host, port: configuration.port),
            serverName: "my-app/1.0.0"
        )
    )

    logger.info("Application built", metadata: [
        "host": "\\(configuration.host)",
        "port": "\\(configuration.port)",
    ])

    return app
}
```

**Key Patterns:**
- ✅ Dependencies constructed first
- ✅ Middleware registered BEFORE routes
- ✅ Controllers registered with `registerRoutes()`
- ✅ Clean separation of concerns
- ✅ Comprehensive logging

---

## Summary

**Production-Ready Checklist:**

1. **Controller Layer**
   - ✅ No business logic
   - ✅ All handlers are `@Sendable` and `async`
   - ✅ Convert `AppError` to `HTTPError`
   - ✅ Use DTOs for request/response

2. **Service Layer**
   - ✅ Protocol-based design
   - ✅ All dependencies injected
   - ✅ NO Hummingbird imports
   - ✅ Throw `AppError`, not `HTTPError`

3. **Repository Layer**
   - ✅ Actor-based for thread safety
   - ✅ No business logic
   - ✅ Wrap third-party errors

4. **Middleware**
   - ✅ Registered BEFORE routes
   - ✅ Use actors for stateful middleware
   - ✅ Always call `next()`

5. **Dependency Injection**
   - ✅ Construct dependencies ONCE
   - ✅ Inject via `AppRequestContext.dependencies`
   - ✅ Never construct services inline

6. **Error Handling**
   - ✅ Domain errors in services (`AppError`)
   - ✅ HTTP errors in controllers (`HTTPError`)
   - ✅ Never let unwrapped errors propagate

7. **Concurrency**
   - ✅ Use actors for shared mutable state
   - ✅ All handlers are `async`
   - ✅ Structured concurrency (no unstructured `Task {}`)

---

**These patterns ensure:**
- Clean architecture with clear layer separation
- Testability through protocol-based design
- Thread safety through actors and Sendable
- Production-grade error handling
- Maintainable and scalable codebase
"""
