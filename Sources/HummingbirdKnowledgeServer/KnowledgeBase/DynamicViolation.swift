// Sources/HummingbirdKnowledgeServer/KnowledgeBase/DynamicViolation.swift
//
// Dynamically generated violation rules from release note parsing.
// Unlike static ArchitecturalViolations, these are auto-generated from deprecation notices
// and require review before activation.

import Foundation

/// Review status for dynamically generated violation rules
enum ViolationReviewStatus: String, Sendable, Codable {
    case draft      // Auto-generated, not yet reviewed
    case reviewed   // Reviewed by human, pending approval
    case approved   // Approved and active for code checking
}

/// A dynamically generated violation rule from release note analysis.
/// Compatible with ArchitecturalViolation but includes review metadata.
struct DynamicViolation: Sendable, Codable {
    let id: String
    let pattern: String         // Regex matched against source code
    let description: String
    let correctionId: String    // Knowledge base entry ID for the fix
    let severity: Severity
    let fixSuggestion: FixSuggestion?

    // Auto-generation metadata
    let reviewStatus: ViolationReviewStatus
    let source: String          // e.g. "auto-generated-from-release"
    let generatedAt: Date       // When the rule was generated
    let sourceRelease: String   // Release version that triggered generation (e.g. "2.5.0")

    init(
        id: String,
        pattern: String,
        description: String,
        correctionId: String,
        severity: Severity,
        fixSuggestion: FixSuggestion? = nil,
        reviewStatus: ViolationReviewStatus = .draft,
        source: String = "auto-generated-from-release",
        generatedAt: Date = Date(),
        sourceRelease: String
    ) {
        self.id = id
        self.pattern = pattern
        self.description = description
        self.correctionId = correctionId
        self.severity = severity
        self.fixSuggestion = fixSuggestion
        self.reviewStatus = reviewStatus
        self.source = source
        self.generatedAt = generatedAt
        self.sourceRelease = sourceRelease
    }

    enum Severity: String, Sendable, Codable {
        case warning    // Suboptimal but not incorrect
        case error      // Wrong — will cause problems
        case critical   // Blocks code generation entirely
    }
}

/// Re-export FixSuggestion from ArchitecturalViolations for compatibility
/// Note: FixSuggestion is defined in ArchitecturalViolations.swift
