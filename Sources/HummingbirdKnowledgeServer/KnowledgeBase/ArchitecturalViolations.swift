// Sources/HummingbirdKnowledgeServer/KnowledgeBase/ArchitecturalViolations.swift
//
// The anti-tutorial rule catalogue.
// Each violation has a regex pattern matched against user-submitted source code.
// Critical violations block code generation entirely.

import Foundation

/// A concrete code-level fix suggestion showing before/after examples.
struct FixSuggestion: Sendable {
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
            severity: .error
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
            severity: .error
        ),

        ArchitecturalViolation(
            id: "validation-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(guard\s+[^}]*(\.isEmpty|\.count|\.contains|!\.)|if\s+[^}]*(\.isEmpty|\.count|\.contains|!\.))"#,
            description: "Validation logic detected inside a route handler closure. "
                + "Input validation must be handled by DTO decoding conformance "
                + "or moved to the service layer — handlers should only dispatch.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "data-transformation-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.map\s*\{|\.flatMap\s*\{|\.compactMap\s*\{|\.reduce\(|\.filter\s*\{)"#,
            description: "Data transformation detected inside a route handler closure. "
                + "Mapping, filtering, and data formatting belongs in the service layer "
                + "or DTO conversion — handlers should receive transformed data, not create it.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error
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
            severity: .error
        ),

        ArchitecturalViolation(
            id: "hardcoded-url",
            pattern: #"(let|var)\s+\w+\s*(:\s*String)?\s*=\s*"https?://[^"]+""#,
            description: "Hardcoded URL in source code. "
                + "All URLs, endpoints, and external service addresses must be "
                + "defined in configuration — never hardcoded as string literals.",
            correctionId: "centralized-configuration",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "hardcoded-credentials",
            pattern: #"(let|var)\s+\w*(password|secret|key|token|apiKey|apiSecret)\w*\s*=\s*"[^"]+"(?!")"#,
            description: "Hardcoded credential or secret in source code. "
                + "Secrets must NEVER be committed to code — use environment variables "
                + "loaded through secure configuration at runtime.",
            correctionId: "secure-configuration",
            severity: .error
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
            severity: .error
        ),

        ArchitecturalViolation(
            id: "blocking-io-in-async",
            pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(FileHandle\(|FileManager\.default\.(contents|createFile|removeItem|moveItem|copyItem)\(|fopen\(|fread\(|fwrite\()"#,
            description: "Blocking file I/O operation in async context. "
                + "Synchronous file operations block the async thread pool — "
                + "use AsyncFileHandle, NIO's NonBlockingFileIO, or dispatch to a dedicated queue.",
            correctionId: "non-blocking-io",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "synchronous-network-call",
            pattern: #"(URLSession\.shared\.dataTask\(|NSURLConnection\.sendSynchronousRequest|URLSession\(configuration:.*\)\.dataTask\()(?!.*await)"#,
            description: "Synchronous or completion-handler-based network call. "
                + "Legacy URLSession.dataTask blocks threads and breaks structured concurrency — "
                + "use async/await URLSession.data(for:) instead.",
            correctionId: "async-concurrency-patterns",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "blocking-sleep-in-async",
            pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(sleep\(|Thread\.sleep|usleep\()"#,
            description: "Blocking sleep call in async context. "
                + "sleep() and Thread.sleep() block the cooperative thread pool — "
                + "use Task.sleep(nanoseconds:) or Task.sleep(for:) to yield correctly.",
            correctionId: "async-concurrency-patterns",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "synchronous-database-call-in-async",
            pattern: #"(async\s+func|async\s+throws|async\s*\{)[^}]*(\.execute\(\)|\.query\()[^}]*(?!await)"#,
            description: "Database call in async context without await. "
                + "Synchronous database operations block the thread pool — "
                + "all database calls must use async/await to preserve concurrency.",
            correctionId: "async-concurrency-patterns",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "global-mutable-state",
            pattern: #"^(public\s+|internal\s+|private\s+)?var\s+\w+\s*:\s*(?!@Sendable)[^\n]*=(?!\s*\{)"#,
            description: "Global mutable variable declared without actor protection or @MainActor isolation. "
                + "Global mutable state causes data races in concurrent code — "
                + "use actors, @MainActor, or make the value immutable (let) instead.",
            correctionId: "actor-for-shared-state",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "missing-sendable-conformance",
            pattern: #"(struct|class|enum)\s+\w+(?!.*:\s*.*Sendable)[^{]*(:\s*[^{]*)?(?=\s*\{)"#,
            description: "Type declaration without Sendable conformance in concurrent context. "
                + "Types used across concurrency boundaries must conform to Sendable — "
                + "add `: Sendable` to structs/enums/actors, or use `final class` with all immutable properties.",
            correctionId: "sendable-types",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "task-detached-without-isolation",
            pattern: #"Task\.detached\s*\{(?!.*@MainActor|.*actor)"#,
            description: "Task.detached called without explicit isolation annotation. "
                + "Detached tasks inherit no isolation and can cause data races — "
                + "use Task { } for structured concurrency or explicitly annotate isolation with @MainActor.",
            correctionId: "structured-concurrency",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "nonisolated-unsafe-usage",
            pattern: #"nonisolated\s*\(unsafe\)"#,
            description: "nonisolated(unsafe) used to bypass Swift 6 concurrency checks. "
                + "This attribute disables safety guarantees and can cause data races — "
                + "use proper actor isolation or Sendable conformance instead of unsafe escapes.",
            correctionId: "actor-for-shared-state",
            severity: .error
        ),

        // ── Warning: suboptimal patterns ──────────────────────────────────────

        ArchitecturalViolation(
            id: "shared-mutable-state-without-actor",
            pattern: #"var\s+\w+\s*:\s*\[.*\]\s*=\s*\[.*\]"#,
            description: "Mutable collection stored as a var at module or class scope "
                + "without actor protection. In Swift 6 strict concurrency, shared "
                + "mutable state requires an actor or explicit synchronisation.",
            correctionId: "actor-for-shared-state",
            severity: .warning
        ),

        ArchitecturalViolation(
            id: "nonisolated-context-access",
            pattern: #"nonisolated.*context\.\w+"#,
            description: "AppRequestContext properties accessed from a nonisolated context. "
                + "Context is value-typed (struct) and Sendable — pass it explicitly "
                + "rather than capturing it across isolation boundaries.",
            correctionId: "request-context-di",
            severity: .warning
        ),

        ArchitecturalViolation(
            id: "magic-numbers",
            pattern: #"(timeout|limit|maxConnections|port|bufferSize|retryCount)\s*[=:]\s*\d{2,}"#,
            description: "Magic number used for configuration value. "
                + "Numeric configuration constants (timeouts, limits, ports, etc.) "
                + "should be defined as named constants or loaded from configuration, "
                + "not embedded as raw literals.",
            correctionId: "centralized-configuration",
            severity: .warning
        ),
    ]
}
