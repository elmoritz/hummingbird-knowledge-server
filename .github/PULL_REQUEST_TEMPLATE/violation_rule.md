# Add Violation Rule: [Rule Name]

Thank you for contributing to the Hummingbird Knowledge Server! This PR template helps ensure your violation rule is complete, accurate, and ready for review.

---

## Violation Details

### Violation ID
<!--
Provide a unique identifier in kebab-case.
Example: "inline-db-in-handler", "service-construction-in-handler"
-->

**ID:** `violation-id-here`

### Pattern Regex
<!--
Provide the regex pattern that will match this violation.
- Use raw string literals: #"pattern"#
- Test thoroughly using regex101.com or similar
- Avoid catastrophic backtracking
- Test against both positive (should match) and negative (should not match) cases
-->

```swift
#"your-regex-pattern-here"#
```

### Description
<!--
Clearly explain:
1. WHAT is wrong (the anti-pattern being detected)
2. WHY it matters (the architectural principle being violated)

Keep it concise but comprehensive (1-3 sentences).
Example: "Database calls inside a route handler closure. Route handlers must be pure dispatchers — all DB access belongs in the repository layer, called via the service layer."
-->

**Description:**



### Correction ID
<!--
Reference the knowledge base entry ID that explains the correct approach.
This must be an existing entry in knowledge.json or submitted alongside this violation.
Example: "route-handler-dispatcher-only"
-->

**Correction ID:** `correction-entry-id-here`

### Severity
<!--
Choose ONE severity level:
- [ ] **critical** — Blocks code generation entirely (makes code fundamentally broken or unmaintainable)
- [ ] **error** — Wrong architecture that will cause problems (violates clean architecture or causes runtime issues)
- [ ] **warning** — Suboptimal but not incorrect (style or maintainability issue)
-->

**Severity:** `.critical` / `.error` / `.warning` _(delete two)_

---

## Test Cases

### Positive Test Cases (Should Match)
<!--
Provide at least 2 code examples that SHOULD trigger this violation.
These demonstrate the anti-pattern your regex detects.
-->

#### Test Case 1
```swift
// Example code that should match the violation pattern


```

#### Test Case 2
```swift
// Another example that should match the violation pattern


```

### Negative Test Cases (Should NOT Match)
<!--
Provide at least 2 code examples that should NOT trigger this violation.
These demonstrate correct code or edge cases that might look similar but are acceptable.
-->

#### Test Case 1
```swift
// Example code that should NOT match (correct pattern)


```

#### Test Case 2
```swift
// Another example that should NOT match


```

---

## Validation Results

<!--
Before submitting, run the validation script to verify your violation rule:

```bash
swift run validate-violation-rule
```

Paste the output here, or confirm all checks passed.
-->

```
Paste validation script output here
```

---

## Pre-Submission Checklist

Before submitting this PR, verify:

- [ ] **ID is unique**: Checked that no existing violation uses this ID
- [ ] **Pattern is accurate**: Tested regex against all positive test cases (all match)
- [ ] **Pattern is accurate**: Tested regex against all negative test cases (none match)
- [ ] **Pattern is efficient**: Verified no catastrophic backtracking using regex101.com
- [ ] **Description is clear**: Explains both WHAT is wrong AND WHY it matters
- [ ] **Correction ID exists**: Referenced knowledge base entry exists or is included in this PR
- [ ] **Severity is appropriate**: Chosen severity matches the impact guidelines
- [ ] **No false positives**: Tested against production Hummingbird code samples
- [ ] **Test cases provided**: Minimum 2 positive and 2 negative test cases included
- [ ] **Validation script passed**: Ran `swift run validate-violation-rule` successfully
- [ ] **Code compiles**: Added violation to `ArchitecturalViolations.swift` and verified compilation
- [ ] **Documentation updated**: If this is a new pattern category, updated CONTRIBUTING.md

---

## Additional Context

<!--
Optional: Add any additional context, rationale, or discussion points.
- Why is this violation important?
- What real-world issues does it prevent?
- Are there any edge cases reviewers should be aware of?
- References to documentation, discussions, or issues?
-->

---

## Reviewer Notes

<!--
For reviewers: Check that:
1. Violation ID follows kebab-case convention
2. Pattern regex is tested and efficient
3. Description clearly explains what and why
4. Correction ID references valid knowledge entry
5. Severity is appropriate for the impact
6. Test cases are comprehensive and accurate
7. Validation script passes
8. No false positives in test suite
-->
