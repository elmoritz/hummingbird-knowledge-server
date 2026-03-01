// Sources/HummingbirdKnowledgeServer/AutoUpdate/ChangelogParser.swift
//
// Parses GitHub release notes (markdown) to extract deprecation information.
// Identifies renamed APIs, removed features, and breaking changes from changelog text.

import Foundation

/// Category of deprecation detected in release notes
enum DeprecationCategory: String, Sendable, Codable {
    case renamed    // API was renamed (old name → new name)
    case removed    // API was removed entirely
    case changed    // API behavior or signature changed in breaking way
}

/// Information about a deprecated API extracted from release notes
struct DeprecationInfo: Sendable, Codable {
    let deprecatedAPI: String           // The old/deprecated API name
    let replacementAPI: String?         // The new API name (nil if removed)
    let description: String             // Human-readable description
    let category: DeprecationCategory   // Type of deprecation
    let migrationGuidance: String?      // Optional migration instructions
}

/// Parses release note markdown to extract deprecation information
struct ChangelogParser: Sendable {

    /// Parse release notes and extract all deprecation information
    func parse(_ markdown: String) -> [DeprecationInfo] {
        var deprecations: [DeprecationInfo] = []

        // Split into lines for processing
        let lines = markdown.components(separatedBy: .newlines)

        // Track if we're inside a deprecation/breaking changes section
        var inDeprecationSection = false
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for deprecation section headers
            if isDeprecationSectionHeader(trimmed) {
                inDeprecationSection = true
                currentSection = trimmed
                continue
            }

            // Exit deprecation section if we hit a new non-deprecation section
            if trimmed.hasPrefix("##") && !isDeprecationSectionHeader(trimmed) {
                inDeprecationSection = false
                currentSection = ""
            }

            // Parse deprecation patterns from the line
            if let deprecation = parseRenamePattern(trimmed) {
                deprecations.append(deprecation)
            } else if let deprecation = parseRemovalPattern(trimmed) {
                deprecations.append(deprecation)
            } else if let deprecation = parseChangePattern(trimmed) {
                deprecations.append(deprecation)
            } else if let deprecation = parseInlineAnnotation(trimmed) {
                deprecations.append(deprecation)
            } else if inDeprecationSection && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                // Generic deprecation item in a deprecation section
                if let deprecation = parseGenericDeprecationItem(trimmed) {
                    deprecations.append(deprecation)
                }
            }
        }

        return deprecations
    }

    // MARK: - Section Detection

    private func isDeprecationSectionHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("deprecated") ||
               lowercased.contains("breaking change") ||
               lowercased.contains("removed") ||
               lowercased.contains("migration")
    }

    // MARK: - Pattern Parsers

    /// Parse rename patterns: "X renamed to Y", "X → Y", "X is now Y"
    private func parseRenamePattern(_ line: String) -> DeprecationInfo? {
        let lowercased = line.lowercased()

        // Pattern 1: "X renamed to Y"
        if lowercased.contains(" renamed to ") {
            let components = line.components(separatedBy: " renamed to ")
            if components.count >= 2 {
                let old = extractAPIName(from: components[0])
                let new = extractAPIName(from: components[1])
                if !old.isEmpty && !new.isEmpty {
                    return DeprecationInfo(
                        deprecatedAPI: old,
                        replacementAPI: new,
                        description: "Renamed to \(new)",
                        category: .renamed,
                        migrationGuidance: "Replace all uses of `\(old)` with `\(new)`"
                    )
                }
            }
        }

        // Pattern 2: "X → Y" or "X -> Y"
        if line.contains("→") || line.contains("->") {
            let separator = line.contains("→") ? "→" : "->"
            let components = line.components(separatedBy: separator)
            if components.count >= 2 {
                let old = extractAPIName(from: components[0])
                let new = extractAPIName(from: components[1])
                // Skip if this looks like a code flow or is too vague
                if !old.isEmpty && !new.isEmpty && !old.contains("(") && old.count < 100 {
                    return DeprecationInfo(
                        deprecatedAPI: old,
                        replacementAPI: new,
                        description: "Renamed to \(new)",
                        category: .renamed,
                        migrationGuidance: "Replace all uses of `\(old)` with `\(new)`"
                    )
                }
            }
        }

        return nil
    }

    /// Extract API name from a string, preferring backtick-enclosed names
    private func extractAPIName(from text: String) -> String {
        // Try to extract backticked name first
        if let start = text.firstIndex(of: "`"),
           let end = text[text.index(after: start)...].firstIndex(of: "`") {
            return String(text[text.index(after: start)..<end])
        }

        // Fall back to trimming common markdown characters
        return text.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "`*-•")))
    }

    /// Parse removal patterns: "Removed X", "X was removed", "X is no longer available"
    private func parseRemovalPattern(_ line: String) -> DeprecationInfo? {
        let lowercased = line.lowercased()

        // Pattern 1: "Removed X"
        if lowercased.contains("removed ") {
            // Try to find what comes after "removed"
            if let removedRange = lowercased.range(of: "removed ") {
                let afterRemoved = String(line[removedRange.upperBound...])
                let api = extractAPIName(from: afterRemoved)
                if !api.isEmpty && !api.lowercased().hasPrefix("the ") && !api.lowercased().hasPrefix("a ") {
                    return DeprecationInfo(
                        deprecatedAPI: api,
                        replacementAPI: nil,
                        description: "Removed from API",
                        category: .removed,
                        migrationGuidance: "This API has been removed. Refactor code to remove dependency."
                    )
                }
            }
        }

        // Pattern 2: "X was removed" or "X is removed"
        if lowercased.contains(" was removed") || lowercased.contains(" is removed") {
            let separator = lowercased.contains(" was removed") ? " was removed" : " is removed"
            if let separatorRange = lowercased.range(of: separator) {
                let beforeSeparator = String(line[..<separatorRange.lowerBound])
                let api = extractAPIName(from: beforeSeparator)
                if !api.isEmpty {
                    return DeprecationInfo(
                        deprecatedAPI: api,
                        replacementAPI: nil,
                        description: "Removed from API",
                        category: .removed,
                        migrationGuidance: "This API has been removed. Refactor code to remove dependency."
                    )
                }
            }
        }

        return nil
    }

    /// Parse change patterns: "X is now Y", "X has changed to Y"
    private func parseChangePattern(_ line: String) -> DeprecationInfo? {
        let lowercased = line.lowercased()

        // Pattern: "X is now Y"
        if lowercased.contains(" is now ") {
            let components = line.components(separatedBy: " is now ")
            if components.count >= 2 {
                let old = extractAPIName(from: components[0])
                let new = extractAPIName(from: components[1])
                if !old.isEmpty && !new.isEmpty && old.count < 100 {
                    return DeprecationInfo(
                        deprecatedAPI: old,
                        replacementAPI: new,
                        description: "Changed to \(new)",
                        category: .changed,
                        migrationGuidance: "Update code to use new behavior: \(new)"
                    )
                }
            }
        }

        return nil
    }

    /// Parse inline deprecation annotations: "@deprecated", "DEPRECATED:"
    private func parseInlineAnnotation(_ line: String) -> DeprecationInfo? {
        let lowercased = line.lowercased()

        if lowercased.contains("@deprecated") || lowercased.contains("deprecated:") {
            // Try to extract API name before the annotation
            if let match = line.range(of: #"`?([^`\s]+)`?\s*[@:-]\s*deprecated"#, options: [.regularExpression, .caseInsensitive]) {
                let matchedText = String(line[match])
                let components = matchedText.components(separatedBy: CharacterSet(charactersIn: "@:-"))
                if let api = components.first {
                    let cleaned = api.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "`*- ")))
                    if !cleaned.isEmpty {
                        return DeprecationInfo(
                            deprecatedAPI: cleaned,
                            replacementAPI: nil,
                            description: "Deprecated API",
                            category: .changed,
                            migrationGuidance: "Check release notes for replacement API"
                        )
                    }
                }
            }
        }

        return nil
    }

    /// Parse generic deprecation items from a deprecation section
    private func parseGenericDeprecationItem(_ line: String) -> DeprecationInfo? {
        // Look for list items with API names in backticks
        if line.hasPrefix("-") || line.hasPrefix("*") || line.hasPrefix("•") {
            if let match = line.range(of: #"`([^`]+)`"#, options: .regularExpression) {
                let api = String(line[match]).trimmingCharacters(in: .init(charactersIn: "`"))
                // Check if there's context about replacement
                let hasReplacement = line.lowercased().contains("use") || line.lowercased().contains("instead")
                return DeprecationInfo(
                    deprecatedAPI: api,
                    replacementAPI: nil,
                    description: "Deprecated in this release",
                    category: .changed,
                    migrationGuidance: hasReplacement ? "See release notes for migration guidance" : nil
                )
            }
        }

        return nil
    }
}
