# Clean Architecture

[← Pitfalls Reference](pitfalls.md) | [Home](index.md) | [Next: MCP Server →](mcp-server.md)

---

## 19. Clean Architecture

### The Core Problem with Tutorial Code

Every Hummingbird tutorial shows this pattern:

```swift
// ❌ Tutorial architecture — everything inline
router.post("/users") { request, context in
    let body = try await request.body.collect(upTo: 1024 * 1024)
    var user = try JSONDecoder().decode(User.self, from: body)
    user.passwordHash = try SHA256.hash(user.password)  // wrong hash, wrong layer
    try await context.db.query("INSERT INTO users ...")
    return user  // returning domain model directly — exposes internal fields
}
```

This has no separation of concerns, no testability, no reusability, and hidden data races.

### The Layer Model

```
┌─────────────────────────────────────────────────────────┐
│                    Transport Layer                       │
│         Router (Hummingbird) — pure HTTP wiring          │
├─────────────────────────────────────────────────────────┤
│                   Controller Layer                       │
│    Input parsing · orchestration · response mapping     │
├─────────────────────────────────────────────────────────┤
│                    Service Layer                         │
│   Business rules · domain logic · no framework imports  │
├─────────────────────────────────────────────────────────┤
│                  Repository Layer                        │
│         Persistence abstraction · query isolation        │
├─────────────────────────────────────────────────────────┤
│                 Infrastructure Layer                     │
│       Database drivers · HTTP clients · file system      │
└─────────────────────────────────────────────────────────┘
```

**Non-negotiable layer rules:**

| File is in | May import | Must NOT import |
|---|---|---|
| Controller | `Hummingbird`, DTOs, Domain | DB drivers, `MCP` |
| Service | `Foundation`, `Logging`, Domain | `Hummingbird`, DB drivers |
| Repository | `Foundation`, DB driver, Domain | `Hummingbird`, Service |
| Domain | `Foundation` | Everything else |

### Flow for a Typical Request

```
POST /users
    │
    ▼
UserController.create
    ├─ Decode CreateUserInput (DTO)
    ├─ input.validate()              ← input validation, no I/O
    └─ userService.create(input)     ← delegate to service
            ├─ repo.find(email)      ← uniqueness check
            ├─ Bcrypt.hash           ← password hashing
            ├─ repo.insert(user)     ← persistence
            └─ return User
    │
    ▼
EditedResponse(.created, UserResponse(user))    ← DTO mapping at controller boundary
```

The controller never touches the database. The service never touches HTTP. The repository never enforces business rules.

---

## 20. Dependency Injection via RequestContext

`RequestContext` is Hummingbird's per-request state carrier. It is also the correct DI container for the entire application.

### The Context Type

```swift
// Sources/App/Context/AppRequestContext.swift

struct AppRequestContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    var dependencies: AppDependencies   // injected by DependencyInjectionMiddleware

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.dependencies = .placeholder   // replaced before any handler runs
    }

    var logger: Logger { coreContext.logger }
}
```

### The Dependency Container

```swift
// Sources/App/Context/AppDependencies.swift

struct AppDependencies: Sendable {
    let userService: any UserServiceProtocol
    let authService: any AuthServiceProtocol
    let emailService: any EmailServiceProtocol

    /// Crashes loudly if accessed before injection is complete.
    /// This ensures misconfiguration fails at startup, not silently at runtime.
    static let placeholder = AppDependencies(
        userService: _PlaceholderCrash(),
        authService: _PlaceholderCrash(),
        emailService: _PlaceholderCrash()
    )
}
```

### The Injection Middleware

```swift
// Sources/App/Middleware/DependencyInjectionMiddleware.swift

struct DependencyInjectionMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func handle(_ request: Request, context: AppRequestContext, next: ...) async throws -> Response {
        var enriched = context
        enriched.dependencies = dependencies
        return try await next(request, enriched)
    }
}
```

### Accessing Dependencies in Handlers

```swift
// In any route handler or downstream middleware:
let user = try await context.dependencies.userService.get(id: id)
```

No singletons. No global state. No service construction at call sites.

---

## 21. The Controller Pattern

Controllers are structs that own a group of related route handlers. They register their own routes, parse input, delegate to services, and map results to responses.

### Controller Protocol

```swift
protocol Controller {
    func registerRoutes(on group: RouterGroup<AppRequestContext>)
}
```

### A Production Controller

```swift
struct UserController: Controller {

    func registerRoutes(on group: RouterGroup<AppRequestContext>) {
        group.get(use: list)
        group.post(use: create)
        group.group(":userID") {
            $0.get(use: get)
            $0.put(use: update)
            $0.delete(use: delete)
        }
    }

    @Sendable
    private func create(_ request: Request, context: AppRequestContext) async throws -> EditedResponse<UserResponse> {
        let input = try await request.decode(as: CreateUserInput.self, context: context)
        try input.validate()
        let user = try await context.dependencies.userService.create(input: input)
        return EditedResponse(status: .created, response: UserResponse(user))
    }

    @Sendable
    private func get(_ request: Request, context: AppRequestContext) async throws -> UserResponse {
        let id = try context.parameters.require("userID", as: UUID.self)
        let user = try await context.dependencies.userService.get(id: id)
        return UserResponse(user)
    }
}
```

### DTOs — Input and Response Types

```swift
// Input DTO — decodes HTTP input, validates at the boundary
struct CreateUserInput: Decodable {
    let name: String
    let email: String
    let password: String

    func validate() throws {
        guard name.count >= 2 else { throw AppError.validation("Name too short") }
        guard email.contains("@") else { throw AppError.validation("Invalid email") }
        guard password.count >= 12 else { throw AppError.validation("Password too short") }
    }
}

// Response DTO — never exposes internal fields
struct UserResponse: Encodable, ResponseGenerator {
    let id: UUID
    let name: String
    let email: String
    let createdAt: Date

    // passwordHash, internalFlags, auditFields — never present here
    init(_ user: User) {
        self.id = user.id
        self.name = user.name
        self.email = user.email
        self.createdAt = user.createdAt
    }
}
```

---

## 22. Service Layer

Services contain all business logic. Zero framework imports. Testable without HTTP and without a database.

### Protocol First

```swift
// Sources/App/Services/UserServiceProtocol.swift
protocol UserServiceProtocol: Sendable {
    func list(query: ListUsersQuery) async throws -> [User]
    func get(id: UUID) async throws -> User
    func create(input: CreateUserInput) async throws -> User
    func update(id: UUID, input: UpdateUserInput) async throws -> User
    func delete(id: UUID) async throws
}
```

### Implementation

```swift
// Sources/App/Services/UserService.swift
// Note: NO import Hummingbird
import Foundation
import Logging
import HummingbirdBcrypt

actor UserService: UserServiceProtocol {
    private let repository: any UserRepositoryProtocol

    func create(input: CreateUserInput) async throws -> User {
        // Business rule enforced here — not in the controller, not in the repository
        guard try await repository.find(email: input.email) == nil else {
            throw AppError.conflict("Email address is already registered")
        }

        let hash = try await Bcrypt.hash(input.password, cost: 12)
        let user = User(id: UUID(), name: input.name, email: input.email.lowercased(), passwordHash: hash)
        try await repository.insert(user)
        return user
    }
}
```

---

## 23. Repository Pattern

Repositories abstract persistence behind protocols. Services depend on the protocol, never on the concrete implementation. This is what makes services unit-testable without a database.

### Protocol

```swift
// Sources/App/Repositories/UserRepositoryProtocol.swift
protocol UserRepositoryProtocol: Sendable {
    func find(id: UUID) async throws -> User?
    func find(email: String) async throws -> User?
    func insert(_ user: User) async throws
    func update(_ user: User) async throws
    func delete(id: UUID) async throws
}
```

### Postgres Implementation

```swift
// Sources/App/Repositories/PostgresUserRepository.swift
struct PostgresUserRepository: UserRepositoryProtocol {
    private let pool: PostgresClient

    func find(id: UUID) async throws -> User? {
        let rows = try await pool.query(
            "SELECT id, name, email, password_hash, created_at FROM users WHERE id = \(id)",
            logger: .init(label: "UserRepository")
        )
        return try await rows.collect().first.map(User.init(row:))
    }
}
```

### In-Memory Fake (for Tests)

```swift
// Tests/AppTests/Fakes/FakeUserRepository.swift
actor FakeUserRepository: UserRepositoryProtocol {
    private var store: [UUID: User] = [:]

    func seed(_ users: [User]) { for u in users { store[u.id] = u } }
    func find(id: UUID) async throws -> User? { store[id] }
    func find(email: String) async throws -> User? { store.values.first { $0.email == email } }
    func insert(_ user: User) async throws { store[user.id] = user }
    func update(_ user: User) async throws { store[user.id] = user }
    func delete(id: UUID) async throws { store.removeValue(forKey: id) }
}
```

---

## 24. Error Handling Architecture

All errors must be typed. Raw database, networking, or third-party errors must never propagate to callers.

```swift
// Sources/App/Errors/AppError.swift
enum AppError: Error, HTTPResponseError {
    case notFound(String, id: Any? = nil)
    case conflict(String)
    case validation(String)
    case unauthorized(String = "Authentication required")
    case forbidden(String = "Insufficient permissions")
    case internal(String, underlying: (any Error)? = nil)

    var status: HTTPResponse.Status {
        switch self {
        case .notFound:     return .notFound
        case .conflict:     return .conflict
        case .validation:   return .badRequest
        case .unauthorized: return .unauthorized
        case .forbidden:    return .forbidden
        case .internal:     return .internalServerError
        }
    }

    func body(allocator: ByteBufferAllocator) -> ByteBuffer? {
        let message: String
        switch self {
        case .notFound(let msg, _):   message = msg
        case .conflict(let msg):      message = msg
        case .validation(let msg):    message = msg
        case .unauthorized(let msg):  message = msg
        case .forbidden(let msg):     message = msg
        case .internal:               message = "An internal error occurred"
        // never expose underlying errors to callers
        }
        return allocator.buffer(string: #"{"error":"\#(message)","status":\#(status.code)}"#)
    }
}
```

**Wrapping at the repository boundary:**

```swift
func insert(_ user: User) async throws {
    do {
        try await pool.query("INSERT INTO users ...")
    } catch {
        throw AppError.internal("Failed to insert user", underlying: error)
    }
}
```

---

[← Pitfalls Reference](pitfalls.md) | [Home](index.md) | [Next: MCP Server →](mcp-server.md)
