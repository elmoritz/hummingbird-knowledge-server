// Sources/HummingbirdKnowledgeServer/KnowledgeBase/ArchitecturalViolations.swift
//
// The anti-tutorial rule catalogue.
// Each violation has a regex pattern matched against user-submitted source code.
// Critical violations block code generation entirely.

import Foundation

/// A rule that identifies an architectural anti-pattern in Hummingbird 2.x code.
struct ArchitecturalViolation: Sendable {
    let id: String
    let pattern: String         // Regex matched against source code
    let description: String
    let correctionId: String    // Knowledge base entry ID for the fix
    let severity: Severity

    enum Severity: Sendable {
        case warning    // Suboptimal but not incorrect
        case error      // Wrong — will cause problems
        case critical   // Blocks code generation entirely
    }
}

/// The complete catalogue of known Hummingbird 2.x architectural violations.
/// Loaded at startup; matched against every code snippet submitted to the server.
enum ArchitecturalViolations {

    static let all: [ArchitecturalViolation] = [

        // ── Critical: blocks code generation ──────────────────────────────────

        ArchitecturalViolation(
            id: "inline-db-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.query|pool\.|db\.)"#,
            description: "Database calls inside a route handler closure. "
                + "Route handlers must be pure dispatchers — all DB access belongs "
                + "in the repository layer, called via the service layer.",
            correctionId: "route-handler-dispatcher-only",
            severity: .critical
        ),

        ArchitecturalViolation(
            id: "service-construction-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*\w+Service\s*\("#,
            description: "Service constructed inline inside a route handler. "
                + "Services must be injected via AppRequestContext — never constructed "
                + "per-request inside a handler closure.",
            correctionId: "dependency-injection-via-context",
            severity: .critical
        ),

        // ── Error: wrong architecture ─────────────────────────────────────────

        ArchitecturalViolation(
            id: "hummingbird-import-in-service",
            pattern: #"^import\s+Hummingbird"#,
            description: "Hummingbird imported in a file under Services/ or Repositories/. "
                + "The service layer must be framework-agnostic. "
                + "Only controllers, middleware, and Application+build.swift may import Hummingbird.",
            correctionId: "service-layer-no-hummingbird",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "raw-error-thrown-from-handler",
            pattern: #"throw\s+(?!HTTPError|AppError)\w+Error"#,
            description: "A third-party or raw error is thrown directly from a route handler. "
                + "All errors must be wrapped in AppError before propagating — "
                + "this ensures consistent HTTP responses and prevents leaking internals.",
            correctionId: "typed-errors-app-error",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "domain-model-across-http-boundary",
            pattern: #"func\s+\w+\([^)]*\)\s*(async\s+)?(throws\s+)?->\s*(?!Response|some ResponseGenerator)\w+Model"#,
            description: "A domain model is returned directly from a route handler. "
                + "DTOs must be used at every HTTP boundary — domain models must never "
                + "cross the HTTP layer raw.",
            correctionId: "dtos-at-boundaries",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "business-logic-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(if\s+\w+\s*[<>=!]+|switch\s+\w+|for\s+\w+\s+in|\.calculate|\.compute|\.process(?!DTO))"#,
            description: "Business logic detected inside a route handler closure. "
                + "Route handlers must be thin dispatchers — all business rules, "
                + "calculations, and processing logic belongs in the service layer.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "validation-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(guard\s+[^}]*(\.isEmpty|\.count|\.contains|!\.)|if\s+[^}]*(\.isEmpty|\.count|\.contains|!\.))"#,
            description: "Validation logic detected inside a route handler closure. "
                + "Input validation must be handled by DTO decoding conformance "
                + "or moved to the service layer — handlers should only dispatch.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error
        ),

        ArchitecturalViolation(
            id: "data-transformation-in-handler",
            pattern: #"router\.(get|post|put|delete|patch).*\{[^}]*(\.map\s*\{|\.flatMap\s*\{|\.compactMap\s*\{|\.reduce\(|\.filter\s*\{)"#,
            description: "Data transformation detected inside a route handler closure. "
                + "Mapping, filtering, and data formatting belongs in the service layer "
                + "or DTO conversion — handlers should receive transformed data, not create it.",
            correctionId: "route-handler-dispatcher-only",
            severity: .error
        ),

        // ── Warning: suboptimal patterns ──────────────────────────────────────

        ArchitecturalViolation(
            id: "shared-mutable-state-without-actor",
            pattern: #"var\s+\w+\s*:\s*\[.*\]\s*=\s*\[.*\]"#,
            description: "Mutable collection stored as a var at module or class scope "
                + "without actor protection. In Swift 6 strict concurrency, shared "
                + "mutable state requires an actor or explicit synchronisation.",
            correctionId: "actor-for-shared-state",
            severity: .warning
        ),

        ArchitecturalViolation(
            id: "nonisolated-context-access",
            pattern: #"nonisolated.*context\.\w+"#,
            description: "AppRequestContext properties accessed from a nonisolated context. "
                + "Context is value-typed (struct) and Sendable — pass it explicitly "
                + "rather than capturing it across isolation boundaries.",
            correctionId: "request-context-di",
            severity: .warning
        ),
    ]
}
