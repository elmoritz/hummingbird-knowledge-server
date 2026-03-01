---
name: Knowledge Entry Contribution
about: Submit a new knowledge base entry for Hummingbird production patterns
title: '[KNOWLEDGE] '
labels: 'contribution, knowledge-entry'
---

# Knowledge Entry Contribution

Thank you for contributing a knowledge base entry to help AI assistants write better Hummingbird code! This template guides you through providing all required information.

---

## Entry Metadata

### Entry ID
**Unique identifier (kebab-case):**
```
<!-- Example: route-handler-dispatcher-only -->
```

### Title
**Short, descriptive title (5-10 words):**
```
<!-- Example: Route Handlers Are Dispatchers Only -->
```

---

## Content

### Pattern Explanation
**Provide a clear explanation of the pattern and why it matters:**

```markdown
<!-- Start with a clear statement of what the pattern is and why it matters.
     Explain the "why", not just the "what".
     Keep it concise but comprehensive (300-600 words ideal). -->
```

### Code Examples

**✅ Correct approach:**
```swift
// ✅ Correct — [brief explanation]

// Provide a complete, production-quality code example showing the RIGHT way
```

**❌ Incorrect approach:**
```swift
// ❌ Wrong — [brief explanation of what's wrong]

// Provide a complete code example showing the WRONG way and why it fails
```

---

## Classification

### Layer
**Select the architecture layer this pattern applies to:**
- [ ] `controller` - Route handlers and HTTP layer
- [ ] `service` - Business logic layer
- [ ] `middleware` - Request/response pipeline
- [ ] `context` - Dependency injection and request context
- [ ] `null` - Cross-cutting or layer-agnostic pattern

### Pattern Tags
**Provide 2-4 descriptive tags (kebab-case) for categorization:**
```
<!-- Example: ["dispatcher-pattern", "thin-controller"] -->
```

### Related Violations
**List IDs of violations this entry corrects (if any):**
```
<!-- Example: ["inline-db-in-handler", "service-construction-in-handler"] -->
<!-- Leave empty [] if this entry doesn't correct specific violations -->
```

---

## Version Compatibility

### Hummingbird Version Range
**Semantic version range this pattern applies to:**
```
<!-- Example: ">=2.0.0" -->
```

### Swift Version Range
**Swift version range required:**
```
<!-- Example: ">=6.0" -->
```

---

## Pattern Type

### Is this a tutorial anti-pattern?
- [ ] Yes - This is an anti-pattern commonly found in tutorials
- [ ] No - This is a production pattern

**If yes, provide the correction entry ID:**
```
<!-- Example: "route-handler-dispatcher-only" -->
<!-- This should reference the knowledge entry that shows the correct approach -->
```

---

## Quality & Source

### Confidence Level
**Rate your confidence in this advice (0.0 to 1.0):**
```
<!-- 1.0 = verified against production code -->
<!-- 0.95 = high confidence, minor edge cases -->
<!-- 0.9 = confident, but limited real-world testing -->
<!-- 0.8 = theoretical but well-reasoned -->
```

### Source
**Contribution source:**
```
community
```
<!-- This should always be "community" for external contributions -->

### Last Verified Date
**Date pattern was last verified (ISO 8601):**
```
<!-- Example: 2026-03-01T00:00:00Z -->
<!-- Use today's date -->
```

---

## Contribution Checklist

Before submitting, verify:

- [ ] **ID is unique**: Checked that this ID doesn't exist in `Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json`
- [ ] **Title is clear**: Short (5-10 words) and descriptive
- [ ] **Content has examples**: Both correct (✅) and incorrect (❌) code provided
- [ ] **Code examples compile**: Tested Swift code snippets for syntax errors
- [ ] **Layer is accurate**: Selected the correct architecture layer
- [ ] **Pattern IDs are descriptive**: Used kebab-case tags for categorization
- [ ] **Violation IDs exist**: If provided, verified they exist in `ArchitecturalViolations.swift`
- [ ] **Version ranges are correct**: Verified compatibility with Hummingbird/Swift versions
- [ ] **Source is "community"**: Confirmed source field is set to "community"
- [ ] **Date is current**: Used today's date in ISO 8601 format
- [ ] **Confidence is appropriate**: Used 1.0 for verified patterns, lower for uncertain advice
- [ ] **No hardcoded secrets**: Code examples don't contain API keys, passwords, or tokens
- [ ] **Follows existing patterns**: Reviewed existing entries in `knowledge.json` for consistency
- [ ] **Validation script passes**: Run `swift test --filter KnowledgeValidationTests` locally

---

## Additional Context

**Provide any additional context about this pattern:**
<!-- Optional: links to documentation, real-world scenarios, common pitfalls, etc. -->

---

## Reviewer Notes

<!-- This section is for maintainers. Leave empty. -->
