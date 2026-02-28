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
}

// MARK: - Knowledge store

/// Thread-safe, actor-isolated store for all knowledge entries and violation rules.
///
/// Entries are loaded from the bundled `knowledge.json` at startup, then enriched
/// at runtime by `KnowledgeUpdateService`. The violation catalogue in
/// `ArchitecturalViolations.all` is compiled into the binary and never changes
/// at runtime — only the knowledge entries are mutable.
actor KnowledgeStore {

    private var entries: [String: KnowledgeEntry] = [:]
    private let violations: [ArchitecturalViolation] = ArchitecturalViolations.all

    // MARK: - Initialisation

    /// Creates a KnowledgeStore with the given seed entries.
    /// Exposed as `internal` so tests can create instances with test data.
    /// Production code should use `loadFromBundle()` instead.
    init(seedEntries: [KnowledgeEntry]) {
        self.entries = Dictionary(uniqueKeysWithValues: seedEntries.map { ($0.id, $0) })
    }

    /// Loads seed entries from the bundled `knowledge.json` resource.
    static func loadFromBundle() throws -> KnowledgeStore {
        guard let url = Bundle.module.url(forResource: "knowledge", withExtension: "json") else {
            throw KnowledgeStoreError.bundleResourceMissing("knowledge.json")
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let seedEntries = try decoder.decode([KnowledgeEntry].self, from: data)
        return KnowledgeStore(seedEntries: seedEntries)
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

    // MARK: - Violation detection

    /// Matches `code` against the compiled violation catalogue.
    /// Returns all violations found, sorted by severity (critical first).
    func detectViolations(in code: String) -> [ArchitecturalViolation] {
        violations.compactMap { violation in
            guard (try? NSRegularExpression(pattern: violation.pattern, options: [.anchorsMatchLines]))
                    .flatMap({ regex in
                        let range = NSRange(code.startIndex..., in: code)
                        return regex.firstMatch(in: code, range: range)
                    }) != nil
            else { return nil }
            return violation
        }.sorted {
            severityRank($0.severity) > severityRank($1.severity)
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

    var description: String {
        switch self {
        case .bundleResourceMissing(let name): return "Bundle resource missing: \(name)"
        case .decodingFailed(let reason): return "Decoding failed: \(reason)"
        }
    }
}
