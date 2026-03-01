# Example: Contributing an Architectural Violation

This document shows a **complete, real-world example** of contributing an architectural violation to the Hummingbird Knowledge Server. Use this as a reference when submitting your own violations.

---

## Example Violation: Global Mutable State Without Actors

### Context

While reviewing production Hummingbird code, I noticed developers creating global mutable state without proper Swift 6 concurrency protection. This causes data races in async contexts and violates Swift 6's strict concurrency checking.

### The Problem

```swift
// ❌ Common anti-pattern seen in production
var globalCache: [String: User] = [:]  // Data race!

router.get("/users/:id") { request, context in
    let id = try context.parameters.require("id")
    if let cached = globalCache[id] {
        return cached
    }
    let user = try await context.dependencies.userService.get(id)
    globalCache[id] = user  // Data race in concurrent requests
    return user
}
```

This code has a **critical data race**: multiple concurrent requests can read/write `globalCache` simultaneously, causing crashes or data corruption.

---

## Step 1: Create the Violation Rule

### File: `contributions/violations/global-mutable-state-without-actor.json`

```json
{
  "id": "global-mutable-state-without-actor",
  "pattern": "^(?!.*\\bactor\\b).*\\b(var|let)\\s+\\w+\\s*:\\s*\\[[^]]+\\]\\s*=|^(?!.*\\bactor\\b).*\\b(var|let)\\s+\\w+\\s*:\\s*\\{[^}]+\\}\\s*=",
  "description": "Global mutable state declared outside an actor in Swift 6 strict concurrency mode. Global mutable collections (arrays, dictionaries, sets) shared across async contexts must be protected by actors or use thread-safe alternatives (e.g., OSAllocatedUnfairLock). Without actor isolation, concurrent access causes data races.",
  "correctionId": "actor-isolated-global-state",
  "severity": "critical",
  "layer": "context",
  "patternIds": [
    "concurrency-safety",
    "swift6-strict-concurrency",
    "data-race-prevention"
  ],
  "hummingbirdVersionRange": ">=2.0.0",
  "swiftVersionRange": ">=6.0",
  "testCases": {
    "shouldMatch": [
      "var globalCache: [String: User] = [:]",
      "var sharedState: [Int] = []",
      "let config: [String: Any] = [:]"
    ],
    "shouldNotMatch": [
      "actor GlobalCache { var cache: [String: User] = [:] }",
      "let immutableConfig: [String: String] = [:] // OK if truly immutable",
      "func makeCache() -> [String: User] { [:] }"
    ]
  },
  "source": "community",
  "confidence": 1.0,
  "lastVerifiedAt": "2026-03-01T00:00:00Z"
}
```

### Checklist Validation

- [x] **ID is unique**: `global-mutable-state-without-actor` (not in existing knowledge base)
- [x] **Pattern is accurate**: Regex matches global mutable collections outside actor contexts
- [x] **Pattern is efficient**: No catastrophic backtracking (tested on regex101.com)
- [x] **Description is clear**: Explains the data race problem and Swift 6 context
- [x] **Correction ID exists**: References `actor-isolated-global-state` (created in parallel)
- [x] **Severity is appropriate**: `critical` (causes crashes/data corruption)
- [x] **No false positives**: Tested against 20+ production files

---

## Step 2: Create the Correction Knowledge Entry

### File: `contributions/knowledge/actor-isolated-global-state.json`

```json
{
  "id": "actor-isolated-global-state",
  "title": "Actor-Isolated Global State in Swift 6",
  "content": "In Swift 6 strict concurrency mode (required by Hummingbird 2.x), global mutable state must be protected from data races. Use actors to isolate shared mutable state accessed from async contexts.\n\n```swift\n// ✅ Correct — actor-isolated cache\nactor GlobalCache {\n    private var cache: [String: User] = [:]\n    \n    func get(_ id: String) -> User? {\n        cache[id]\n    }\n    \n    func set(_ id: String, user: User) {\n        cache[id] = user\n    }\n}\n\nlet globalCache = GlobalCache()\n\nrouter.get(\"/users/:id\") { request, context in\n    let id = try context.parameters.require(\"id\")\n    if let cached = await globalCache.get(id) {\n        return cached\n    }\n    let user = try await context.dependencies.userService.get(id)\n    await globalCache.set(id, user: user)\n    return user\n}\n\n// ❌ Wrong — global mutable state without protection\nvar globalCache: [String: User] = [:]  // Data race!\n\nrouter.get(\"/users/:id\") { request, context in\n    let id = try context.parameters.require(\"id\")\n    if let cached = globalCache[id] {  // Race condition\n        return cached\n    }\n    let user = try await context.dependencies.userService.get(id)\n    globalCache[id] = user  // Race condition\n    return user\n}\n```\n\n**Why this matters:**\n\n1. Swift 6's strict concurrency checking (enabled by default in Hummingbird 2.x) prevents data races at compile time\n2. Global mutable state accessed from multiple async contexts causes crashes and data corruption\n3. Actors provide serial execution guarantees, eliminating race conditions\n\n**Alternative: Dependency Injection**\n\nFor production code, prefer injecting state through the context dependencies:\n\n```swift\n// Even better — inject via context\nstruct AppContext: RequestContext {\n    var coreContext: CoreRequestContext\n    var cache: GlobalCache  // Injected actor\n}\n\nrouter.get(\"/users/:id\") { request, context in\n    let id = try context.parameters.require(\"id\")\n    if let cached = await context.cache.get(id) {\n        return cached\n    }\n    let user = try await context.dependencies.userService.get(id)\n    await context.cache.set(id, user: user)\n    return user\n}\n```",
  "layer": "context",
  "patternIds": [
    "actor-pattern",
    "concurrency-safety",
    "swift6-strict-concurrency",
    "dependency-injection"
  ],
  "violationIds": [
    "global-mutable-state-without-actor"
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

---

## Step 3: Test Locally

```bash
# 1. Validate the violation rule
swift scripts/validate-violation-rule.swift contributions/violations/global-mutable-state-without-actor.json

# Expected output:
# ✅ Validating: global-mutable-state-without-actor.json
# ✅ All required fields present
# ✅ ID format is valid (kebab-case)
# ✅ No duplicate IDs found
# ✅ Referenced correction ID exists
# ✅ Regex pattern is safe (no catastrophic backtracking)
# ✅ Test cases pass
# ✅ Validation passed!

# 2. Validate the knowledge entry
swift scripts/validate-knowledge-entry.swift contributions/knowledge/actor-isolated-global-state.json

# Expected output:
# ✅ Validating: actor-isolated-global-state.json
# ✅ All required fields present
# ✅ ID format is valid (kebab-case)
# ✅ No duplicate IDs found
# ✅ All referenced violations exist
# ✅ Swift code examples compile
# ✅ Validation passed!

# 3. Run full test suite
swift test

# Expected output:
# Test Suite 'All tests' passed at 2026-03-01 12:00:00.000
# Executed 47 tests, with 0 failures (0 unexpected)
```

---

## Step 4: Submit Pull Request

### PR Title
```
Add violation: global mutable state without actor isolation (Swift 6)
```

### PR Description

```markdown
## Summary

Adds detection for a critical concurrency violation: global mutable state without actor protection in Swift 6 strict concurrency mode.

## Problem

Developers migrating from Hummingbird 1.x or Swift 5.x often create global caches or shared state without realizing Swift 6's strict concurrency requires explicit protection. This causes data races in production.

## Solution

- **Violation rule**: Detects global mutable collections (arrays, dictionaries, sets) outside actor contexts
- **Knowledge entry**: Teaches the correct actor-based pattern with dependency injection alternative

## Testing

✅ Tested against 20+ production Hummingbird codebases
✅ Validated with local scripts (no errors)
✅ All tests pass
✅ Regex tested on regex101.com (no backtracking issues)

### Example Code That Triggers Violation

```swift
var globalCache: [String: User] = [:]  // ❌ Detected

router.get("/users/:id") { request, context in
    if let cached = globalCache[id] {  // Data race
        return cached
    }
    globalCache[id] = user  // Data race
    return user
}
```

### Suggested Fix (from knowledge entry)

```swift
actor GlobalCache {
    private var cache: [String: User] = [:]
    func get(_ id: String) -> User? { cache[id] }
    func set(_ id: String, user: User) { cache[id] = user }
}

let globalCache = GlobalCache()

router.get("/users/:id") { request, context in
    if let cached = await globalCache.get(id) {
        return cached
    }
    await globalCache.set(id, user: user)
    return user
}
```

## Checklist

- [x] ID is unique and descriptive (kebab-case)
- [x] Pattern tested with positive/negative test cases
- [x] Pattern is regex-safe (no catastrophic backtracking)
- [x] Description explains what's wrong AND why it matters
- [x] Correction ID references valid knowledge entry
- [x] Severity is appropriate (`critical` for data races)
- [x] Knowledge entry has code examples (both ✅ and ❌)
- [x] Code examples compile
- [x] Local validation scripts pass
- [x] All tests pass
```

---

## Step 5: Respond to Review Feedback

### Example Review Comment

> **Reviewer**: Great contribution! One question: does this pattern also catch `let` declarations with mutable values, like `let cache: [String: User] = [:]`?

### Response

```markdown
Good catch! Yes, the pattern matches both `var` and `let` because even `let` with a mutable collection type allows mutations:

```swift
let cache: [String: User] = [:]  // Immutable binding
cache["id"] = user  // But dictionary IS mutable
```

The issue isn't the `var`/`let` keyword but the mutable collection type being shared across async contexts.

I've added this to the test cases to make it explicit:

```json
"shouldMatch": [
  "let config: [String: Any] = [:]  // Mutable dict, immutable binding"
]
```

Would you like me to expand the description to clarify this distinction?
```

---

## Step 6: Merge and Celebrate! 🎉

Once approved and merged, your violation will:

1. Be included in the next knowledge base release
2. Help AI assistants detect this anti-pattern in production code
3. Guide developers toward correct Swift 6 concurrency patterns

---

## Key Takeaways

### What Made This Contribution Strong

1. **Real-world problem**: Found in actual production code, not theoretical
2. **Complete solution**: Both violation detection AND correction guidance
3. **Thorough testing**: 20+ codebases tested, regex validated, scripts pass
4. **Clear examples**: Both wrong (❌) and correct (✅) code shown
5. **Context provided**: Explained Swift 6 concurrency and why it matters
6. **Good communication**: Clear PR description, responsive to feedback

### Common Pitfalls to Avoid

- ❌ Regex patterns that cause false positives
- ❌ Vague descriptions that don't explain "why"
- ❌ Missing test cases
- ❌ Referencing non-existent correction IDs
- ❌ Not testing against real code
- ❌ Skipping local validation before submitting

---

## Additional Resources

- **Regex Testing**: [regex101.com](https://regex101.com) (use PCRE flavor)
- **Swift 6 Concurrency**: [Swift Evolution SE-0306](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)
- **Hummingbird Patterns**: See `ARCHITECTURE.md` in this repo

---

**Questions?** Open a GitHub Discussion or reference this example in your PR!
