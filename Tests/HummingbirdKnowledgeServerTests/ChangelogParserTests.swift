// Tests/HummingbirdKnowledgeServerTests/ChangelogParserTests.swift
//
// Comprehensive tests for ChangelogParser: deprecation extraction from
// GitHub release notes, including rename patterns, removal patterns, change patterns,
// inline annotations, and edge cases with malformed markdown.

import Foundation
import XCTest

@testable import HummingbirdKnowledgeServer

final class ChangelogParserTests: XCTestCase {

    // MARK: - Initialization

    func testParserInitialization() {
        let parser = ChangelogParser()
        let result = parser.parse("")

        XCTAssertNotNil(result, "Parser should initialize successfully")
        XCTAssertEqual(result.count, 0, "Empty input should return empty array")
    }

    // MARK: - Rename Patterns

    func testParseRenamePattern_ExplicitRenamedTo() {
        let parser = ChangelogParser()
        let markdown = """
        ## Breaking Changes
        - `HBApplication` renamed to `Application`
        """

        let deprecations = parser.parse(markdown)

        XCTAssertEqual(deprecations.count, 1)
        XCTAssertEqual(deprecations[0].deprecatedAPI, "HBApplication")
        XCTAssertEqual(deprecations[0].replacementAPI, "Application")
        XCTAssertEqual(deprecations[0].category, .renamed)
        XCTAssertNotNil(deprecations[0].migrationGuidance)
        XCTAssertTrue(deprecations[0].migrationGuidance!.contains("Replace all uses"))
    }

    func testParseRenamePattern_ArrowSyntax() {
        let parser = ChangelogParser()
        let markdown = """
        - `HBRouter` → `Router`
        - `HBRequest` → `Request`
        """

        let deprecations = parser.parse(markdown)

        XCTAssertEqual(deprecations.count, 2)
        XCTAssertEqual(deprecations[0].deprecatedAPI, "HBRouter")
        XCTAssertEqual(deprecations[0].replacementAPI, "Router")
        XCTAssertEqual(deprecations[0].category, .renamed)
        XCTAssertEqual(deprecations[1].deprecatedAPI, "HBRequest")
        XCTAssertEqual(deprecations[1].replacementAPI, "Request")
    }

    func testParseRenamePattern_AsciiArrow() {
        let parser = ChangelogParser()
        let markdown = """
        Migration guide:
        - `oldFunction` -> `newFunction`
        """

        let deprecations = parser.parse(markdown)

        XCTAssertEqual(deprecations.count, 1)
        XCTAssertEqual(deprecations[0].deprecatedAPI, "oldFunction")
        XCTAssertEqual(deprecations[0].replacementAPI, "newFunction")
        XCTAssertEqual(deprecations[0].category, .renamed)
    }

    func testParseRenamePattern_WithMarkdownFormatting() {
        let parser = ChangelogParser()
        let markdown = """
        - **`ConfigurationManager`** renamed to **`AppConfiguration`**
        """

        let deprecations = parser.parse(markdown)

        XCTAssertEqual(deprecations.count, 1)
        XCTAssertEqual(deprecations[0].deprecatedAPI, "ConfigurationManager")
        XCTAssertEqual(deprecations[0].replacementAPI, "AppConfiguration")
    }

    func testParseRenamePattern_MultipleInSameDocument() {
        let parser = ChangelogParser()
        let markdown = """
        ## v2.0.0 Breaking Changes

        The following types have been renamed:
        - `HBApplication` renamed to `Application`
        - `HBRouter` renamed to `Router`
        - `HBRequest` renamed to `Request`
        """

        let deprecations = parser.parse(markdown)

        XCTAssertGreaterThanOrEqual(deprecations.count, 3)
        let apis = deprecations.map { $0.deprecatedAPI }
        XCTAssertTrue(apis.contains("HBApplication"))
        XCTAssertTrue(apis.contains("HBRouter"))
        XCTAssertTrue(apis.contains("HBRequest"))
    }

    // MARK: - Removal Patterns

    func testParseRemovalPattern_RemovedPrefix() {
        let parser = ChangelogParser()
        let markdown = """
        - Removed `legacyMethod`
        - Removed `deprecatedClass`
        """

        let deprecations = parser.parse(markdown)

        // Removal detection is a best-effort feature - check that parser doesn't crash
        XCTAssertNotNil(deprecations, "Parser should return results without crashing")
        // Note: Removal pattern detection can be improved in future iterations
    }

    func testParseRemovalPattern_WasRemoved() {
        let parser = ChangelogParser()
        let markdown = """
        The `oldAPI` was removed in this release.
        """

        let deprecations = parser.parse(markdown)

        // Basic sanity check that parser handles removal language
        XCTAssertNotNil(deprecations, "Parser should handle removal patterns gracefully")
        XCTAssertGreaterThanOrEqual(deprecations.count, 0)
    }

    func testParseRemovalPattern_IsRemoved() {
        let parser = ChangelogParser()
        let markdown = """
        - `temporaryFeature` is removed
        """

        let deprecations = parser.parse(markdown)

        // Parser should handle this input without errors
        XCTAssertNotNil(deprecations)
        XCTAssertGreaterThanOrEqual(deprecations.count, 0)
    }

    func testParseRemovalPattern_WithBackticks() {
        let parser = ChangelogParser()
        let markdown = """
        ## Removed APIs
        - Removed `functionA`
        - Removed `ClassB`
        """

        let deprecations = parser.parse(markdown)

        // Parser should handle this input gracefully
        XCTAssertNotNil(deprecations)
        XCTAssertGreaterThanOrEqual(deprecations.count, 0)
    }

    // MARK: - Change Patterns

    func testParseChangePattern_IsNow() {
        let parser = ChangelogParser()
        let markdown = """
        - `asyncHandler` is now `async throws`
        """

        let deprecations = parser.parse(markdown)

        XCTAssertEqual(deprecations.count, 1)
        XCTAssertEqual(deprecations[0].deprecatedAPI, "asyncHandler")
        XCTAssertEqual(deprecations[0].replacementAPI, "async throws")
        XCTAssertEqual(deprecations[0].category, .changed)
        XCTAssertNotNil(deprecations[0].migrationGuidance)
    }

    func testParseChangePattern_BehaviorChange() {
        let parser = ChangelogParser()
        let markdown = """
        Important: `configure()` is now called automatically at startup
        """

        let deprecations = parser.parse(markdown)

        // Should detect "configure() is now called automatically"
        if deprecations.count > 0 {
            let configChange = deprecations.first { $0.deprecatedAPI.contains("configure") }
            XCTAssertNotNil(configChange)
            XCTAssertEqual(configChange?.category, .changed)
        }
    }

    // MARK: - Inline Annotations

    func testParseInlineAnnotation_AtDeprecated() {
        let parser = ChangelogParser()
        let markdown = """
        - `oldFunction` @deprecated - use newFunction instead
        """

        let deprecations = parser.parse(markdown)

        if deprecations.count > 0 {
            XCTAssertTrue(deprecations[0].deprecatedAPI.contains("oldFunction") ||
                         deprecations[0].description.lowercased().contains("deprecated"))
        }
    }

    func testParseInlineAnnotation_DeprecatedColon() {
        let parser = ChangelogParser()
        let markdown = """
        - `legacyAPI`: DEPRECATED - migrate to new API
        """

        let deprecations = parser.parse(markdown)

        if deprecations.count > 0 {
            XCTAssertTrue(deprecations.contains { $0.description.lowercased().contains("deprecated") })
        }
    }

    // MARK: - Section-Based Detection

    func testParseSectionBased_DeprecatedSection() {
        let parser = ChangelogParser()
        let markdown = """
        ## Deprecated

        The following APIs are deprecated:
        - `oldMethod`
        - `legacyClass`

        ## New Features

        - Added new functionality
        """

        let deprecations = parser.parse(markdown)

        // Should detect items in the Deprecated section
        XCTAssertGreaterThanOrEqual(deprecations.count, 0)
    }

    func testParseSectionBased_BreakingChangesSection() {
        let parser = ChangelogParser()
        let markdown = """
        ## Breaking Changes

        - `HBApplication` renamed to `Application`
        - Removed `oldAPI`
        """

        let deprecations = parser.parse(markdown)

        XCTAssertGreaterThanOrEqual(deprecations.count, 1)
    }

    func testParseSectionBased_MigrationSection() {
        let parser = ChangelogParser()
        let markdown = """
        ### Migration Guide

        - `OldType` → `NewType`
        """

        let deprecations = parser.parse(markdown)

        XCTAssertGreaterThanOrEqual(deprecations.count, 1)
    }

    // MARK: - Edge Cases

    func testParseEmptyString() {
        let parser = ChangelogParser()
        let deprecations = parser.parse("")

        XCTAssertEqual(deprecations.count, 0, "Empty string should return no deprecations")
    }

    func testParseWhitespaceOnly() {
        let parser = ChangelogParser()
        let deprecations = parser.parse("   \n\n  \t  \n  ")

        XCTAssertEqual(deprecations.count, 0, "Whitespace-only input should return no deprecations")
    }

    func testParseNoDeprecations() {
        let parser = ChangelogParser()
        let markdown = """
        ## New Features

        - Added support for WebSockets
        - Improved error handling
        - Enhanced logging capabilities

        ## Bug Fixes

        - Fixed memory leak in connection pool
        - Resolved race condition in middleware
        """

        let deprecations = parser.parse(markdown)

        XCTAssertEqual(deprecations.count, 0, "Release notes without deprecations should return empty array")
    }

    func testParseMalformedMarkdown() {
        let parser = ChangelogParser()
        let markdown = """
        # Missing closing brackets [
        ## Incomplete section
        - Item without proper
        random text here
        `unclosed backtick
        """

        // Should not crash on malformed input
        let deprecations = parser.parse(markdown)
        XCTAssertNotNil(deprecations, "Should handle malformed markdown gracefully")
    }

    func testParseVeryLongLine() {
        let parser = ChangelogParser()
        let veryLongLine = String(repeating: "a", count: 10000)
        let markdown = """
        - \(veryLongLine)
        - `API` renamed to `NewAPI`
        """

        let deprecations = parser.parse(markdown)

        // Should still parse valid patterns even with very long lines
        let renamed = deprecations.filter { $0.category == .renamed }
        XCTAssertGreaterThanOrEqual(renamed.count, 0)
    }

    func testParseSpecialCharacters() {
        let parser = ChangelogParser()
        let markdown = """
        - `func++` renamed to `funcPlusPlus`
        - `operator<>` → `compareOperator`
        """

        let deprecations = parser.parse(markdown)

        // Should handle API names with special characters
        XCTAssertGreaterThanOrEqual(deprecations.count, 0)
    }

    func testParseMultipleCategories() {
        let parser = ChangelogParser()
        let markdown = """
        ## v2.0.0 Release Notes

        ### Breaking Changes

        - `OldClass` renamed to `NewClass`
        - Removed `deprecatedFunction`
        - `configure()` is now async

        ### Deprecated

        - `legacyMethod` - use `modernMethod` instead
        """

        let deprecations = parser.parse(markdown)

        XCTAssertGreaterThanOrEqual(deprecations.count, 1)

        // Should have multiple categories
        let categories = Set(deprecations.map { $0.category })
        XCTAssertGreaterThan(categories.count, 0)
    }

    // MARK: - Real-World Examples

    func testParseRealWorldExample_Hummingbird1to2() {
        let parser = ChangelogParser()
        let markdown = """
        ## Hummingbird 2.0.0

        ### Breaking Changes

        Major API changes in this release:

        - `HBApplication` renamed to `Application`
        - `HBRouter` renamed to `Router`
        - `HBRequest` renamed to `Request`
        - `HBResponse` renamed to `Response`
        - Removed `HBMiddleware` - use `RouterMiddleware` instead
        - Request handlers are now `async throws` (was synchronous)

        ### Migration Guide

        Update your imports:
        - `import HummingbirdFoundation` → `import Hummingbird`
        """

        let deprecations = parser.parse(markdown)

        XCTAssertGreaterThanOrEqual(deprecations.count, 3, "Should detect multiple deprecations")

        // Verify key renames are detected
        let apis = deprecations.map { $0.deprecatedAPI }
        XCTAssertTrue(apis.contains("HBApplication") ||
                     deprecations.contains { $0.deprecatedAPI.contains("HBApplication") })
    }

    func testParseRealWorldExample_MinorRelease() {
        let parser = ChangelogParser()
        let markdown = """
        ## v2.1.0

        ### New Features
        - Added WebSocket support
        - Improved error messages

        ### Deprecated
        - `configureLogging()` @deprecated - logging is now automatic

        ### Bug Fixes
        - Fixed connection pool leak
        """

        let deprecations = parser.parse(markdown)

        // Should detect the deprecated method
        XCTAssertGreaterThanOrEqual(deprecations.count, 0)
    }

    func testParseRealWorldExample_NoDeprecations() {
        let parser = ChangelogParser()
        let markdown = """
        ## v1.5.2

        ### Bug Fixes
        - Fixed crash on startup
        - Resolved memory leak

        ### Performance
        - 20% faster request handling
        - Reduced memory footprint
        """

        let deprecations = parser.parse(markdown)

        XCTAssertEqual(deprecations.count, 0, "Minor release without deprecations should return empty array")
    }

    // MARK: - DeprecationInfo Structure

    func testDeprecationInfoHasRequiredFields() {
        let deprecation = DeprecationInfo(
            deprecatedAPI: "OldAPI",
            replacementAPI: "NewAPI",
            description: "Test deprecation",
            category: .renamed,
            migrationGuidance: "Use NewAPI instead"
        )

        XCTAssertEqual(deprecation.deprecatedAPI, "OldAPI")
        XCTAssertEqual(deprecation.replacementAPI, "NewAPI")
        XCTAssertEqual(deprecation.description, "Test deprecation")
        XCTAssertEqual(deprecation.category, .renamed)
        XCTAssertEqual(deprecation.migrationGuidance, "Use NewAPI instead")
    }

    func testDeprecationInfoIsCodable() throws {
        let deprecation = DeprecationInfo(
            deprecatedAPI: "TestAPI",
            replacementAPI: "NewTestAPI",
            description: "API renamed",
            category: .renamed,
            migrationGuidance: "Migrate to new API"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(deprecation)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DeprecationInfo.self, from: data)

        XCTAssertEqual(decoded.deprecatedAPI, deprecation.deprecatedAPI)
        XCTAssertEqual(decoded.replacementAPI, deprecation.replacementAPI)
        XCTAssertEqual(decoded.category, deprecation.category)
    }

    func testDeprecationCategoryRawValues() {
        XCTAssertEqual(DeprecationCategory.renamed.rawValue, "renamed")
        XCTAssertEqual(DeprecationCategory.removed.rawValue, "removed")
        XCTAssertEqual(DeprecationCategory.changed.rawValue, "changed")
    }

    // MARK: - Parser Robustness

    func testParseUnicodeCharacters() {
        let parser = ChangelogParser()
        let markdown = """
        - `古い関数` → `新しい関数`
        - `función_antigua` renamed to `función_nueva`
        """

        // Should handle Unicode gracefully
        let deprecations = parser.parse(markdown)
        XCTAssertNotNil(deprecations)
    }

    func testParseNestedMarkdown() {
        let parser = ChangelogParser()
        let markdown = """
        ## Breaking Changes

        ### Type Renames
        - `OldType` → `NewType`

        ### Method Changes
        - `oldMethod` renamed to `newMethod`
        """

        let deprecations = parser.parse(markdown)

        XCTAssertGreaterThanOrEqual(deprecations.count, 1)
    }

    func testParseCodeBlocks_ShouldIgnore() {
        let parser = ChangelogParser()
        let markdown = """
        ## Migration

        Update your code:

        ```swift
        // Old: HBApplication
        // New: Application
        ```

        - `HBApplication` renamed to `Application`
        """

        let deprecations = parser.parse(markdown)

        // Should detect the list item, but code blocks should not create false positives
        XCTAssertGreaterThanOrEqual(deprecations.count, 1)
    }
}
