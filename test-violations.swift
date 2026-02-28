// test-violations.swift
//
// Test cases for architectural violation detection.
// Each violation has at least two test cases:
//   ✓ SHOULD TRIGGER - Code that violates the rule
//   ✗ SHOULD NOT TRIGGER - Code that follows the rule
//
// This file is used to validate that ArchitecturalViolations.swift
// correctly detects anti-patterns in Hummingbird 2.x code.

import Foundation

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - CRITICAL VIOLATIONS (blocks code generation)
// ══════════════════════════════════════════════════════════════════════════════

// ──────────────────────────────────────────────────────────────────────────────
// 1. inline-db-in-handler
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Database call directly in handler
func testInlineDbInHandler_Positive1() {
    router.get("/users/:id") { request, context in
        let userId = try request.uri.decode()
        let user = try await db.query("SELECT * FROM users WHERE id = ?", userId)
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: Connection pool access in handler
func testInlineDbInHandler_Positive2() {
    router.post("/articles") { request, context in
        let dto = try await request.decode(as: CreateArticleDTO.self)
        let result = try await pool.execute("INSERT INTO articles...")
        return Response(status: .created)
    }
}

// ✗ SHOULD NOT TRIGGER: Service layer handles DB
func testInlineDbInHandler_Negative1() {
    router.get("/users/:id") { request, context in
        let userId = try request.uri.decode()
        let user = try await context.userService.getUser(by: userId)
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Repository called from service
func testInlineDbInHandler_Negative2() {
    class UserService {
        func getUser(by id: UUID) async throws -> UserDTO {
            let entity = try await userRepository.findById(id)
            return UserDTO(from: entity)
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 2. service-construction-in-handler
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Service constructed in handler
func testServiceConstructionInHandler_Positive1() {
    router.get("/users") { request, context in
        let userService = UserService(repository: userRepository)
        let users = try await userService.listUsers()
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: Service initialized per-request
func testServiceConstructionInHandler_Positive2() {
    router.post("/orders") { request, context in
        let orderService = OrderService()
        let order = try await orderService.createOrder(dto)
        return Response(status: .created)
    }
}

// ✗ SHOULD NOT TRIGGER: Service injected via context
func testServiceConstructionInHandler_Negative1() {
    router.get("/users") { request, context in
        let users = try await context.userService.listUsers()
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Service from dependency injection
func testServiceConstructionInHandler_Negative2() {
    router.post("/orders") { request, context in
        let dto = try await request.decode(as: CreateOrderDTO.self)
        let order = try await context.orderService.createOrder(dto)
        return Response(status: .created)
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - ERROR VIOLATIONS (wrong architecture)
// ══════════════════════════════════════════════════════════════════════════════

// ──────────────────────────────────────────────────────────────────────────────
// 3. hummingbird-import-in-service
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Hummingbird imported in service layer
// File: Services/UserService.swift
import Hummingbird
struct UserService {
    func getUser(id: UUID) async throws -> UserDTO {
        return UserDTO()
    }
}

// ✓ SHOULD TRIGGER: Hummingbird in repository
// File: Repositories/UserRepository.swift
import Hummingbird
import Foundation
class UserRepository {
    func findById(_ id: UUID) async throws -> UserEntity {
        return UserEntity()
    }
}

// ✗ SHOULD NOT TRIGGER: Foundation in service layer
// File: Services/UserService.swift
import Foundation
struct UserServiceCorrect {
    func getUser(id: UUID) async throws -> UserDTO {
        return UserDTO()
    }
}

// ✗ SHOULD NOT TRIGGER: Hummingbird in controller
// File: Controllers/UserController.swift
import Hummingbird
func buildUserRoutes(router: Router) {
    router.get("/users") { request, context in
        return Response(status: .ok)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 4. raw-error-thrown-from-handler
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Third-party error thrown directly
func testRawErrorThrownFromHandler_Positive1() {
    router.get("/data") { request, context in
        throw DecodingError.dataCorrupted(DecodingError.Context())
    }
}

// ✓ SHOULD TRIGGER: Custom error not wrapped
func testRawErrorThrownFromHandler_Positive2() {
    router.post("/upload") { request, context in
        throw ValidationError.invalidFormat
    }
}

// ✗ SHOULD NOT TRIGGER: AppError thrown
func testRawErrorThrownFromHandler_Negative1() {
    router.get("/data") { request, context in
        throw AppError.notFound(resource: "User", id: "123")
    }
}

// ✗ SHOULD NOT TRIGGER: HTTPError thrown
func testRawErrorThrownFromHandler_Negative2() {
    router.post("/upload") { request, context in
        throw HTTPError(.badRequest, message: "Invalid file format")
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 5. domain-model-across-http-boundary
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Domain model returned from handler
func getUserModel(id: UUID) async throws -> UserModel {
    return UserModel(id: id, name: "Test")
}

// ✓ SHOULD TRIGGER: Domain model returned async
func fetchProductModel() async -> ProductModel {
    return ProductModel()
}

// ✗ SHOULD NOT TRIGGER: DTO returned
func getUserDTO(id: UUID) async throws -> UserDTO {
    return UserDTO(id: id, name: "Test")
}

// ✗ SHOULD NOT TRIGGER: Response returned
func getUserResponse() async throws -> Response {
    return Response(status: .ok)
}

// ──────────────────────────────────────────────────────────────────────────────
// 6. domain-entity-across-http-boundary
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Domain entity returned from handler
func getUserEntity(id: UUID) throws -> UserEntity {
    return UserEntity(id: id)
}

// ✓ SHOULD TRIGGER: Entity returned async
func getOrderEntity() async throws -> OrderEntity {
    return OrderEntity()
}

// ✗ SHOULD NOT TRIGGER: DTO returned
func getUserDTOCorrect(id: UUID) throws -> UserDTO {
    return UserDTO()
}

// ✗ SHOULD NOT TRIGGER: ResponseGenerator opaque type
func getUserResponseGen() -> some ResponseGenerator {
    return Response(status: .ok)
}

// ──────────────────────────────────────────────────────────────────────────────
// 7. domain-model-array-across-http-boundary
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Array of models returned
func listUsersModel() async throws -> [UserModel] {
    return []
}

// ✓ SHOULD TRIGGER: Array of entities returned
func listOrdersEntity() async -> [OrderEntity] {
    return []
}

// ✗ SHOULD NOT TRIGGER: Array of DTOs returned
func listUsersDTO() async throws -> [UserDTO] {
    return []
}

// ✗ SHOULD NOT TRIGGER: Response with DTO array
func listUsersResponse() async throws -> Response {
    let dtos = [UserDTO]()
    return Response(status: .ok)
}

// ──────────────────────────────────────────────────────────────────────────────
// 8. domain-model-in-request-decode
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Decode into domain model
func testDomainModelInRequestDecode_Positive1() {
    router.post("/users") { request, context in
        let user = try await request.decode(as: UserModel.self)
        return Response(status: .created)
    }
}

// ✓ SHOULD TRIGGER: Decode into entity
func testDomainModelInRequestDecode_Positive2() {
    router.put("/orders/:id") { request, context in
        let order = try await request.decode(as: OrderEntity.self)
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Decode into DTO
func testDomainModelInRequestDecode_Negative1() {
    router.post("/users") { request, context in
        let dto = try await request.decode(as: CreateUserDTO.self)
        return Response(status: .created)
    }
}

// ✗ SHOULD NOT TRIGGER: Decode into request DTO
func testDomainModelInRequestDecode_Negative2() {
    router.put("/orders/:id") { request, context in
        let dto = try await request.decode(as: UpdateOrderRequest.self)
        return Response(status: .ok)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 9. business-logic-in-handler
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Conditional logic in handler
func testBusinessLogicInHandler_Positive1() {
    router.post("/checkout") { request, context in
        let dto = try await request.decode(as: CheckoutDTO.self)
        if dto.total > 100 {
            return Response(status: .ok)
        }
        return Response(status: .badRequest)
    }
}

// ✓ SHOULD TRIGGER: Calculation in handler
func testBusinessLogicInHandler_Positive2() {
    router.get("/price") { request, context in
        let price = basePrice.calculate(withTax: true)
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: Switch statement in handler
func testBusinessLogicInHandler_Positive3() {
    router.post("/process") { request, context in
        switch orderType {
        case .standard: return Response(status: .ok)
        case .express: return Response(status: .accepted)
        }
    }
}

// ✓ SHOULD TRIGGER: Loop in handler
func testBusinessLogicInHandler_Positive4() {
    router.get("/aggregate") { request, context in
        for item in items {
            total += item.price
        }
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Pure dispatcher
func testBusinessLogicInHandler_Negative1() {
    router.post("/checkout") { request, context in
        let dto = try await request.decode(as: CheckoutDTO.self)
        let result = try await context.orderService.checkout(dto)
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: processDTO is allowed
func testBusinessLogicInHandler_Negative2() {
    router.post("/data") { request, context in
        let dto = try await request.decode(as: DataDTO.self)
        let processed = dto.processDTO()
        return Response(status: .ok)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 10. validation-in-handler
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Guard with isEmpty check
func testValidationInHandler_Positive1() {
    router.post("/users") { request, context in
        let dto = try await request.decode(as: CreateUserDTO.self)
        guard !dto.name.isEmpty else {
            throw HTTPError(.badRequest)
        }
        return Response(status: .created)
    }
}

// ✓ SHOULD TRIGGER: If with count validation
func testValidationInHandler_Positive2() {
    router.post("/comment") { request, context in
        let dto = try await request.decode(as: CommentDTO.self)
        if dto.text.count < 10 {
            throw HTTPError(.badRequest)
        }
        return Response(status: .created)
    }
}

// ✓ SHOULD TRIGGER: Guard with contains check
func testValidationInHandler_Positive3() {
    router.post("/tag") { request, context in
        guard dto.tags.contains("required") else {
            throw HTTPError(.badRequest)
        }
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Validation in service layer
func testValidationInHandler_Negative1() {
    router.post("/users") { request, context in
        let dto = try await request.decode(as: CreateUserDTO.self)
        let user = try await context.userService.createUser(dto)
        return Response(status: .created)
    }
}

// ✗ SHOULD NOT TRIGGER: DTO decoding handles validation
func testValidationInHandler_Negative2() {
    struct CreateUserDTO: Codable {
        let name: String
        let email: String

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            if name.isEmpty { throw DecodingError.dataCorrupted(...) }
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 11. data-transformation-in-handler
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Map in handler
func testDataTransformationInHandler_Positive1() {
    router.get("/users") { request, context in
        let users = try await context.userService.listUsers()
        let names = users.map { $0.name }
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: Filter in handler
func testDataTransformationInHandler_Positive2() {
    router.get("/active-users") { request, context in
        let users = try await context.userService.listUsers()
        let active = users.filter { $0.isActive }
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: Reduce in handler
func testDataTransformationInHandler_Positive3() {
    router.get("/total") { request, context in
        let items = try await context.itemService.list()
        let total = items.reduce(0) { $0 + $1.price }
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: CompactMap in handler
func testDataTransformationInHandler_Positive4() {
    router.get("/ids") { request, context in
        let items = try await context.itemService.list()
        let ids = items.compactMap { $0.id }
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Service returns transformed data
func testDataTransformationInHandler_Negative1() {
    router.get("/users") { request, context in
        let dtos = try await context.userService.listActiveUserDTOs()
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Transformation in service layer
func testDataTransformationInHandler_Negative2() {
    class UserService {
        func listActiveUserDTOs() async throws -> [UserDTO] {
            let entities = try await repository.findAll()
            return entities.filter { $0.isActive }.map { UserDTO(from: $0) }
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 12. missing-request-decode
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: POST without decode (long enough handler)
func testMissingRequestDecode_Positive1() {
    router.post("/users") { request, context in
        let userService = context.userService
        let result = try await userService.createUserFromRequest(request)
        return Response(status: .created)
    }
}

// ✓ SHOULD TRIGGER: PUT without decode
func testMissingRequestDecode_Positive2() {
    router.put("/users/:id") { request, context in
        let userId = try request.uri.decode()
        let result = try await context.userService.updateUserRaw(userId, request)
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: POST with decode
func testMissingRequestDecode_Negative1() {
    router.post("/users") { request, context in
        let dto = try await request.decode(as: CreateUserDTO.self)
        let result = try await context.userService.createUser(dto)
        return Response(status: .created)
    }
}

// ✗ SHOULD NOT TRIGGER: GET has no body
func testMissingRequestDecode_Negative2() {
    router.get("/users") { request, context in
        let users = try await context.userService.listUsers()
        return Response(status: .ok)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 13. unchecked-uri-parameters
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Direct path access without validation
func testUncheckedUriParameters_Positive1() {
    router.get("/*") { request, context in
        let path = request.uri.path
        let file = try await loadFile(at: path)
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: Path assigned to variable without validation
func testUncheckedUriParameters_Positive2() {
    router.get("/download") { request, context in
        let filePath = request.uri.path
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Path validation with equality check
func testUncheckedUriParameters_Negative1() {
    router.get("/*") { request, context in
        if request.uri.path == "/health" {
            return Response(status: .ok)
        }
        return Response(status: .notFound)
    }
}

// ✗ SHOULD NOT TRIGGER: Path validation with startsWith
func testUncheckedUriParameters_Negative2() {
    router.get("/*") { request, context in
        if request.uri.path.starts(with: "/api/") {
            return Response(status: .ok)
        }
        return Response(status: .notFound)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 14. unchecked-query-parameters
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Direct query parameter access
func testUncheckedQueryParameters_Positive1() {
    router.get("/search") { request, context in
        let query = request.uri.queryParameters["q"]
        let results = try await context.searchService.search(query)
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: Query parameter without guard/if let
func testUncheckedQueryParameters_Positive2() {
    router.get("/filter") { request, context in
        let limit = request.uri.queryParameters["limit"]
        let items = try await context.itemService.list(limit: limit)
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: isEmpty check on queryParameters
func testUncheckedQueryParameters_Negative1() {
    router.get("/search") { request, context in
        if request.uri.queryParameters.isEmpty {
            return Response(status: .badRequest)
        }
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: DTO decoding handles query params
func testUncheckedQueryParameters_Negative2() {
    router.get("/search") { request, context in
        let dto = try await request.decode(as: SearchQueryDTO.self)
        let results = try await context.searchService.search(dto)
        return Response(status: .ok)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 15. raw-parameter-in-service-call
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: request.uri passed to service
func testRawParameterInServiceCall_Positive1() {
    router.get("/download") { request, context in
        let file = try await service.downloadFile(request.uri.path)
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: request.headers passed to service
func testRawParameterInServiceCall_Positive2() {
    router.post("/webhook") { request, context in
        try await service.processWebhook(request.headers.authorization)
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: request.parameters passed to service
func testRawParameterInServiceCall_Positive3() {
    router.get("/user/:id") { request, context in
        let user = try await service.getUser(request.parameters.id)
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Validated DTO passed to service
func testRawParameterInServiceCall_Negative1() {
    router.get("/download") { request, context in
        let dto = try await request.decode(as: DownloadDTO.self)
        let file = try await service.downloadFile(dto.filename)
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Extracted and validated parameter
func testRawParameterInServiceCall_Negative2() {
    router.get("/user/:id") { request, context in
        let userId: UUID = try request.uri.decode()
        let user = try await service.getUser(userId)
        return Response(status: .ok)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 16. direct-env-access
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: ProcessInfo.processInfo.environment access
func testDirectEnvAccess_Positive1() {
    let dbUrl = ProcessInfo.processInfo.environment["DATABASE_URL"]
}

// ✓ SHOULD TRIGGER: getenv() call
func testDirectEnvAccess_Positive2() {
    let apiKey = getenv("API_KEY")
}

// ✓ SHOULD TRIGGER: ProcessInfo.environment access
func testDirectEnvAccess_Positive3() {
    let port = ProcessInfo.environment["PORT"]
}

// ✗ SHOULD NOT TRIGGER: Configuration struct
func testDirectEnvAccess_Negative1() {
    let dbUrl = Configuration.shared.databaseURL
}

// ✗ SHOULD NOT TRIGGER: Injected config
func testDirectEnvAccess_Negative2() {
    struct AppConfig {
        let apiKey: String
        let port: Int
    }
    let config = AppConfig(apiKey: "...", port: 8080)
}

// ──────────────────────────────────────────────────────────────────────────────
// 17. hardcoded-url
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: HTTP URL hardcoded
func testHardcodedUrl_Positive1() {
    let apiUrl = "http://api.example.com/v1"
}

// ✓ SHOULD TRIGGER: HTTPS URL with type annotation
func testHardcodedUrl_Positive2() {
    let endpoint: String = "https://api.stripe.com/v1/charges"
}

// ✓ SHOULD TRIGGER: Variable with hardcoded URL
func testHardcodedUrl_Positive3() {
    var webhookUrl = "https://hooks.slack.com/services/T00/B00/XXX"
}

// ✗ SHOULD NOT TRIGGER: URL from configuration
func testHardcodedUrl_Negative1() {
    let apiUrl = Configuration.shared.externalApiUrl
}

// ✗ SHOULD NOT TRIGGER: URL built from config
func testHardcodedUrl_Negative2() {
    let baseUrl = config.baseUrl
    let fullUrl = "\(baseUrl)/api/v1"
}

// ──────────────────────────────────────────────────────────────────────────────
// 18. hardcoded-credentials
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Hardcoded password
func testHardcodedCredentials_Positive1() {
    let password = "mySecretPassword123"
}

// ✓ SHOULD TRIGGER: API key hardcoded
func testHardcodedCredentials_Positive2() {
    let apiKey = "sk_live_1234567890abcdef"
}

// ✓ SHOULD TRIGGER: Token hardcoded
func testHardcodedCredentials_Positive3() {
    var authToken = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
}

// ✓ SHOULD TRIGGER: API secret
func testHardcodedCredentials_Positive4() {
    let apiSecret = "secret_key_12345"
}

// ✗ SHOULD NOT TRIGGER: Password from environment
func testHardcodedCredentials_Negative1() {
    let password = Configuration.shared.databasePassword
}

// ✗ SHOULD NOT TRIGGER: Empty string literal for other purpose
func testHardcodedCredentials_Negative2() {
    let placeholder = ""
    let username = "admin"
}

// ──────────────────────────────────────────────────────────────────────────────
// 19. swallowed-error
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Empty catch block
func testSwallowedError_Positive1() {
    do {
        try riskyOperation()
    } catch {
    }
}

// ✓ SHOULD TRIGGER: Empty catch with whitespace
func testSwallowedError_Positive2() {
    do {
        try dangerousCall()
    } catch {

    }
}

// ✗ SHOULD NOT TRIGGER: Catch with logging
func testSwallowedError_Negative1() {
    do {
        try riskyOperation()
    } catch {
        logger.error("Operation failed: \(error)")
    }
}

// ✗ SHOULD NOT TRIGGER: Catch with error wrapping
func testSwallowedError_Negative2() {
    do {
        try dangerousCall()
    } catch {
        throw AppError.internalError(cause: error)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 20. error-discarded-with-underscore
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Error caught with underscore, not logged
func testErrorDiscardedWithUnderscore_Positive1() {
    do {
        try riskyOperation()
    } catch _ {
        return nil
    }
}

// ✓ SHOULD TRIGGER: Error bound but not logged or thrown
func testErrorDiscardedWithUnderscore_Positive2() {
    do {
        try dangerousCall()
    } catch let error {
        return Response(status: .internalServerError)
    }
}

// ✗ SHOULD NOT TRIGGER: Error logged
func testErrorDiscardedWithUnderscore_Negative1() {
    do {
        try riskyOperation()
    } catch let error {
        logger.error("Failed: \(error)")
        return nil
    }
}

// ✗ SHOULD NOT TRIGGER: Error wrapped in AppError
func testErrorDiscardedWithUnderscore_Negative2() {
    do {
        try dangerousCall()
    } catch let error {
        throw AppError.wrapped(error)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 21. generic-error-message
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Short generic error message
func testGenericErrorMessage_Positive1() {
    throw ValidationError("Invalid input")
}

// ✓ SHOULD TRIGGER: Generic error without context
func testGenericErrorMessage_Positive2() {
    throw AppError("Failed")
}

// ✓ SHOULD TRIGGER: No contextual details
func testGenericErrorMessage_Positive3() {
    throw DatabaseError("Query error")
}

// ✗ SHOULD NOT TRIGGER: Error with context (using colon)
func testGenericErrorMessage_Negative1() {
    throw AppError("Failed to create user: invalid email format")
}

// ✗ SHOULD NOT TRIGGER: Detailed error message
func testGenericErrorMessage_Negative2() {
    throw ValidationError("User email validation failed for user ID \(userId): domain not whitelisted")
}

// ──────────────────────────────────────────────────────────────────────────────
// 22. print-in-error-handler
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: print() in catch block
func testPrintInErrorHandler_Positive1() {
    do {
        try riskyOperation()
    } catch {
        print("Error occurred: \(error)")
    }
}

// ✓ SHOULD TRIGGER: debugPrint() in catch block
func testPrintInErrorHandler_Positive2() {
    do {
        try dangerousCall()
    } catch let error {
        debugPrint(error)
        throw AppError.wrapped(error)
    }
}

// ✗ SHOULD NOT TRIGGER: Logger in catch block
func testPrintInErrorHandler_Negative1() {
    do {
        try riskyOperation()
    } catch {
        logger.error("Operation failed: \(error)")
    }
}

// ✗ SHOULD NOT TRIGGER: Log with context
func testPrintInErrorHandler_Negative2() {
    do {
        try dangerousCall()
    } catch let error {
        log.error("Failed to process request", metadata: ["error": "\(error)"])
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 23. missing-error-wrapping
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Error re-thrown without wrapping
func testMissingErrorWrapping_Positive1() {
    do {
        try externalLibraryCall()
    } catch let error {
        throw error
    }
}

// ✓ SHOULD TRIGGER: Third-party error propagated directly
func testMissingErrorWrapping_Positive2() {
    do {
        try databaseQuery()
    } catch let dbError {
        throw dbError
    }
}

// ✗ SHOULD NOT TRIGGER: Error wrapped in AppError
func testMissingErrorWrapping_Negative1() {
    do {
        try externalLibraryCall()
    } catch let error {
        throw AppError.externalServiceFailed(service: "PaymentAPI", cause: error)
    }
}

// ✗ SHOULD NOT TRIGGER: Custom error thrown
func testMissingErrorWrapping_Negative2() {
    do {
        try databaseQuery()
    } catch let error {
        throw AppError.databaseError("Failed to execute query", underlyingError: error)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 24. response-without-status-code
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Response without status parameter
func testResponseWithoutStatusCode_Positive1() {
    return Response(body: .init(byteBuffer: buffer))
}

// ✓ SHOULD TRIGGER: Response with only body
func testResponseWithoutStatusCode_Positive2() {
    return Response(body: responseData)
}

// ✗ SHOULD NOT TRIGGER: Response with explicit status
func testResponseWithoutStatusCode_Negative1() {
    return Response(status: .ok, body: .init(byteBuffer: buffer))
}

// ✗ SHOULD NOT TRIGGER: Status code specified
func testResponseWithoutStatusCode_Negative2() {
    return Response(status: .created, headers: headers, body: data)
}

// ──────────────────────────────────────────────────────────────────────────────
// 25. inconsistent-response-format
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Hardcoded string in response body
func testInconsistentResponseFormat_Positive1() {
    return Response(status: .ok, body: "Success")
}

// ✓ SHOULD TRIGGER: JSON string literal
func testInconsistentResponseFormat_Positive2() {
    return Response(status: .created, body: "{\"id\": 123}")
}

// ✗ SHOULD NOT TRIGGER: DTO encoded as body
func testInconsistentResponseFormat_Negative1() {
    let dto = UserDTO(id: userId, name: "Test")
    return Response(status: .ok, body: dto.encode())
}

// ✗ SHOULD NOT TRIGGER: Structured response
func testInconsistentResponseFormat_Negative2() {
    return Response(status: .ok, body: .init(data: encodedDTO))
}

// ──────────────────────────────────────────────────────────────────────────────
// 26. response-missing-content-type
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Response without Content-Type header
func testResponseMissingContentType_Positive1() {
    return Response(status: .ok, body: jsonData)
}

// ✓ SHOULD TRIGGER: Response with body but no header
func testResponseMissingContentType_Positive2() {
    return Response(status: .created, headers: [:], body: payload)
}

// ✗ SHOULD NOT TRIGGER: Response with Content-Type header
func testResponseMissingContentType_Negative1() {
    return Response(status: .ok, body: jsonData)
        .withHeader(.contentType, "application/json")
}

// ✗ SHOULD NOT TRIGGER: Content-Type set in chain
func testResponseMissingContentType_Negative2() {
    return Response(status: .ok, body: xmlData)
        .withHeader(.contentType, "application/xml")
}

// ──────────────────────────────────────────────────────────────────────────────
// 27. sleep-in-handler
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: sleep() in route handler
func testSleepInHandler_Positive1() {
    router.get("/slow") { request, context in
        sleep(2)
        return Response(status: .ok)
    }
}

// ✓ SHOULD TRIGGER: Thread.sleep in handler
func testSleepInHandler_Positive2() {
    router.post("/delayed") { request, context in
        Thread.sleep(forTimeInterval: 1.5)
        return Response(status: .created)
    }
}

// ✓ SHOULD TRIGGER: usleep in handler
func testSleepInHandler_Positive3() {
    router.get("/wait") { request, context in
        usleep(1000000)
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Task.sleep (async)
func testSleepInHandler_Negative1() {
    router.get("/throttled") { request, context in
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return Response(status: .ok)
    }
}

// ✗ SHOULD NOT TRIGGER: Async delay in service
func testSleepInHandler_Negative2() {
    class RateLimitedService {
        func performAction() async throws {
            try await Task.sleep(for: .seconds(1))
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 28. blocking-io-in-async
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: FileHandle in async function
async func testBlockingIoInAsync_Positive1() {
    let handle = FileHandle(forReadingAtPath: "/tmp/file.txt")
}

// ✓ SHOULD TRIGGER: FileManager.contents in async
async func testBlockingIoInAsync_Positive2() {
    let data = FileManager.default.contents(atPath: "/tmp/data.bin")
}

// ✓ SHOULD TRIGGER: fopen in async context
async func testBlockingIoInAsync_Positive3() {
    let file = fopen("/tmp/output.log", "r")
}

// ✓ SHOULD TRIGGER: FileManager.createFile in async
async throws func testBlockingIoInAsync_Positive4() {
    FileManager.default.createFile(atPath: "/tmp/new.txt", contents: data)
}

// ✗ SHOULD NOT TRIGGER: AsyncFileHandle (hypothetical)
async func testBlockingIoInAsync_Negative1() {
    let handle = try await AsyncFileHandle.open("/tmp/file.txt")
}

// ✗ SHOULD NOT TRIGGER: Non-blocking I/O wrapper
async func testBlockingIoInAsync_Negative2() {
    let data = try await nonBlockingIO.readFile("/tmp/data.bin")
}

// ──────────────────────────────────────────────────────────────────────────────
// 29. synchronous-network-call
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: URLSession.dataTask without await
func testSynchronousNetworkCall_Positive1() {
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        // completion handler
    }
    task.resume()
}

// ✓ SHOULD TRIGGER: Synchronous URLSession
func testSynchronousNetworkCall_Positive2() {
    let session = URLSession(configuration: .default)
    session.dataTask(with: request) { data, response, error in
        // completion handler
    }
}

// ✗ SHOULD NOT TRIGGER: Async URLSession.data
async func testSynchronousNetworkCall_Negative1() {
    let (data, response) = try await URLSession.shared.data(for: request)
}

// ✗ SHOULD NOT TRIGGER: Async URLSession with await
async func testSynchronousNetworkCall_Negative2() {
    let (data, _) = try await URLSession.shared.data(from: url)
}

// ──────────────────────────────────────────────────────────────────────────────
// 30. blocking-sleep-in-async
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: sleep() in async function
async func testBlockingSleepInAsync_Positive1() {
    sleep(2)
    return "Done"
}

// ✓ SHOULD TRIGGER: Thread.sleep in async
async func testBlockingSleepInAsync_Positive2() {
    Thread.sleep(forTimeInterval: 1.0)
}

// ✓ SHOULD TRIGGER: usleep in async context
async func testBlockingSleepInAsync_Positive3() {
    usleep(500000)
}

// ✗ SHOULD NOT TRIGGER: Task.sleep (proper async)
async func testBlockingSleepInAsync_Negative1() {
    try await Task.sleep(nanoseconds: 2_000_000_000)
}

// ✗ SHOULD NOT TRIGGER: Task.sleep with Duration
async func testBlockingSleepInAsync_Negative2() {
    try await Task.sleep(for: .seconds(1))
}

// ──────────────────────────────────────────────────────────────────────────────
// 31. synchronous-database-call-in-async
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: .execute() in async without await
async func testSynchronousDatabaseCallInAsync_Positive1() {
    let result = db.execute("SELECT * FROM users")
}

// ✓ SHOULD TRIGGER: .query() without await
async func testSynchronousDatabaseCallInAsync_Positive2() {
    let rows = pool.query("SELECT id FROM products")
}

// ✗ SHOULD NOT TRIGGER: Async database call with await
async func testSynchronousDatabaseCallInAsync_Negative1() {
    let result = try await db.execute("SELECT * FROM users")
}

// ✗ SHOULD NOT TRIGGER: Awaited query
async func testSynchronousDatabaseCallInAsync_Negative2() {
    let rows = try await pool.query("SELECT id FROM products")
}

// ──────────────────────────────────────────────────────────────────────────────
// 32. global-mutable-state
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Global var without protection
var globalCache: [String: Any] = [:]

// ✓ SHOULD TRIGGER: Public mutable state
public var sharedConfig: Configuration = Configuration()

// ✓ SHOULD TRIGGER: Internal var
internal var requestCount: Int = 0

// ✗ SHOULD NOT TRIGGER: Global let (immutable)
let globalConstants: [String: String] = ["key": "value"]

// ✗ SHOULD NOT TRIGGER: Computed property (closure after =)
var computedValue: String = {
    return "computed"
}()

// ──────────────────────────────────────────────────────────────────────────────
// 33. missing-sendable-conformance
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Struct without Sendable
struct UserModel {
    let id: UUID
    let name: String
}

// ✓ SHOULD TRIGGER: Class without Sendable
class OrderEntity {
    let id: UUID
    init(id: UUID) { self.id = id }
}

// ✓ SHOULD TRIGGER: Enum without Sendable
enum PaymentStatus {
    case pending
    case completed
    case failed
}

// ✗ SHOULD NOT TRIGGER: Struct with Sendable
struct UserDTO: Sendable {
    let id: UUID
    let name: String
}

// ✗ SHOULD NOT TRIGGER: Final class with Sendable
final class OrderService: Sendable {
    let repository: OrderRepository
    init(repository: OrderRepository) {
        self.repository = repository
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 34. task-detached-without-isolation
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Task.detached without isolation
func testTaskDetachedWithoutIsolation_Positive1() {
    Task.detached {
        await performBackgroundWork()
    }
}

// ✓ SHOULD TRIGGER: Detached task no annotation
func testTaskDetachedWithoutIsolation_Positive2() {
    Task.detached {
        let result = await compute()
        return result
    }
}

// ✗ SHOULD NOT TRIGGER: Task.detached with @MainActor
func testTaskDetachedWithoutIsolation_Negative1() {
    Task.detached { @MainActor in
        await updateUI()
    }
}

// ✗ SHOULD NOT TRIGGER: Structured Task
func testTaskDetachedWithoutIsolation_Negative2() {
    Task {
        await performBackgroundWork()
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// 35. nonisolated-unsafe-usage
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: nonisolated(unsafe) attribute
actor DataProcessor {
    nonisolated(unsafe) var cache: [String: Data] = [:]
}

// ✓ SHOULD TRIGGER: Unsafe escape from isolation
class SharedResource {
    nonisolated(unsafe) var counter: Int = 0
}

// ✗ SHOULD NOT TRIGGER: Proper actor isolation
actor SafeDataProcessor {
    var cache: [String: Data] = [:]
}

// ✗ SHOULD NOT TRIGGER: Standard nonisolated (not unsafe)
actor Service {
    nonisolated func publicMethod() -> String {
        return "safe"
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - WARNING VIOLATIONS (suboptimal patterns)
// ══════════════════════════════════════════════════════════════════════════════

// ──────────────────────────────────────────────────────────────────────────────
// 36. shared-mutable-state-without-actor
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Mutable array at module scope
var moduleCache: [String] = []

// ✓ SHOULD TRIGGER: Mutable dictionary as var
var userSessions: [UUID: Session] = [:]

// ✗ SHOULD NOT TRIGGER: Immutable collection
let allowedDomains: [String] = ["example.com", "test.com"]

// ✗ SHOULD NOT TRIGGER: Actor-protected state
actor SessionManager {
    var activeSessions: [UUID: Session] = [:]
}

// ──────────────────────────────────────────────────────────────────────────────
// 37. nonisolated-context-access
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Context accessed in nonisolated
actor RequestProcessor {
    nonisolated func process() {
        let service = context.userService
    }
}

// ✓ SHOULD TRIGGER: nonisolated context property access
class Handler {
    nonisolated func handle() {
        let repo = context.repository
    }
}

// ✗ SHOULD NOT TRIGGER: Isolated context access
actor IsolatedProcessor {
    func process(context: AppRequestContext) {
        let service = context.userService
    }
}

// ✗ SHOULD NOT TRIGGER: Context passed explicitly
func handleRequest(context: AppRequestContext) {
    let service = context.userService
}

// ──────────────────────────────────────────────────────────────────────────────
// 38. magic-numbers
// ──────────────────────────────────────────────────────────────────────────────

// ✓ SHOULD TRIGGER: Magic timeout value
func testMagicNumbers_Positive1() {
    let timeout = 30000
}

// ✓ SHOULD TRIGGER: Magic limit value
func testMagicNumbers_Positive2() {
    let maxConnections = 100
}

// ✓ SHOULD TRIGGER: Magic port assignment
func testMagicNumbers_Positive3() {
    let port: Int = 8080
}

// ✓ SHOULD TRIGGER: Magic buffer size
func testMagicNumbers_Positive4() {
    let bufferSize = 4096
}

// ✗ SHOULD NOT TRIGGER: Named constant
func testMagicNumbers_Negative1() {
    let timeout = Configuration.requestTimeout
}

// ✗ SHOULD NOT TRIGGER: Small/common numbers
func testMagicNumbers_Negative2() {
    let retryCount = 3
    let offset = 1
}

// ══════════════════════════════════════════════════════════════════════════════
// MARK: - Test Support Types
// ══════════════════════════════════════════════════════════════════════════════

// Mock types used in test cases above
struct UserDTO: Codable {
    let id: UUID
    let name: String
    init() { self.id = UUID(); self.name = "" }
    init(id: UUID, name: String) { self.id = id; self.name = name }
    init(from entity: UserEntity) { self.id = entity.id; self.name = "" }
}

struct CreateUserDTO: Codable {
    let name: String
    let email: String
}

struct UpdateOrderRequest: Codable {
    let status: String
}

struct CheckoutDTO: Codable {
    let total: Double
}

struct DataDTO: Codable {
    func processDTO() -> DataDTO { return self }
}

struct CommentDTO: Codable {
    let text: String
    let tags: [String]
}

struct SearchQueryDTO: Codable {
    let query: String
}

struct DownloadDTO: Codable {
    let filename: String
}

struct CreateArticleDTO: Codable {
    let title: String
}

struct CreateOrderDTO: Codable {
    let items: [String]
}

struct UserModel {
    let id: UUID
    let name: String
    init() { self.id = UUID(); self.name = "" }
    init(id: UUID, name: String) { self.id = id; self.name = name }
}

struct ProductModel {
    init() {}
}

struct UserEntity {
    let id: UUID
    let isActive: Bool
    init() { self.id = UUID(); self.isActive = true }
    init(id: UUID) { self.id = id; self.isActive = true }
}

struct OrderEntity {
    init() {}
}

struct Session {
    let id: UUID
    init() { self.id = UUID() }
}

struct Configuration {
    static let shared = Configuration()
    let databaseURL = "postgres://localhost"
    let externalApiUrl = "https://api.example.com"
    let databasePassword = "secret"
    static let requestTimeout = 30000
}

struct AppRequestContext {
    let userService: UserService
    let orderService: OrderService
    let itemService: ItemService
    let searchService: SearchService
    let repository: UserRepository
}

class UserService {
    func getUser(by id: UUID) async throws -> UserDTO { return UserDTO() }
    func listUsers() async throws -> [UserDTO] { return [] }
    func createUser(_ dto: CreateUserDTO) async throws -> UserDTO { return UserDTO() }
    func listActiveUserDTOs() async throws -> [UserDTO] { return [] }
}

class OrderService {
    func createOrder(_ dto: CreateOrderDTO) async throws -> OrderEntity { return OrderEntity() }
    func checkout(_ dto: CheckoutDTO) async throws -> OrderEntity { return OrderEntity() }
}

class ItemService {
    func list() async throws -> [ItemDTO] { return [] }
}

class SearchService {
    func search(_ query: String?) async throws -> [SearchResult] { return [] }
    func search(_ dto: SearchQueryDTO) async throws -> [SearchResult] { return [] }
}

struct ItemDTO {
    let id: UUID
    let price: Double
    init() { self.id = UUID(); self.price = 0.0 }
}

struct SearchResult {
    let id: UUID
    init() { self.id = UUID() }
}

class UserRepository {
    func findById(_ id: UUID) async throws -> UserEntity { return UserEntity() }
    func findAll() async throws -> [UserEntity] { return [] }
}

enum ValidationError: Error {
    case invalidFormat
}

struct Response {
    init(status: HTTPStatus) {}
    init(status: HTTPStatus, body: ResponseBody) {}
    init(status: HTTPStatus, headers: [String: String], body: ResponseBody) {}
    init(body: ResponseBody) {}

    func withHeader(_ name: HTTPHeader, _ value: String) -> Response { return self }
}

struct ResponseBody {
    init(byteBuffer: ByteBuffer) {}
    init(data: Data) {}
}

enum HTTPStatus {
    case ok, created, accepted, badRequest, notFound, internalServerError
}

enum HTTPHeader {
    case contentType
}

struct HTTPError: Error {
    let status: HTTPStatus
    let message: String
    init(_ status: HTTPStatus, message: String = "") {
        self.status = status
        self.message = message
    }
}

struct AppError: Error {
    static func notFound(resource: String, id: String) -> AppError { return AppError() }
    static func internalError(cause: Error) -> AppError { return AppError() }
    static func wrapped(_ error: Error) -> AppError { return AppError() }
    static func externalServiceFailed(service: String, cause: Error) -> AppError { return AppError() }
    static func databaseError(_ message: String, underlyingError: Error) -> AppError { return AppError() }
}

struct ByteBuffer {}
struct Router {
    func get(_ path: String, handler: @escaping (Request, AppRequestContext) async throws -> Response) {}
    func post(_ path: String, handler: @escaping (Request, AppRequestContext) async throws -> Response) {}
    func put(_ path: String, handler: @escaping (Request, AppRequestContext) async throws -> Response) {}
    func patch(_ path: String, handler: @escaping (Request, AppRequestContext) async throws -> Response) {}
    func delete(_ path: String, handler: @escaping (Request, AppRequestContext) async throws -> Response) {}
}

struct Request {
    let uri: URI
    let parameters: Parameters
    func decode<T: Decodable>(as type: T.Type) async throws -> T { fatalError() }
}

struct URI {
    let path: String
    let queryParameters: [String: String]
    func decode<T>() throws -> T { fatalError() }
}

struct Parameters {
    let id: String
}

let router = Router()
let db = Database()
let pool = ConnectionPool()
let userRepository = UserRepository()
let logger = Logger()
let log = Logger()

struct Database {
    func query(_ sql: String, _ params: Any...) async throws -> [Any] { return [] }
    func execute(_ sql: String) async throws -> Any { return "" }
}

struct ConnectionPool {
    func execute(_ sql: String) async throws -> Any { return "" }
    func query(_ sql: String) async throws -> [Any] { return [] }
}

struct Logger {
    func error(_ message: String) {}
    func error(_ message: String, metadata: [String: String]) {}
}
