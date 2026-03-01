#!/usr/bin/env swift

// generate-pr-checklist.swift
//
// Generates PR review checklists for different contribution types.
// Outputs markdown checklists that reviewers can use to verify contribution quality.

import Foundation

// MARK: - Data Models

enum ContributionType: String {
    case violation
    case knowledge

    var displayName: String {
        switch self {
        case .violation: return "Violation Rule"
        case .knowledge: return "Knowledge Entry"
        }
    }
}

// MARK: - Checklist Generator

class ChecklistGenerator {

    func generate(for type: ContributionType) -> String {
        switch type {
        case .violation:
            return generateViolationChecklist()
        case .knowledge:
            return generateKnowledgeChecklist()
        }
    }

    private func generateViolationChecklist() -> String {
        return """
        # PR Review Checklist: Violation Rule Contribution

        Use this checklist to review the violation rule contribution systematically.

        ## 🔍 Required Checks

        ### Format & Structure
        - [ ] **Violation ID follows kebab-case convention**
          - Format: lowercase words separated by hyphens
          - Example: `inline-db-in-handler`, `service-construction-in-handler`

        - [ ] **ID is unique in ArchitecturalViolations.swift**
          - No existing violation uses this ID
          - Run: `grep -r "\\\"PROPOSED_ID\\\"" Sources/HummingbirdKnowledgeServer/`

        ### Regex Pattern
        - [ ] **Pattern regex is syntactically valid**
          - Compiles without errors in Swift
          - Use `#"raw string literal"#` format

        - [ ] **Pattern is tested and efficient**
          - No catastrophic backtracking
          - Verify on regex101.com or similar
          - Test complexity with long input strings

        - [ ] **Pattern matches all positive test cases**
          - Minimum 2 positive test cases provided
          - All positive cases trigger the violation

        - [ ] **Pattern doesn't match negative test cases**
          - Minimum 2 negative test cases provided
          - None of the negative cases trigger the violation

        ### Content Quality
        - [ ] **Description clearly explains WHAT is wrong**
          - States the anti-pattern being detected
          - Specific and concrete, not vague

        - [ ] **Description clearly explains WHY it matters**
          - References architectural principle being violated
          - Explains the impact or consequences
          - Length: 50+ characters (ideally 1-3 sentences)

        - [ ] **Correction ID references valid knowledge entry**
          - Entry exists in `knowledge.json` OR
          - Entry is included in this same PR
          - Run: `grep -r "\\\"CORRECTION_ID\\\"" Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json`

        ### Severity
        - [ ] **Severity is appropriate for the impact**
          - `critical` — Blocks code generation (makes code fundamentally broken)
          - `error` — Wrong architecture that causes problems
          - `warning` — Suboptimal but not incorrect

        ### Test Cases
        - [ ] **Test cases are comprehensive**
          - Cover common scenarios
          - Cover edge cases
          - Realistic code examples

        - [ ] **Test cases are accurate**
          - Positive cases genuinely violate the rule
          - Negative cases are genuinely correct patterns

        - [ ] **No false positives in test suite**
          - Tested against production Hummingbird code samples
          - Won't trigger on legitimate patterns

        ## ✅ Validation
        - [ ] **Validation script passes**
          - Run: `swift scripts/validate-violation-rule.swift [contribution-file.json]`
          - Exit code 0 with no errors

        - [ ] **Code compiles when added to ArchitecturalViolations.swift**
          - Run: `swift build`
          - No compilation errors

        ## 📝 Documentation
        - [ ] **If new pattern category, CONTRIBUTING.md is updated**
          - New category documented with examples
          - Guidelines for similar patterns added

        ## 🎯 Final Review
        - [ ] **Contribution adds clear value to the knowledge base**
          - Addresses real-world anti-pattern
          - Not overly specific or too broad
          - Complements existing violations

        ---

        ## Approval Criteria

        ✅ **Approve** if all required checks pass and contribution adds value
        ⚠️ **Request changes** if critical checks fail or major issues found
        💬 **Comment** for suggestions that improve quality but don't block merge

        """
    }

    private func generateKnowledgeChecklist() -> String {
        return """
        # PR Review Checklist: Knowledge Entry Contribution

        Use this checklist to review the knowledge entry contribution systematically.

        ## 🔍 Required Checks

        ### Format & Structure
        - [ ] **Entry ID follows kebab-case convention**
          - Format: lowercase words separated by hyphens
          - Example: `route-handler-dispatcher-only`, `repository-layer-db-access`

        - [ ] **ID is unique in knowledge.json**
          - No existing entry uses this ID
          - Run: `grep -r "\\"PROPOSED_ID\\"" Sources/HummingbirdKnowledgeServer/KnowledgeBase/knowledge.json`

        - [ ] **Title is clear and concise**
          - Length: 5-10 words
          - Descriptive and specific
          - Not too generic or too verbose

        ### Content Quality
        - [ ] **Content has comprehensive explanation**
          - Explains WHAT the pattern is
          - Explains WHY it matters
          - Provides architectural context
          - Length: 300-600 words ideal (minimum 50 characters)

        - [ ] **Content includes correct code example (✅)**
          - Marked with `✅ Correct` or similar
          - Shows the RIGHT way to implement the pattern
          - Complete, production-quality code
          - Code compiles without errors

        - [ ] **Content includes incorrect code example (❌)**
          - Marked with `❌ Wrong` or similar
          - Shows the WRONG way (anti-pattern)
          - Explains what's wrong with this approach
          - Demonstrates consequences or issues

        - [ ] **Code examples compile successfully**
          - Run: `swift scripts/validate-knowledge-entry.swift [contribution-file.json]`
          - All code examples marked with ✅ compile
          - No syntax errors

        ### Classification
        - [ ] **Layer is accurate**
          - Valid values: `controller`, `service`, `repository`, `model`, `middleware`, `configuration`, `transport`, `context`, or `null`
          - Layer matches the pattern's scope
          - `null` used only for cross-cutting concerns

        - [ ] **Pattern tags are descriptive**
          - 2-4 tags provided
          - Tags use kebab-case
          - Tags are specific and searchable

        - [ ] **If tutorial pattern, correctionId logic is correct**
          - `isTutorialPattern: true` → `correctionId` must be provided
          - `isTutorialPattern: false` → `correctionId` should be `null`
          - CorrectionId references valid knowledge entry

        ### Version Compatibility
        - [ ] **Hummingbird version range is valid**
          - Format: `>=X.Y.Z` or `X.Y.Z...Y.Y.Y`
          - Semantic versioning format
          - Realistic version (e.g., `>=2.0.0`)

        - [ ] **Swift version range is valid**
          - Format: `>=X.Y` or `X.Y...Y.Y`
          - Semantic versioning format
          - Realistic version (e.g., `>=6.0`)

        ### Quality & Source
        - [ ] **Confidence level is appropriate**
          - Value between 0.0 and 1.0
          - `1.0` = verified against production code
          - `0.95` = high confidence, minor edge cases
          - `0.9` = confident, limited real-world testing
          - `0.8` = theoretical but well-reasoned

        - [ ] **Source is "community"**
          - External contributions should always have `source: "community"`

        - [ ] **Last verified date is current**
          - ISO 8601 format: `YYYY-MM-DDTHH:MM:SSZ`
          - Date is reasonable (not future, not too old)

        ### Security
        - [ ] **No hardcoded secrets in code examples**
          - No API keys, passwords, tokens
          - No real database connection strings
          - No personally identifiable information

        ## ✅ Validation
        - [ ] **Validation script passes**
          - Run: `swift scripts/validate-knowledge-entry.swift [contribution-file.json]`
          - Exit code 0 with no errors

        - [ ] **Follows existing entry patterns**
          - Reviewed existing entries in `knowledge.json`
          - Matches style and format conventions
          - Consistent terminology

        ## 📝 Documentation
        - [ ] **If new pattern category, documentation is updated**
          - CONTRIBUTING.md includes guidelines for similar patterns
          - Examples added for new pattern types

        ## 🎯 Final Review
        - [ ] **Contribution adds clear value to the knowledge base**
          - Addresses real-world production pattern
          - Not duplicating existing entries
          - Complements existing knowledge

        - [ ] **Content is technically accurate**
          - Pattern recommendations are sound
          - No misleading or incorrect advice
          - Aligns with Hummingbird best practices

        ---

        ## Approval Criteria

        ✅ **Approve** if all required checks pass and contribution adds value
        ⚠️ **Request changes** if critical checks fail or major issues found
        💬 **Comment** for suggestions that improve quality but don't block merge

        """
    }
}

// MARK: - CLI

class CLI {

    func run() {
        let args = CommandLine.arguments

        // Handle help flag
        if args.contains("--help") || args.contains("-h") {
            printHelp()
            exit(0)
        }

        // Parse type argument
        guard let typeIndex = args.firstIndex(of: "--type"),
              typeIndex + 1 < args.count else {
            printError("Missing required argument: --type")
            printUsage()
            exit(1)
        }

        let typeValue = args[typeIndex + 1]
        guard let contributionType = ContributionType(rawValue: typeValue) else {
            printError("Invalid contribution type: '\(typeValue)'")
            printError("Valid types: violation, knowledge")
            exit(1)
        }

        // Generate and print checklist
        let generator = ChecklistGenerator()
        let checklist = generator.generate(for: contributionType)
        print(checklist)
        exit(0)
    }

    private func printHelp() {
        print("""
        generate-pr-checklist.swift - Generate PR review checklists for contributions

        USAGE:
            swift scripts/generate-pr-checklist.swift --type <TYPE>

        ARGUMENTS:
            --type <TYPE>    Type of contribution (required)
                             Values: violation, knowledge

        OPTIONS:
            --help, -h       Show this help message

        DESCRIPTION:
            Generates markdown checklists that PR reviewers can use to systematically
            verify contribution quality. The checklist includes all validation requirements,
            best practices, and approval criteria.

        EXAMPLES:
            # Generate checklist for violation rule review
            swift scripts/generate-pr-checklist.swift --type violation

            # Generate checklist for knowledge entry review
            swift scripts/generate-pr-checklist.swift --type knowledge

            # Save checklist to file
            swift scripts/generate-pr-checklist.swift --type violation > review-checklist.md

        CHECKLIST TYPES:

            violation - Violation Rule Contribution
                       Checklist for reviewing architectural violation rules, including
                       ID format, regex patterns, test cases, severity, and validation.

            knowledge - Knowledge Entry Contribution
                       Checklist for reviewing knowledge base entries, including content
                       quality, code examples, layer classification, and version compatibility.

        OUTPUT:
            Markdown-formatted checklist printed to stdout. Use shell redirection to save
            to a file, or copy-paste into PR review comments.

        EXIT CODES:
            0 - Success
            1 - Invalid arguments or usage error

        """)
    }

    private func printUsage() {
        print("Usage: swift scripts/generate-pr-checklist.swift --type <violation|knowledge>")
        print("Try 'swift scripts/generate-pr-checklist.swift --help' for more information.")
    }

    private func printError(_ message: String) {
        FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
    }
}

// MARK: - Entry Point

let cli = CLI()
cli.run()
