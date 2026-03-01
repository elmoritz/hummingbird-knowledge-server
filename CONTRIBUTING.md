# Contributing to Hummingbird Knowledge Server

Thank you for helping improve the Hummingbird Knowledge Server! This document explains how to contribute architectural violations and knowledge base entries that help AI assistants write production-quality Hummingbird code.

---

## What You Can Contribute

### 1. **Architectural Violations**
Anti-patterns and common mistakes in Hummingbird 2.x code that should be flagged and corrected. These are matched against user-submitted code using regex patterns.

### 2. **Knowledge Base Entries**
Production-quality architectural patterns, best practices, and corrections for violations. These teach AI assistants the right way to build Hummingbird applications.

---

## Contributing Architectural Violations

Architectural violations identify anti-patterns that should be flagged when detected in user code. Each violation has three severity levels:

- **`critical`**: Blocks code generation entirely (e.g., database calls in route handlers)
- **`error`**: Wrong architecture that will cause problems (e.g., raw errors thrown from handlers)
- **`warning`**: Suboptimal but not incorrect (e.g., magic numbers in configuration)

### Violation Format

Violations are defined in `Sources/HummingbirdKnowledgeServer/KnowledgeBase/ArchitecturalViolations.swift`:

```swift
ArchitecturalViolation(
    id: "unique-violation-id",
    pattern: #"regex-pattern-to-match"#,
    description: "Clear explanation of what's wrong and why it matters.",
    correctionId: "knowledge-base-entry-id",
    severity: .critical  // or .error or .warning
)
```

### Example Violation

```swift
ArchitecturalViolation(
    id: "inline-db-in-handler",
    pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.query|pool\.|db\.)"#,
    description: "Database calls inside a route handler closure. "
        + "Route handlers must be pure dispatchers — all DB access belongs "
        + "in the repository layer, called via the service layer.",
    correctionId: "route-handler-dispatcher-only",
    severity: .critical
)
```

### Violation Checklist

Before submitting a violation, ensure:

- [ ] **ID is unique**: Use kebab-case, descriptive, and not already in use
- [ ] **Pattern is accurate**: Test your regex against both positive and negative cases
- [ ] **Pattern is efficient**: Avoid catastrophic backtracking (use tools like regex101.com)
- [ ] **Description is clear**: Explain what's wrong AND why it matters
- [ ] **Correction ID exists**: Reference a knowledge base entry that explains the fix
- [ ] **Severity is appropriate**:
  - `critical`: Makes code fundamentally broken or unmaintainable
  - `error`: Violates clean architecture or will cause runtime issues
  - `warning`: Suboptimal style or maintainability issue
- [ ] **No false positives**: Test against production Hummingbird code to ensure accuracy

### Testing Your Violation Pattern

```swift
let pattern = #"your-regex-here"#
let testCode = """
router.post("/users") { request, context in
    try await db.query("INSERT INTO users...") // Should match
}
"""

if testCode.range(of: pattern, options: .regularExpression) != nil {
    print("✅ Pattern matches")
}
```

---

## Contributing Knowledge Base Entries

Knowledge base entries teach AI assistants production-quality Hummingbird patterns. They include code examples showing both correct and incorrect approaches.

### Entry Format

Entries are defined in `Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json`:

```json
{
  "id": "unique-entry-id",
  "title": "Human-Readable Pattern Name",
  "content": "Detailed explanation with code examples...",
  "layer": "controller",
  "patternIds": ["pattern-tag-1", "pattern-tag-2"],
  "violationIds": ["violation-id-this-corrects"],
  "hummingbirdVersionRange": ">=2.0.0",
  "swiftVersionRange": ">=6.0",
  "isTutorialPattern": false,
  "correctionId": null,
  "confidence": 1.0,
  "source": "embedded",
  "lastVerifiedAt": "2026-03-01T00:00:00Z"
}
```

### Example Entry

```json
{
  "id": "route-handler-dispatcher-only",
  "title": "Route Handlers Are Dispatchers Only",
  "content": "In Hummingbird 2.x clean architecture, route handlers have exactly one job: dispatch to the service layer and return the result. They must not contain business logic, database calls, or service construction.\n\n```swift\n// ✅ Correct — pure dispatcher\nrouter.post(\"/users\") { request, context in\n    let dto = try await request.decode(as: CreateUserRequest.self, context: context)\n    let user = try await context.dependencies.userService.create(dto)\n    return CreateUserResponse(user)\n}\n\n// ❌ Wrong — business logic in handler\nrouter.post(\"/users\") { request, context in\n    let dto = try await request.decode(as: CreateUserRequest.self, context: context)\n    guard !dto.email.isEmpty else { throw HTTPError(.badRequest) }\n    let hashed = BCrypt.hash(dto.password)\n    let user = User(email: dto.email, passwordHash: hashed)\n    try await db.save(user)\n    return user\n}\n```",
  "layer": "controller",
  "patternIds": ["dispatcher-pattern", "thin-controller"],
  "violationIds": ["inline-db-in-handler", "service-construction-in-handler"],
  "hummingbirdVersionRange": ">=2.0.0",
  "swiftVersionRange": ">=6.0",
  "isTutorialPattern": false,
  "correctionId": null,
  "confidence": 1.0,
  "source": "embedded",
  "lastVerifiedAt": "2025-01-01T00:00:00Z"
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | Unique identifier in kebab-case |
| `title` | `string` | Short, descriptive title for the pattern |
| `content` | `string` | Full explanation with code examples (supports Markdown) |
| `layer` | `string?` | Architecture layer: `controller`, `service`, `middleware`, `context`, or `null` |
| `patternIds` | `string[]` | Tags for categorization (e.g., `["dto-pattern", "api-boundary"]`) |
| `violationIds` | `string[]` | IDs of violations this entry corrects |
| `hummingbirdVersionRange` | `string` | Semantic version range (e.g., `">=2.0.0"`) |
| `swiftVersionRange` | `string` | Swift version range (e.g., `">=6.0"`) |
| `isTutorialPattern` | `boolean` | `true` if this is an anti-pattern commonly found in tutorials |
| `correctionId` | `string?` | ID of entry that corrects this pattern (for anti-patterns) |
| `confidence` | `number` | 0.0-1.0 confidence score in the advice |
| `source` | `string` | Source of knowledge: `"embedded"`, `"github"`, `"community"` |
| `lastVerifiedAt` | `string` | ISO 8601 date when pattern was last verified |

### Content Writing Guidelines

Your `content` field should:

1. **Start with a clear statement** of what the pattern is and why it matters
2. **Include code examples** showing:
   - ✅ **Correct approach** with explanation
   - ❌ **Wrong approach** with explanation of why it's incorrect
3. **Use consistent formatting**:
   - Mark correct examples with `// ✅ Correct —`
   - Mark incorrect examples with `// ❌ Wrong —`
   - Use triple backticks with `swift` language marker
4. **Focus on production patterns**, not tutorial simplifications
5. **Explain the "why"**, not just the "what"
6. **Keep it concise** but comprehensive (300-600 words ideal)

### Entry Checklist

Before submitting an entry, ensure:

- [ ] **ID is unique**: Use kebab-case, descriptive, and not already in use
- [ ] **Title is clear**: Short (5-10 words) and descriptive
- [ ] **Content has examples**: Both correct (✅) and incorrect (❌) code
- [ ] **Code examples compile**: Test your Swift code snippets
- [ ] **Layer is accurate**: Choose `controller`, `service`, `middleware`, `context`, or `null`
- [ ] **Pattern IDs are descriptive**: Use kebab-case tags for categorization
- [ ] **Violation IDs exist**: Reference actual violations in `ArchitecturalViolations.swift`
- [ ] **Version ranges are correct**: Verify compatibility with Hummingbird/Swift versions
- [ ] **Source is "community"**: For community contributions
- [ ] **Date is current**: Use today's date in ISO 8601 format
- [ ] **Confidence is appropriate**: Use 1.0 for verified patterns, lower for uncertain advice

---

## Submission Process

### 1. Fork and Clone

```bash
git clone https://github.com/your-username/hummingbird-knowledge-server
cd hummingbird-knowledge-server
git checkout -b add-[violation-or-entry-name]
```

### 2. Make Your Changes

**For violations:**
- Edit `Sources/HummingbirdKnowledgeServer/KnowledgeBase/ArchitecturalViolations.swift`
- Add your violation to the `all` array in the appropriate severity section

**For knowledge entries:**
- Edit `Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json`
- Add your entry to the JSON array (maintain proper JSON formatting)
- Validate JSON syntax: `cat knowledge.json | jq .` (requires jq)

### 3. Test Your Changes

```bash
# Build and run locally
swift run -c release HummingbirdKnowledgeServer

# Run tests
swift test

# Test your violation pattern against sample code
# (add test cases to the test suite)
```

### 4. Validate JSON

For knowledge base entries:

```bash
# Install jq if you don't have it: brew install jq
cat Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json | jq . > /dev/null && echo "✅ Valid JSON"
```

### 5. Submit a Pull Request

```bash
git add .
git commit -m "Add [violation/entry]: [brief description]"
git push origin add-[violation-or-entry-name]
```

Create a pull request with:
- **Title**: Clear description (e.g., "Add violation for global mutable state without actors")
- **Description**: Explain what the violation/entry detects and why it matters
- **Testing**: Describe how you tested the pattern
- **Examples**: Include sample code that triggers the violation (for violations)

---

## Automated Validation

All pull requests are automatically validated by our GitHub Actions workflow. This ensures that contributions meet quality standards before being merged.

### What Gets Validated Automatically

When you open a pull request, the workflow:

1. **Detects changes** to contribution files in:
   - `contributions/violations/*.json` — Violation rule submissions
   - `contributions/knowledge/*.json` — Knowledge entry submissions

2. **Runs validation scripts** on each contribution:
   - Validates JSON structure and required fields
   - Checks for duplicate IDs across the knowledge base
   - Verifies referenced IDs exist (e.g., `correctionId`, `violationIds`)
   - Tests regex patterns for safety (no catastrophic backtracking)
   - Validates code examples can compile
   - Checks semantic version ranges

3. **Posts results** as a PR comment with:
   - ✅/❌ Status for each file validated
   - Detailed error messages for failures
   - A checklist of quality requirements for your contribution type

### Running Validation Locally

**Before submitting your PR**, run validation locally to catch issues early:

#### Validate a Violation Rule

```bash
swift scripts/validate-violation-rule.swift contributions/violations/your-rule.json
```

#### Validate a Knowledge Entry

```bash
# Validate format and structure (skip compilation check)
swift scripts/validate-knowledge-entry.swift contributions/knowledge/your-entry.json --skip-compile
```

**Note**: The `--skip-compile` flag skips code compilation checks, which require the full Swift package context. Code examples will be validated for compilation when your contribution is merged and included in the test suite.

**Example output:**

```
✅ Validating: my-new-pattern.json

Checking structure...
✅ All required fields present
✅ ID format is valid (kebab-case)
✅ No duplicate IDs found

Checking references...
✅ All referenced violations exist
✅ All referenced patterns exist

Checking code examples...
✅ Swift code examples compile

✅ Validation passed!
```

### What to Do If Validation Fails

If the automated validation workflow reports errors:

1. **Read the error message carefully** — The workflow provides specific details about what failed:
   - Missing required fields
   - Invalid JSON syntax
   - Duplicate IDs
   - Non-existent reference IDs
   - Regex pattern errors
   - Invalid semantic version ranges

2. **Fix the issue locally**:
   ```bash
   # Make your corrections
   vim contributions/violations/your-rule.json

   # Re-run validation
   swift scripts/validate-violation-rule.swift contributions/violations/your-rule.json
   ```

3. **Push the fix**:
   ```bash
   git add contributions/violations/your-rule.json
   git commit -m "Fix validation errors in your-rule.json"
   git push
   ```

4. **Wait for re-validation** — The workflow will automatically re-run on your updated PR

### Common Validation Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Duplicate ID found` | Another entry already uses this ID | Choose a unique ID in kebab-case |
| `Referenced ID does not exist` | Your `correctionId` or `violationIds` reference missing entries | Verify the ID exists in the knowledge base |
| `Invalid JSON syntax` | Malformed JSON (missing comma, bracket, etc.) | Use `jq` to validate: `cat file.json \| jq .` |
| `Invalid regex pattern` | Pattern has catastrophic backtracking or syntax error | Test on [regex101.com](https://regex101.com) with PCRE flavor |
| `Missing required field` | JSON is missing a required property | Check the field descriptions and add the missing field |
| `Invalid semantic version` | Version range doesn't follow semver format | Use format like `">=2.0.0"` or `"^2.0.0"` |

### Validation Requirements

All contributions must pass:

1. **Compilation**: `swift build` succeeds
2. **Tests**: `swift test` passes
3. **JSON validation**: All JSON files are syntactically valid
4. **No duplicate IDs**: IDs must be unique across all violations and entries
5. **Referenced IDs exist**:
   - Violation `correctionId` must reference an existing knowledge entry
   - Knowledge entry `violationIds` must reference existing violations
6. **Code examples compile**: All Swift code in examples must be valid
7. **Regex patterns are safe**: No catastrophic backtracking in violation patterns

---

## Community Guidelines

### Quality Standards

- **Accuracy first**: Only submit patterns you've verified in production Hummingbird code
- **No speculation**: Avoid patterns based on assumptions or unverified claims
- **Production focus**: Avoid tutorial-style simplifications — this is for production code
- **Clear explanations**: Write for developers who may be new to Hummingbird but not to Swift

### What We're Looking For

**High priority:**
- Common mistakes from Hummingbird 1.x migration
- Swift 6 concurrency violations specific to Hummingbird
- Clean architecture violations in server-side Swift
- Performance anti-patterns in async/NIO contexts

**Not currently needed:**
- General Swift style guides (focus on Hummingbird-specific patterns)
- IDE configuration or tooling setup
- Deployment-specific patterns (unless Hummingbird-specific)

### Code of Conduct

- Be respectful and constructive in discussions
- Focus on technical merit, not personal preferences
- Provide evidence for architectural claims
- Help reviewers by explaining your reasoning

---

## Questions?

- **General questions**: Open a GitHub Discussion
- **Bug reports**: Open a GitHub Issue
- **Pattern clarifications**: Reference the `ARCHITECTURE.md` file

---

## License

By contributing, you agree that your contributions will be licensed under the same MIT License that covers this project.

---

Thank you for helping make Hummingbird development better for everyone! 🚀
