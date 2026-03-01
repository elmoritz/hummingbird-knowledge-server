// Sources/HummingbirdKnowledgeServer/KnowledgeBase/KnowledgeStore.swift
//
// Thread-safe knowledge store loaded at startup from the bundled seed file.
// The KnowledgeUpdateService refreshes entries from GitHub and SSWG at runtime.

import Foundation

// MARK: - Knowledge entry schema

/// A single knowledge entry covering a pattern, pitfall, or architectural rule.
struct KnowledgeEntry: Codable, Sendable {
    let id: String
    let title: String
    let content: String
    let layer: ArchitecturalLayer?
    let patternIds: [String]
    let violationIds: [String]
    let hummingbirdVersionRange: String     // semver range, e.g. ">=2.0.0"
    let swiftVersionRange: String           // e.g. ">=6.0"
    let isTutorialPattern: Bool             // true = this is an anti-pattern example
    let correctionId: String?               // required when isTutorialPattern == true
    let confidence: Double                  // 0.0 to 1.0
    let source: String
    let lastVerifiedAt: Date?
}

/// The architectural layer a knowledge entry applies to.
enum ArchitecturalLayer: String, Codable, Sendable, CaseIterable {
    case controller
    case service
    case repository
    case model
    case middleware
    case configuration
    case transport
    case context
    case testing
}

// MARK: - Knowledge store

/// Thread-safe, actor-isolated store for all knowledge entries and violation rules.
///
/// Entries are loaded from the bundled `knowledge.json` at startup, then enriched
/// at runtime by `KnowledgeUpdateService`. The static violation catalogue in
/// `ArchitecturalViolations.all` is compiled into the binary and never changes.
/// Dynamic violations are auto-generated from release notes and can be updated at runtime.
actor KnowledgeStore {

    private var entries: [String: KnowledgeEntry] = [:]
    private let violations: [ArchitecturalViolation] = ArchitecturalViolations.all
    private var dynamicViolations: [DynamicViolation] = []
    private let dynamicViolationsFileURL: URL

    // MARK: - Initialisation

    /// Creates a KnowledgeStore with the given seed entries and dynamic violations file URL.
    /// Exposed as `internal` so tests can create instances with test data.
    /// Production code should use `loadFromBundle()` instead.
    init(seedEntries: [KnowledgeEntry], dynamicViolationsFileURL: URL) {
        self.entries = Dictionary(uniqueKeysWithValues: seedEntries.map { ($0.id, $0) })
        self.dynamicViolationsFileURL = dynamicViolationsFileURL
    }

    /// Loads seed entries from the bundled `knowledge.json` resource
    /// and dynamic violations from persistent storage.
    static func loadFromBundle() async throws -> KnowledgeStore {
        // Load knowledge entries from bundle
        guard let url = Bundle.module.url(forResource: "knowledge", withExtension: "json") else {
            throw KnowledgeStoreError.bundleResourceMissing("knowledge.json")
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let seedEntries = try decoder.decode([KnowledgeEntry].self, from: data)

        // Determine writable location for dynamic violations
        let fileManager = FileManager.default
        let appSupportDir = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeDir = appSupportDir.appendingPathComponent("HummingbirdKnowledgeServer", isDirectory: true)
        try fileManager.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let dynamicViolationsURL = storeDir.appendingPathComponent("dynamic-violations.json")

        // Initialize store
        let store = KnowledgeStore(seedEntries: seedEntries, dynamicViolationsFileURL: dynamicViolationsURL)

        // Load dynamic violations from persistent storage (if exists)
        try await store.loadDynamicViolations()

        return store
    }

    /// Loads dynamic violations from the persistent file.
    /// If the file doesn't exist, initializes from the bundled seed file.
    private func loadDynamicViolations() throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: dynamicViolationsFileURL.path) {
            // Load from persistent storage
            let data = try Data(contentsOf: dynamicViolationsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.dynamicViolations = try decoder.decode([DynamicViolation].self, from: data)
        } else {
            // Initialize from bundled seed file
            if let bundleURL = Bundle.module.url(forResource: "dynamic-violations", withExtension: "json") {
                let data = try Data(contentsOf: bundleURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                self.dynamicViolations = try decoder.decode([DynamicViolation].self, from: data)
                // Save to persistent location
                try saveDynamicViolations()
            } else {
                // No seed file, start with empty array
                self.dynamicViolations = []
            }
        }
    }

    /// Saves dynamic violations to the persistent file.
    private func saveDynamicViolations() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dynamicViolations)
        try data.write(to: dynamicViolationsFileURL, options: [.atomic])
    }

    // MARK: - Reads

    var count: Int { entries.count }

    func entry(for id: String) -> KnowledgeEntry? {
        entries[id]
    }

    func allEntries() -> [KnowledgeEntry] {
        Array(entries.values)
    }

    func entries(for layer: ArchitecturalLayer) -> [KnowledgeEntry] {
        entries.values.filter { $0.layer == layer }
    }

    func pitfalls() -> [KnowledgeEntry] {
        entries.values
            .filter { !$0.isTutorialPattern }
            .sorted { $0.confidence > $1.confidence }
    }

    func antiPatternEntries() -> [KnowledgeEntry] {
        entries.values.filter { $0.isTutorialPattern }
    }

    func sswgPackages() -> [KnowledgeEntry] {
        entries.values.filter { $0.source == "sswg-index" }
    }

    // MARK: - Violation detection

    /// Matches `code` against both static and dynamic violation catalogues.
    /// Returns all violations found, sorted by severity (critical first).
    /// Only includes approved dynamic violations.
    func detectViolations(in code: String) -> [ArchitecturalViolation] {
        // Check static violations
        let staticMatches = violations.compactMap { violation -> ArchitecturalViolation? in
            guard (try? NSRegularExpression(pattern: violation.pattern, options: [.anchorsMatchLines]))
                    .flatMap({ regex in
                        let range = NSRange(code.startIndex..., in: code)
                        return regex.firstMatch(in: code, range: range)
                    }) != nil
            else { return nil }
            return violation
        }

        // Check dynamic violations (approved only)
        let approvedDynamic = dynamicViolations.filter { $0.reviewStatus == .approved }
        let dynamicMatches = approvedDynamic.compactMap { violation -> ArchitecturalViolation? in
            guard (try? NSRegularExpression(pattern: violation.pattern, options: [.anchorsMatchLines]))
                    .flatMap({ regex in
                        let range = NSRange(code.startIndex..., in: code)
                        return regex.firstMatch(in: code, range: range)
                    }) != nil
            else { return nil }
            return convertToArchitecturalViolation(violation)
        }

        // Combine and sort by severity
        return (staticMatches + dynamicMatches).sorted {
            severityRank($0.severity) > severityRank($1.severity)
        }
    }

    /// Converts a DynamicViolation to ArchitecturalViolation for uniform handling.
    private func convertToArchitecturalViolation(_ dynamic: DynamicViolation) -> ArchitecturalViolation {
        ArchitecturalViolation(
            id: dynamic.id,
            pattern: dynamic.pattern,
            description: dynamic.description,
            correctionId: dynamic.correctionId,
            severity: convertSeverity(dynamic.severity),
            fixSuggestion: dynamic.fixSuggestion
        )
    }

    /// Converts DynamicViolation.Severity to ArchitecturalViolation.Severity.
    private func convertSeverity(_ severity: DynamicViolation.Severity) -> ArchitecturalViolation.Severity {
        switch severity {
        case .warning:  return .warning
        case .error:    return .error
        case .critical: return .critical
        }
    }

    private func severityRank(_ severity: ArchitecturalViolation.Severity) -> Int {
        switch severity {
        case .critical: return 2
        case .error:    return 1
        case .warning:  return 0
        }
    }

    // MARK: - Updates

    /// Upserts a knowledge entry. Called by `KnowledgeUpdateService` during refresh.
    func upsert(_ entry: KnowledgeEntry) {
        entries[entry.id] = entry
    }

    /// Upserts multiple entries in a single actor turn. More efficient than calling
    /// `upsert` in a loop from outside the actor.
    func upsertAll(_ newEntries: [KnowledgeEntry]) {
        for entry in newEntries {
            entries[entry.id] = entry
        }
    }

    // MARK: - Dynamic violation management

    /// Upserts a dynamic violation. Called by `KnowledgeUpdateService` when auto-generating
    /// rules from release notes. Replaces existing violation with the same ID.
    /// Persists the change to disk.
    func upsertDynamicViolation(_ violation: DynamicViolation) throws {
        if let index = dynamicViolations.firstIndex(where: { $0.id == violation.id }) {
            dynamicViolations[index] = violation
        } else {
            dynamicViolations.append(violation)
        }
        try saveDynamicViolations()
    }

    /// Returns all dynamic violations, regardless of review status.
    func getDynamicViolations() -> [DynamicViolation] {
        dynamicViolations
    }

    /// Updates the review status of a dynamic violation.
    /// Throws if the violation ID is not found.
    /// Persists the change to disk.
    func updateReviewStatus(id: String, status: ViolationReviewStatus) throws {
        guard let index = dynamicViolations.firstIndex(where: { $0.id == id }) else {
            throw KnowledgeStoreError.violationNotFound(id)
        }

        let existing = dynamicViolations[index]
        let updated = DynamicViolation(
            id: existing.id,
            pattern: existing.pattern,
            description: existing.description,
            correctionId: existing.correctionId,
            severity: existing.severity,
            fixSuggestion: existing.fixSuggestion,
            reviewStatus: status,
            source: existing.source,
            generatedAt: existing.generatedAt,
            sourceRelease: existing.sourceRelease
        )
        dynamicViolations[index] = updated
        try saveDynamicViolations()
    }

    // MARK: - Formatted content for MCP resources

    func pitfallCatalogueText() -> String {
        let items = pitfalls()
        guard !items.isEmpty else { return "No pitfalls recorded yet." }
        return items.enumerated().map { i, entry in
            "## \(i + 1). \(entry.title)\n\(entry.content)"
        }.joined(separator: "\n\n---\n\n")
    }
}

// MARK: - Errors

enum KnowledgeStoreError: Error, CustomStringConvertible {
    case bundleResourceMissing(String)
    case decodingFailed(String)
    case violationNotFound(String)

    var description: String {
        switch self {
        case .bundleResourceMissing(let name): return "Bundle resource missing: \(name)"
        case .decodingFailed(let reason): return "Decoding failed: \(reason)"
        case .violationNotFound(let id): return "Dynamic violation not found: \(id)"
        }
    }
}
