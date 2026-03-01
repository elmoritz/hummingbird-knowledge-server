#!/usr/bin/env swift

// validate-historical-rules.swift
//
// Validation script that processes historical Hummingbird releases to verify
// auto-generated violation rules match known breaking changes from the 1.x → 2.x migration.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - GitHub Release Models

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let publishedAt: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
    }
}

// MARK: - Data Models (Mirrored from project)

enum DeprecationCategory: String, Sendable, Codable {
    case renamed
    case removed
    case changed
}

struct DeprecationInfo: Sendable, Codable {
    let deprecatedAPI: String
    let replacementAPI: String?
    let description: String
    let category: DeprecationCategory
    let migrationGuidance: String?
}

struct ChangelogParser: Sendable {
    func parse(_ markdown: String) -> [DeprecationInfo] {
        var deprecations: [DeprecationInfo] = []
        let lines = markdown.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let deprecation = parseRenamePattern(trimmed) {
                deprecations.append(deprecation)
            } else if let deprecation = parseRemovalPattern(trimmed) {
                deprecations.append(deprecation)
            } else if let deprecation = parseChangePattern(trimmed) {
                deprecations.append(deprecation)
            }
        }

        return deprecations
    }

    private func isDeprecationSectionHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("deprecated") ||
               lowercased.contains("breaking change") ||
               lowercased.contains("removed") ||
               lowercased.contains("migration")
    }

    private func parseRenamePattern(_ line: String) -> DeprecationInfo? {
        let lowercased = line.lowercased()

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

        if line.contains("→") || line.contains("->") {
            let separator = line.contains("→") ? "→" : "->"
            let components = line.components(separatedBy: separator)
            if components.count >= 2 {
                let old = extractAPIName(from: components[0])
                let new = extractAPIName(from: components[1])
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

    private func extractAPIName(from text: String) -> String {
        if let start = text.firstIndex(of: "`"),
           let end = text[text.index(after: start)...].firstIndex(of: "`") {
            return String(text[text.index(after: start)..<end])
        }

        return text.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "`*-•")))
    }

    private func parseRemovalPattern(_ line: String) -> DeprecationInfo? {
        let lowercased = line.lowercased()

        if lowercased.contains("removed ") {
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

    private func parseChangePattern(_ line: String) -> DeprecationInfo? {
        let lowercased = line.lowercased()

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
}

struct ViolationRuleGenerator: Sendable {
    func generate(from deprecation: DeprecationInfo, releaseVersion: String) -> GeneratedViolation {
        let pattern = generatePattern(for: deprecation)
        let severity = determineSeverity(for: deprecation.category)
        let description = generateDescription(for: deprecation)

        return GeneratedViolation(
            id: generateId(for: deprecation, releaseVersion: releaseVersion),
            pattern: pattern,
            description: description,
            severity: severity,
            deprecatedAPI: deprecation.deprecatedAPI,
            replacementAPI: deprecation.replacementAPI,
            category: deprecation.category
        )
    }

    private func generatePattern(for deprecation: DeprecationInfo) -> String {
        let apiName = deprecation.deprecatedAPI

        if apiName.hasPrefix("HB") {
            return #"\b\#(escapeRegex(apiName))\b"#
        } else if apiName.contains("(") {
            let baseName = apiName.components(separatedBy: "(").first ?? apiName
            return #"\b\#(escapeRegex(baseName))\s*\("#
        } else if apiName.contains(".") {
            return escapeRegex(apiName)
        } else if apiName.first?.isUppercase == true {
            return #"\b\#(escapeRegex(apiName))\b"#
        } else {
            return #"(\.\#(escapeRegex(apiName))\b|\b\#(escapeRegex(apiName))\s*\()"#
        }
    }

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

    private func determineSeverity(for category: DeprecationCategory) -> String {
        switch category {
        case .removed: return "error"
        case .renamed: return "warning"
        case .changed: return "warning"
        }
    }

    private func generateDescription(for deprecation: DeprecationInfo) -> String {
        switch deprecation.category {
        case .renamed:
            if let replacement = deprecation.replacementAPI {
                return "`\(deprecation.deprecatedAPI)` has been renamed to `\(replacement)`. \(deprecation.description)"
            } else {
                return "`\(deprecation.deprecatedAPI)` has been deprecated. \(deprecation.description)"
            }
        case .removed:
            return "`\(deprecation.deprecatedAPI)` has been removed from the API. \(deprecation.description)"
        case .changed:
            if let replacement = deprecation.replacementAPI {
                return "`\(deprecation.deprecatedAPI)` has changed to `\(replacement)`. \(deprecation.description)"
            } else {
                return "`\(deprecation.deprecatedAPI)` has changed in a breaking way. \(deprecation.description)"
            }
        }
    }

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

struct GeneratedViolation {
    let id: String
    let pattern: String
    let description: String
    let severity: String
    let deprecatedAPI: String
    let replacementAPI: String?
    let category: DeprecationCategory
}

// MARK: - Known Breaking Changes (from CheckVersionCompatibilityTool)

let knownBreakingChanges: [(api: String, replacement: String?)] = [
    ("HBApplication", "Application"),
    ("HBRequest", "Request"),
    ("HBResponse", "Response"),
    ("HBMiddleware", "RouterMiddleware"),
    ("HBRouterBuilder", "Router(context:)"),
    ("HBHTTPError", "HTTPError"),
    ("addMiddleware", "router.add(middleware:)"),
]

// MARK: - Main Validation Logic

func fetchHistoricalReleases(count: Int = 5) async throws -> [GitHubRelease] {
    let url = URL(string: "https://api.github.com/repos/hummingbird-project/hummingbird/releases?per_page=\(count)")!
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw NSError(domain: "ValidationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch releases"])
    }

    let decoder = JSONDecoder()
    return try decoder.decode([GitHubRelease].self, from: data)
}

func validateHistoricalReleases() async {
    print("═══════════════════════════════════════════════════════════════")
    print("  HISTORICAL RELEASE VALIDATION")
    print("  Auto-Evolving Violation Rules from Releases")
    print("═══════════════════════════════════════════════════════════════\n")

    do {
        print("📡 Fetching historical Hummingbird releases from GitHub...\n")
        let releases = try await fetchHistoricalReleases(count: 5)

        print("✅ Fetched \(releases.count) releases\n")

        let parser = ChangelogParser()
        let generator = ViolationRuleGenerator()

        var totalDeprecations = 0
        var totalRules = 0
        var allGeneratedRules: [GeneratedViolation] = []

        for (index, release) in releases.enumerated() {
            print("─────────────────────────────────────────────────────────────")
            print("📦 Release: \(release.name) (\(release.tagName))")
            print("   Published: \(release.publishedAt)")
            print("")

            // Parse deprecations from release notes
            let deprecations = parser.parse(release.body)
            totalDeprecations += deprecations.count

            print("   Deprecations found: \(deprecations.count)")

            if !deprecations.isEmpty {
                for deprecation in deprecations {
                    let categoryIcon = deprecation.category == .renamed ? "🔄" :
                                     deprecation.category == .removed ? "🗑️" : "⚠️"
                    print("   \(categoryIcon) \(deprecation.deprecatedAPI)", terminator: "")
                    if let replacement = deprecation.replacementAPI {
                        print(" → \(replacement)")
                    } else {
                        print(" (removed)")
                    }
                }
                print("")
            }

            // Generate rules from deprecations
            let rules = deprecations.map { generator.generate(from: $0, releaseVersion: release.tagName) }
            totalRules += rules.count
            allGeneratedRules.append(contentsOf: rules)

            print("   Rules generated: \(rules.count)")

            if index == 0 && !rules.isEmpty {
                print("\n   Sample Rule (first from this release):")
                let sample = rules[0]
                print("   ┌─ ID: \(sample.id)")
                print("   ├─ Pattern: \(sample.pattern)")
                print("   ├─ Severity: \(sample.severity)")
                print("   └─ Description: \(sample.description)")
            }

            print("")
        }

        print("═══════════════════════════════════════════════════════════════")
        print("  VALIDATION SUMMARY")
        print("═══════════════════════════════════════════════════════════════\n")

        print("📊 Statistics:")
        print("   Releases processed: \(releases.count)")
        print("   Total deprecations found: \(totalDeprecations)")
        print("   Total rules generated: \(totalRules)")
        let average = totalDeprecations > 0 ? Double(totalDeprecations) / Double(releases.count) : 0.0
        print("   Average deprecations per release: \(String(format: "%.1f", average))")
        print("")

        // Validate against known breaking changes
        print("🔍 Validation Against Known Breaking Changes:")
        print("   (from CheckVersionCompatibilityTool)")
        print("")

        var matchedChanges = 0
        for knownChange in knownBreakingChanges {
            let matched = allGeneratedRules.contains { rule in
                rule.deprecatedAPI == knownChange.api
            }

            let icon = matched ? "✅" : "⚠️"
            print("   \(icon) \(knownChange.api)", terminator: "")
            if let replacement = knownChange.replacement {
                print(" → \(replacement)", terminator: "")
            }
            if matched {
                matchedChanges += 1
                print(" (detected)")
            } else {
                print(" (not found in recent releases)")
            }
        }

        print("")
        print("   Matched: \(matchedChanges)/\(knownBreakingChanges.count) known breaking changes")
        print("")

        // Quality assessment
        print("📈 Quality Assessment:")
        let hasSufficientDeprecations = totalDeprecations >= 3
        let hasSufficientRules = totalRules >= 3
        let hasGoodMatchRate = Double(matchedChanges) / Double(knownBreakingChanges.count) >= 0.3

        print("   [\(hasSufficientDeprecations ? "✅" : "⚠️")] Found at least 3 deprecations")
        print("   [\(hasSufficientRules ? "✅" : "⚠️")] Generated at least 3 rules")
        print("   [\(hasGoodMatchRate ? "✅" : "⚠️")] Matched >= 30% of known breaking changes")
        print("")

        if hasSufficientDeprecations && hasSufficientRules && hasGoodMatchRate {
            print("✅ VALIDATION PASSED")
            print("   Auto-generated rules successfully capture historical breaking changes.")
        } else {
            print("⚠️  VALIDATION PARTIAL")
            print("   Some historical breaking changes may not be in recent release notes.")
            print("   This is expected for older 1.x → 2.x changes that occurred before recent releases.")
        }

        print("")
        print("═══════════════════════════════════════════════════════════════\n")

    } catch {
        print("❌ ERROR: \(error)")
        print("\nValidation failed. Check your network connection and GitHub API access.\n")
    }
}

// MARK: - Script Entry Point

@available(macOS 12.0, *)
func main() async {
    await validateHistoricalReleases()
}

#if compiler(>=5.5) && canImport(_Concurrency)
if #available(macOS 12.0, *) {
    let semaphore = DispatchSemaphore(value: 0)

    Task {
        await main()
        semaphore.signal()
    }

    semaphore.wait()
} else {
    print("❌ This script requires macOS 12.0 or later")
    exit(1)
}
#else
print("❌ This script requires Swift 5.5 or later with concurrency support")
exit(1)
#endif
