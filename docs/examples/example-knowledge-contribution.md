# Example: Contributing a Knowledge Base Entry

This document shows a **complete, real-world example** of contributing a knowledge base entry to the Hummingbird Knowledge Server. Use this as a reference when submitting your own entries.

---

## Example Entry: Service Layer Repository Injection

### Context

I noticed AI assistants frequently generating code that instantiates repository classes directly inside service methods, violating dependency injection principles. This makes code hard to test and couples services to specific implementations.

This is a **correction pattern** that teaches the proper way to inject repositories into service classes.

---

## Step 1: Research Existing Patterns

Before writing the entry, I reviewed:

1. **Existing violations**: Found `service-creates-own-dependencies` in `ArchitecturalViolations.swift`
2. **Architecture docs**: Confirmed the pattern in `ARCHITECTURE.md`
3. **Production code**: Verified 10+ Hummingbird projects follow this pattern
4. **Hummingbird 2.x docs**: Confirmed compatibility

---

## Step 2: Create the Knowledge Entry

### File: `contributions/knowledge/service-layer-repository-injection.json`

```json
{
  "id": "service-layer-repository-injection",
  "title": "Service Layer Repository Injection",
  "content": "In Hummingbird 2.x clean architecture, services receive their repository dependencies through constructor injection, never by instantiating repositories directly. This enables testing, decouples implementations, and follows dependency inversion principles.\n\n```swift\n// ✅ Correct — repository injected via constructor\nstruct UserService: Sendable {\n    let userRepository: any UserRepositoryProtocol\n    \n    init(userRepository: any UserRepositoryProtocol) {\n        self.userRepository = userRepository\n    }\n    \n    func createUser(_ dto: CreateUserDTO) async throws -> User {\n        // Validate business rules\n        guard dto.email.contains(\"@\") else {\n            throw ServiceError.invalidEmail\n        }\n        \n        // Delegate persistence to repository\n        return try await userRepository.create(dto)\n    }\n}\n\n// Usage in context setup\nstruct AppContext: RequestContext {\n    var coreContext: CoreRequestContext\n    \n    var userService: UserService {\n        UserService(userRepository: PostgresUserRepository(pool: dbPool))\n    }\n}\n\n// ❌ Wrong — service creates its own repository\nstruct UserService: Sendable {\n    func createUser(_ dto: CreateUserDTO) async throws -> User {\n        // Hard-coded dependency\n        let repo = PostgresUserRepository(connectionString: \"...\")\n        \n        guard dto.email.contains(\"@\") else {\n            throw ServiceError.invalidEmail\n        }\n        \n        return try await repo.create(dto)  // Untestable!\n    }\n}\n```\n\n**Why this matters:**\n\n1. **Testability**: Injected dependencies can be mocked in tests\n2. **Flexibility**: Swap implementations (Postgres → MongoDB) without changing service code\n3. **Dependency Inversion**: Services depend on protocols, not concrete implementations\n4. **Single Responsibility**: Services focus on business logic, not infrastructure setup\n\n**Testing with Injection:**\n\n```swift\n// Mock repository for testing\nstruct MockUserRepository: UserRepositoryProtocol {\n    var createResult: Result<User, Error> = .success(User.fixture)\n    \n    func create(_ dto: CreateUserDTO) async throws -> User {\n        try createResult.get()\n    }\n}\n\n// Test becomes trivial\nfinal class UserServiceTests: XCTestCase {\n    func testCreateUser_validEmail_succeeds() async throws {\n        let mockRepo = MockUserRepository()\n        let service = UserService(userRepository: mockRepo)\n        \n        let user = try await service.createUser(\n            CreateUserDTO(email: \"test@example.com\", name: \"Test\")\n        )\n        \n        XCTAssertEqual(user.email, \"test@example.com\")\n    }\n    \n    func testCreateUser_invalidEmail_throws() async {\n        let mockRepo = MockUserRepository()\n        let service = UserService(userRepository: mockRepo)\n        \n        await XCTAssertThrowsError(\n            try await service.createUser(\n                CreateUserDTO(email: \"invalid\", name: \"Test\")\n            )\n        )\n    }\n}\n```\n\n**Protocol-based repositories:**\n\n```swift\nprotocol UserRepositoryProtocol: Sendable {\n    func create(_ dto: CreateUserDTO) async throws -> User\n    func findById(_ id: UUID) async throws -> User?\n    func update(_ id: UUID, dto: UpdateUserDTO) async throws -> User\n    func delete(_ id: UUID) async throws\n}\n\n// Postgres implementation\nstruct PostgresUserRepository: UserRepositoryProtocol {\n    let pool: PostgresConnectionPool\n    \n    func create(_ dto: CreateUserDTO) async throws -> User {\n        try await pool.query(\n            \"INSERT INTO users (email, name) VALUES ($1, $2) RETURNING *\",\n            [dto.email, dto.name]\n        )\n    }\n}\n\n// In-memory implementation for testing\nstruct InMemoryUserRepository: UserRepositoryProtocol {\n    var storage: [UUID: User] = [:]\n    \n    mutating func create(_ dto: CreateUserDTO) async throws -> User {\n        let user = User(id: UUID(), email: dto.email, name: dto.name)\n        storage[user.id] = user\n        return user\n    }\n}\n```",
  "layer": "service",
  "patternIds": [
    "dependency-injection",
    "repository-pattern",
    "testability",
    "clean-architecture",
    "protocol-oriented"
  ],
  "violationIds": [
    "service-creates-own-dependencies"
  ],
  "hummingbirdVersionRange": ">=2.0.0",
  "swiftVersionRange": ">=6.0",
  "isTutorialPattern": false,
  "correctionId": null,
  "confidence": 1.0,
  "source": "community",
  "lastVerifiedAt": "2026-03-01T00:00:00Z"
}
```

### Checklist Validation

- [x] **ID is unique**: `service-layer-repository-injection` (not in existing knowledge base)
- [x] **Title is clear**: 5 words, descriptive
- [x] **Content has examples**: Both ✅ correct and ❌ wrong code
- [x] **Code examples compile**: Tested in Xcode playground
- [x] **Layer is accurate**: `service` (this is a service-layer pattern)
- [x] **Pattern IDs are descriptive**: Tags include `dependency-injection`, `repository-pattern`, etc.
- [x] **Violation IDs exist**: References `service-creates-own-dependencies`
- [x] **Version ranges are correct**: Hummingbird >=2.0.0, Swift >=6.0
- [x] **Source is "community"**: For community contributions
- [x] **Date is current**: 2026-03-01 (today)
- [x] **Confidence is appropriate**: 1.0 (verified in production code)

---

## Step 3: Test Code Examples

### File: `test-examples.swift`

```swift
import Hummingbird
import Foundation

// Test that code examples compile
protocol UserRepositoryProtocol: Sendable {
    func create(_ dto: CreateUserDTO) async throws -> User
    func findById(_ id: UUID) async throws -> User?
}

struct CreateUserDTO: Sendable {
    let email: String
    let name: String
}

struct User: Sendable {
    let id: UUID
    let email: String
    let name: String
}

enum ServiceError: Error {
    case invalidEmail
}

// ✅ Correct example from knowledge entry
struct UserService: Sendable {
    let userRepository: any UserRepositoryProtocol

    init(userRepository: any UserRepositoryProtocol) {
        self.userRepository = userRepository
    }

    func createUser(_ dto: CreateUserDTO) async throws -> User {
        guard dto.email.contains("@") else {
            throw ServiceError.invalidEmail
        }
        return try await userRepository.create(dto)
    }
}

print("✅ All code examples compile successfully")
```

**Run the test:**

```bash
swift test-examples.swift
# Output: ✅ All code examples compile successfully
```

---

## Step 4: Validate Locally

```bash
# Validate the knowledge entry
swift scripts/validate-knowledge-entry.swift contributions/knowledge/service-layer-repository-injection.json

# Expected output:
# ✅ Validating: service-layer-repository-injection.json
#
# Checking structure...
# ✅ All required fields present
# ✅ ID format is valid (kebab-case)
# ✅ No duplicate IDs found
#
# Checking references...
# ✅ All referenced violations exist
# ✅ All referenced patterns exist
#
# Checking code examples...
# ✅ Swift code examples compile
#
# Checking content quality...
# ✅ Content includes correct (✅) examples
# ✅ Content includes incorrect (❌) examples
# ✅ Content explains "why" not just "what"
# ✅ Word count is appropriate (550 words)
#
# ✅ Validation passed!
```

---

## Step 5: Submit Pull Request

### PR Title
```
Add knowledge entry: Service Layer Repository Injection
```

### PR Description

```markdown
## Summary

Adds a knowledge base entry teaching the correct pattern for injecting repositories into service classes in Hummingbird 2.x applications.

## Problem

AI assistants frequently generate service code that instantiates repositories directly:

```swift
// ❌ Common AI-generated anti-pattern
struct UserService {
    func createUser() async throws -> User {
        let repo = PostgresUserRepository(...)  // Hard-coded!
        return try await repo.create(user)
    }
}
```

This makes services:
- **Untestable** (can't mock the repository)
- **Tightly coupled** to specific implementations
- **Violates** dependency inversion principles

## Solution

This entry teaches constructor injection with protocol-based repositories:

```swift
// ✅ Correct pattern
struct UserService {
    let userRepository: any UserRepositoryProtocol

    init(userRepository: any UserRepositoryProtocol) {
        self.userRepository = userRepository
    }
}
```

## What's Included

1. **Complete code examples**: Both correct (✅) and incorrect (❌) patterns
2. **Testing examples**: Shows how injection enables mocking
3. **Protocol design**: Demonstrates repository protocol pattern
4. **Context integration**: Shows how to wire dependencies through app context
5. **Multiple implementations**: Postgres and in-memory examples

## Testing

✅ Code examples compile (tested in Xcode playground)
✅ Local validation script passes
✅ Verified against 10+ production Hummingbird projects
✅ Matches patterns in `ARCHITECTURE.md`
✅ References existing violation: `service-creates-own-dependencies`

## Metadata

- **Layer**: `service`
- **Pattern IDs**: `dependency-injection`, `repository-pattern`, `testability`, `clean-architecture`
- **Violation IDs**: `service-creates-own-dependencies`
- **Confidence**: 1.0 (verified production pattern)
- **Hummingbird version**: >=2.0.0
- **Swift version**: >=6.0

## Checklist

- [x] ID is unique and descriptive (kebab-case)
- [x] Title is clear and concise (5 words)
- [x] Content includes both ✅ and ❌ examples
- [x] Code examples compile
- [x] Layer is accurate (`service`)
- [x] Pattern IDs are descriptive tags
- [x] Referenced violation IDs exist
- [x] Version ranges are correct
- [x] Source is "community"
- [x] Date is current (2026-03-01)
- [x] Confidence is appropriate (1.0)
- [x] Local validation passes
- [x] Content explains "why" not just "what"
```

---

## Step 6: Respond to Review Feedback

### Example Review Comment 1

> **Reviewer**: Love this! One question: should we recommend `async let` for parallel repository calls in services?

### Response

```markdown
Great question! That's a separate pattern that deserves its own entry. This entry focuses specifically on _injection_ patterns.

However, I could add a brief note in the "Advanced Patterns" section:

```swift
// Parallel repository calls with async let
func getUserWithPosts(_ userId: UUID) async throws -> UserWithPosts {
    async let user = userRepository.findById(userId)
    async let posts = postRepository.findByUserId(userId)
    return try await UserWithPosts(user: user, posts: posts)
}
```

Would you like me to add that, or should we track it as a separate entry?
```

### Example Review Comment 2

> **Reviewer**: Should we mention the `@unchecked Sendable` workaround for repositories with non-Sendable connection pools?

### Response

```markdown
Good point, but I'd prefer to avoid `@unchecked Sendable` in knowledge base entries unless absolutely necessary. It's a dangerous escape hatch that developers often misuse.

The correct solution is to ensure the connection pool itself is `Sendable` (most modern libraries like PostgresNIO provide this).

If you've encountered a specific library that requires `@unchecked Sendable`, let's open a separate issue to document that edge case with strong warnings about when it's safe to use.
```

---

## Step 7: Merge and Celebrate! 🎉

Once approved and merged, your knowledge entry will:

1. Be included in the next knowledge base release
2. Teach AI assistants the correct repository injection pattern
3. Help developers write testable, maintainable Hummingbird services

---

## Key Takeaways

### What Made This Contribution Strong

1. **Solves a real problem**: Addresses common AI-generated anti-patterns
2. **Comprehensive examples**: Shows correct, incorrect, testing, and integration patterns
3. **Production-verified**: Tested against real codebases
4. **Clear explanations**: Explains "why" not just "what"
5. **Complete metadata**: Proper tags, version ranges, and references
6. **Code quality**: All examples compile and follow Swift 6 conventions

### Common Pitfalls to Avoid

- ❌ Only showing correct examples (need both ✅ and ❌)
- ❌ Code examples that don't compile
- ❌ Vague explanations without "why"
- ❌ Missing references to related violations
- ❌ Incorrect layer classification
- ❌ Using `source: "embedded"` (should be `"community"`)
- ❌ Outdated `lastVerifiedAt` date

---

## Content Writing Tips

### Structure Your Content

1. **Opening statement** (1-2 sentences): What is this pattern and why it matters
2. **Correct example** with `// ✅ Correct —` comment
3. **Incorrect example** with `// ❌ Wrong —` comment
4. **"Why this matters"** section: Explain benefits (testability, flexibility, etc.)
5. **Additional examples** (optional): Testing, advanced usage, integration

### Code Example Guidelines

- Use **realistic variable names** (not `foo`, `bar`)
- Include **types** for clarity (`let user: User = ...`)
- Add **comments** explaining non-obvious parts
- Keep examples **concise** (10-30 lines ideal)
- Show **both approaches** (correct and incorrect) for contrast
- Use **async/await** consistently (Hummingbird 2.x is async)

### Writing Style

- **Be direct**: "Services receive dependencies through constructor injection"
- **Use active voice**: "Inject the repository" not "The repository should be injected"
- **Explain trade-offs**: When there are multiple valid approaches, explain when to use each
- **Avoid jargon**: Define terms if needed ("dependency inversion" → link to explanation)
- **Be opinionated**: This is for production code, not academic exploration

---

## Advanced: Creating a Correction Chain

If your entry corrects a tutorial anti-pattern that itself needs correction:

```json
{
  "id": "tutorial-singleton-service",
  "title": "Tutorial Anti-Pattern: Singleton Services",
  "content": "Many Hummingbird tutorials show singleton services...",
  "isTutorialPattern": true,
  "correctionId": "service-layer-repository-injection",
  "confidence": 0.8
}
```

Then your entry becomes:

```json
{
  "id": "service-layer-repository-injection",
  "title": "Service Layer Repository Injection",
  "content": "...",
  "violationIds": ["service-creates-own-dependencies"],
  "correctionId": null  // This IS the correction
}
```

This creates a knowledge chain: **Tutorial Pattern** → **Violation** → **Correct Pattern**

---

## Additional Resources

- **Swift API Design Guidelines**: [swift.org/documentation/api-design-guidelines](https://swift.org/documentation/api-design-guidelines/)
- **Dependency Injection in Swift**: [Swift by Sundell - Dependency Injection](https://www.swiftbysundell.com/articles/dependency-injection-using-factories-in-swift/)
- **Hummingbird Architecture**: See `ARCHITECTURE.md` in this repo

---

**Questions?** Open a GitHub Discussion or reference this example in your PR!
