// Sources/HummingbirdKnowledgeServer/KnowledgeBase/ArchitecturalViolations.swift
//
// The anti-tutorial rule catalogue.
// Each violation has a regex pattern matched against user-submitted source code.
// Critical violations block code generation entirely.

import Foundation

/// A concrete code-level fix suggestion showing before/after examples.
struct FixSuggestion: Sendable, Codable {
    let before: String          // The anti-pattern code example
    let after: String           // The corrected code example
    let explanation: String     // Why the fix is necessary and how it works
}

/// A rule that identifies an architectural anti-pattern in Hummingbird 2.x code.
struct ArchitecturalViolation: Sendable {
    let id: String
    let pattern: String         // Regex matched against source code
    let description: String
    let correctionId: String    // Knowledge base entry ID for the fix
    let severity: Severity
    let fixSuggestion: FixSuggestion?

    init(
        id: String,
        pattern: String,
        description: String,
        correctionId: String,
        severity: Severity,
        fixSuggestion: FixSuggestion? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.description = description
        self.correctionId = correctionId
        self.severity = severity
        self.fixSuggestion = fixSuggestion
    }

    enum Severity: Sendable {
        case warning    // Suboptimal but not incorrect
        case error      // Wrong — will cause problems
        case critical   // Blocks code generation entirely
    }
}

/// The complete catalogue of known Hummingbird 2.x architectural violations.
/// Loaded at startup; matched against every code snippet submitted to the server.
enum ArchitecturalViolations {

    static let all: [ArchitecturalViolation] = [

        // ── Critical: blocks code generation ──────────────────────────────────

        ArchitecturalViolation(
            id: "inline-db-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.query|pool\.|db\.)"#,
            description: "Database calls inside a route handler closure. "
                + "Route handlers must be pure dispatchers — all DB access belongs "
                + "in the repository layer, called via the service layer.",
            correctionId: "route-handler-dispatcher-only",
            severity: .critical,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — database call in handler
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)
                        guard !dto.email.isEmpty else { throw HTTPError(.badRequest) }
                        let hashed = BCrypt.hash(dto.password)
                        let user = User(email: dto.email, passwordHash: hashed)
                        try await db.save(user)  // Direct DB access!
                        return user
                    }
                    """,
                after: """
                    // ✅ Correct — pure dispatcher
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)
                        let user = try await context.dependencies.userService.create(dto)
                        return CreateUserResponse(user)
                    }
                    """,
                explanation: "Route handlers have exactly one job: dispatch to the service layer and return the result. "
                    + "They must not contain business logic, database calls, or service construction. "
                    + "This keeps handlers thin, testable, and framework-agnostic. All database access must go through "
                    + "the repository layer, which is called by the service layer, which is called by the handler."
            )
        ),

        ArchitecturalViolation(
            id: "service-construction-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*\w+Service\s*\("#,
            description: "Service constructed inline inside a route handler. "
                + "Services must be injected via AppRequestContext — never constructed "
                + "per-request inside a handler closure.",
            correctionId: "dependency-injection-via-context",
            severity: .critical,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — service constructed inline
                    router.get("/users/:id") { request, context in
                        let repo = PostgresUserRepository(pool: globalPool)
                        let service = UserService(repository: repo)  // Constructed per request!
                        let id = try context.parameters.require("id")
                        return try await service.find(id: id)
                    }
                    """,
                after: """
                    // ✅ Correct — service from AppRequestContext
                    router.get("/users/:id") { request, context in
                        let id = try context.parameters.require("id")
                        return try await context.dependencies.userService.find(id: id)
                    }
                    """,
                explanation: "All dependencies (services, repositories, stores) must be accessed through "
                    + "AppRequestContext.dependencies. This gives you a single, testable, type-safe injection point. "
                    + "Constructing services inside handlers creates coupling, makes testing impossible, and wastes "
                    + "resources by reconstructing dependencies on every request. DependencyInjectionMiddleware "
                    + "populates context.dependencies at the start of every request with pre-configured instances."
            )
        ),

        // ── Error: wrong architecture ─────────────────────────────────────────

        ArchitecturalViolation(
            id: "hummingbird-import-in-service",
            pattern: #"^import\s+Hummingbird"#,
            description: "Hummingbird imported in a file under Services/ or Repositories/. "
                + "The service layer must be framework-agnostic. "
                + "Only controllers, middleware, and Application+build.swift may import Hummingbird.",
            correctionId: "service-layer-no-hummingbird",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — Hummingbird leaked into service layer
                    import Hummingbird

                    struct UserService {
                        func create(_ req: Request) async throws -> Response {
                            let dto = try await req.decode(as: CreateUserRequest.self, context: context)
                            let user = User(email: dto.email)
                            try await repository.insert(user)
                            return Response(status: .created, body: ...)
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — pure Swift service
                    import Foundation

                    struct UserService {
                        let repository: any UserRepositoryProtocol

                        func create(_ request: CreateUserRequest) async throws -> User {
                            guard !request.email.isEmpty else {
                                throw AppError.invalidInput(reason: "Email must not be empty")
                            }
                            return try await repository.insert(User(email: request.email))
                        }
                    }
                    """,
                explanation: "The service layer encodes business logic independently of any web framework. "
                    + "No Hummingbird import means the service can be tested without an HTTP context and can be "
                    + "reused across transports (HTTP, CLI, background jobs). Services should accept domain types "
                    + "or DTOs as parameters, never Request or Response objects. This keeps your business logic "
                    + "portable and testable."
            )
        ),

        ArchitecturalViolation(
            id: "raw-error-thrown-from-handler",
            pattern: #"throw\s+(?!HTTPError|AppError)\w+Error"#,
            description: "A third-party or raw error is thrown directly from a route handler. "
                + "All errors must be wrapped in AppError before propagating — "
                + "this ensures consistent HTTP responses and prevents leaking internals.",
            correctionId: "typed-errors-app-error",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — raw third-party error thrown
                    router.get("/users/:id") { request, context in
                        let id = try context.parameters.require("id")
                        guard let uuid = UUID(uuidString: id) else {
                            throw ValidationError("Invalid UUID")  // Raw error type!
                        }
                        return try await context.dependencies.userService.find(id: uuid)
                    }
                    """,
                after: """
                    // ✅ Correct — wrapped in AppError
                    router.get("/users/:id") { request, context in
                        let id = try context.parameters.require("id")
                        guard let uuid = UUID(uuidString: id) else {
                            throw AppError.invalidInput(reason: "Invalid UUID format for user ID")
                        }
                        return try await context.dependencies.userService.find(id: uuid)
                    }
                    """,
                explanation: "Raw third-party errors expose internal implementation details and can leak sensitive information "
                    + "to clients. AppError provides a consistent error interface with proper HTTP status code mapping. "
                    + "Wrapping errors at boundaries ensures predictable API responses and prevents internal stack traces "
                    + "from being exposed to end users."
            )
        ),

        ArchitecturalViolation(
            id: "domain-model-across-http-boundary",
            pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*(?!Response|some ResponseGenerator)\w+Model"#,
            description: "A domain model is returned directly from a route handler. "
                + "DTOs must be used at every HTTP boundary — domain models must never "
                + "cross the HTTP layer raw.",
            correctionId: "dtos-at-boundaries",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — domain model returned directly
                    router.get("/users/:id") { request, context in
                        let id = try context.parameters.require("id")
                        let user = try await context.dependencies.userService.find(id: id)
                        return user  // UserModel crosses HTTP boundary!
                    }
                    """,
                after: """
                    // ✅ Correct — DTO at the boundary
                    router.get("/users/:id") { request, context in
                        let id = try context.parameters.require("id")
                        let user = try await context.dependencies.userService.find(id: id)
                        return UserResponse(user)  // Wrapped in DTO
                    }

                    struct UserResponse: Codable, ResponseCodable {
                        let id: String
                        let email: String
                        let createdAt: Date

                        init(_ user: UserModel) {
                            self.id = user.id.uuidString
                            self.email = user.email
                            self.createdAt = user.createdAt
                        }
                    }
                    """,
                explanation: "Domain models contain internal implementation details and can change as your domain evolves. "
                    + "DTOs provide a stable public contract independent of internal model changes. They also let you "
                    + "control exactly what data is exposed (hiding sensitive fields) and how it's formatted (date formats, "
                    + "ID representations, etc.). Always convert domain models to DTOs before returning from route handlers."
            )
        ),

        ArchitecturalViolation(
            id: "domain-entity-across-http-boundary",
            pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*(?!Response|some ResponseGenerator)\w+Entity"#,
            description: "A domain entity is returned directly from a route handler. "
                + "DTOs must be used at every HTTP boundary — domain entities must never "
                + "cross the HTTP layer raw.",
            correctionId: "dtos-at-boundaries",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — domain entity returned directly
                    router.get("/products/:id") { request, context in
                        let id = try context.parameters.require("id")
                        let product = try await context.dependencies.productService.find(id: id)
                        return product  // ProductEntity crosses HTTP boundary!
                    }
                    """,
                after: """
                    // ✅ Correct — DTO at the boundary
                    router.get("/products/:id") { request, context in
                        let id = try context.parameters.require("id")
                        let product = try await context.dependencies.productService.find(id: id)
                        return ProductResponse(product)  // Wrapped in DTO
                    }

                    struct ProductResponse: Codable, ResponseCodable {
                        let id: String
                        let name: String
                        let price: Decimal

                        init(_ entity: ProductEntity) {
                            self.id = entity.id.uuidString
                            self.name = entity.name
                            self.price = entity.price
                        }
                    }
                    """,
                explanation: "Domain entities represent database records and often contain ORM metadata, internal state, "
                    + "and relationships that shouldn't be exposed through the API. DTOs create a clean separation between "
                    + "your internal data model and your public API contract, preventing accidental exposure of internal details "
                    + "and allowing your domain model to evolve without breaking API clients."
            )
        ),

        ArchitecturalViolation(
            id: "domain-model-array-across-http-boundary",
            pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*\[\w+(Model|Entity)\]"#,
            description: "An array of domain models/entities is returned directly from a route handler. "
                + "DTOs must be used at every HTTP boundary — convert domain models to DTOs "
                + "before returning from route handlers.",
            correctionId: "dtos-at-boundaries",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — array of domain models returned directly
                    router.get("/users") { request, context in
                        let users = try await context.dependencies.userService.listAll()
                        return users  // [UserModel] crosses HTTP boundary!
                    }
                    """,
                after: """
                    // ✅ Correct — array mapped to DTOs
                    router.get("/users") { request, context in
                        let users = try await context.dependencies.userService.listAll()
                        return UserListResponse(users: users.map(UserResponse.init))
                    }

                    struct UserListResponse: Codable, ResponseCodable {
                        let users: [UserResponse]
                    }

                    struct UserResponse: Codable, ResponseCodable {
                        let id: String
                        let email: String

                        init(_ user: UserModel) {
                            self.id = user.id.uuidString
                            self.email = user.email
                        }
                    }
                    """,
                explanation: "Returning arrays of domain models directly exposes internal structure and couples your API "
                    + "to your domain model. Always map collections to DTOs using .map(). Consider wrapping arrays in a "
                    + "response object (e.g., UserListResponse) to allow future pagination metadata or other fields without "
                    + "breaking the API contract."
            )
        ),

        ArchitecturalViolation(
            id: "domain-model-in-request-decode",
            pattern: #"request\.decode\(as:\s*\w+(Model|Entity)\.self"#,
            description: "Domain model or entity used in request.decode(). "
                + "DTOs must be used at HTTP boundaries — decode to a DTO, "
                + "then convert to domain model in the service layer.",
            correctionId: "dtos-at-boundaries",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — domain model in request.decode
                    router.post("/users") { request, context in
                        let user = try await request.decode(as: UserModel.self, context: context)
                        return try await context.dependencies.userService.create(user)
                    }
                    """,
                after: """
                    // ✅ Correct — DTO in request.decode
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)
                        let user = try await context.dependencies.userService.create(dto)
                        return CreateUserResponse(user)
                    }

                    struct CreateUserRequest: Decodable {
                        let email: String
                        let password: String

                        init(from decoder: Decoder) throws {
                            let container = try decoder.container(keyedBy: CodingKeys.self)
                            email = try container.decode(String.self, forKey: .email)
                            password = try container.decode(String.self, forKey: .password)

                            guard email.contains("@") else {
                                throw DecodingError.dataCorruptedError(
                                    forKey: .email, in: container,
                                    debugDescription: "Email must be valid"
                                )
                            }
                        }
                    }
                    """,
                explanation: "Decoding directly into domain models bypasses validation and couples your HTTP layer to your "
                    + "domain layer. DTOs let you validate input at the boundary, provide clear API contracts, and keep domain "
                    + "models internal. The DTO's init(from:) method is the perfect place for input validation, rejecting invalid "
                    + "requests before they reach your service layer."
            )
        ),

        ArchitecturalViolation(
            id: "business-logic-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(if\s+\w+\s*[<>=!]+|switch\s+\w+|for\s+\w+\s+in|\.calculate|\.compute|\.process(?!DTO))"#,
            description: "Business logic detected inside a route handler closure. "
                + "Route handlers must be thin dispatchers — all business rules, "
                + "calculations, and processing logic belongs in the service layer.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — business logic in handler
                    router.post("/orders/:id/discount") { request, context in
                        let id = try context.parameters.require("id")
                        let order = try await context.dependencies.orderService.find(id: id)

                        // Business logic in handler!
                        var discountRate = 0.0
                        if order.totalAmount > 1000 {
                            discountRate = 0.15
                        } else if order.totalAmount > 500 {
                            discountRate = 0.10
                        } else if order.totalAmount > 100 {
                            discountRate = 0.05
                        }

                        let discount = order.totalAmount * discountRate
                        return DiscountResponse(discount: discount, rate: discountRate)
                    }
                    """,
                after: """
                    // ✅ Correct — business logic in service layer
                    router.post("/orders/:id/discount") { request, context in
                        let id = try context.parameters.require("id")
                        let discount = try await context.dependencies.orderService.calculateDiscount(orderId: id)
                        return DiscountResponse(discount)
                    }

                    // In OrderService.swift:
                    func calculateDiscount(orderId: String) async throws -> Discount {
                        let order = try await repository.find(id: orderId)

                        let discountRate: Decimal
                        if order.totalAmount > 1000 {
                            discountRate = 0.15
                        } else if order.totalAmount > 500 {
                            discountRate = 0.10
                        } else if order.totalAmount > 100 {
                            discountRate = 0.05
                        } else {
                            discountRate = 0.0
                        }

                        return Discount(amount: order.totalAmount * discountRate, rate: discountRate)
                    }
                    """,
                explanation: "Business rules, calculations, and conditional logic belong in the service layer, not handlers. "
                    + "Handlers that contain business logic become impossible to test without spinning up an HTTP server, "
                    + "can't be reused from other transports, and violate single responsibility. Move all business decisions "
                    + "to services where they can be tested, evolved, and reused independently of HTTP."
            )
        ),

        ArchitecturalViolation(
            id: "validation-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(guard\s+[^}]*(\.isEmpty|\.count|\.contains|!\.)|if\s+[^}]*(\.isEmpty|\.count|\.contains|!\.))"#,
            description: "Validation logic detected inside a route handler closure. "
                + "Input validation must be handled by DTO decoding conformance "
                + "or moved to the service layer — handlers should only dispatch.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — validation in handler
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)

                        // Validation in handler!
                        guard !dto.email.isEmpty else {
                            throw HTTPError(.badRequest, message: "Email required")
                        }
                        guard dto.email.contains("@") else {
                            throw HTTPError(.badRequest, message: "Invalid email")
                        }
                        guard dto.password.count >= 8 else {
                            throw HTTPError(.badRequest, message: "Password too short")
                        }

                        let user = try await context.dependencies.userService.create(dto)
                        return CreateUserResponse(user)
                    }
                    """,
                after: """
                    // ✅ Correct — validation in DTO init(from:)
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)
                        let user = try await context.dependencies.userService.create(dto)
                        return CreateUserResponse(user)
                    }

                    struct CreateUserRequest: Decodable {
                        let email: String
                        let password: String

                        init(from decoder: Decoder) throws {
                            let container = try decoder.container(keyedBy: CodingKeys.self)
                            email = try container.decode(String.self, forKey: .email)
                            password = try container.decode(String.self, forKey: .password)

                            guard !email.isEmpty, email.contains("@") else {
                                throw DecodingError.dataCorruptedError(
                                    forKey: .email, in: container,
                                    debugDescription: "Email must be valid"
                                )
                            }
                            guard password.count >= 8 else {
                                throw DecodingError.dataCorruptedError(
                                    forKey: .password, in: container,
                                    debugDescription: "Password must be at least 8 characters"
                                )
                            }
                        }
                    }
                    """,
                explanation: "Input validation belongs in the DTO's init(from:) method, not in route handlers. "
                    + "This ensures validation happens automatically during request.decode(), provides clear error "
                    + "messages at the boundary, and keeps handlers thin. DTOs define the valid shape of input data — "
                    + "validation is part of that definition. Handlers should only dispatch to services after "
                    + "validation has already succeeded."
            )
        ),

        ArchitecturalViolation(
            id: "data-transformation-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.map\s*\{|\.flatMap\s*\{|\.compactMap\s*\{|\.reduce\(|\.filter\s*\{)"#,
            description: "Data transformation detected inside a route handler closure. "
                + "Mapping, filtering, and data formatting belongs in the service layer "
                + "or DTO conversion — handlers should receive transformed data, not create it.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — data transformation in handler
                    router.get("/users/active") { request, context in
                        let users = try await context.dependencies.userService.listAll()

                        // Data transformation in handler!
                        let activeUsers = users
                            .filter { $0.status == .active }
                            .map { user in
                                UserSummary(
                                    id: user.id.uuidString,
                                    name: "\\(user.firstName) \\(user.lastName)",
                                    email: user.email
                                )
                            }

                        return ActiveUsersResponse(users: activeUsers)
                    }
                    """,
                after: """
                    // ✅ Correct — transformation in service layer
                    router.get("/users/active") { request, context in
                        let summaries = try await context.dependencies.userService.listActiveSummaries()
                        return ActiveUsersResponse(users: summaries)
                    }

                    // In UserService.swift:
                    func listActiveSummaries() async throws -> [UserSummary] {
                        let users = try await repository.findAll()
                        return users
                            .filter { $0.status == .active }
                            .map { user in
                                UserSummary(
                                    id: user.id.uuidString,
                                    name: "\\(user.firstName) \\(user.lastName)",
                                    email: user.email
                                )
                            }
                    }
                    """,
                explanation: "Data transformation logic (filtering, mapping, aggregating) belongs in the service layer, "
                    + "not in route handlers. Handlers that transform data can't be tested independently, duplicate "
                    + "transformation logic across endpoints, and violate the dispatcher pattern. Services should "
                    + "return already-transformed data ready for DTO conversion. This keeps handlers thin and makes "
                    + "transformation logic reusable across different endpoints."
            )
        ),

        ArchitecturalViolation(
            id: "missing-request-decode",
            pattern: #"router\.(post|put|patch).*\{(?!.*request\.decode\(|.*decode\(as:)[^}]{50,}\}"#,
            description: "POST/PUT/PATCH handler with no request.decode() call. "
                + "Handlers that accept request bodies must decode them into DTOs "
                + "for type safety and validation — never parse request data manually.",
            correctionId: "dtos-at-boundaries",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — no request.decode, manual parsing
                    router.post("/users") { request, context in
                        let body = request.body.buffer
                        let json = try JSONSerialization.jsonObject(with: Data(buffer: body))
                        // Manual parsing is error-prone and unvalidated
                        return try await context.dependencies.userService.create(...)
                    }
                    """,
                after: """
                    // ✅ Correct — request.decode with DTO
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)
                        let user = try await context.dependencies.userService.create(dto)
                        return CreateUserResponse(user)
                    }

                    struct CreateUserRequest: Decodable {
                        let email: String
                        let password: String
                    }
                    """,
                explanation: "Manual JSON parsing is error-prone, verbose, and bypasses type safety. Using request.decode() "
                    + "with a DTO gives you automatic validation, type checking, and clear documentation of what the endpoint "
                    + "expects. The Decodable protocol handles all the parsing for you, and custom init(from:) lets you add "
                    + "validation rules at the boundary."
            )
        ),

        ArchitecturalViolation(
            id: "unchecked-uri-parameters",
            pattern: #"request\.uri\.path(?!\s*(==|!=|\.starts|\.contains))|\blet\s+\w+\s*=\s*request\.uri\.path\b"#,
            description: "Direct access to request.uri.path without validation. "
                + "URI paths must be validated before use — either through route parameter "
                + "binding with type constraints or explicit validation in DTOs.",
            correctionId: "request-validation-via-dto",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — unchecked URI path access
                    router.get("/users/:id") { request, context in
                        let path = request.uri.path
                        let id = path.split(separator: "/").last  // Unsafe parsing!
                        return try await context.dependencies.userService.find(id: String(id ?? ""))
                    }
                    """,
                after: """
                    // ✅ Correct — validated route parameter
                    router.get("/users/:id") { request, context in
                        let id = try context.parameters.require("id", as: String.self)
                        return try await context.dependencies.userService.find(id: id)
                    }
                    """,
                explanation: "Manually parsing URI paths is fragile and bypasses Hummingbird's route parameter validation. "
                    + "Use route parameter placeholders (e.g., :id) and context.parameters.require() to safely extract and "
                    + "validate path parameters. This ensures type safety, provides clear error messages for invalid requests, "
                    + "and documents what the route expects."
            )
        ),

        ArchitecturalViolation(
            id: "unchecked-query-parameters",
            pattern: #"request\.uri\.queryParameters(?!\s*\.isEmpty)|\blet\s+\w+\s*=\s*request\.uri\.queryParameters\[(?!.*guard|.*if let)"#,
            description: "Direct access to query parameters without validation. "
                + "Query parameters must be validated through DTO decoding — "
                + "never access queryParameters dictionary directly and pass raw values to services.",
            correctionId: "request-validation-via-dto",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — unchecked query parameter access
                    router.get("/users") { request, context in
                        let page = request.uri.queryParameters["page"] ?? "1"
                        let limit = request.uri.queryParameters["limit"] ?? "10"
                        // No validation, unsafe parsing
                        return try await context.dependencies.userService.list(
                            page: Int(page) ?? 1,
                            limit: Int(limit) ?? 10
                        )
                    }
                    """,
                after: """
                    // ✅ Correct — query parameters validated via DTO
                    router.get("/users") { request, context in
                        let query = try await request.decode(as: ListUsersQuery.self, context: context)
                        let users = try await context.dependencies.userService.list(
                            page: query.page,
                            limit: query.limit
                        )
                        return UserListResponse(users: users.map(UserResponse.init))
                    }

                    struct ListUsersQuery: Decodable {
                        let page: Int
                        let limit: Int

                        init(from decoder: Decoder) throws {
                            let container = try decoder.container(keyedBy: CodingKeys.self)
                            page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
                            limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 10

                            guard limit > 0, limit <= 100 else {
                                throw DecodingError.dataCorruptedError(
                                    forKey: .limit, in: container,
                                    debugDescription: "Limit must be between 1 and 100"
                                )
                            }
                        }
                    }
                    """,
                explanation: "Accessing query parameters directly from request.uri.queryParameters bypasses validation and "
                    + "type safety. Define a query DTO that decodes and validates all query parameters in one place. This "
                    + "ensures invalid input is rejected early, provides clear error messages, and documents what query "
                    + "parameters the endpoint accepts. Use init(from:) to add validation rules and sensible defaults."
            )
        ),

        ArchitecturalViolation(
            id: "raw-parameter-in-service-call",
            pattern: #"service\.\w+\([^)]*request\.(uri|parameters|headers)\."#,
            description: "Raw request property passed directly to service layer method. "
                + "All request data must be validated and converted to DTOs before "
                + "passing to the service layer — services must not receive raw Request objects.",
            correctionId: "request-validation-via-dto",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — raw request properties passed to service
                    router.post("/users") { request, context in
                        let result = try await context.dependencies.userService.create(
                            email: request.uri.queryParameters["email"],
                            auth: request.headers[.authorization]
                        )
                        return result
                    }
                    """,
                after: """
                    // ✅ Correct — validated DTO passed to service
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)
                        let user = try await context.dependencies.userService.create(dto)
                        return CreateUserResponse(user)
                    }

                    struct CreateUserRequest: Decodable {
                        let email: String
                        let password: String

                        init(from decoder: Decoder) throws {
                            let container = try decoder.container(keyedBy: CodingKeys.self)
                            email = try container.decode(String.self, forKey: .email)
                            password = try container.decode(String.self, forKey: .password)

                            guard email.contains("@") else {
                                throw DecodingError.dataCorruptedError(
                                    forKey: .email, in: container,
                                    debugDescription: "Email must be valid"
                                )
                            }
                        }
                    }
                    """,
                explanation: "Services must be framework-agnostic and should never receive raw HTTP Request objects or their "
                    + "properties. This couples the service layer to Hummingbird and makes testing difficult. Always decode "
                    + "request data into a validated DTO in the handler, then pass the DTO to the service. This maintains "
                    + "clean separation of concerns and keeps services independently testable."
            )
        ),

        ArchitecturalViolation(
            id: "direct-env-access",
            pattern: #"(ProcessInfo\.processInfo\.environment\[|getenv\(|ProcessInfo\.environment)"#,
            description: "Direct environment variable access in application code. "
                + "All configuration must be loaded through a centralized Configuration struct "
                + "at startup — never access environment variables directly at runtime.",
            correctionId: "centralized-configuration",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — direct environment access at runtime
                    struct UserService {
                        func sendEmail(to: String, subject: String) async throws {
                            let apiKey = ProcessInfo.processInfo.environment["SENDGRID_API_KEY"]!
                            let sendgrid = SendGridClient(apiKey: apiKey)
                            try await sendgrid.send(to: to, subject: subject)
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — configuration injected via dependencies
                    struct AppConfiguration: Sendable {
                        let sendGridAPIKey: String
                        let databaseURL: String

                        static func fromEnvironment() throws -> AppConfiguration {
                            guard let apiKey = ProcessInfo.processInfo.environment["SENDGRID_API_KEY"],
                                  let dbURL = ProcessInfo.processInfo.environment["DATABASE_URL"],
                                  !apiKey.isEmpty, !dbURL.isEmpty else {
                                throw AppError.configurationError(reason: "Missing required environment variables")
                            }
                            return AppConfiguration(sendGridAPIKey: apiKey, databaseURL: dbURL)
                        }
                    }

                    struct UserService {
                        let config: AppConfiguration
                        let emailClient: EmailClient

                        func sendEmail(to: String, subject: String) async throws {
                            try await emailClient.send(to: to, subject: subject)
                        }
                    }

                    // In Application+build.swift:
                    let config = try AppConfiguration.fromEnvironment()
                    let emailClient = SendGridClient(apiKey: config.sendGridAPIKey)
                    let userService = UserService(config: config, emailClient: emailClient)
                    """,
                explanation: "Environment variables must be loaded once at application startup through a centralized "
                    + "Configuration struct, never accessed directly at runtime. This provides a single source of truth, "
                    + "enables configuration validation at startup (fail fast), makes testing easier (inject test config), "
                    + "and documents all configuration requirements in one place. Direct environment access scatters "
                    + "configuration throughout the codebase and makes it impossible to validate or test."
            )
        ),

        ArchitecturalViolation(
            id: "hardcoded-url",
            pattern: #"(let|var)\s+\w+\s*(:\s*String)?\s*=\s*"https?://[^"]+""#,
            description: "Hardcoded URL in source code. "
                + "All URLs, endpoints, and external service addresses must be "
                + "defined in configuration — never hardcoded as string literals.",
            correctionId: "centralized-configuration",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — hardcoded URL
                    struct PaymentService {
                        func processPayment(amount: Decimal) async throws {
                            let apiURL = "https://api.stripe.com/v1/charges"  // Hardcoded!
                            let request = URLRequest(url: URL(string: apiURL)!)
                            let (data, _) = try await URLSession.shared.data(for: request)
                            return try JSONDecoder().decode(PaymentResponse.self, from: data)
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — URL from configuration
                    struct AppConfiguration: Sendable {
                        let stripeAPIBaseURL: String
                        let databaseURL: String

                        static func fromEnvironment() throws -> AppConfiguration {
                            guard let stripeURL = ProcessInfo.processInfo.environment["STRIPE_API_URL"],
                                  let dbURL = ProcessInfo.processInfo.environment["DATABASE_URL"],
                                  !stripeURL.isEmpty, !dbURL.isEmpty else {
                                throw AppError.configurationError(reason: "Missing required environment variables")
                            }
                            return AppConfiguration(stripeAPIBaseURL: stripeURL, databaseURL: dbURL)
                        }
                    }

                    struct PaymentService {
                        let config: AppConfiguration

                        func processPayment(amount: Decimal) async throws {
                            let apiURL = "\\(config.stripeAPIBaseURL)/v1/charges"
                            let request = URLRequest(url: URL(string: apiURL)!)
                            let (data, _) = try await URLSession.shared.data(for: request)
                            return try JSONDecoder().decode(PaymentResponse.self, from: data)
                        }
                    }
                    """,
                explanation: "Hardcoded URLs make it impossible to change endpoints between environments (dev, staging, "
                    + "production) without modifying code. URLs must be loaded from configuration so they can vary by "
                    + "environment. This enables testing against mock servers, switching between service providers, and "
                    + "zero-downtime migrations to new endpoints. All external service addresses should be configurable, "
                    + "never baked into source code."
            )
        ),

        ArchitecturalViolation(
            id: "hardcoded-credentials",
            pattern: #"(let|var)\s+\w*(password|secret|key|token|apiKey|apiSecret)\w*\s*=\s*"[^"]+"(?!")"#,
            description: "Hardcoded credential or secret in source code. "
                + "Secrets must NEVER be committed to code — use environment variables "
                + "loaded through secure configuration at runtime.",
            correctionId: "secure-configuration",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ CRITICAL SECURITY VULNERABILITY — hardcoded secrets
                    struct AuthService {
                        let jwtSecret = "super-secret-key-12345"  // ⚠️ NEVER DO THIS!
                        let apiKey = "sk_live_abc123def456"       // ⚠️ SECURITY BREACH!
                        let databasePassword = "mysqlpass123"     // ⚠️ Credentials exposed!

                        func generateToken(userId: String) -> String {
                            return JWT.sign(payload: ["userId": userId], secret: jwtSecret)
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — secrets from environment
                    struct AppConfiguration: Sendable {
                        let jwtSecret: String
                        let apiKey: String
                        let databasePassword: String

                        static func fromEnvironment() throws -> AppConfiguration {
                            guard let jwtSecret = ProcessInfo.processInfo.environment["JWT_SECRET"],
                                  let apiKey = ProcessInfo.processInfo.environment["API_KEY"],
                                  let dbPassword = ProcessInfo.processInfo.environment["DATABASE_PASSWORD"],
                                  !jwtSecret.isEmpty, !apiKey.isEmpty, !dbPassword.isEmpty else {
                                throw AppError.configurationError(reason: "Required secrets not found in environment")
                            }
                            return AppConfiguration(
                                jwtSecret: jwtSecret,
                                apiKey: apiKey,
                                databasePassword: dbPassword
                            )
                        }
                    }

                    struct AuthService {
                        let config: AppConfiguration

                        func generateToken(userId: String) -> String {
                            return JWT.sign(payload: ["userId": userId], secret: config.jwtSecret)
                        }
                    }
                    """,
                explanation: "NEVER hardcode secrets (API keys, passwords, tokens, encryption keys) in source code. "
                    + "Hardcoded secrets get committed to version control, exposed in logs, leaked in stack traces, "
                    + "and can't be rotated without code changes. Load all secrets from environment variables at startup, "
                    + "use secret management services (AWS Secrets Manager, HashiCorp Vault) in production, and NEVER "
                    + "commit .env files to version control. Use different secrets for dev, staging, and production, "
                    + "and rotate them regularly."
            )
        ),

        ArchitecturalViolation(
            id: "swallowed-error",
            pattern: #"catch\s*\{[\s\n]*\}"#,
            description: "Empty catch block that swallows errors without handling. "
                + "Silently ignoring errors hides failures and makes debugging impossible — "
                + "always log errors, convert them to AppError, or handle them explicitly.",
            correctionId: "typed-errors-app-error",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — error silently swallowed
                    func fetchUserData() async {
                        do {
                            let data = try await externalAPI.fetch()
                            process(data)
                        } catch {
                            // Empty catch — error disappears!
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — error logged and handled
                    func fetchUserData() async throws {
                        do {
                            let data = try await externalAPI.fetch()
                            process(data)
                        } catch {
                            logger.error("Failed to fetch user data", metadata: [
                                "error": "\\(error)",
                                "operation": "fetchUserData"
                            ])
                            throw AppError.externalServiceError(
                                service: "externalAPI",
                                reason: error.localizedDescription
                            )
                        }
                    }
                    """,
                explanation: "Empty catch blocks hide errors and make production debugging impossible. When errors occur, "
                    + "you need visibility into what went wrong. Always log errors with context (what operation failed, "
                    + "what input caused the failure), then either re-throw as AppError or handle the error explicitly "
                    + "with fallback logic. Silent failures lead to data inconsistency and frustrated users."
            )
        ),

        ArchitecturalViolation(
            id: "error-discarded-with-underscore",
            pattern: #"catch\s+(_|\w+)\s*\{(?!.*logger|.*log\.|.*throw|.*AppError)"#,
            description: "Error caught but not logged or re-thrown. "
                + "Catching an error without logging it or wrapping it in AppError "
                + "makes production debugging impossible — always preserve error context.",
            correctionId: "typed-errors-app-error",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — error caught but discarded
                    func updateUser(id: String, data: UserData) async -> Bool {
                        do {
                            try await repository.update(id: id, data: data)
                            return true
                        } catch _ {
                            return false  // Error information lost!
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — error logged and re-thrown
                    func updateUser(id: String, data: UserData) async throws {
                        do {
                            try await repository.update(id: id, data: data)
                        } catch {
                            logger.error("Failed to update user", metadata: [
                                "userId": "\\(id)",
                                "error": "\\(error)",
                                "operation": "updateUser"
                            ])
                            throw AppError.databaseError(
                                operation: "update user",
                                reason: error.localizedDescription
                            )
                        }
                    }
                    """,
                explanation: "Catching errors without logging or re-throwing them destroys valuable debugging information. "
                    + "When something fails in production, you need to know what failed, why it failed, and what data "
                    + "was involved. Always log errors with structured metadata (entity IDs, operation names, input values), "
                    + "then re-throw as AppError to preserve the error chain while providing clean error responses."
            )
        ),

        ArchitecturalViolation(
            id: "generic-error-message",
            pattern: #"throw\s+\w*Error\("[^"]{1,20}"\)(?!.*:)"#,
            description: "Error thrown with generic message and no context. "
                + "Error messages must include context about what failed and why — "
                + "add details like entity IDs, operation names, or input values that failed validation.",
            correctionId: "typed-errors-app-error",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — generic error with no context
                    func deleteUser(id: String) async throws {
                        guard let user = try await repository.find(id: id) else {
                            throw AppError.notFound(reason: "Not found")  // Which entity? What ID?
                        }
                        try await repository.delete(user)
                    }
                    """,
                after: """
                    // ✅ Correct — error with full context
                    func deleteUser(id: String) async throws {
                        guard let user = try await repository.find(id: id) else {
                            throw AppError.notFound(
                                entity: "User",
                                id: id,
                                reason: "User with ID \\(id) does not exist"
                            )
                        }
                        try await repository.delete(user)
                    }
                    """,
                explanation: "Generic error messages like 'Not found' or 'Invalid input' provide no debugging context. "
                    + "When an error occurs in production, you need to know what entity was affected, what ID was used, "
                    + "and what operation failed. Include specific details in error messages: entity types, IDs, field names, "
                    + "validation constraints that were violated, and the operation that was attempted. This makes logs "
                    + "searchable and debugging possible."
            )
        ),

        ArchitecturalViolation(
            id: "print-in-error-handler",
            pattern: #"catch[^}]*\{[^}]*(print\(|debugPrint\()"#,
            description: "print() or debugPrint() used in error handling instead of structured logging. "
                + "Print statements are not searchable, not structured, and disappear in production — "
                + "use Logger with proper log levels and context instead.",
            correctionId: "structured-logging",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — print() for error logging
                    func processPayment(amount: Decimal) async throws {
                        do {
                            try await paymentGateway.charge(amount: amount)
                        } catch {
                            print("Payment failed: \\(error)")  // Not structured, not searchable!
                            throw error
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — structured logging with Logger
                    func processPayment(amount: Decimal) async throws {
                        do {
                            try await paymentGateway.charge(amount: amount)
                        } catch {
                            logger.error("Payment processing failed", metadata: [
                                "amount": "\\(amount)",
                                "error": "\\(error)",
                                "errorType": "\\(type(of: error))",
                                "operation": "processPayment"
                            ])
                            throw AppError.paymentError(
                                amount: amount,
                                reason: error.localizedDescription
                            )
                        }
                    }
                    """,
                explanation: "print() statements are development tools that don't belong in production code. They aren't "
                    + "captured by logging systems, can't be filtered by severity, don't support structured metadata, "
                    + "and disappear in production environments. Use Logger with proper log levels (error, warning, info, debug) "
                    + "and structured metadata for all production logging. This makes logs searchable, filterable, and "
                    + "integrates with monitoring systems for alerting and debugging."
            )
        ),

        ArchitecturalViolation(
            id: "missing-error-wrapping",
            pattern: #"catch\s+let\s+(\w+)\s*\{[^}]*throw\s+\1\s*\}"#,
            description: "Third-party error re-thrown directly without wrapping in AppError. "
                + "Raw errors from libraries leak implementation details to clients — "
                + "wrap all external errors in AppError with context about the operation that failed.",
            correctionId: "typed-errors-app-error",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — raw database error re-thrown
                    func findUser(id: String) async throws -> User {
                        do {
                            return try await repository.find(id: id)
                        } catch let dbError {
                            throw dbError  // PostgresError leaks to handler!
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — wrapped in AppError
                    func findUser(id: String) async throws -> User {
                        do {
                            return try await repository.find(id: id)
                        } catch let dbError as DatabaseError {
                            logger.error("Database query failed", metadata: [
                                "userId": "\\(id)",
                                "error": "\\(dbError)",
                                "operation": "findUser"
                            ])
                            throw AppError.databaseError(
                                operation: "find user by ID",
                                reason: dbError.localizedDescription
                            )
                        } catch {
                            throw AppError.internalError(reason: error.localizedDescription)
                        }
                    }
                    """,
                explanation: "Re-throwing third-party errors directly exposes internal implementation details (database types, "
                    + "connection strings, table names) to clients and makes it impossible to change underlying libraries "
                    + "without breaking error handling. Wrap all external errors in AppError at layer boundaries, adding "
                    + "context about what operation was attempted. This provides consistent error responses, prevents "
                    + "information leakage, and allows you to change implementations without affecting error contracts."
            )
        ),

        ArchitecturalViolation(
            id: "response-without-status-code",
            pattern: #"Response\s*\([^)]*(?!status:)[^)]*\)"#,
            description: "Response created without explicit status code. "
                + "Every HTTP response must explicitly set a status code — "
                + "implicit defaults hide intent and make API behavior unclear to readers.",
            correctionId: "explicit-http-status-codes",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — no explicit status code
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)
                        let user = try await context.dependencies.userService.create(dto)
                        return Response(body: .init(data: try JSONEncoder().encode(user)))
                    }
                    """,
                after: """
                    // ✅ Correct — explicit status code
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)
                        let user = try await context.dependencies.userService.create(dto)
                        return CreateUserResponse(user)  // ResponseCodable handles status
                    }

                    // Or if using Response directly:
                    router.delete("/users/:id") { request, context in
                        let id = try context.parameters.require("id")
                        try await context.dependencies.userService.delete(id: id)
                        return Response(status: .noContent)  // Explicit .noContent
                    }
                    """,
                explanation: "Omitting status codes relies on implicit defaults (usually 200 OK), which hides the intent "
                    + "of the response and makes the API contract unclear. HTTP status codes communicate semantic meaning: "
                    + "201 Created for new resources, 204 No Content for successful deletes, 404 Not Found for missing "
                    + "resources. Always specify status codes explicitly, either through ResponseCodable DTOs (which "
                    + "set appropriate defaults) or Response(status:) for explicit control."
            )
        ),

        ArchitecturalViolation(
            id: "inconsistent-response-format",
            pattern: #"return\s+Response\s*\([^)]*body:[^)]*"[^"]*"[^)]*\)"#,
            description: "Response created with hardcoded string body instead of DTO. "
                + "All HTTP responses must use structured DTOs for consistency — "
                + "never return raw strings or manually constructed JSON in Response bodies.",
            correctionId: "dtos-at-boundaries",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — hardcoded string response
                    router.post("/users") { request, context in
                        let user = try await context.dependencies.userService.create(...)
                        return Response(
                            status: .created,
                            body: .init(byteBuffer: ByteBuffer(string: "{\\"id\\":\\"123\\"}"))
                        )
                    }
                    """,
                after: """
                    // ✅ Correct — structured DTO response
                    router.post("/users") { request, context in
                        let dto = try await request.decode(as: CreateUserRequest.self, context: context)
                        let user = try await context.dependencies.userService.create(dto)
                        return CreateUserResponse(user)
                    }

                    struct CreateUserResponse: Codable, ResponseCodable {
                        let id: String
                        let email: String
                        let createdAt: Date

                        init(_ user: UserModel) {
                            self.id = user.id.uuidString
                            self.email = user.email
                            self.createdAt = user.createdAt
                        }
                    }
                    """,
                explanation: "Manually constructing JSON strings is error-prone, inconsistent, and bypasses type safety. "
                    + "Always use ResponseCodable DTOs that automatically encode to JSON. This ensures consistent response "
                    + "formats, proper content-type headers, correct JSON encoding (dates, optionals, etc.), and compile-time "
                    + "verification of your response structure."
            )
        ),

        ArchitecturalViolation(
            id: "response-missing-content-type",
            pattern: #"Response\s*\([^)]*body:[^)]*\)(?!\s*\.withHeader\s*\(.*content-type)"#,
            description: "Response created without Content-Type header. "
                + "HTTP responses must explicitly declare their media type — "
                + "add .withHeader(.contentType, \"application/json\") or use response encoding middleware.",
            correctionId: "explicit-content-type-headers",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — no Content-Type header
                    router.get("/health") { request, context in
                        let json = "{\\"status\\":\\"healthy\\"}"
                        return Response(
                            status: .ok,
                            body: .init(byteBuffer: ByteBuffer(string: json))
                        )  // Missing Content-Type!
                    }
                    """,
                after: """
                    // ✅ Correct — explicit Content-Type with DTO
                    router.get("/health") { request, context in
                        return HealthResponse(status: "healthy")
                    }

                    struct HealthResponse: Codable, ResponseCodable {
                        let status: String
                    }

                    // Or if using Response directly:
                    router.get("/health") { request, context in
                        let json = "{\\"status\\":\\"healthy\\"}"
                        return Response(
                            status: .ok,
                            headers: [.contentType: "application/json"],
                            body: .init(byteBuffer: ByteBuffer(string: json))
                        )
                    }
                    """,
                explanation: "HTTP responses without Content-Type headers leave clients guessing about how to parse the body. "
                    + "Browsers and API clients use Content-Type to determine if they're receiving JSON, HTML, plain text, "
                    + "or binary data. Always set Content-Type explicitly. The cleanest approach is using ResponseCodable "
                    + "DTOs which automatically set 'application/json' and handle encoding. If using Response directly, "
                    + "add headers: [.contentType: \"application/json\"] to declare the media type."
            )
        ),

        ArchitecturalViolation(
            id: "sleep-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(sleep\(|Thread\.sleep|usleep\()"#,
            description: "Sleep call detected inside a route handler. "
                + "Blocking the thread pool with sleep() destroys concurrency performance — "
                + "use Task.sleep() or await-based delays instead of blocking sleep calls.",
            correctionId: "async-concurrency-patterns",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — blocking sleep in handler
                    router.post("/process") { request, context in
                        let dto = try await request.decode(as: ProcessRequest.self, context: context)
                        try await context.dependencies.processingService.start(dto)

                        // Blocking sleep — destroys concurrency!
                        sleep(5)  // Blocks the entire thread for 5 seconds!

                        let result = try await context.dependencies.processingService.getResult()
                        return ProcessResponse(result)
                    }
                    """,
                after: """
                    // ✅ Correct — non-blocking async sleep
                    router.post("/process") { request, context in
                        let dto = try await request.decode(as: ProcessRequest.self, context: context)
                        try await context.dependencies.processingService.start(dto)

                        // Non-blocking async sleep — yields to other tasks
                        try await Task.sleep(for: .seconds(5))

                        let result = try await context.dependencies.processingService.getResult()
                        return ProcessResponse(result)
                    }

                    // Better: use polling or callbacks instead of sleep
                    router.post("/process") { request, context in
                        let dto = try await request.decode(as: ProcessRequest.self, context: context)
                        let jobId = try await context.dependencies.processingService.start(dto)
                        return ProcessStartedResponse(jobId: jobId, statusURL: "/jobs/\\(jobId)")
                    }
                    """,
                explanation: "Thread.sleep() and sleep() block the cooperative thread pool that Swift's async/await runtime "
                    + "uses for concurrency. Blocking a thread prevents other async tasks from making progress, destroying "
                    + "throughput. Use Task.sleep(for:) which suspends the current task without blocking threads, allowing "
                    + "other work to proceed. Better yet, redesign to use job queues, polling endpoints, or WebSockets "
                    + "instead of blocking HTTP requests with delays."
            )
        ),

        ArchitecturalViolation(
            id: "blocking-io-in-async",
            pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(FileHandle\(|FileManager\.default\.(contents|createFile|removeItem|moveItem|copyItem)\(|fopen\(|fread\(|fwrite\()"#,
            description: "Blocking file I/O operation in async context. "
                + "Synchronous file operations block the async thread pool — "
                + "use AsyncFileHandle, NIO's NonBlockingFileIO, or dispatch to a dedicated queue.",
            correctionId: "non-blocking-io",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — blocking file I/O in async context
                    func loadConfig() async throws -> Config {
                        let data = FileManager.default.contents(atPath: "/etc/config.json")
                        guard let data = data else { throw ConfigError.notFound }
                        return try JSONDecoder().decode(Config.self, from: data)
                    }
                    """,
                after: """
                    // ✅ Correct — non-blocking file I/O
                    import NIOPosix
                    import NIOCore

                    func loadConfig(fileIO: NonBlockingFileIO, allocator: ByteBufferAllocator) async throws -> Config {
                        let fileHandle = try await fileIO.openFile(path: "/etc/config.json", eventLoop: eventLoop)
                        defer { try? fileHandle.close() }
                        let buffer = try await fileIO.read(fileHandle: fileHandle, allocator: allocator, eventLoop: eventLoop)
                        return try JSONDecoder().decode(Config.self, from: Data(buffer: buffer))
                    }
                    """,
                explanation: "Synchronous file operations block the cooperative thread pool that Swift's async/await "
                    + "runtime uses for concurrency. This destroys parallelism and can cause deadlocks. "
                    + "Use NIO's NonBlockingFileIO for async file operations, or dispatch blocking operations "
                    + "to a dedicated serial queue. In Hummingbird, NonBlockingFileIO is available through the application's "
                    + "event loop group and should be injected via dependencies."
            )
        ),

        ArchitecturalViolation(
            id: "synchronous-network-call",
            pattern: #"(URLSession\.shared\.dataTask\(|NSURLConnection\.sendSynchronousRequest|URLSession\(configuration:.*\)\.dataTask\()(?!.*await)"#,
            description: "Synchronous or completion-handler-based network call. "
                + "Legacy URLSession.dataTask blocks threads and breaks structured concurrency — "
                + "use async/await URLSession.data(for:) instead.",
            correctionId: "async-concurrency-patterns",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — completion-handler-based network call
                    func fetchUser(id: String, completion: @escaping (User?) -> Void) {
                        let url = URL(string: "https://api.example.com/users/\\(id)")!
                        URLSession.shared.dataTask(with: url) { data, response, error in
                            guard let data = data, error == nil else {
                                completion(nil)
                                return
                            }
                            let user = try? JSONDecoder().decode(User.self, from: data)
                            completion(user)
                        }.resume()
                    }
                    """,
                after: """
                    // ✅ Correct — async/await network call
                    func fetchUser(id: String) async throws -> User {
                        let url = URL(string: "https://api.example.com/users/\\(id)")!
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let httpResponse = response as? HTTPURLResponse,
                              (200...299).contains(httpResponse.statusCode) else {
                            throw AppError.networkError(reason: "Invalid response")
                        }
                        return try JSONDecoder().decode(User.self, from: data)
                    }
                    """,
                explanation: "Completion-handler-based URLSession.dataTask breaks structured concurrency, makes error "
                    + "handling complex, and can cause callback hell. Swift 6 async/await provides URLSession.data(from:) "
                    + "which integrates seamlessly with structured concurrency, automatic cancellation, and proper error "
                    + "propagation. This eliminates race conditions and makes concurrent code readable and maintainable."
            )
        ),

        ArchitecturalViolation(
            id: "blocking-sleep-in-async",
            pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(sleep\(|Thread\.sleep|usleep\()"#,
            description: "Blocking sleep call in async context. "
                + "sleep() and Thread.sleep() block the cooperative thread pool — "
                + "use Task.sleep(nanoseconds:) or Task.sleep(for:) to yield correctly.",
            correctionId: "async-concurrency-patterns",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — blocking sleep in async context
                    func retryWithBackoff() async throws -> Response {
                        for attempt in 1...3 {
                            do {
                                return try await makeRequest()
                            } catch {
                                if attempt < 3 {
                                    sleep(UInt32(attempt))  // Blocks the thread!
                                }
                            }
                        }
                        throw AppError.maxRetriesExceeded
                    }
                    """,
                after: """
                    // ✅ Correct — non-blocking sleep with Task.sleep
                    func retryWithBackoff() async throws -> Response {
                        for attempt in 1...3 {
                            do {
                                return try await makeRequest()
                            } catch {
                                if attempt < 3 {
                                    try await Task.sleep(for: .seconds(attempt))  // Yields properly
                                }
                            }
                        }
                        throw AppError.maxRetriesExceeded
                    }
                    """,
                explanation: "Foundation's sleep() and Thread.sleep() block the underlying thread, preventing the Swift "
                    + "concurrency runtime from scheduling other tasks on that thread. This destroys concurrency performance "
                    + "and can cause deadlocks. Task.sleep(for:) or Task.sleep(nanoseconds:) yields the thread back to the "
                    + "runtime, allowing other tasks to run while waiting. Task.sleep also respects task cancellation automatically."
            )
        ),

        ArchitecturalViolation(
            id: "synchronous-database-call-in-async",
            pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(\.execute\(\)|\.query\()[^}]*(?!await)"#,
            description: "Database call in async context without await. "
                + "Synchronous database operations block the thread pool — "
                + "all database calls must use async/await to preserve concurrency.",
            correctionId: "async-concurrency-patterns",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — synchronous database call in async context
                    func findUser(id: UUID) async throws -> User {
                        let result = pool.query("SELECT * FROM users WHERE id = $1", [id])  // Missing await!
                        guard let row = result.first else {
                            throw AppError.notFound
                        }
                        return User(from: row)
                    }
                    """,
                after: """
                    // ✅ Correct — async database call with await
                    func findUser(id: UUID) async throws -> User {
                        let result = try await pool.query("SELECT * FROM users WHERE id = $1", [id])
                        guard let row = result.first else {
                            throw AppError.notFound
                        }
                        return User(from: row)
                    }
                    """,
                explanation: "Database operations are I/O-bound and can take significant time. Calling them synchronously "
                    + "in an async context blocks the cooperative thread pool, preventing other tasks from running. "
                    + "Modern database drivers (PostgresNIO, MongoKitten, etc.) provide async/await APIs that integrate "
                    + "with Swift's structured concurrency. Always use await with database calls to yield the thread "
                    + "while waiting for I/O, maintaining application throughput and responsiveness."
            )
        ),

        ArchitecturalViolation(
            id: "global-mutable-state",
            pattern: #"^(public\s+|internal\s+|private\s+)?var\s+\w+\s*:\s*(?!@Sendable)[^\n]*=(?!\s*\{)"#,
            description: "Global mutable variable declared without actor protection or @MainActor isolation. "
                + "Global mutable state causes data races in concurrent code — "
                + "use actors, @MainActor, or make the value immutable (let) instead.",
            correctionId: "actor-for-shared-state",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — global mutable state without protection
                    var requestCount: Int = 0
                    var activeConnections: [String: Connection] = [:]

                    router.get("/metrics") { request, context in
                        requestCount += 1  // Data race!
                        return MetricsResponse(count: requestCount)
                    }
                    """,
                after: """
                    // ✅ Correct — actor-protected state
                    actor MetricsStore {
                        private var requestCount: Int = 0
                        private var activeConnections: [String: Connection] = [:]

                        func incrementRequests() -> Int {
                            requestCount += 1
                            return requestCount
                        }

                        func recordConnection(id: String, connection: Connection) {
                            activeConnections[id] = connection
                        }
                    }

                    router.get("/metrics") { request, context in
                        let count = await context.dependencies.metrics.incrementRequests()
                        return MetricsResponse(count: count)
                    }
                    """,
                explanation: "Global mutable variables create data races in concurrent code because multiple requests "
                    + "can access and modify them simultaneously without synchronization. Swift 6 strict concurrency "
                    + "mode enforces this at compile time. Actors provide safe serialized access to mutable state — "
                    + "all access is serialized through the actor's executor. Inject the actor via AppRequestContext.dependencies "
                    + "to maintain testability and proper dependency management."
            )
        ),

        ArchitecturalViolation(
            id: "missing-sendable-conformance",
            pattern: #"(struct|class|enum)\s+\w+(?!.*:\s*.*Sendable)[^{]*(:\s*[^{]*)?(?=\s*\{)"#,
            description: "Type declaration without Sendable conformance in concurrent context. "
                + "Types used across concurrency boundaries must conform to Sendable — "
                + "add `: Sendable` to structs/enums/actors, or use `final class` with all immutable properties.",
            correctionId: "sendable-types",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — type without Sendable conformance
                    struct UserService {
                        let repository: UserRepository
                        let logger: Logger

                        func create(_ request: CreateUserRequest) async throws -> User {
                            return try await repository.insert(User(email: request.email))
                        }
                    }

                    struct AppDependencies {
                        let userService: UserService  // Not Sendable!
                    }
                    """,
                after: """
                    // ✅ Correct — Sendable conformance declared
                    struct UserService: Sendable {
                        let repository: UserRepository
                        let logger: Logger

                        func create(_ request: CreateUserRequest) async throws -> User {
                            return try await repository.insert(User(email: request.email))
                        }
                    }

                    struct AppDependencies: Sendable {
                        let userService: UserService
                    }
                    """,
                explanation: "Types that cross concurrency boundaries (passed between actors, tasks, or async contexts) "
                    + "must conform to Sendable to guarantee thread-safety. Sendable is a marker protocol checked at compile time. "
                    + "Structs and enums with all Sendable properties get automatic conformance, but it's best to declare it explicitly. "
                    + "For classes, use `final class` with only immutable (`let`) properties. Swift 6 strict concurrency mode "
                    + "enforces this requirement, catching data races at compile time instead of runtime crashes."
            )
        ),

        ArchitecturalViolation(
            id: "task-detached-without-isolation",
            pattern: #"Task\.detached\s*\{(?!.*@MainActor|.*actor)"#,
            description: "Task.detached called without explicit isolation annotation. "
                + "Detached tasks inherit no isolation and can cause data races — "
                + "use Task { } for structured concurrency or explicitly annotate isolation with @MainActor.",
            correctionId: "structured-concurrency",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — detached task without isolation
                    func processInBackground(data: Data) {
                        Task.detached {
                            // Inherits no actor context, can cause data races
                            await self.processor.process(data)
                            self.updateUI()  // Potential data race!
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — structured concurrency with Task
                    func processInBackground(data: Data) {
                        Task {
                            // Inherits current actor context automatically
                            await self.processor.process(data)
                            await MainActor.run {
                                self.updateUI()  // Safe: explicitly on MainActor
                            }
                        }
                    }

                    // Or if you must detach, annotate isolation explicitly:
                    func processDetached(data: Data) {
                        Task.detached { @MainActor in
                            await processor.process(data)
                            updateUI()  // Safe: isolated to MainActor
                        }
                    }
                    """,
                explanation: "Task.detached creates an unstructured task that inherits no actor isolation from its context, "
                    + "breaking structured concurrency guarantees and creating data race opportunities. Prefer Task { } "
                    + "which automatically inherits the current actor context and maintains parent-child task relationships "
                    + "for automatic cancellation. If you must use Task.detached for truly independent work, explicitly "
                    + "annotate the isolation domain with @MainActor or access actors through await to ensure safety."
            )
        ),

        ArchitecturalViolation(
            id: "nonisolated-unsafe-usage",
            pattern: #"nonisolated\s*\(unsafe\)"#,
            description: "nonisolated(unsafe) used to bypass Swift 6 concurrency checks. "
                + "This attribute disables safety guarantees and can cause data races — "
                + "use proper actor isolation or Sendable conformance instead of unsafe escapes.",
            correctionId: "actor-for-shared-state",
            severity: .error,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — using nonisolated(unsafe) to silence warnings
                    actor CacheStore {
                        nonisolated(unsafe) var cache: [String: Any] = [:]  // Bypasses safety!

                        func get(_ key: String) -> Any? {
                            return cache[key]  // Data race potential!
                        }

                        func set(_ key: String, value: Any) {
                            cache[key] = value  // Not actually isolated!
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — properly isolated actor state
                    actor CacheStore {
                        private var cache: [String: Any] = [:]  // Properly isolated

                        func get(_ key: String) -> Any? {
                            return cache[key]  // Safe: serialized access
                        }

                        func set(_ key: String, value: Any) {
                            cache[key] = value  // Safe: serialized access
                        }
                    }

                    // Or use Sendable types if truly immutable:
                    actor ConfigStore {
                        nonisolated let staticConfig: Configuration  // Safe: immutable Sendable type
                        private var dynamicConfig: Configuration

                        init(config: Configuration) {
                            self.staticConfig = config
                            self.dynamicConfig = config
                        }
                    }
                    """,
                explanation: "nonisolated(unsafe) is an escape hatch that tells the compiler 'trust me, I know what I'm doing' "
                    + "and disables concurrency safety checks. This defeats the entire purpose of Swift 6 strict concurrency mode "
                    + "and can introduce data races that crash at runtime. Instead, keep mutable state properly isolated within "
                    + "the actor (remove nonisolated), or use nonisolated only for truly immutable Sendable values. "
                    + "If you think you need nonisolated(unsafe), you almost certainly need to redesign your concurrency model."
            )
        ),

        // ── Warning: suboptimal patterns ──────────────────────────────────────

        ArchitecturalViolation(
            id: "shared-mutable-state-without-actor",
            pattern: #"var\s+\w+\s*:\s*\[.*\]\s*=\s*\[.*\]"#,
            description: "Mutable collection stored as a var at module or class scope "
                + "without actor protection. In Swift 6 strict concurrency, shared "
                + "mutable state requires an actor or explicit synchronisation.",
            correctionId: "actor-for-shared-state",
            severity: .warning,
            fixSuggestion: FixSuggestion(
                before: """
                    // ❌ Wrong — shared mutable collection without protection
                    class SessionManager {
                        var activeSessions: [String: Session] = [:]  // Data race!

                        func addSession(_ session: Session) {
                            activeSessions[session.id] = session
                        }

                        func removeSession(id: String) {
                            activeSessions.removeValue(forKey: id)
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — actor-protected mutable collection
                    actor SessionManager {
                        private var activeSessions: [String: Session] = [:]

                        func addSession(_ session: Session) {
                            activeSessions[session.id] = session
                        }

                        func removeSession(id: String) {
                            activeSessions.removeValue(forKey: id)
                        }

                        func getSession(id: String) -> Session? {
                            return activeSessions[id]
                        }
                    }

                    // Usage:
                    router.get("/session/:id") { request, context in
                        let id = try context.parameters.require("id")
                        guard let session = await context.dependencies.sessionManager.getSession(id: id) else {
                            throw HTTPError(.notFound)
                        }
                        return SessionResponse(session)
                    }
                    """,
                explanation: "Mutable collections (arrays, dictionaries, sets) shared across concurrent contexts create data races. "
                    + "Multiple tasks can simultaneously read and write, corrupting data structure invariants and causing crashes. "
                    + "Swift 6 strict concurrency mode catches this at compile time. Actors provide safe concurrent access — "
                    + "all mutations are serialized through the actor's executor. Make the collection private within the actor "
                    + "and expose it only through actor-isolated methods that are accessed with await."
            )
        ),

        ArchitecturalViolation(
            id: "nonisolated-context-access",
            pattern: #"nonisolated.*context\.\w+"#,
            description: "AppRequestContext properties accessed from a nonisolated context. "
                + "Context is value-typed (struct) and Sendable — pass it explicitly "
                + "rather than capturing it across isolation boundaries.",
            correctionId: "request-context-di",
            severity: .warning,
            fixSuggestion: FixSuggestion(
                before: """
                    // ⚠️ Suboptimal — context captured across isolation boundary
                    actor RateLimitStore {
                        private var requestCounts: [String: Int] = [:]

                        nonisolated func checkLimit(for request: Request, context: AppRequestContext) -> Bool {
                            let ip = request.remoteAddress?.ipAddress ?? "unknown"
                            // Accessing context from nonisolated method
                            context.logger.info("Checking rate limit for \\(ip)")
                            return true
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — logger passed explicitly
                    actor RateLimitStore {
                        private var requestCounts: [String: Int] = [:]

                        nonisolated func checkLimit(for request: Request, logger: Logger) -> Bool {
                            let ip = request.remoteAddress?.ipAddress ?? "unknown"
                            logger.info("Checking rate limit for \\(ip)")
                            return true
                        }
                    }

                    // Usage in handler:
                    router.get("/api/data") { request, context in
                        let allowed = rateLimitStore.checkLimit(for: request, logger: context.logger)
                        guard allowed else { throw HTTPError(.tooManyRequests) }
                        // ...
                    }
                    """,
                explanation: "AppRequestContext is a value type (struct) and is Sendable, so accessing it from nonisolated "
                    + "contexts is safe but can be inefficient due to copying. More importantly, it's better to pass "
                    + "only the specific properties you need (like logger) rather than the entire context. This makes "
                    + "dependencies explicit, improves testability, and avoids unnecessary copying of the context struct "
                    + "across isolation boundaries."
            )
        ),

        ArchitecturalViolation(
            id: "magic-numbers",
            pattern: #"(timeout|limit|maxConnections|port|bufferSize|retryCount)\s*[=:]\s*\d{2,}"#,
            description: "Magic number used for configuration value. "
                + "Numeric configuration constants (timeouts, limits, ports, etc.) "
                + "should be defined as named constants or loaded from configuration, "
                + "not embedded as raw literals.",
            correctionId: "centralized-configuration",
            severity: .warning,
            fixSuggestion: FixSuggestion(
                before: """
                    // ⚠️ Suboptimal — magic numbers scattered throughout code
                    struct DatabaseClient {
                        func connect() async throws {
                            let connection = try await pool.connect(
                                timeout: 30,           // What does 30 mean? Seconds? Milliseconds?
                                maxConnections: 100,   // Why 100? Can we change it?
                                port: 5432             // Magic number for PostgreSQL port
                            )
                            return connection
                        }
                    }

                    struct APIClient {
                        func fetch() async throws {
                            let request = URLRequest(url: url)
                            request.timeoutInterval = 60  // Another magic number
                            let (data, _) = try await URLSession.shared.data(for: request)
                            return data
                        }
                    }
                    """,
                after: """
                    // ✅ Correct — configuration values defined centrally
                    struct AppConfiguration: Sendable {
                        let databaseTimeout: Duration
                        let databaseMaxConnections: Int
                        let databasePort: Int
                        let httpRequestTimeout: TimeInterval

                        static func fromEnvironment() throws -> AppConfiguration {
                            let dbTimeout = ProcessInfo.processInfo.environment["DB_TIMEOUT"]
                                .flatMap { Int($0) } ?? 30
                            let dbMaxConns = ProcessInfo.processInfo.environment["DB_MAX_CONNECTIONS"]
                                .flatMap { Int($0) } ?? 100
                            let dbPort = ProcessInfo.processInfo.environment["DB_PORT"]
                                .flatMap { Int($0) } ?? 5432

                            return AppConfiguration(
                                databaseTimeout: .seconds(dbTimeout),
                                databaseMaxConnections: dbMaxConns,
                                databasePort: dbPort,
                                httpRequestTimeout: 60.0
                            )
                        }
                    }

                    struct DatabaseClient {
                        let config: AppConfiguration

                        func connect() async throws {
                            let connection = try await pool.connect(
                                timeout: config.databaseTimeout,
                                maxConnections: config.databaseMaxConnections,
                                port: config.databasePort
                            )
                            return connection
                        }
                    }

                    struct APIClient {
                        let config: AppConfiguration

                        func fetch() async throws {
                            let request = URLRequest(url: url)
                            request.timeoutInterval = config.httpRequestTimeout
                            let (data, _) = try await URLSession.shared.data(for: request)
                            return data
                        }
                    }
                    """,
                explanation: "Magic numbers (raw numeric literals for configuration) make code hard to understand and "
                    + "impossible to tune without code changes. What does '30' mean — seconds? milliseconds? retries? "
                    + "Named constants document intent, enable environment-specific tuning (different timeouts for dev "
                    + "vs production), and centralize configuration so you can see all tunables in one place. All "
                    + "configuration values (timeouts, limits, ports, buffer sizes) should be defined in AppConfiguration "
                    + "with clear names and loaded from environment variables for flexibility."
            )
        ),
    ]
}
