// Sources/HummingbirdKnowledgeServer/AutoUpdate/ViolationRuleGenerator.swift
//
// Generates violation rules from parsed deprecation information.
// Converts DeprecationInfo from changelog parsing into DynamicViolation rules
// that can be used to detect deprecated API usage in code.

import Foundation

/// Generates DynamicViolation rules from parsed deprecation information
struct ViolationRuleGenerator: Sendable {

    /// Generate a DynamicViolation from deprecation information
    /// - Parameters:
    ///   - deprecation: Parsed deprecation info from release notes
    ///   - releaseVersion: Version string of the release (e.g. "2.5.0")
    /// - Returns: A dynamic violation rule ready for code checking
    func generate(from deprecation: DeprecationInfo, releaseVersion: String) -> DynamicViolation {
        let pattern = generatePattern(for: deprecation)
        let severity = determineSeverity(for: deprecation.category)
        let description = generateDescription(for: deprecation)
        let correctionId = generateCorrectionId(for: deprecation)
        let fixSuggestion = generateFixSuggestion(for: deprecation)

        return DynamicViolation(
            id: generateId(for: deprecation, releaseVersion: releaseVersion),
            pattern: pattern,
            description: description,
            correctionId: correctionId,
            severity: severity,
            fixSuggestion: fixSuggestion,
            reviewStatus: .draft,
            source: "auto-generated-from-release",
            generatedAt: Date(),
            sourceRelease: releaseVersion
        )
    }

    // MARK: - Pattern Generation

    /// Generate a regex pattern that matches deprecated API usage
    private func generatePattern(for deprecation: DeprecationInfo) -> String {
        let apiName = deprecation.deprecatedAPI

        // Detect API type based on naming conventions
        if apiName.hasPrefix("HB") {
            // Hummingbird type (HBApplication, HBRequest, etc.)
            // Match word boundaries to avoid partial matches
            return #"\b\#(escapeRegex(apiName))\b"#
        } else if apiName.contains("(") {
            // Function or method signature
            let baseName = apiName.components(separatedBy: "(").first ?? apiName
            return #"\b\#(escapeRegex(baseName))\s*\("#
        } else if apiName.contains(".") {
            // Qualified name or property access
            return escapeRegex(apiName)
        } else if apiName.first?.isUppercase == true {
            // Likely a type name (class, struct, protocol, enum)
            // Match in common contexts: declarations, type annotations, initializations
            return #"\b\#(escapeRegex(apiName))\b"#
        } else {
            // Likely a method or property name
            // Match as method call, property access, or reference
            return #"(\.\#(escapeRegex(apiName))\b|\b\#(escapeRegex(apiName))\s*\()"#
        }
    }

    /// Escape special regex characters in API names
    private func escapeRegex(_ string: String) -> String {
        let specialChars = CharacterSet(charactersIn: #".+*?^$()[]{}|\/"#)
        var result = ""
        for char in string {
            if char.unicodeScalars.contains(where: { specialChars.contains($0) }) {
                result += "\\"
            }
            result += String(char)
        }
        return result
    }

    // MARK: - Severity Determination

    /// Determine violation severity based on deprecation category
    private func determineSeverity(for category: DeprecationCategory) -> DynamicViolation.Severity {
        switch category {
        case .removed:
            // Removed APIs will cause compilation errors — high severity
            return .error
        case .renamed:
            // Renamed APIs are deprecated but may still compile — medium severity
            return .warning
        case .changed:
            // Changed APIs may have subtle behavioral differences — medium severity
            return .warning
        }
    }

    // MARK: - Description Generation

    /// Generate a human-readable description for the violation
    private func generateDescription(for deprecation: DeprecationInfo) -> String {
        switch deprecation.category {
        case .renamed:
            if let replacement = deprecation.replacementAPI {
                return "`\(deprecation.deprecatedAPI)` has been renamed to `\(replacement)`. "
                    + "\(deprecation.description)"
            } else {
                return "`\(deprecation.deprecatedAPI)` has been deprecated. "
                    + "\(deprecation.description)"
            }
        case .removed:
            return "`\(deprecation.deprecatedAPI)` has been removed from the API. "
                + "\(deprecation.description)"
        case .changed:
            if let replacement = deprecation.replacementAPI {
                return "`\(deprecation.deprecatedAPI)` has changed to `\(replacement)`. "
                    + "\(deprecation.description)"
            } else {
                return "`\(deprecation.deprecatedAPI)` has changed in a breaking way. "
                    + "\(deprecation.description)"
            }
        }
    }

    // MARK: - Correction ID Generation

    /// Generate a knowledge base correction ID
    private func generateCorrectionId(for deprecation: DeprecationInfo) -> String {
        // Convert API name to kebab-case for knowledge base ID
        let sanitized = deprecation.deprecatedAPI
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        switch deprecation.category {
        case .renamed:
            return "deprecated-\(sanitized)-renamed"
        case .removed:
            return "deprecated-\(sanitized)-removed"
        case .changed:
            return "deprecated-\(sanitized)-changed"
        }
    }

    // MARK: - Fix Suggestion Generation

    /// Generate a fix suggestion with before/after examples
    private func generateFixSuggestion(for deprecation: DeprecationInfo) -> FixSuggestion? {
        guard let replacement = deprecation.replacementAPI else {
            // No replacement available for removed APIs
            return nil
        }

        let before: String
        let after: String
        let explanation: String

        // Generate examples based on API type
        if deprecation.deprecatedAPI.hasPrefix("HB") {
            // Hummingbird type rename
            before = """
                // ❌ Wrong — using deprecated type
                import Hummingbird

                let app = \(deprecation.deprecatedAPI)()
                """
            after = """
                // ✅ Correct — using current type
                import Hummingbird

                let app = \(replacement)()
                """
            explanation = "\(deprecation.deprecatedAPI) was renamed to \(replacement) in this release. "
                + "Update all type references, variable declarations, and function signatures to use the new name. "
                + (deprecation.migrationGuidance ?? "The API is functionally identical; only the name has changed.")
        } else {
            // Generic API rename
            before = """
                // ❌ Wrong — using deprecated API
                \(generateExampleUsage(for: deprecation.deprecatedAPI))
                """
            after = """
                // ✅ Correct — using current API
                \(generateExampleUsage(for: replacement))
                """
            explanation = "\(deprecation.description). "
                + (deprecation.migrationGuidance ?? "Update all references to use the new API name.")
        }

        return FixSuggestion(
            before: before,
            after: after,
            explanation: explanation
        )
    }

    /// Generate example usage code for an API
    private func generateExampleUsage(for apiName: String) -> String {
        if apiName.contains("(") {
            // Method call
            return "\(apiName)"
        } else if apiName.first?.isUppercase == true {
            // Type usage
            return "let instance = \(apiName)()"
        } else {
            // Property or method
            return "someObject.\(apiName)"
        }
    }

    // MARK: - ID Generation

    /// Generate a unique ID for the violation
    private func generateId(for deprecation: DeprecationInfo, releaseVersion: String) -> String {
        let sanitized = deprecation.deprecatedAPI
            .lowercased()
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        let versionSanitized = releaseVersion.replacingOccurrences(of: ".", with: "-")
        return "auto-\(sanitized)-v\(versionSanitized)"
    }
}
