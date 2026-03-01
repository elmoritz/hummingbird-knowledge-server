// Tests/HummingbirdKnowledgeServerTests/ViolationRuleGeneratorTests.swift
//
// Comprehensive tests for ViolationRuleGenerator: generation of DynamicViolation rules
// from DeprecationInfo, pattern generation, severity determination, description generation,
// correction ID generation, and fix suggestions.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class ViolationRuleGeneratorTests: XCTestCase {

    // MARK: - Basic Generation

    func testGenerateCreatesValidDynamicViolation() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "HBApplication",
            replacementAPI: "Application",
            description: "Type renamed in v2.0.0",
            category: .renamed,
            migrationGuidance: "Replace all references with Application"
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertFalse(violation.id.isEmpty)
        XCTAssertFalse(violation.pattern.isEmpty)
        XCTAssertFalse(violation.description.isEmpty)
        XCTAssertFalse(violation.correctionId.isEmpty)
        XCTAssertEqual(violation.reviewStatus, .draft)
        XCTAssertEqual(violation.source, "auto-generated-from-release")
        XCTAssertEqual(violation.sourceRelease, "2.0.0")
    }

    func testGeneratePopulatesAllFields() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "oldMethod",
            replacementAPI: "newMethod",
            description: "Method renamed",
            category: .renamed,
            migrationGuidance: "Use newMethod instead"
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "1.5.0")

        XCTAssertNotNil(violation.id)
        XCTAssertNotNil(violation.pattern)
        XCTAssertNotNil(violation.description)
        XCTAssertNotNil(violation.correctionId)
        XCTAssertNotNil(violation.severity)
        XCTAssertNotNil(violation.fixSuggestion)
        XCTAssertEqual(violation.sourceRelease, "1.5.0")
    }

    // MARK: - Pattern Generation

    func testGeneratePatternForHummingbirdType() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "HBApplication",
            replacementAPI: "Application",
            description: "Type renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        // Should generate word boundary pattern for HB-prefixed types
        XCTAssertTrue(violation.pattern.contains("HBApplication"))
        XCTAssertTrue(violation.pattern.contains(#"\b"#))
    }

    func testGeneratePatternForFunctionWithParentheses() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "configure()",
            replacementAPI: "setup()",
            description: "Function renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        // Should generate pattern for function call
        XCTAssertTrue(violation.pattern.contains("configure"))
    }

    func testGeneratePatternForQualifiedName() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "context.logger",
            replacementAPI: "request.logger",
            description: "Property moved",
            category: .changed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        // Should escape the dot in the qualified name
        XCTAssertTrue(violation.pattern.contains("context"))
        XCTAssertTrue(violation.pattern.contains("logger"))
    }

    func testGeneratePatternForTypeNameUppercase() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "OldRouter",
            replacementAPI: "NewRouter",
            description: "Type renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        // Should generate word boundary pattern for type names
        XCTAssertTrue(violation.pattern.contains("OldRouter"))
        XCTAssertTrue(violation.pattern.contains(#"\b"#))
    }

    func testGeneratePatternEscapesSpecialCharacters() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "operator+",
            replacementAPI: "addOperator",
            description: "Operator renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        // Pattern should be generated even with special characters
        XCTAssertFalse(violation.pattern.isEmpty)
        XCTAssertTrue(violation.pattern.contains("operator"))
    }

    // MARK: - Severity Determination

    func testSeverityForRemovedAPI() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "RemovedClass",
            replacementAPI: nil,
            description: "Class removed",
            category: .removed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertEqual(violation.severity, .error, "Removed APIs should have error severity")
    }

    func testSeverityForRenamedAPI() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "OldName",
            replacementAPI: "NewName",
            description: "API renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertEqual(violation.severity, .warning, "Renamed APIs should have warning severity")
    }

    func testSeverityForChangedAPI() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "asyncMethod",
            replacementAPI: "async throws",
            description: "Method signature changed",
            category: .changed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertEqual(violation.severity, .warning, "Changed APIs should have warning severity")
    }

    // MARK: - Description Generation

    func testDescriptionForRenamedAPIWithReplacement() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "HBApplication",
            replacementAPI: "Application",
            description: "Type renamed in major release",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertTrue(violation.description.contains("HBApplication"))
        XCTAssertTrue(violation.description.contains("Application"))
        XCTAssertTrue(violation.description.contains("renamed"))
        XCTAssertTrue(violation.description.contains("Type renamed in major release"))
    }

    func testDescriptionForRenamedAPIWithoutReplacement() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "OldAPI",
            replacementAPI: nil,
            description: "API deprecated without replacement",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertTrue(violation.description.contains("OldAPI"))
        XCTAssertTrue(violation.description.contains("deprecated"))
        XCTAssertTrue(violation.description.contains("API deprecated without replacement"))
    }

    func testDescriptionForRemovedAPI() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "RemovedClass",
            replacementAPI: nil,
            description: "No longer supported",
            category: .removed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertTrue(violation.description.contains("RemovedClass"))
        XCTAssertTrue(violation.description.contains("removed"))
        XCTAssertTrue(violation.description.contains("No longer supported"))
    }

    func testDescriptionForChangedAPIWithReplacement() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "configure()",
            replacementAPI: "async configure()",
            description: "Method is now async",
            category: .changed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertTrue(violation.description.contains("configure()"))
        XCTAssertTrue(violation.description.contains("async configure()"))
        XCTAssertTrue(violation.description.contains("changed"))
        XCTAssertTrue(violation.description.contains("Method is now async"))
    }

    func testDescriptionForChangedAPIWithoutReplacement() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "someMethod",
            replacementAPI: nil,
            description: "Behavior changed significantly",
            category: .changed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertTrue(violation.description.contains("someMethod"))
        XCTAssertTrue(violation.description.contains("changed"))
        XCTAssertTrue(violation.description.contains("breaking"))
    }

    // MARK: - Correction ID Generation

    func testCorrectionIdForRenamedAPI() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "HBApplication",
            replacementAPI: "Application",
            description: "Type renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertTrue(violation.correctionId.contains("deprecated"))
        XCTAssertTrue(violation.correctionId.contains("HBApplication"))
        XCTAssertTrue(violation.correctionId.contains("renamed"))
    }

    func testCorrectionIdForRemovedAPI() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "OldClass",
            replacementAPI: nil,
            description: "Class removed",
            category: .removed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertTrue(violation.correctionId.contains("deprecated"))
        XCTAssertTrue(violation.correctionId.contains("OldClass"))
        XCTAssertTrue(violation.correctionId.contains("removed"))
    }

    func testCorrectionIdForChangedAPI() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "changedMethod",
            replacementAPI: "async changedMethod",
            description: "Method changed",
            category: .changed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertTrue(violation.correctionId.contains("deprecated"))
        XCTAssertTrue(violation.correctionId.contains("changedMethod"))
        XCTAssertTrue(violation.correctionId.contains("changed"))
    }

    func testCorrectionIdSanitizesSpecialCharacters() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "old.method()",
            replacementAPI: "new.method()",
            description: "Method renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        // Should replace dots and parentheses with hyphens
        XCTAssertFalse(violation.correctionId.contains("("))
        XCTAssertFalse(violation.correctionId.contains(")"))
        XCTAssertTrue(violation.correctionId.contains("-"))
    }

    // MARK: - Fix Suggestion Generation

    func testFixSuggestionForHummingbirdTypeRename() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "HBApplication",
            replacementAPI: "Application",
            description: "Type renamed in v2.0.0",
            category: .renamed,
            migrationGuidance: "The API is functionally identical"
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertNotNil(violation.fixSuggestion)
        XCTAssertTrue(violation.fixSuggestion!.before.contains("HBApplication"))
        XCTAssertTrue(violation.fixSuggestion!.after.contains("Application"))
        XCTAssertTrue(violation.fixSuggestion!.explanation.contains("renamed"))
        XCTAssertTrue(violation.fixSuggestion!.explanation.contains("functionally identical"))
    }

    func testFixSuggestionForGenericAPIRename() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "oldMethod",
            replacementAPI: "newMethod",
            description: "Method renamed for clarity",
            category: .renamed,
            migrationGuidance: "Update all method calls"
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertNotNil(violation.fixSuggestion)
        XCTAssertTrue(violation.fixSuggestion!.before.contains("oldMethod"))
        XCTAssertTrue(violation.fixSuggestion!.after.contains("newMethod"))
        XCTAssertTrue(violation.fixSuggestion!.explanation.contains("Method renamed for clarity"))
        XCTAssertTrue(violation.fixSuggestion!.explanation.contains("Update all method calls"))
    }

    func testFixSuggestionNilForRemovedAPI() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "RemovedClass",
            replacementAPI: nil,
            description: "Class removed",
            category: .removed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertNil(violation.fixSuggestion, "Removed APIs without replacement should have no fix suggestion")
    }

    func testFixSuggestionContainsBeforeAfterExamples() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "OldType",
            replacementAPI: "NewType",
            description: "Type renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertNotNil(violation.fixSuggestion)
        XCTAssertFalse(violation.fixSuggestion!.before.isEmpty)
        XCTAssertFalse(violation.fixSuggestion!.after.isEmpty)
        XCTAssertFalse(violation.fixSuggestion!.explanation.isEmpty)
    }

    // MARK: - ID Generation

    func testIdGenerationIsUnique() {
        let generator = ViolationRuleGenerator()

        let deprecation1 = DeprecationInfo(
            deprecatedAPI: "API1",
            replacementAPI: "NewAPI1",
            description: "Test",
            category: .renamed,
            migrationGuidance: nil
        )

        let deprecation2 = DeprecationInfo(
            deprecatedAPI: "API2",
            replacementAPI: "NewAPI2",
            description: "Test",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation1 = generator.generate(from: deprecation1, releaseVersion: "2.0.0")
        let violation2 = generator.generate(from: deprecation2, releaseVersion: "2.0.0")

        XCTAssertNotEqual(violation1.id, violation2.id, "Different APIs should generate unique IDs")
    }

    func testIdGenerationIncludesVersion() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "TestAPI",
            replacementAPI: "NewTestAPI",
            description: "Test",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation1 = generator.generate(from: deprecation, releaseVersion: "2.0.0")
        let violation2 = generator.generate(from: deprecation, releaseVersion: "2.1.0")

        XCTAssertNotEqual(violation1.id, violation2.id, "Different versions should generate different IDs")
        XCTAssertTrue(violation1.id.contains("2-0-0"))
        XCTAssertTrue(violation2.id.contains("2-1-0"))
    }

    func testIdGenerationSanitizesSpecialCharacters() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "test.method()",
            replacementAPI: "newMethod",
            description: "Test",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertFalse(violation.id.contains("("))
        XCTAssertFalse(violation.id.contains(")"))
        XCTAssertFalse(violation.id.contains("."))
        XCTAssertTrue(violation.id.contains("-"))
    }

    func testIdGenerationIsLowercase() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "CamelCaseAPI",
            replacementAPI: "NewAPI",
            description: "Test",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertEqual(violation.id, violation.id.lowercased(), "ID should be lowercase")
    }

    func testIdGenerationStartsWithAuto() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "TestAPI",
            replacementAPI: "NewAPI",
            description: "Test",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertTrue(violation.id.hasPrefix("auto-"), "Auto-generated IDs should start with 'auto-'")
    }

    // MARK: - Edge Cases

    func testGenerateWithEmptyDescription() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "TestAPI",
            replacementAPI: "NewAPI",
            description: "",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        // Should still generate a valid violation
        XCTAssertFalse(violation.id.isEmpty)
        XCTAssertFalse(violation.pattern.isEmpty)
        XCTAssertFalse(violation.description.isEmpty)
    }

    func testGenerateWithNilMigrationGuidance() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "TestAPI",
            replacementAPI: "NewAPI",
            description: "API renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        // Should still generate fix suggestion
        XCTAssertNotNil(violation.fixSuggestion)
    }

    func testGenerateWithUnicodeCharacters() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "测试API",
            replacementAPI: "新API",
            description: "API renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        // Should handle Unicode gracefully
        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertNotNil(violation)
        XCTAssertFalse(violation.id.isEmpty)
    }

    func testGenerateWithVeryLongAPIName() {
        let generator = ViolationRuleGenerator()
        let longName = String(repeating: "VeryLongAPIName", count: 10)
        let deprecation = DeprecationInfo(
            deprecatedAPI: longName,
            replacementAPI: "NewAPI",
            description: "API renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertNotNil(violation)
        XCTAssertFalse(violation.id.isEmpty)
        XCTAssertFalse(violation.pattern.isEmpty)
    }

    // MARK: - Multiple Categories

    func testGenerateMultipleDeprecationsProducesDifferentViolations() {
        let generator = ViolationRuleGenerator()

        let renamed = DeprecationInfo(
            deprecatedAPI: "OldName",
            replacementAPI: "NewName",
            description: "Renamed",
            category: .renamed,
            migrationGuidance: nil
        )

        let removed = DeprecationInfo(
            deprecatedAPI: "RemovedAPI",
            replacementAPI: nil,
            description: "Removed",
            category: .removed,
            migrationGuidance: nil
        )

        let changed = DeprecationInfo(
            deprecatedAPI: "ChangedAPI",
            replacementAPI: "async ChangedAPI",
            description: "Changed",
            category: .changed,
            migrationGuidance: nil
        )

        let v1 = generator.generate(from: renamed, releaseVersion: "2.0.0")
        let v2 = generator.generate(from: removed, releaseVersion: "2.0.0")
        let v3 = generator.generate(from: changed, releaseVersion: "2.0.0")

        XCTAssertNotEqual(v1.id, v2.id)
        XCTAssertNotEqual(v1.id, v3.id)
        XCTAssertNotEqual(v2.id, v3.id)

        XCTAssertNotEqual(v1.severity, v2.severity)
        XCTAssertEqual(v1.severity, v3.severity)

        XCTAssertNotNil(v1.fixSuggestion)
        XCTAssertNil(v2.fixSuggestion)
        XCTAssertNotNil(v3.fixSuggestion)
    }

    // MARK: - Real-World Examples

    func testGenerateForRealWorldHummingbirdRename() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "HBApplication",
            replacementAPI: "Application",
            description: "Hummingbird 2.0 removes the HB prefix from all types",
            category: .renamed,
            migrationGuidance: "Replace HBApplication with Application throughout your codebase. The API is functionally identical."
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertEqual(violation.severity, .warning)
        XCTAssertTrue(violation.pattern.contains("HBApplication"))
        XCTAssertTrue(violation.description.contains("renamed"))
        XCTAssertNotNil(violation.fixSuggestion)
        XCTAssertTrue(violation.fixSuggestion!.before.contains("HBApplication"))
        XCTAssertTrue(violation.fixSuggestion!.after.contains("Application"))
    }

    func testGenerateForRealWorldMethodSignatureChange() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "router.group",
            replacementAPI: "router.group async",
            description: "Router group method is now async",
            category: .changed,
            migrationGuidance: "Add async/await to your route group handlers"
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.1.0")

        XCTAssertEqual(violation.severity, .warning)
        XCTAssertTrue(violation.description.contains("changed"))
        XCTAssertNotNil(violation.fixSuggestion)
    }

    func testGenerateForRealWorldRemoval() {
        let generator = ViolationRuleGenerator()
        let deprecation = DeprecationInfo(
            deprecatedAPI: "HBMiddleware",
            replacementAPI: nil,
            description: "HBMiddleware has been removed. Use RouterMiddleware protocol instead.",
            category: .removed,
            migrationGuidance: nil
        )

        let violation = generator.generate(from: deprecation, releaseVersion: "2.0.0")

        XCTAssertEqual(violation.severity, .error)
        XCTAssertTrue(violation.description.contains("removed"))
        XCTAssertNil(violation.fixSuggestion)
    }
}
